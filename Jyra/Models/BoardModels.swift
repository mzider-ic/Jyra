import Foundation
import SwiftUI

// MARK: - Persisted board config

struct Board: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var jiraBoardId: Int
    var jiraBoardName: String
    var pointsField: String = ""
    var pointsFieldName: String = ""
    var metricRules: [BoardMetricRule] = []
}

// MARK: - Time unit for duration conditions

enum RuleTimeUnit: String, Codable, CaseIterable, Equatable {
    case hours = "hours"
    case days  = "days"
    case weeks = "weeks"

    var displayName: String { rawValue }

    var toHours: Double {
        switch self {
        case .hours: return 1
        case .days:  return 24
        case .weeks: return 168
        }
    }
}

// MARK: - Logical connector between conditions

enum RuleConnector: String, Codable, CaseIterable, Equatable {
    case and = "AND"
    case or  = "OR"
}

// MARK: - Single condition within a rule

struct RuleCondition: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var negated:  Bool            = false
    var field:    BoardRuleField
    var op:       BoardRuleOperator
    var value:    String          = ""
    var timeUnit: RuleTimeUnit    = .hours

    var thresholdHours: Double {
        (Double(value) ?? 0) * timeUnit.toHours
    }
}

// MARK: - Board metric rule

struct BoardMetricRule: Identifiable, Equatable {
    var id:         String         = UUID().uuidString
    var name:       String         = ""
    var conditions: [RuleCondition]
    var connector:  RuleConnector  = .and
    var color:      RuleColor
    var isEnabled:  Bool           = true
}

// MARK: - Codable with legacy single-condition migration

extension BoardMetricRule: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, conditions, connector, color, isEnabled
        // Legacy keys from the old single-condition format
        case legacyField = "field"
        case legacyOp    = "op"
        case legacyValue = "value"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self,       forKey: .id)        ?? UUID().uuidString
        name      = try c.decodeIfPresent(String.self,       forKey: .name)      ?? ""
        color     = try c.decode(RuleColor.self,             forKey: .color)
        isEnabled = try c.decodeIfPresent(Bool.self,         forKey: .isEnabled) ?? true
        connector = (try? c.decodeIfPresent(RuleConnector.self, forKey: .connector)) ?? .and

        if let conds = try? c.decodeIfPresent([RuleCondition].self, forKey: .conditions),
           !conds.isEmpty {
            conditions = conds
        } else {
            // Migrate from old single-condition format
            let field = (try? c.decode(BoardRuleField.self,    forKey: .legacyField)) ?? .hoursInStatus
            let op    = (try? c.decode(BoardRuleOperator.self, forKey: .legacyOp))    ?? .greaterThan
            let value = (try? c.decode(String.self,            forKey: .legacyValue)) ?? "24"
            conditions = [RuleCondition(field: field, op: op, value: value)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(name,       forKey: .name)
        try c.encode(conditions, forKey: .conditions)
        try c.encode(connector,  forKey: .connector)
        try c.encode(color,      forKey: .color)
        try c.encode(isEnabled,  forKey: .isEnabled)
    }
}

struct RuleColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    var swiftUI: Color { Color(red: r, green: g, blue: b) }

    static let neonRed    = RuleColor(r: 1,    g: 0.15, b: 0.15)
    static let neonOrange = RuleColor(r: 1,    g: 0.45, b: 0)
    static let neonYellow = RuleColor(r: 1,    g: 0.94, b: 0)
    static let neonGreen  = RuleColor(r: 0.22, g: 1,    b: 0.08)
    static let neonCyan   = RuleColor(r: 0,    g: 0.83, b: 1)
    static let neonPurple = RuleColor(r: 0.75, g: 0,    b: 1)
    static let neonPink   = RuleColor(r: 1,    g: 0,    b: 0.55)

    static let presets: [RuleColor] = [.neonRed, .neonOrange, .neonYellow, .neonGreen, .neonCyan, .neonPurple, .neonPink]
}

enum BoardRuleField: String, Codable, CaseIterable {
    case statusCategory = "statusCategory"
    case hoursInStatus  = "hoursInStatus"
    case storyPoints    = "storyPoints"
    case priority       = "priority"
    case isBlocked      = "isBlocked"
    case statusName     = "statusName"
    case issueType      = "issueType"
    case label          = "label"

    var displayName: String {
        switch self {
        case .statusCategory: return "Status Category"
        case .hoursInStatus:  return "Hours in Status"
        case .storyPoints:    return "Story Points"
        case .priority:       return "Priority"
        case .isBlocked:      return "Is Blocked"
        case .statusName:     return "Status Name"
        case .issueType:      return "Issue Type"
        case .label:          return "Has Label"
        }
    }

    var isBoolean:  Bool { self == .isBlocked }
    var isNumeric:  Bool { self == .hoursInStatus || self == .storyPoints }
    var isTimeBased: Bool { self == .hoursInStatus }

    var compatibleOperators: [BoardRuleOperator] {
        switch self {
        case .statusCategory:              return [.equals, .notEquals]
        case .hoursInStatus, .storyPoints: return [.greaterThan, .lessThan, .equals]
        case .isBlocked:                   return [.isTrue]
        default:                           return [.equals, .notEquals, .contains]
        }
    }

    // Picker options for statusCategory field
    static let statusCategoryOptions: [(key: String, display: String)] = [
        ("new",           "To Do"),
        ("indeterminate", "In Progress"),
        ("done",          "Done"),
    ]
}

enum BoardRuleOperator: String, Codable, CaseIterable {
    case greaterThan = "gt"
    case lessThan    = "lt"
    case equals      = "eq"
    case notEquals   = "neq"
    case contains    = "contains"
    case isTrue      = "isTrue"

    var displayName: String {
        switch self {
        case .greaterThan: return ">"
        case .lessThan:    return "<"
        case .equals:      return "="
        case .notEquals:   return "≠"
        case .contains:    return "contains"
        case .isTrue:      return "is true"
        }
    }
}

// MARK: - Runtime issue model (fetched, not persisted)

struct BoardIssue: Identifiable {
    let id: String
    let key: String
    let summary: String
    let description: String?
    let statusName: String
    let statusCategoryKey: String   // "new" | "indeterminate" | "done"
    let storyPoints: Double?
    let assigneeName: String?
    let priorityName: String?
    let issueTypeName: String?
    let labels: [String]
    let created: Date?
    let updated: Date?
    let parentKey: String?
    let parentSummary: String?

    var isBlocked: Bool {
        let lc = labels.map { $0.lowercased() }
        return lc.contains("blocked") || lc.contains("impediment")
            || statusName.lowercased().contains("blocked")
    }

    var hoursInStatus: Double {
        guard let updated else { return 0 }
        return Date().timeIntervalSince(updated) / 3600
    }

    var pointsText: String {
        guard let pts = storyPoints else { return "" }
        return pts == pts.rounded() ? "\(Int(pts))" : String(format: "%.1f", pts)
    }

    var assigneeInitials: String {
        guard let name = assigneeName else { return "" }
        return name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
    }

    func matches(_ rule: BoardMetricRule) -> Bool {
        guard rule.isEnabled, !rule.conditions.isEmpty else { return false }
        let results = rule.conditions.map { cond in
            let hit = evaluateCondition(cond)
            return cond.negated ? !hit : hit
        }
        switch rule.connector {
        case .and: return results.allSatisfy { $0 }
        case .or:  return results.contains    { $0 }
        }
    }

    private func evaluateCondition(_ cond: RuleCondition) -> Bool {
        switch cond.field {
        case .statusCategory:
            let key = statusCategoryKey.lowercased()
            switch cond.op {
            case .equals:    return key == cond.value.lowercased()
            case .notEquals: return key != cond.value.lowercased()
            default:         return false
            }
        case .isBlocked:
            return isBlocked
        case .hoursInStatus:
            let threshold = cond.thresholdHours
            switch cond.op {
            case .greaterThan: return hoursInStatus > threshold
            case .lessThan:    return hoursInStatus < threshold
            case .equals:      return abs(hoursInStatus - threshold) < 0.5
            default:           return false
            }
        case .storyPoints:
            guard let pts = storyPoints, let threshold = Double(cond.value) else { return false }
            switch cond.op {
            case .greaterThan: return pts > threshold
            case .lessThan:    return pts < threshold
            case .equals:      return pts == threshold
            case .notEquals:   return pts != threshold
            default:           return false
            }
        case .priority:
            let p = (priorityName ?? "").lowercased()
            switch cond.op {
            case .equals:    return p == cond.value.lowercased()
            case .notEquals: return p != cond.value.lowercased()
            case .contains:  return p.contains(cond.value.lowercased())
            default:         return false
            }
        case .statusName:
            let s = statusName.lowercased()
            switch cond.op {
            case .equals:    return s == cond.value.lowercased()
            case .notEquals: return s != cond.value.lowercased()
            case .contains:  return s.contains(cond.value.lowercased())
            default:         return false
            }
        case .issueType:
            let t = (issueTypeName ?? "").lowercased()
            switch cond.op {
            case .equals:    return t == cond.value.lowercased()
            case .notEquals: return t != cond.value.lowercased()
            case .contains:  return t.contains(cond.value.lowercased())
            default:         return false
            }
        case .label:
            switch cond.op {
            case .equals:   return labels.contains { $0.lowercased() == cond.value.lowercased() }
            case .contains: return labels.contains { $0.lowercased().contains(cond.value.lowercased()) }
            default:        return false
            }
        }
    }

    func cardBorderColor(rules: [BoardMetricRule]) -> Color? {
        if isBlocked { return RuleColor.neonRed.swiftUI }
        return rules.first(where: { matches($0) })?.color.swiftUI
    }
}

// MARK: - Column model

struct BoardColumn: Identifiable {
    let id: String
    let title: String
    let statusCategoryKey: String
    var issues: [BoardIssue]

    var neonColor: Color {
        switch statusCategoryKey {
        case "new":           return RuleColor.neonCyan.swiftUI
        case "indeterminate": return RuleColor.neonPurple.swiftUI
        case "done":          return RuleColor.neonGreen.swiftUI
        default:              return .gray
        }
    }
}
