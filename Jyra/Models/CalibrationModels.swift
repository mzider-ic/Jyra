import Foundation
import SwiftUI

// MARK: - Grade Level

enum GradeLevel: String, Codable, CaseIterable, Hashable {
    case intern             = "Intern"
    case engineer           = "Engineer"
    case seniorEngineer     = "Senior Engineer"
    case staffEngineer      = "Staff Engineer"
    case principalEngineer  = "Principal Engineer"
    case engineeringManager = "Engineering Manager"
    case productOwner       = "Product Owner"
    case businessAnalyst    = "Business Analyst"

    /// Whether this role participates in calibration metrics.
    /// POs and BAs are tracked in the roster but excluded from the calibration view.
    var isCalibrationRole: Bool {
        switch self {
        case .productOwner, .businessAnalyst: return false
        default: return true
        }
    }

    var shortName: String {
        switch self {
        case .intern:             return "Intern"
        case .engineer:           return "Eng"
        case .seniorEngineer:     return "Sr. Eng"
        case .staffEngineer:      return "Staff"
        case .principalEngineer:  return "Principal"
        case .engineeringManager: return "EM"
        case .productOwner:       return "PO"
        case .businessAnalyst:    return "BA"
        }
    }

    var neonColor: Color {
        switch self {
        case .intern:             return RuleColor.neonCyan.swiftUI
        case .engineer:           return RuleColor.neonGreen.swiftUI
        case .seniorEngineer:     return RuleColor.neonPurple.swiftUI
        case .staffEngineer:      return RuleColor.neonOrange.swiftUI
        case .principalEngineer:  return RuleColor.neonRed.swiftUI
        case .engineeringManager: return Color(white: 0.65)
        case .productOwner:       return Color(white: 0.55)
        case .businessAnalyst:    return Color(white: 0.55)
        }
    }
}

// MARK: - GitLab activity

struct GitLabActivity {
    var commits: Int  = 0
    var comments: Int = 0
    var mrOpened: Int = 0
    var mrReviewed: Int = 0
    var mrMerged: Int = 0

    var totalEvents: Int { commits + comments + mrOpened + mrReviewed + mrMerged }
}

// MARK: - Persisted config

struct EngineerAssignment: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var jiraAccountId: String
    var displayName: String
    var gradeLevel: GradeLevel
    var gitlabUsername: String = ""
}

struct CalibrationBoardRef: Codable, Equatable {
    var boardId: Int
    var boardName: String
    var pointsField: String = ""
    var pointsFieldName: String = ""
}

struct CalibrationConfig: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var boards: [CalibrationBoardRef] = []
    var sprintCount: Int = 3
    var engineers: [EngineerAssignment] = []
}

// MARK: - Runtime (not persisted)

struct CalibrationIssue {
    var key: String
    var accountId: String?
    var displayName: String?
    var points: Double
    var isDone: Bool
    var inProgressAt: Date?
    var doneAt: Date?

    var cycleDays: Double? {
        guard let s = inProgressAt, let e = doneAt, e > s else { return nil }
        return e.timeIntervalSince(s) / 86_400
    }
}

struct CalibrationSprint {
    var sprintId: Int
    var sprintName: String
    var boardId: Int
    var issues: [CalibrationIssue]
    var committedPoints: Double { issues.reduce(0) { $0 + $1.points } }
}

struct EngineerMetrics: Identifiable {
    var id: String { "\(accountId)-\(boardId)" }
    var accountId: String
    var displayName: String
    var gitlabUsername: String
    var gradeLevel: GradeLevel
    var boardId: Int
    var boardName: String
    var completedPoints: Double
    var completedIssueCount: Int
    var teamCommittedPoints: Double
    var sprintsAnalyzed: Int
    var avgCycleTimeDays: Double?
    var gradeRank: Int = 0
    var gradePercentile: Double = 0
    var gitLabActivity: GitLabActivity? = nil

    var relativeWorkload: Double {
        guard teamCommittedPoints > 0 else { return 0 }
        return completedPoints / teamCommittedPoints
    }

    var relativeWorkloadPct: String {
        String(format: "%.1f%%", relativeWorkload * 100)
    }

    var avgPointsPerSprint: Double {
        guard sprintsAnalyzed > 0 else { return 0 }
        return completedPoints / Double(sprintsAnalyzed)
    }

    var cycleTimeFormatted: String {
        guard let d = avgCycleTimeDays else { return "—" }
        return d < 1 ? String(format: "%.0fh", d * 24) : String(format: "%.1f d", d)
    }
}

struct GradeLevelSummary: Identifiable {
    var id: String { gradeLevel.rawValue }
    var gradeLevel: GradeLevel
    var engineers: [EngineerMetrics]

    var avgRelativeWorkload: Double {
        guard !engineers.isEmpty else { return 0 }
        return engineers.map(\.relativeWorkload).reduce(0, +) / Double(engineers.count)
    }

    var avgRelativeWorkloadPct: String { String(format: "%.1f%%", avgRelativeWorkload * 100) }
}

// MARK: - Computation

func computeEngineerMetrics(
    sprints: [CalibrationSprint],
    boardRef: CalibrationBoardRef,
    assignments: [EngineerAssignment]
) -> [EngineerMetrics] {
    var completedPts:  [String: Double]   = [:]
    var completedCnt:  [String: Int]      = [:]
    var cycleTimes:    [String: [Double]] = [:]
    var nameByAcct:    [String: String]   = [:]
    var teamCommitted  = 0.0

    for sprint in sprints {
        teamCommitted += sprint.committedPoints
        for issue in sprint.issues {
            guard let aid = issue.accountId else { continue }
            if let n = issue.displayName { nameByAcct[aid] = n }
            if issue.isDone {
                completedPts[aid, default: 0] += issue.points
                completedCnt[aid, default: 0] += 1
                if let ct = issue.cycleDays { cycleTimes[aid, default: []].append(ct) }
            }
        }
    }

    // Only produce metrics for engineers who are explicitly on the roster
    // and have a calibration-eligible role (not PO / BA).
    // Unrostered assignees and POs/BAs still contribute to teamCommittedPoints
    // (their work counts as "other work" in the denominator).
    return assignments.compactMap { assignment -> EngineerMetrics? in
        guard assignment.gradeLevel.isCalibrationRole else { return nil }
        let aid   = assignment.jiraAccountId
        let times = cycleTimes[aid] ?? []
        return EngineerMetrics(
            accountId: aid,
            displayName: assignment.displayName,
            gitlabUsername: assignment.gitlabUsername,
            gradeLevel: assignment.gradeLevel,
            boardId: boardRef.boardId,
            boardName: boardRef.boardName,
            completedPoints: completedPts[aid] ?? 0,
            completedIssueCount: completedCnt[aid] ?? 0,
            teamCommittedPoints: teamCommitted,
            sprintsAnalyzed: sprints.count,
            avgCycleTimeDays: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
        )
    }
}

func normalizeByGrade(_ metrics: [EngineerMetrics]) -> [GradeLevelSummary] {
    let grouped = Dictionary(grouping: metrics, by: \.gradeLevel)
    return GradeLevel.allCases.compactMap { grade in
        guard var engineers = grouped[grade], !engineers.isEmpty else { return nil }
        engineers.sort { $0.relativeWorkload > $1.relativeWorkload }
        let n = engineers.count
        for i in engineers.indices {
            engineers[i].gradeRank       = i + 1
            engineers[i].gradePercentile = n > 1 ? Double(n - 1 - i) / Double(n - 1) : 1.0
        }
        return GradeLevelSummary(gradeLevel: grade, engineers: engineers)
    }
}
