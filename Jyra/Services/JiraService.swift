import Foundation

actor JiraService {
    private let config: AppConfig
    private let session: URLSession

    init(config: AppConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Boards

    func fetchBoards() async throws -> [JiraBoard] {
        var all: [JiraBoard] = []
        var startAt = 0
        repeat {
            let resp: BoardsResponse = try await get("/rest/agile/1.0/board", query: [
                "startAt": "\(startAt)", "maxResults": "50"
            ])
            all += resp.values
            if resp.isLast { break }
            startAt += resp.values.count
        } while true
        return all
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
        return try await get("/rest/api/3/field")
    }

    // MARK: - Velocity (Greenhopper)

    func fetchVelocity(boardId: Int) async throws -> VelocityResponse {
        return try await get("/rest/greenhopper/1.0/rapid/charts/velocity", query: [
            "rapidViewId": "\(boardId)"
        ])
    }

    // MARK: - Processed velocity

    func fetchVelocityEntries(boardId: Int) async throws -> [VelocityEntry] {
        async let velocityResp = fetchVelocity(boardId: boardId)
        async let sprints = fetchSprints(boardId: boardId)

        let (vel, allSprints) = try await (velocityResp, sprints)

        let sprintMap = Dictionary(uniqueKeysWithValues: allSprints.map { ($0.id, $0) })
        let fmt = ISO8601DateFormatter()

        return vel.sprints.compactMap { ref -> VelocityEntry? in
            guard let stats = vel.velocityStatEntries["\(ref.id)"] else { return nil }
            let sprint = sprintMap[ref.id]
            return VelocityEntry(
                id: ref.id,
                sprintName: ref.name,
                startDate: sprint?.startDate.flatMap { fmt.date(from: $0) },
                endDate: sprint?.endDate.flatMap { fmt.date(from: $0) },
                committed: stats.estimated.value,
                completed: stats.completed.value
            )
        }.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
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
        var teamSummaries: [TeamVelocitySummary] = []

        try await withThrowingTaskGroup(of: TeamVelocitySummary.self) { group in
            for team in config.teams {
                group.addTask {
                    let entries = try await self.fetchVelocityEntries(boardId: team.boardId)
                    let recent = Array(entries.suffix(6))
                    let avg = recent.isEmpty ? 0 : recent.map(\.completed).reduce(0, +) / Double(recent.count)

                    var sprintLen = 14
                    if recent.count >= 2,
                       let s = recent[recent.count-1].startDate,
                       let e = recent[recent.count-1].endDate {
                        sprintLen = max(1, Calendar.current.dateComponents([.day], from: s, to: e).day ?? 14)
                    }

                    return TeamVelocitySummary(
                        id: "\(team.boardId)",
                        boardId: team.boardId,
                        name: team.name,
                        avgVelocity: avg,
                        sprintLengthDays: sprintLen,
                        recentSprints: recent
                    )
                }
            }
            for try await summary in group {
                teamSummaries.append(summary)
            }
        }

        teamSummaries.sort { $0.name < $1.name }

        let combined = teamSummaries.map(\.avgVelocity).reduce(0, +)
        let sprintsLeft = combined > 0 ? Int((config.totalPoints / combined).rounded(.up)) : 0

        var burnPoints: [ProjectBurnPoint] = []
        let remaining = config.totalPoints
        for i in 0...max(sprintsLeft, 1) {
            let isFuture = i > 0
            let label = i == 0 ? "Now" : "Sprint +\(i)"
            let projected: Double? = isFuture ? max(0, remaining - combined * Double(i)) : nil
            burnPoints.append(ProjectBurnPoint(
                label: label,
                remaining: isFuture ? nil : remaining,
                projected: projected,
                isFuture: isFuture
            ))
        }

        return ProjectBurnResult(
            points: burnPoints,
            teams: teamSummaries,
            combinedVelocity: combined,
            totalPoints: config.totalPoints,
            sprintsRemaining: sprintsLeft
        )
    }

    // MARK: - HTTP

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

        let patched = try JSONSerialization.data(withJSONObject: json)

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
