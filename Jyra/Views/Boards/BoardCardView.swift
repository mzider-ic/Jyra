import SwiftUI

struct BoardCardView: View {
    let issue: BoardIssue
    let rules: [BoardMetricRule]
    var onTap: () -> Void = {}

    private var borderColor: Color? { issue.cardBorderColor(rules: rules) }
    private var isHighlighted: Bool { borderColor != nil }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                topRow
                if issue.isBlocked { blockedBadge }
                summaryText
                bottomRow
                if let priority = issue.priorityName {
                    priorityLabel(priority)
                }
            }
            .padding(10)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var topRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(issue.key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if let type = issue.issueTypeName {
                Text(type)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var blockedBadge: some View {
        Label("BLOCKED", systemImage: "exclamationmark.octagon.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(RuleColor.neonRed.swiftUI)
    }

    private var summaryText: some View {
        Text(issue.summary)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if !issue.pointsText.isEmpty {
                pointsBadge
            }
            Spacer()
            if !issue.assigneeInitials.isEmpty {
                assigneeAvatar
            }
        }
    }

    private var pointsBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 7))
            Text(issue.pointsText)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(RuleColor.neonGreen.swiftUI)
    }

    private var assigneeAvatar: some View {
        Text(issue.assigneeInitials)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.25))
                    .overlay(Circle().stroke(RuleColor.neonCyan.swiftUI.opacity(0.5), lineWidth: 1))
            )
    }

    private func priorityLabel(_ priority: String) -> some View {
        let color = priorityColor(priority)
        return Text(priority.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Background

    private var cardBackground: some View {
        let border = borderColor ?? Color.white.opacity(0.06)
        let glow   = borderColor?.opacity(0.3) ?? .clear
        return RoundedRectangle(cornerRadius: 8)
            .fill(Color(red: 0.08, green: 0.08, blue: 0.13))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: isHighlighted ? 1.5 : 1))
            .shadow(color: glow, radius: isHighlighted ? 6 : 0)
    }

    // MARK: - Helpers

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "critical", "highest": return RuleColor.neonRed.swiftUI
        case "high":                return RuleColor.neonOrange.swiftUI
        case "low", "lowest":       return RuleColor.neonCyan.swiftUI
        default:                    return .secondary
        }
    }
}
