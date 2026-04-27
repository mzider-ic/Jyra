import Foundation

actor JiraService {
    private let config: AppConfig
    private let session: URLSession
    private var cachedFields: [JiraField]? = nil
    private var cachedPreferredPointsField: JiraField? = nil

    init(config: AppConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Connection test

    func ping() async throws -> String {
        struct Myself: Decodable { let displayName: String }
        let me: Myself = try await get("/rest/api/3/myself")
        return me.displayName
    }

    // MARK: - Boards

    func searchBoards(name: String = "") async throws -> [JiraBoard] {
        var query: [String: String] = ["maxResults": "20"]
        if !name.isEmpty { query["name"] = name }
        let resp: BoardsResponse = try await get("/rest/agile/1.0/board", query: query)
        return resp.values
    }

    // MARK: - Sprints

    func fetchSprints(boardId: Int) async throws -> [JiraSprint] {
        var all: [JiraSprint] = []
        var startAt = 0
        repeat {
            let resp: SprintsResponse = try await get(
                "/rest/agile/1.0/board/\(boardId)/sprint",
                query: ["startAt": "\(startAt)", "maxResults": "50"]
            )
            all += resp.values
            if resp.isLast { break }
            startAt += resp.values.count
        } while true
        return all
    }

    func fetchActiveSprint(boardId: Int) async throws -> JiraSprint? {
        let resp: SprintsResponse = try await get(
            "/rest/agile/1.0/board/\(boardId)/sprint",
            query: ["state": "active"]
        )
        return resp.values.first
    }

    // MARK: - Fields

    func fetchFields() async throws -> [JiraField] {
        if let cachedFields {
            return cachedFields
        }
        let fields: [JiraField] = try await get("/rest/api/3/field")
        cachedFields = fields
        return fields
    }

    // MARK: - Velocity (Greenhopper)

    func fetchVelocity(boardId: Int) async throws -> VelocityResponse {
        var allSprints: [VelocityResponse.SprintRef] = []
        var allStats: [String: VelocityResponse.VelocityStats] = [:]
        var seenSprintIds = Set<Int>()
        var transactionId: String? = nil

        for _ in 0..<12 {
            let page = try await fetchVelocityPage(boardId: boardId, transactionId: transactionId)

            var addedSprint = false
            for sprint in page.sprints where seenSprintIds.insert(sprint.id).inserted {
                allSprints.append(sprint)
                addedSprint = true
            }

            for (key, value) in page.velocityStatEntries {
                allStats[key] = value
            }

            let nextTransactionId = page.transactionId
            if nextTransactionId == nil || (!addedSprint && nextTransactionId == transactionId) {
                break
            }
            transactionId = nextTransactionId
        }

        return VelocityResponse(
            sprints: allSprints,
            velocityStatEntries: allStats,
            transactionId: transactionId
        )
    }

    // MARK: - Processed velocity

    func fetchVelocityEntries(boardId: Int) async throws -> [VelocityEntry] {
        async let velocityResp = fetchVelocity(boardId: boardId)
        async let sprints = fetchSprints(boardId: boardId)
        async let currentSprintEntry = fetchCurrentSprintVelocityEntry(boardId: boardId)
        async let activeSprint = fetchActiveSprint(boardId: boardId)

        let (vel, allSprints, activeEntry, activeSprintInfo) = try await (velocityResp, sprints, currentSprintEntry, activeSprint)
        let activeSprintId = activeSprintInfo?.id ?? activeEntry?.id

        let sprintMap = Dictionary(uniqueKeysWithValues: allSprints.map { ($0.id, $0) })

        var entries = vel.sprints.compactMap { ref -> VelocityEntry? in
            guard let stats = vel.velocityStatEntries["\(ref.id)"] else { return nil }
            let sprint = sprintMap[ref.id]
            return VelocityEntry(
                id: ref.id,
                sprintName: ref.name,
                startDate: parseJiraDate(sprint?.startDate),
                endDate: parseJiraDate(sprint?.endDate),
                completeDate: parseJiraDate(sprint?.completeDate),
                committed: stats.estimated.value,
                completed: stats.completed.value,
                isActive: ref.id == activeSprintId
            )
        }

        if let activeEntry {
            entries.removeAll { $0.id == activeEntry.id }
            entries.append(activeEntry)
        }

        return entries.sorted { lhs, rhs in
            velocitySortDate(for: lhs) < velocitySortDate(for: rhs)
        }
    }

    // MARK: - Sprint issues for burndown

    func fetchSprintIssues(boardId: Int, sprintId: Int?, pointsField: String) async throws -> SprintIssuesResponse {
        let resolvedSprintId: Int
        if let sid = sprintId {
            resolvedSprintId = sid
        } else {
            guard let active = try await fetchActiveSprint(boardId: boardId) else {
                throw JiraError.noActiveSprint
            }
            resolvedSprintId = active.id
        }

        var all: [SprintIssuesResponse.SprintIssue] = []
        var startAt = 0
        let fields = "summary,status,created,resolutiondate,\(pointsField)"

        repeat {
            let resp: SprintIssuesResponse = try await get(
                "/rest/agile/1.0/board/\(boardId)/sprint/\(resolvedSprintId)/issue",
                query: [
                    "fields": fields,
                    "startAt": "\(startAt)",
                    "maxResults": "100"
                ],
                pointsField: pointsField
            )
            all += resp.issues
            if all.count >= resp.total { break }
            startAt += resp.issues.count
        } while true

        return SprintIssuesResponse(issues: all, total: all.count)
    }

    // MARK: - Burndown result

    func fetchBurndown(config: BurndownConfig) async throws -> BurndownResult {
        let sprintId: Int? = {
            if case .specific(let id) = config.sprintId { return id }
            return nil
        }()

        // Auto-detect preferred points field when none is configured.
        // "story_points" is the mock-server placeholder; treat it as unconfigured
        // so real Jira instances get the correct customfield_XXXXX ID.
        let pointsField: String
        let isUnconfigured = config.pointsField.isEmpty || config.pointsField == "story_points"
        if isUnconfigured {
            pointsField = (try? await fetchPreferredPointsField())?.id ?? "story_points"
        } else {
            pointsField = config.pointsField
        }

        async let issuesResp = fetchSprintIssues(boardId: config.boardId, sprintId: sprintId, pointsField: pointsField)
        async let sprintsResp = fetchSprints(boardId: config.boardId)

        let (issues, sprints) = try await (issuesResp, sprintsResp)

        let targetSprintId: Int
        if let sid = sprintId {
            targetSprintId = sid
        } else {
            guard let active = sprints.first(where: { $0.state == "active" }) else {
                throw JiraError.noActiveSprint
            }
            targetSprintId = active.id
        }

        guard let sprint = sprints.first(where: { $0.id == targetSprintId }) else {
            throw JiraError.sprintNotFound
        }

        guard let startDate = parseJiraDate(sprint.startDate),
              let endDate = parseJiraDate(sprint.endDate) else {
            throw JiraError.missingSprintDates
        }

        return buildBurndown(
            issues: issues.issues,
            sprint: sprint,
            startDate: startDate,
            endDate: endDate,
            pointsFieldName: config.pointsFieldName
        )
    }

    private func buildBurndown(
        issues: [SprintIssuesResponse.SprintIssue],
        sprint: JiraSprint,
        startDate: Date,
        endDate: Date,
        pointsFieldName: String
    ) -> BurndownResult {
        let cal = Calendar.current
        let now = Date()
        let totalPoints = issues.reduce(0.0) { $0 + ($1.fields.storyPoints ?? 0) }

        var days: [Date] = []
        var cursor = startDate
        while cursor <= max(endDate, now) {
            days.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        let sprintDays = max(1, cal.dateComponents([.day], from: startDate, to: endDate).day ?? 1)

        var completedByDay: [Date: Double] = [:]
        for issue in issues {
            guard issue.fields.status.statusCategory.key == "done",
                  let resStr = issue.fields.resolutiondate,
                  let resDate = parseJiraDate(resStr) else { continue }
            let day = cal.startOfDay(for: resDate)
            completedByDay[day, default: 0] += issue.fields.storyPoints ?? 0
        }

        var cumCompleted = 0.0
        var points: [BurndownPoint] = []

        for (idx, day) in days.enumerated() {
            let isFuture = day > now
            let isWeekend = cal.isDateInWeekend(day)
            let dayNum = cal.dateComponents([.day], from: startDate, to: day).day ?? 0
            let ideal = max(0, totalPoints * (1.0 - Double(dayNum) / Double(sprintDays)))

            if !isFuture {
                cumCompleted += completedByDay[cal.startOfDay(for: day)] ?? 0
            }
            let actual: Double? = isFuture ? nil : (totalPoints - cumCompleted)

            var projected: Double? = nil
            if isFuture, totalPoints > 0 {
                let elapsedDays = Double(cal.dateComponents([.day], from: startDate, to: now).day ?? 0)
                if elapsedDays > 0 {
                    let burnRate = cumCompleted / elapsedDays
                    projected = max(0, totalPoints - cumCompleted - burnRate * Double(idx - days.firstIndex(where: { $0 > now })! + 1))
                }
            }

            let label = DateFormatter.shortDay.string(from: day)
            points.append(BurndownPoint(
                id: label + "\(idx)",
                label: label,
                date: day,
                ideal: ideal,
                actual: actual,
                projected: projected,
                scopeAdded: nil,
                isWeekend: isWeekend,
                isFuture: isFuture
            ))
        }

        let remaining = totalPoints - cumCompleted
        var projectedEnd: Date? = nil
        let elapsedDays = Double(cal.dateComponents([.day], from: startDate, to: min(now, endDate)).day ?? 0)
        if elapsedDays > 0, cumCompleted > 0 {
            let burnRate = cumCompleted / elapsedDays
            let daysLeft = remaining / burnRate
            projectedEnd = cal.date(byAdding: .day, value: Int(daysLeft.rounded()), to: now)
        }

        return BurndownResult(
            points: points,
            sprintName: sprint.name,
            startDate: startDate,
            endDate: endDate,
            initialPoints: totalPoints,
            completedPoints: cumCompleted,
            remainingPoints: remaining,
            projectedEndDate: projectedEnd,
            pointsFieldName: pointsFieldName
        )
    }

    // MARK: - Project burn-up

    func fetchBurnUp(config: ProjectBurnRateConfig) async throws -> BurnUpResult {
        guard !config.parentIssues.isEmpty else {
            return BurnUpResult(points: [], totalScope: 0, completedPoints: 0, issueCount: 0, backlogCount: 0, backlogPoints: 0)
        }
        let sprintField = try await fetchSprintField()

        // Collect unique non-empty per-epic fields; "story_points" is the mock placeholder, skip it.
        let isMockPlaceholder = { (f: String) in f.isEmpty || f == "story_points" }
        var allFields = config.parentIssues.map(\.pointsField).filter { !isMockPlaceholder($0) }
        if !isMockPlaceholder(config.pointsField), !allFields.contains(config.pointsField) {
            allFields.append(config.pointsField)
        }
        if allFields.isEmpty {
            allFields = [(try? await fetchPreferredPointsField())?.id ?? "story_points"]
        }

        let issues = try await fetchChildIssues(
            parentKeys: config.parentIssues.map(\.key),
            pointsFields: Array(Set(allFields)),
            sprintField: sprintField
        )
        return buildBurnUp(issues: issues)
    }

    // MARK: - Board issues (Kanban / Scrum board view — active sprint only)

    func fetchBoardIssues(boardId: Int, pointsField: String?) async throws -> [BoardIssue] {
        let resolvedField: String
        if let pf = pointsField, !pf.isEmpty, pf != "story_points" {
            resolvedField = pf
        } else if let preferred = try? await fetchPreferredPointsField() {
            resolvedField = preferred.id
        } else {
            resolvedField = "story_points"
        }

        // Scope to the active sprint so the board shows only current-sprint cards.
        // Fall back to the full board endpoint when no active sprint exists.
        let path: String
        if let activeSprint = try? await fetchActiveSprint(boardId: boardId) {
            path = "/rest/agile/1.0/board/\(boardId)/sprint/\(activeSprint.id)/issue"
        } else {
            path = "/rest/agile/1.0/board/\(boardId)/issue"
        }

        let fields = "summary,status,assignee,priority,issuetype,labels,created,updated,parent,description,\(resolvedField)"
        var all: [[String: Any]] = []
        var startAt = 0

        repeat {
            let payload = try await getJSON(path, query: [
                "startAt": "\(startAt)", "maxResults": "100", "fields": fields
            ])
            guard let raw = payload["issues"] as? [[String: Any]] else { break }
            let total = payload["total"] as? Int ?? raw.count
            all.append(contentsOf: raw)
            if all.count >= total || raw.isEmpty { break }
            startAt += raw.count
        } while true

        return all.compactMap { parseBoardIssue($0, pointsField: resolvedField) }
    }

    private func parseBoardIssue(_ json: [String: Any], pointsField: String) -> BoardIssue? {
        guard let id     = json["id"]  as? String,
              let key    = json["key"] as? String,
              let fields = json["fields"] as? [String: Any] else { return nil }

        let summary  = fields["summary"] as? String ?? ""

        let statusDict       = fields["status"] as? [String: Any]
        let statusName       = statusDict?["name"] as? String ?? ""
        let catDict          = statusDict?["statusCategory"] as? [String: Any]
        let statusCategoryKey = catDict?["key"] as? String ?? "new"

        let assigneeName  = (fields["assignee"] as? [String: Any])?["displayName"] as? String
        let priorityName  = (fields["priority"]  as? [String: Any])?["name"] as? String
        let issueTypeName = (fields["issuetype"] as? [String: Any])?["name"] as? String

        let labels      = fields["labels"] as? [String] ?? []
        let storyPoints = parsePointValue(fields[pointsField])
        let created     = parseJiraDate(fields["created"] as? String)
        let updated     = parseJiraDate(fields["updated"] as? String)

        let parentDict    = fields["parent"] as? [String: Any]
        let parentKey     = parentDict?["key"] as? String
        let parentSummary = (parentDict?["fields"] as? [String: Any])?["summary"] as? String

        let description = extractBoardDescription(fields["description"])

        return BoardIssue(
            id: id, key: key, summary: summary, description: description,
            statusName: statusName, statusCategoryKey: statusCategoryKey,
            storyPoints: storyPoints, assigneeName: assigneeName,
            priorityName: priorityName, issueTypeName: issueTypeName,
            labels: labels, created: created, updated: updated,
            parentKey: parentKey, parentSummary: parentSummary
        )
    }

    private func extractBoardDescription(_ value: Any?) -> String? {
        if let str = value as? String { return str.isEmpty ? nil : str }
        guard let adf     = value as? [String: Any],
              let content = adf["content"] as? [[String: Any]] else { return nil }
        let text = adfPlainText(content)
        return text.isEmpty ? nil : text
    }

    private func adfPlainText(_ nodes: [[String: Any]]) -> String {
        var result = ""
        for node in nodes {
            if let text = node["text"] as? String { result += text }
            if let children = node["content"] as? [[String: Any]] { result += adfPlainText(children) }
            let type = node["type"] as? String ?? ""
            if ["paragraph", "heading", "bulletList", "orderedList"].contains(type) { result += "\n" }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Calibration

    func fetchCalibrationSprints(boardId: Int, sprintCount: Int, pointsField: String) async throws -> [CalibrationSprint] {
        let allSprints = try await fetchSprints(boardId: boardId)
        let closed = Array(allSprints.filter { $0.state == "closed" }.suffix(sprintCount))
        let active = Array(allSprints.filter { $0.state == "active" }.prefix(1))
        let target = closed + active

        var result: [CalibrationSprint] = []
        for sprint in target {
            let raw = try await getJSON(
                "/rest/agile/1.0/board/\(boardId)/sprint/\(sprint.id)/issue",
                query: [
                    "expand": "changelog",
                    "maxResults": "200",
                    "fields": "summary,status,assignee,\(pointsField)"
                ]
            )
            guard let issues = raw["issues"] as? [[String: Any]] else { continue }
            let calibIssues = issues.compactMap { parseCalibrationIssue($0, pointsField: pointsField) }
            result.append(CalibrationSprint(
                sprintId: sprint.id,
                sprintName: sprint.name,
                boardId: boardId,
                issues: calibIssues
            ))
        }
        return result
    }

    private func parseCalibrationIssue(_ json: [String: Any], pointsField: String) -> CalibrationIssue? {
        guard let key    = json["key"]    as? String,
              let fields = json["fields"] as? [String: Any] else { return nil }

        let assigneeDict = fields["assignee"] as? [String: Any]
        let accountId    = assigneeDict?["accountId"]   as? String
        let displayName  = assigneeDict?["displayName"] as? String
        let points       = parsePointValue(fields[pointsField]) ?? 0

        let statusDict = fields["status"]           as? [String: Any]
        let catDict    = statusDict?["statusCategory"] as? [String: Any]
        let isDone     = catDict?["key"] as? String == "done"

        var inProgressAt: Date? = nil
        var doneAt: Date?       = nil

        if let changelog = json["changelog"] as? [String: Any],
           let histories = changelog["histories"] as? [[String: Any]] {
            let sorted = histories.sorted {
                ($0["created"] as? String ?? "") < ($1["created"] as? String ?? "")
            }
            for history in sorted {
                guard let items   = history["items"]   as? [[String: Any]],
                      let created = parseJiraDate(history["created"] as? String) else { continue }
                for item in items {
                    guard (item["field"] as? String) == "status" else { continue }
                    let toStr = (item["toString"] as? String ?? "").lowercased()
                    if inProgressAt == nil && isInProgressStatus(toStr) { inProgressAt = created }
                    if doneAt       == nil && isDoneStatus(toStr)        { doneAt       = created }
                }
            }
        }

        return CalibrationIssue(
            key: key, accountId: accountId, displayName: displayName,
            points: points, isDone: isDone,
            inProgressAt: inProgressAt, doneAt: doneAt
        )
    }

    private func isInProgressStatus(_ name: String) -> Bool {
        name.contains("progress") || name == "doing" || name == "active"
        || name.contains("review") || name.contains("dev") || name.contains("test")
    }

    private func isDoneStatus(_ name: String) -> Bool {
        name == "done" || name == "closed" || name == "resolved"
        || name.contains("complete") || name == "released" || name == "accepted"
    }

    func searchIssuePicker(query: String) async throws -> [JiraIssuePickerResponse.Issue] {
        let resp: JiraIssuePickerResponse = try await get("/rest/api/3/issue/picker", query: [
            "query": query,
            "currentJQL": "ORDER BY updated DESC"
        ])
        return Array(Set(resp.sections.flatMap(\.issues))).sorted { $0.key < $1.key }
    }

    private func fetchCurrentSprintVelocityEntry(boardId: Int) async throws -> VelocityEntry? {
        guard let activeSprint = try await fetchActiveSprint(boardId: boardId) else {
            return nil
        }

        guard let pointsField = try await fetchPreferredPointsField() else {
            return nil
        }

        let issues = try await fetchSprintIssues(
            boardId: boardId,
            sprintId: activeSprint.id,
            pointsField: pointsField.id
        )

        let committed = issues.issues.reduce(0.0) { $0 + ($1.fields.storyPoints ?? 0) }
        let completed = issues.issues.reduce(0.0) { partial, issue in
            let isDone = issue.fields.status.statusCategory.key == "done"
            return partial + (isDone ? (issue.fields.storyPoints ?? 0) : 0)
        }

        return VelocityEntry(
            id: activeSprint.id,
            sprintName: activeSprint.name,
            startDate: parseJiraDate(activeSprint.startDate),
            endDate: parseJiraDate(activeSprint.endDate),
            completeDate: parseJiraDate(activeSprint.completeDate),
            committed: committed,
            completed: completed,
            isActive: true
        )
    }

    private func velocitySortDate(for entry: VelocityEntry) -> Date {
        entry.completeDate ?? entry.endDate ?? entry.startDate ?? .distantPast
    }

    private func parseJiraDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: value) {
            return date
        }

        let locale = Locale(identifier: "en_US_POSIX")

        func parse(_ format: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = format
            return formatter.date(from: value)
        }

        return parse("yyyy-MM-dd'T'HH:mm:ss.SSSZ") ?? parse("yyyy-MM-dd'T'HH:mm:ssZ")
    }

    // MARK: - HTTP

    private func fetchVelocityPage(boardId: Int, transactionId: String?) async throws -> VelocityResponse {
        var query = ["rapidViewId": "\(boardId)"]
        if let transactionId, !transactionId.isEmpty {
            query["transactionId"] = transactionId
        }
        return try await get("/rest/greenhopper/1.0/rapid/charts/velocity", query: query)
    }

    private func fetchSprintField() async throws -> String {
        let fields = try await fetchFields()
        return fields.first(where: { $0.custom && $0.name.localizedCaseInsensitiveContains("sprint") })?.id
            ?? "customfield_10020"
    }

    private func fetchChildIssues(parentKeys: [String], pointsFields: [String], sprintField: String) async throws -> [IssueForBurnUp] {
        let keys = Array(Set(parentKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard !keys.isEmpty else { return [] }

        let quoted = keys.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")

        // Next-gen (team-managed) projects: stories use parent field
        let byParent = try await runChildIssueSearch(
            jql: "parent in (\(quoted)) ORDER BY created ASC",
            pointsFields: pointsFields, sprintField: sprintField
        )
        if !byParent.isEmpty { return byParent }

        // Classic (company-managed) projects: stories use Epic Link custom field
        return (try? await runChildIssueSearch(
            jql: "\"Epic Link\" in (\(quoted)) ORDER BY created ASC",
            pointsFields: pointsFields, sprintField: sprintField
        )) ?? []
    }

    private func runChildIssueSearch(jql: String, pointsFields: [String], sprintField: String) async throws -> [IssueForBurnUp] {
        let requestedFields = Array(Set(["summary", "status", "issuetype"] + pointsFields + [sprintField, "customfield_10020"]))
        let fieldsCsv = requestedFields.joined(separator: ",")
        var all: [IssueForBurnUp] = []
        var startAt = 0

        repeat {
            let payload = try await getJSON("/rest/api/3/search/jql", query: [
                "jql": jql,
                "fields": fieldsCsv,
                "maxResults": "100",
                "startAt": "\(startAt)"
            ])

            guard let issuesRaw = payload["issues"] as? [[String: Any]] else { break }
            let total = payload["total"] as? Int ?? issuesRaw.count

            for json in issuesRaw {
                let f = json["fields"] as? [String: Any]
                let statusKey = ((f?["status"] as? [String: Any])?["statusCategory"] as? [String: Any])?["key"] as? String
                let sprintValue = f?[sprintField] ?? f?["customfield_10020"]
                // Try each configured field in order; take the first non-nil value
                var storyPoints: Double? = nil
                for field in pointsFields {
                    if let v = parsePointValue(f?[field]) { storyPoints = v; break }
                }
                all.append(IssueForBurnUp(
                    id: json["id"] as? String ?? UUID().uuidString,
                    key: json["key"] as? String ?? "",
                    summary: f?["summary"] as? String ?? "",
                    storyPoints: storyPoints,
                    isDone: statusKey == "done",
                    sprint: parseSprintInfo(sprintValue)
                ))
            }

            if all.count >= total || issuesRaw.isEmpty { break }
            startAt += issuesRaw.count
        } while true

        return all
    }

    private func parseSprintInfo(_ value: Any?) -> SprintInfo? {
        if let arr = value as? [[String: Any]] { return arr.last.flatMap(sprintFromDict) }
        if let single = value as? [String: Any] { return sprintFromDict(single) }
        // Greenhopper serialized string: "com.atlassian.greenhopper...Sprint@abc[id=1,name=Sprint 1,...]"
        if let str = value as? String, str.contains("[") { return sprintFromGreenhopperString(str) }
        return nil
    }

    private func sprintFromDict(_ d: [String: Any]) -> SprintInfo? {
        // JSONSerialization may give id as Int or as Double (e.g. 123.0)
        let id: Int
        if let v = d["id"] as? Int { id = v }
        else if let v = d["id"] as? Double { id = Int(v) }
        else { return nil }
        return SprintInfo(
            id: id,
            name: d["name"] as? String ?? "",
            state: (d["state"] as? String ?? "").lowercased(),
            startDate: parseJiraDate(d["startDate"] as? String),
            endDate: parseJiraDate(d["endDate"] as? String)
        )
    }

    private func sprintFromGreenhopperString(_ str: String) -> SprintInfo? {
        guard let open = str.firstIndex(of: "["), let close = str.lastIndex(of: "]") else { return nil }
        let inner = String(str[str.index(after: open)..<close])
        var kv: [String: String] = [:]
        for pair in inner.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { kv[String(parts[0])] = String(parts[1]) }
        }
        guard let idStr = kv["id"], let id = Int(idStr) else { return nil }
        return SprintInfo(
            id: id,
            name: kv["name"] ?? "",
            state: (kv["state"] ?? "").lowercased(),
            startDate: parseJiraDate(kv["startDate"]),
            endDate: parseJiraDate(kv["endDate"])
        )
    }

    private func buildBurnUp(issues: [IssueForBurnUp]) -> BurnUpResult {
        let totalScope = issues.reduce(0.0) { $0 + ($1.storyPoints ?? 0) }
        let completedPoints = issues.filter(\.isDone).reduce(0.0) { $0 + ($1.storyPoints ?? 0) }

        let backlogIssues = issues.filter { $0.sprint == nil }
        let backlogPoints = backlogIssues.reduce(0.0) { $0 + ($1.storyPoints ?? 0) }

        // Collect unique sprints ordered by start date
        var sprintMap: [Int: SprintInfo] = [:]
        var sprintIssues: [Int: [IssueForBurnUp]] = [:]
        for issue in issues {
            guard let s = issue.sprint else { continue }
            sprintMap[s.id] = s
            sprintIssues[s.id, default: []].append(issue)
        }

        let ordered = sprintMap.values.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        var cumCompleted = 0.0
        var points: [BurnUpPoint] = []
        for sprint in ordered {
            let done = sprintIssues[sprint.id, default: []].filter(\.isDone).reduce(0.0) { $0 + ($1.storyPoints ?? 0) }
            cumCompleted += done
            points.append(BurnUpPoint(
                id: "\(sprint.id)",
                label: sprint.name,
                sprintState: sprint.state,
                totalScope: totalScope,
                cumulativeCompleted: cumCompleted
            ))
        }

        // Append a backlog bucket if there are unsprinted stories
        if !backlogIssues.isEmpty {
            points.append(BurnUpPoint(
                id: "backlog",
                label: "Backlog (\(backlogIssues.count))",
                sprintState: nil,
                totalScope: totalScope,
                cumulativeCompleted: cumCompleted
            ))
        }

        return BurnUpResult(
            points: points,
            totalScope: totalScope,
            completedPoints: completedPoints,
            issueCount: issues.count,
            backlogCount: backlogIssues.count,
            backlogPoints: backlogPoints
        )
    }

    private func fetchPreferredPointsField() async throws -> JiraField? {
        if let cachedPreferredPointsField {
            return cachedPreferredPointsField
        }

        let fields = try await fetchFields()
        let preferred = fields.first {
            $0.name.compare("Story Points", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ?? fields.first {
            $0.name.localizedCaseInsensitiveContains("story point")
        } ?? fields.first {
            $0.name.localizedCaseInsensitiveContains("point estimate")
        } ?? fields.first {
            $0.name.localizedCaseInsensitiveContains("story")
            && $0.name.localizedCaseInsensitiveContains("point")
        }

        cachedPreferredPointsField = preferred
        return preferred
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], pointsField: String? = nil) async throws -> T {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw JiraError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(config.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NetworkLogger.shared.enqueue(.init(
                timestamp: start, method: "GET",
                url: request.url?.absoluteString ?? path,
                statusCode: nil, duration: Date().timeIntervalSince(start),
                requestBody: nil, responseBody: nil, error: error.localizedDescription
            ))
            throw error
        }
        let duration = Date().timeIntervalSince(start)
        let http = response as? HTTPURLResponse

        if NetworkLogger.isEnabledGlobal {
            NetworkLogger.shared.enqueue(.init(
                timestamp: start, method: "GET",
                url: request.url?.absoluteString ?? path,
                statusCode: http?.statusCode, duration: duration,
                requestBody: nil, responseBody: prettyJSON(data),
                error: http.map { (200..<300).contains($0.statusCode) ? nil : "HTTP \($0.statusCode)" } ?? nil
            ))
        }

        guard let http else { throw JiraError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JiraError.httpError(http.statusCode, body)
        }

        if let field = pointsField {
            return try decodeWithDynamicPoints(data: data, pointsField: field)
        }
        return try JSONDecoder.jira.decode(T.self, from: data)
    }

    private func getJSON(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw JiraError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(config.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NetworkLogger.shared.enqueue(.init(
                timestamp: start, method: "GET",
                url: request.url?.absoluteString ?? path,
                statusCode: nil, duration: Date().timeIntervalSince(start),
                requestBody: nil, responseBody: nil, error: error.localizedDescription
            ))
            throw error
        }
        let duration = Date().timeIntervalSince(start)
        let http = response as? HTTPURLResponse

        guard let http else { throw JiraError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if NetworkLogger.isEnabledGlobal {
                NetworkLogger.shared.enqueue(.init(
                    timestamp: start, method: "GET",
                    url: request.url?.absoluteString ?? path,
                    statusCode: http.statusCode, duration: duration,
                    requestBody: nil, responseBody: body, error: "HTTP \(http.statusCode)"
                ))
            }
            throw JiraError.httpError(http.statusCode, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JiraError.invalidResponse
        }
        if NetworkLogger.isEnabledGlobal {
            let body = (try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            NetworkLogger.shared.enqueue(.init(
                timestamp: start, method: "GET",
                url: request.url?.absoluteString ?? path,
                statusCode: http.statusCode, duration: duration,
                requestBody: nil, responseBody: body, error: nil
            ))
        }
        return json
    }

    private func prettyJSON(_ data: Data) -> String {
        let limit = 20_000
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            return str.count <= limit ? str : String(str.prefix(limit)) + "\n…(truncated)"
        }
        let raw = String(data: data.prefix(limit), encoding: .utf8) ?? ""
        return raw.isEmpty ? "<empty>" : raw
    }

    private func decodeWithDynamicPoints<T: Decodable>(data: Data, pointsField: String) throws -> T {
        //11 Only SprintIssuesResponse needs dynamic story points patching.
        // If another Decodable type calls through here, decode it normally.
        if T.self != SprintIssuesResponse.self {
            return try JSONDecoder.jira.decode(T.self, from: data)
        }
        // Decode normally first.
        let decoder = JSONDecoder.jira
        var result = try decoder.decode(SprintIssuesResponse.self, from: data)
        // Patch storyPoints from raw JSON using parsePointValue (supports numeric + option objects + arrays
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issueJson = root["issues"] as? [[String: Any]] {
            for i in result.issues.indices where i < issueJson.count {
                if let fields = issueJson[i]["fields"] as? [String: Any] {
                    result.issues[i].fields.storyPoints = parsePointValue(fields[pointsField])
                }
            }
        }
        return result as! T
    }

    private func parsePointValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        
        if let dict = value as? [String: Any] {
            if let v = parsePointValue(dict["value"]) { return v }
            if let v = parsePointValue(dict["name"]) { return v }
            if let v = parsePointValue(dict["label"]) { return v }
            return nil
        }
        
        if let arr = value as? [Any] {
            for item in arr {
                if let v = parsePointValue(item) { return v }
            }
            return nil
        }
        return nil
    }
}

extension JSONDecoder {
    static let jira: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension DateFormatter {
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

enum JiraError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case noActiveSprint
    case sprintNotFound
    case missingSprintDates

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .noActiveSprint: return "No active sprint found"
        case .sprintNotFound: return "Sprint not found"
        case .missingSprintDates: return "Sprint is missing start or end dates"
        }
    }
}
