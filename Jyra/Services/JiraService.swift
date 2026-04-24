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

        async let issuesResp = fetchSprintIssues(boardId: config.boardId, sprintId: sprintId, pointsField: config.pointsField)
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
        let fmt = ISO8601DateFormatter()

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
                  let resDate = fmt.date(from: resStr) else { continue }
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

        // Collect all unique non-empty per-epic fields; fall back to global, then "story_points"
        var allFields = config.parentIssues.map(\.pointsField).filter { !$0.isEmpty }
        if !config.pointsField.isEmpty, !allFields.contains(config.pointsField) {
            allFields.append(config.pointsField)
        }
        if allFields.isEmpty { allFields = ["story_points"] }

        let issues = try await fetchChildIssues(
            parentKeys: config.parentIssues.map(\.key),
            pointsFields: Array(Set(allFields)),
            sprintField: sprintField
        )
        return buildBurnUp(issues: issues)
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

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw JiraError.invalidResponse }
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

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JiraError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JiraError.httpError(http.statusCode, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JiraError.invalidResponse
        }
        return json
    }

    private func decodeWithDynamicPoints<T: Decodable>(data: Data, pointsField: String) throws -> T {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var issues = json["issues"] as? [[String: Any]] else {
            return try JSONDecoder.jira.decode(T.self, from: data)
        }

        for i in issues.indices {
            if var fields = issues[i]["fields"] as? [String: Any] {
                if let pts = fields[pointsField] as? Double {
                    fields["storyPoints_decoded"] = pts
                } else if let pts = fields[pointsField] as? Int {
                    fields["storyPoints_decoded"] = Double(pts)
                }
                issues[i]["fields"] = fields
            }
        }
        json["issues"] = issues

        _ = try JSONSerialization.data(withJSONObject: json)

        // Inject storyPoints via a custom decoder
        let decoder = JSONDecoder.jira
        var result = try decoder.decode(SprintIssuesResponse.self, from: data)

        // Re-patch story points from original JSON
        for i in result.issues.indices {
            if let issueJson = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["issues"] as? [[String: Any]],
               i < issueJson.count,
               let fields = issueJson[i]["fields"] as? [String: Any] {
                if let pts = fields[pointsField] as? Double {
                    result.issues[i].fields.storyPoints = pts
                } else if let pts = fields[pointsField] as? Int {
                    result.issues[i].fields.storyPoints = Double(pts)
                }
            }
        }

        return result as! T
    }

    private func parsePointValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
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
