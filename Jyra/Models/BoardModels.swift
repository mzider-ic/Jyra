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

struct BoardMetricRule: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String = ""
    var field: BoardRuleField
    var op: BoardRuleOperator
    var value: String = ""
    var color: RuleColor
    var isEnabled: Bool = true
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
    case hoursInStatus = "hoursInStatus"
    case storyPoints   = "storyPoints"
    case priority      = "priority"
    case isBlocked     = "isBlocked"
    case statusName    = "statusName"
    case issueType     = "issueType"
    case label         = "label"

    var displayName: String {
        switch self {
        case .hoursInStatus: return "Hours in Status"
        case .storyPoints:   return "Story Points"
        case .priority:      return "Priority"
        case .isBlocked:     return "Is Blocked"
        case .statusName:    return "Status Name"
        case .issueType:     return "Issue Type"
        case .label:         return "Has Label"
        }
    }

    var isBoolean: Bool { self == .isBlocked }
    var isNumeric: Bool { self == .hoursInStatus || self == .storyPoints }

    var compatibleOperators: [BoardRuleOperator] {
        switch self {
        case .hoursInStatus, .storyPoints: return [.greaterThan, .lessThan, .equals]
        case .isBlocked:                   return [.isTrue]
        default:                           return [.equals, .notEquals, .contains]
        }
    }
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
        guard rule.isEnabled else { return false }
        switch rule.field {
        case .isBlocked:
            return isBlocked
        case .hoursInStatus:
            guard let threshold = Double(rule.value) else { return false }
            switch rule.op {
            case .greaterThan: return hoursInStatus > threshold
            case .lessThan:    return hoursInStatus < threshold
            case .equals:      return abs(hoursInStatus - threshold) < 0.5
            default:           return false
            }
        case .storyPoints:
            guard let pts = storyPoints, let threshold = Double(rule.value) else { return false }
            switch rule.op {
            case .greaterThan: return pts > threshold
            case .lessThan:    return pts < threshold
            case .equals:      return pts == threshold
            case .notEquals:   return pts != threshold
            default:           return false
            }
        case .priority:
            let p = (priorityName ?? "").lowercased()
            switch rule.op {
            case .equals:    return p == rule.value.lowercased()
            case .notEquals: return p != rule.value.lowercased()
            case .contains:  return p.contains(rule.value.lowercased())
            default:         return false
            }
        case .statusName:
            let s = statusName.lowercased()
            switch rule.op {
            case .equals:    return s == rule.value.lowercased()
            case .notEquals: return s != rule.value.lowercased()
            case .contains:  return s.contains(rule.value.lowercased())
            default:         return false
            }
        case .issueType:
            let t = (issueTypeName ?? "").lowercased()
            switch rule.op {
            case .equals:    return t == rule.value.lowercased()
            case .notEquals: return t != rule.value.lowercased()
            case .contains:  return t.contains(rule.value.lowercased())
            default:         return false
            }
        case .label:
            switch rule.op {
            case .equals:   return labels.contains { $0.lowercased() == rule.value.lowercased() }
            case .contains: return labels.contains { $0.lowercased().contains(rule.value.lowercased()) }
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
