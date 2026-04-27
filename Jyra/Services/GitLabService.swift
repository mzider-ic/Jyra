import Foundation

final class GitLabService {
    private let token: String
    private let base = URL(string: "https://gitlab.com/api/v4")!

    init(token: String) {
        self.token = token
    }

    // MARK: - Public API

    /// Returns the authenticated user's username for connection testing.
    func ping() async throws -> String {
        let obj = try await get("/user")
        guard let dict = obj as? [String: Any],
              let username = dict["username"] as? String else {
            throw GitLabError.unexpectedResponse
        }
        return username
    }

    /// Resolves a GitLab username to its numeric user ID.
    func resolveUserId(username: String) async throws -> Int? {
        let obj = try await get("/users", query: ["username": username])
        guard let arr = obj as? [[String: Any]], let first = arr.first else { return nil }
        return first["id"] as? Int
    }

    /// Fetches aggregated activity metrics for a user since the given date.
    func fetchActivity(userId: Int, since: Date) async throws -> GitLabActivity {
        var activity = GitLabActivity()
        let afterStr = Self.dateString(since)

        var page = 1
        while page <= 10 {
            let obj = try await get("/users/\(userId)/events", query: [
                "after": afterStr,
                "per_page": "100",
                "page": "\(page)"
            ])
            guard let events = obj as? [[String: Any]], !events.isEmpty else { break }

            for event in events {
                let action     = event["action_name"] as? String ?? ""
                let targetType = event["target_type"] as? String ?? ""

                switch action {
                case "pushed to", "pushed new":
                    if let push = event["push_data"] as? [String: Any],
                       let count = push["commit_count"] as? Int {
                        activity.commits += count
                    } else {
                        activity.commits += 1
                    }
                case "commented on":
                    activity.comments += 1
                case "opened":
                    if targetType == "MergeRequest" { activity.mrOpened += 1 }
                case "accepted":
                    if targetType == "MergeRequest" { activity.mrReviewed += 1 }
                case "merged":
                    if targetType == "MergeRequest" { activity.mrMerged += 1 }
                default:
                    break
                }
            }

            if events.count < 100 { break }
            page += 1
        }

        return activity
    }

    // MARK: - Networking

    private func get(_ path: String, query: [String: String] = [:]) async throws -> Any {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitLabError.httpError(http.statusCode, body)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

// MARK: - Errors

enum GitLabError: LocalizedError {
    case unexpectedResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Unexpected GitLab API response."
        case .httpError(let code, _):
            return "GitLab API error \(code)."
        }
    }
}
