import Foundation

// MARK: - Dashboard

struct Dashboard: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var widgets: [Widget] = []
}

// MARK: - Widget

struct Widget: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var type: WidgetType
    var size: WidgetSize = .half
    var config: WidgetConfig
    var customHeight: Double?
}

enum WidgetType: String, Codable, CaseIterable {
    case velocity = "velocity"
    case burndown = "burndown"
    case projectBurnRate = "projectBurnRate"

    var displayName: String {
        switch self {
        case .velocity:       return "Velocity"
        case .burndown:       return "Burndown"
        case .projectBurnRate: return "Project Burn Rate"
        }
    }

    var description: String {
        switch self {
        case .velocity:
            return "Committed vs completed story points across sprints, with rolling average."
        case .burndown:
            return "Sprint burndown with ideal line, scope changes, and projected completion."
        case .projectBurnRate:
            return "Multi-team project progress and projected finish date."
        }
    }
}

enum WidgetSize: String, Codable, CaseIterable {
    case half = "half"
    case full = "full"

    var displayName: String {
        switch self {
        case .half: return "Half width"
        case .full: return "Full width"
        }
    }
}

// MARK: - Widget configs

enum WidgetConfig: Codable, Equatable {
    case velocity(VelocityConfig)
    case burndown(BurndownConfig)
    case projectBurnRate(ProjectBurnRateConfig)

    private enum CodingKeys: String, CodingKey { case type, payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "velocity":       self = .velocity(try c.decode(VelocityConfig.self, forKey: .payload))
        case "burndown":       self = .burndown(try c.decode(BurndownConfig.self, forKey: .payload))
        case "projectBurnRate": self = .projectBurnRate(try c.decode(ProjectBurnRateConfig.self, forKey: .payload))
        default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .velocity(let v):
            try c.encode("velocity", forKey: .type)
            try c.encode(v, forKey: .payload)
        case .burndown(let b):
            try c.encode("burndown", forKey: .type)
            try c.encode(b, forKey: .payload)
        case .projectBurnRate(let p):
            try c.encode("projectBurnRate", forKey: .type)
            try c.encode(p, forKey: .payload)
        }
    }
}

struct VelocityConfig: Codable, Equatable {
    var boardId: Int
    var boardName: String
    var title: String
    var paletteOverride: VelocityPalette?

    init(boardId: Int, boardName: String, title: String = "", paletteOverride: VelocityPalette? = nil) {
        self.boardId = boardId
        self.boardName = boardName
        self.title = title
        self.paletteOverride = paletteOverride
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? boardName : trimmed
    }
}

struct BurndownConfig: Codable, Equatable {
    var boardId: Int
    var boardName: String
    var sprintId: SprintSelection = .active
    var sprintName: String = "Active sprint"
    var pointsField: String = "story_points"
    var pointsFieldName: String = "Story Points"

    enum SprintSelection: Codable, Equatable {
        case active
        case specific(Int)

        var displayValue: String {
            switch self {
            case .active: return "active"
            case .specific(let id): return "\(id)"
            }
        }
    }
}

struct ProjectBurnRateConfig: Codable, Equatable {
    var projectName: String
    var pointsField: String
    var pointsFieldName: String
    var parentIssues: [ScopeIssue]

    init(
        projectName: String,
        pointsField: String = "story_points",
        pointsFieldName: String = "Story Points",
        parentIssues: [ScopeIssue] = []
    ) {
        self.projectName = projectName
        self.pointsField = pointsField
        self.pointsFieldName = pointsFieldName
        self.parentIssues = parentIssues
    }

    struct ScopeIssue: Codable, Equatable, Identifiable {
        var id: String { key }
        var key: String
        var summary: String
    }

    // Legacy keys kept so old saved configs decode without error.
    private enum CodingKeys: String, CodingKey {
        case projectName, pointsField, pointsFieldName, parentIssues
        case teamBoardId, teamBoardName, totalPoints, teams  // ignored on read, never written
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try c.decode(String.self, forKey: .projectName)
        pointsField = try c.decodeIfPresent(String.self, forKey: .pointsField) ?? "story_points"
        pointsFieldName = try c.decodeIfPresent(String.self, forKey: .pointsFieldName) ?? "Story Points"
        parentIssues = try c.decodeIfPresent([ScopeIssue].self, forKey: .parentIssues) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectName, forKey: .projectName)
        try c.encode(pointsField, forKey: .pointsField)
        try c.encode(pointsFieldName, forKey: .pointsFieldName)
        try c.encode(parentIssues, forKey: .parentIssues)
    }
}
