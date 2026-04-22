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
        let fmt = ISO8601DateFormatter()

        var entries = vel.sprints.compactMap { ref -> VelocityEntry? in
            guard let stats = vel.velocityStatEntries["\(ref.id)"] else { return nil }
            let sprint = sprintMap[ref.id]
            return VelocityEntry(
                id: ref.id,
                sprintName: ref.name,
                startDate: sprint?.startDate.flatMap { fmt.date(from: $0) },
                endDate: sprint?.endDate.flatMap { fmt.date(from: $0) },
                completeDate: sprint?.completeDate.flatMap { fmt.date(from: $0) },
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

        let fmt = ISO8601DateFormatter()
        guard let startDate = sprint.startDate.flatMap({ fmt.date(from: $0) }),
              let endDate = sprint.endDate.flatMap({ fmt.date(from: $0) }) else {
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

    // MARK: - Project burn rate

    func fetchProjectBurnRate(config: ProjectBurnRateConfig) async throws -> ProjectBurnResult {
        guard let boardId = config.teamBoardId else {
            return ProjectBurnResult(
                points: [],
                team: TeamVelocitySummary(
                    id: "unconfigured",
                    boardId: 0,
                    name: config.teamBoardName,
                    avgVelocity: 0,
                    sprintLengthDays: 14,
                    recentSprints: []
                ),
                combinedVelocity: 0,
                totalPoints: 0,
                sprintsRemaining: 0,
                scopeIssues: []
            )
        }

        async let entriesTask = fetchVelocityEntries(boardId: boardId)
        async let scopeTask = fetchProjectScopeIssues(parentKeys: config.parentIssues.map(\.key), pointsField: config.pointsField)

        let entries = try await entriesTask
        let scopeIssues = try await scopeTask

        let recent = Array(entries.suffix(6))
        let avgVelocity = recent.isEmpty ? 0 : recent.map(\.completed).reduce(0, +) / Double(recent.count)

        var sprintLength = 14
        if let last = recent.last,
           let start = last.startDate,
           let end = last.endDate {
            sprintLength = max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 14)
        }

        let teamSummary = TeamVelocitySummary(
            id: "\(boardId)",
            boardId: boardId,
            name: config.teamBoardName,
            avgVelocity: avgVelocity,
            sprintLengthDays: sprintLength,
            recentSprints: recent
        )

        let totalPoints = scopeIssues.reduce(0.0) { $0 + $1.pointValue }
        let sprintsLeft = avgVelocity > 0 ? Int((totalPoints / avgVelocity).rounded(.up)) : 0

        var burnPoints: [ProjectBurnPoint] = []
        let remaining = totalPoints
        for i in 0...max(sprintsLeft, 1) {
            let isFuture = i > 0
            let label = i == 0 ? "Now" : "Sprint +\(i)"
            let projected: Double? = isFuture ? max(0, remaining - avgVelocity * Double(i)) : nil
            burnPoints.append(ProjectBurnPoint(
                label: label,
                remaining: isFuture ? nil : remaining,
                projected: projected,
                isFuture: isFuture
            ))
        }

        return ProjectBurnResult(
            points: burnPoints,
            team: teamSummary,
            combinedVelocity: avgVelocity,
            totalPoints: totalPoints,
            sprintsRemaining: sprintsLeft,
            scopeIssues: scopeIssues.sorted { lhs, rhs in
                if lhs.pointValue == rhs.pointValue { return lhs.key < rhs.key }
                return lhs.pointValue > rhs.pointValue
            }
        )
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

        let fmt = ISO8601DateFormatter()
        let committed = issues.issues.reduce(0.0) { $0 + ($1.fields.storyPoints ?? 0) }
        let completed = issues.issues.reduce(0.0) { partial, issue in
            let isDone = issue.fields.status.statusCategory.key == "done"
            return partial + (isDone ? (issue.fields.storyPoints ?? 0) : 0)
        }

        return VelocityEntry(
            id: activeSprint.id,
            sprintName: activeSprint.name,
            startDate: activeSprint.startDate.flatMap { fmt.date(from: $0) },
            endDate: activeSprint.endDate.flatMap { fmt.date(from: $0) },
            completeDate: activeSprint.completeDate.flatMap { fmt.date(from: $0) },
            committed: committed,
            completed: completed,
            isActive: true
        )
    }

    private func velocitySortDate(for entry: VelocityEntry) -> Date {
        entry.completeDate ?? entry.endDate ?? entry.startDate ?? .distantPast
    }

    // MARK: - HTTP

    private func fetchVelocityPage(boardId: Int, transactionId: String?) async throws -> VelocityResponse {
        var query = ["rapidViewId": "\(boardId)"]
        if let transactionId, !transactionId.isEmpty {
            query["transactionId"] = transactionId
        }
        return try await get("/rest/greenhopper/1.0/rapid/charts/velocity", query: query)
    }

    private func fetchProjectScopeIssues(parentKeys: [String], pointsField: String) async throws -> [ProjectScopeIssue] {
        let normalizedKeys = Array(Set(parentKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard !normalizedKeys.isEmpty else { return [] }

        var merged: [String: JiraIssue] = [:]

        for issue in try await fetchIssuesByJQL(
            "issuekey in (\(normalizedKeys.map(jqlQuote).joined(separator: ", ")))",
            pointsField: pointsField
        ) {
            merged[issue.key] = issue
        }

        for jql in childScopeJQLs(for: normalizedKeys) {
            do {
                let issues = try await fetchIssuesByJQL(jql, pointsField: pointsField)
                for issue in issues {
                    merged[issue.key] = issue
                }
            } catch JiraError.httpError(let code, _) where code == 400 {
                continue
            }
        }

        return merged.values.compactMap { issue in
            guard let storyPoints = issue.storyPoints, storyPoints > 0 else { return nil }
            return ProjectScopeIssue(
                id: issue.id,
                key: issue.key,
                summary: issue.summary,
                pointValue: storyPoints
            )
        }
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

    private func fetchIssuesByJQL(_ jql: String, pointsField: String) async throws -> [JiraIssue] {
        var allIssues: [JiraIssue] = []
        var startAt = 0

        repeat {
            let payload: [String: Any] = try await getJSON(
                "/rest/api/3/search",
                query: [
                    "jql": jql,
                    "fields": "summary,issuetype,parent,\(pointsField)",
                    "maxResults": "100",
                    "startAt": "\(startAt)"
                ]
            )

            guard let issues = payload["issues"] as? [[String: Any]] else { break }
            let total = payload["total"] as? Int ?? issues.count
            let parsed = issues.map { parseJiraIssue($0, pointsField: pointsField) }
            allIssues += parsed

            if allIssues.count >= total || issues.isEmpty {
                break
            }
            startAt += issues.count
        } while true

        return allIssues
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

    private func parseJiraIssue(_ json: [String: Any], pointsField: String) -> JiraIssue {
        let fields = json["fields"] as? [String: Any]
        let issueType = (fields?["issuetype"] as? [String: Any])?["name"] as? String
        let parentKey = ((fields?["parent"] as? [String: Any])?["key"] as? String)
        let summary = fields?["summary"] as? String ?? ""
        let storyPoints = parsePointValue(fields?[pointsField])

        return JiraIssue(
            id: json["id"] as? String ?? UUID().uuidString,
            key: json["key"] as? String ?? "",
            summary: summary,
            issueTypeName: issueType,
            parentKey: parentKey,
            storyPoints: storyPoints
        )
    }

    private func parsePointValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func childScopeJQLs(for parentKeys: [String]) -> [String] {
        let quotedKeys = parentKeys.map(jqlQuote).joined(separator: ", ")
        return [
            "parent in (\(quotedKeys))",
            "\"Epic Link\" in (\(quotedKeys))"
        ]
    }

    private func jqlQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
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
