import SwiftUI

struct BoardCardDetailView: View {
    let issue: BoardIssue
    let jiraBaseURL: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                metadataGrid
                if let desc = issue.description, !desc.isEmpty {
                    descriptionSection(desc)
                }
                if !issue.labels.isEmpty {
                    labelsSection
                }
                if let parent = issue.parentKey {
                    parentSection(key: parent, summary: issue.parentSummary)
                }
                timingSection
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(issue.key)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(RuleColor.neonCyan.swiftUI)
                if let type = issue.issueTypeName {
                    Text(type)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
                if issue.isBlocked {
                    Label("BLOCKED", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(RuleColor.neonRed.swiftUI)
                }
                Spacer()
                if !jiraBaseURL.isEmpty, let url = URL(string: "\(jiraBaseURL)/browse/\(issue.key)") {
                    Link(destination: url) {
                        Label("Open in Jira", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
            Text(issue.summary)
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
    }

    // MARK: - Metadata grid

    private var metadataGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
            metaCell("Status", value: issue.statusName,
                     color: statusColor(issue.statusCategoryKey))
            if let priority = issue.priorityName {
                metaCell("Priority", value: priority,
                         color: priorityColor(priority))
            }
            if issue.storyPoints != nil {
                metaCell("Points", value: issue.pointsText,
                         color: RuleColor.neonGreen.swiftUI)
            }
            if let assignee = issue.assigneeName {
                metaCell("Assignee", value: assignee, color: .secondary)
            }
            metaCell("Hours in Status", value: String(format: "%.1f h", issue.hoursInStatus),
                     color: issue.hoursInStatus > 48 ? RuleColor.neonOrange.swiftUI : .secondary)
        }
    }

    private func metaCell(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Description

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Description")
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Labels

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Labels")
            FlowLayout(spacing: 6) {
                ForEach(issue.labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(labelColor(label).opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(labelColor(label).opacity(0.5), lineWidth: 1))
                        )
                        .foregroundStyle(labelColor(label))
                }
            }
        }
    }

    // MARK: - Parent

    private func parentSection(key: String, summary: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Parent")
            HStack(spacing: 8) {
                Text(key)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(RuleColor.neonCyan.swiftUI)
                if let sum = summary {
                    Text(sum)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        HStack(spacing: 20) {
            if let created = issue.created {
                timingCell("Created", date: created)
            }
            if let updated = issue.updated {
                timingCell("Last Updated", date: updated)
            }
        }
    }

    private func timingCell(_ label: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(date, style: .date)
                .font(.system(size: 12))
            Text(date, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(1)
    }

    private func statusColor(_ categoryKey: String) -> Color {
        switch categoryKey {
        case "new":           return RuleColor.neonCyan.swiftUI
        case "indeterminate": return RuleColor.neonPurple.swiftUI
        case "done":          return RuleColor.neonGreen.swiftUI
        default:              return .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "critical", "highest": return RuleColor.neonRed.swiftUI
        case "high":                return RuleColor.neonOrange.swiftUI
        case "low", "lowest":       return RuleColor.neonCyan.swiftUI
        default:                    return .secondary
        }
    }

    private func labelColor(_ label: String) -> Color {
        switch label.lowercased() {
        case "blocked", "impediment": return RuleColor.neonRed.swiftUI
        case "backend":               return RuleColor.neonPurple.swiftUI
        case "frontend":              return RuleColor.neonCyan.swiftUI
        case "urgent":                return RuleColor.neonOrange.swiftUI
        default:                      return RuleColor.neonYellow.swiftUI
        }
    }
}

// MARK: - Simple flow layout for labels

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
