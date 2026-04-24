import Foundation

// MARK: - Boards

struct JiraBoard: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let type: String
}

struct BoardsResponse: Decodable {
    let values: [JiraBoard]
    let isLast: Bool
    let startAt: Int
    let maxResults: Int
}

// MARK: - Sprints

struct JiraSprint: Identifiable, Decodable {
    let id: Int
    let name: String
    let state: String
    let startDate: String?
    let endDate: String?
    let completeDate: String?
}

struct SprintsResponse: Decodable {
    let values: [JiraSprint]
    let isLast: Bool
}

// MARK: - Fields

struct JiraField: Decodable, Identifiable {
    let id: String
    let name: String
    let custom: Bool
    let schema: Schema?

    struct Schema: Decodable {
        let type: String?
    }
}

// MARK: - Velocity (Greenhopper)

struct VelocityResponse: Decodable {
    let sprints: [SprintRef]
    let velocityStatEntries: [String: VelocityStats]
    let transactionId: String?

    init(
        sprints: [SprintRef],
        velocityStatEntries: [String: VelocityStats],
        transactionId: String?
    ) {
        self.sprints = sprints
        self.velocityStatEntries = velocityStatEntries
        self.transactionId = transactionId
    }

    struct SprintRef: Decodable {
        let id: Int
        let name: String
        let state: String
    }

    struct VelocityStats: Decodable {
        let estimated: PointValue
        let completed: PointValue

        struct PointValue: Decodable {
            let value: Double
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sprints
        case velocityStatEntries
        case transactionId
        case transactionid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sprints = try c.decodeIfPresent([SprintRef].self, forKey: .sprints) ?? []
        velocityStatEntries = try c.decodeIfPresent([String: VelocityStats].self, forKey: .velocityStatEntries) ?? [:]
        transactionId =
            try c.decodeIfPresent(String.self, forKey: .transactionId) ??
            (try c.decodeIfPresent(String.self, forKey: .transactionid))
    }
}

// MARK: - Processed models

struct VelocityEntry: Identifiable, Equatable {
    let id: Int
    let sprintName: String
    let startDate: Date?
    let endDate: Date?
    let completeDate: Date?
    let committed: Double
    let completed: Double
    let isActive: Bool
}

struct BurndownPoint: Identifiable {
    let id: String
    let label: String
    let date: Date
    let ideal: Double
    let actual: Double?
    let projected: Double?
    let scopeAdded: Double?
    let isWeekend: Bool
    let isFuture: Bool
}

struct BurndownResult {
    let points: [BurndownPoint]
    let sprintName: String
    let startDate: Date
    let endDate: Date
    let initialPoints: Double
    let completedPoints: Double
    let remainingPoints: Double
    let projectedEndDate: Date?
    let pointsFieldName: String
}

// MARK: - Project burn-up

struct SprintInfo: Hashable {
    let id: Int
    let name: String
    let state: String   // "active" | "closed" | "future"
    let startDate: Date?
    let endDate: Date?
}

struct IssueForBurnUp: Identifiable {
    let id: String
    let key: String
    let summary: String
    let storyPoints: Double?
    let isDone: Bool
    let sprint: SprintInfo?
}

struct BurnUpPoint: Identifiable {
    let id: String
    let label: String
    let sprintState: String?    // nil = backlog bucket
    let totalScope: Double
    let cumulativeCompleted: Double
}

struct BurnUpResult {
    let points: [BurnUpPoint]
    let totalScope: Double
    let completedPoints: Double
    let issueCount: Int
}

struct JiraIssue: Identifiable, Hashable {
    let id: String
    let key: String
    let summary: String
    let issueTypeName: String?
    let parentKey: String?
    let storyPoints: Double?
}

struct JiraIssuePickerResponse: Decodable {
    let sections: [Section]

    struct Section: Decodable {
        let issues: [Issue]
    }

    struct Issue: Decodable, Hashable {
        let id: String
        let key: String
        let summary: String
        let subtitle: String?  // issue type (e.g. "Epic", "Story") returned by Jira picker

        // Real Jira Cloud returns id as Int; mock returns String.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let intId = try? c.decode(Int.self, forKey: .id) {
                id = String(intId)
            } else {
                id = try c.decode(String.self, forKey: .id)
            }
            key = try c.decode(String.self, forKey: .key)
            summary = try c.decode(String.self, forKey: .summary)
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        }

        private enum CodingKeys: String, CodingKey {
            case id, key, summary, subtitle
        }
    }
}

// MARK: - Issue response for burndown

struct SprintIssuesResponse: Decodable {
    var issues: [SprintIssue]
    let total: Int

    struct SprintIssue: Decodable {
        let id: String
        let key: String
        var fields: IssueFields
    }

    struct IssueFields: Decodable {
        let summary: String
        let status: IssueStatus
        let created: String
        let resolutiondate: String?

        // Story points decoded dynamically — see JiraService
        var storyPoints: Double?

        enum CodingKeys: String, CodingKey {
            case summary, status, created, resolutiondate
        }
    }

    struct IssueStatus: Decodable {
        let name: String
        let statusCategory: StatusCategory

        struct StatusCategory: Decodable {
            let key: String
        }
    }
}
