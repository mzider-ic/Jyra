import SwiftUI
import Charts

struct VelocityWidgetView: View {
    let config: VelocityConfig
    @Environment(ConfigService.self) private var configService

    @State private var entries: [VelocityEntry] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var showExpanded = false

    private let displayCount = 6

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let err = error {
                errorView(err)
            } else if entries.isEmpty {
                emptyView
            } else {
                chartView(entries: Array(entries.suffix(displayCount)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .task { await load() }
        .onTapGesture { if !entries.isEmpty { showExpanded = true } }
        .sheet(isPresented: $showExpanded) {
            expandedSheet
        }
    }

    private var loadingView: some View {
        ProgressView("Loading velocity…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView("No data", systemImage: "chart.bar")
    }

    private func chartView(entries: [VelocityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryRow(entries: entries)

            ZStack {
                pointsChart(entries: entries)
                completionChart(entries: entries)
            }
            .frame(minHeight: 270)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            legend
        }
    }

    private func summaryRow(entries: [VelocityEntry]) -> some View {
        let avg = average(entries: entries)
        let avgCompletion = averageCompletion(entries: entries)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last \(entries.count) sprints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Avg completion: \(Int(avgCompletion.rounded()))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Avg velocity: \(Int(avg)) pts")
                .font(.caption.bold())
                .foregroundStyle(palette.averageColor)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: palette.committedColor.opacity(0.85), label: "Committed")
            legendItem(color: palette.completedColor, label: "Completed")
            legendItem(color: palette.completionColor, label: "% Complete")
            legendItem(color: palette.averageColor, label: "Avg Velocity")
        }
        .font(.system(size: 10))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func average(entries: [VelocityEntry]) -> Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map(\.completed).reduce(0, +) / Double(entries.count)
    }

    private func averageCompletion(entries: [VelocityEntry]) -> Double {
        guard !entries.isEmpty else { return 0 }
        let percents = entries.map(completionPercent(for:))
        return percents.reduce(0, +) / Double(percents.count)
    }

    private func completionPercent(for entry: VelocityEntry) -> Double {
        guard entry.committed > 0 else { return 0 }
        return min(100, max(0, (entry.completed / entry.committed) * 100))
    }

    private func pointsChart(entries: [VelocityEntry]) -> some View {
        let avg = average(entries: entries)
        let sprintDomain = entries.map(\.sprintName)

        return Chart {
            ForEach(entries) { entry in
                BarMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Committed", entry.committed)
                )
                .position(by: .value("Series", "Committed"))
                .foregroundStyle(palette.committedColor.gradient)
                .cornerRadius(4)
                .opacity(0.85)

                BarMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Completed", entry.completed)
                )
                .position(by: .value("Series", "Completed"))
                .foregroundStyle(palette.completedColor.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    if entry.isActive {
                        activeSprintBadge
                    }
                }
            }

            RuleMark(y: .value("Average", avg))
                .foregroundStyle(palette.averageColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("avg \(Int(avg.rounded()))")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.averageColor)
                }
        }
        .chartXScale(domain: sprintDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(.white.opacity(0.12))
                AxisTick()
                AxisValueLabel {
                    if let points = value.as(Double.self) {
                        Text("\(Int(points.rounded()))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Story Points")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let sprint = value.as(String.self) {
                        Text(shortSprintLabel(sprint))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.white.opacity(0.015)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private func completionChart(entries: [VelocityEntry]) -> some View {
        let sprintDomain = entries.map(\.sprintName)

        return Chart {
            ForEach(entries) { entry in
                LineMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Percent Complete", completionPercent(for: entry))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.completionColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Percent Complete", completionPercent(for: entry))
                )
                .foregroundStyle(palette.completionColor)
                .symbolSize(35)
            }
        }
        .chartXScale(domain: sprintDomain)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                AxisTick()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                            .foregroundStyle(.secondary)
                    } else if let percent = value.as(Double.self) {
                        Text("\(Int(percent.rounded()))%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            Text("Percent Complete")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
        .allowsHitTesting(false)
    }

    private var palette: VelocityPalette {
        config.paletteOverride ?? configService.config?.velocityPalette ?? .default
    }

    private var activeSprintBadge: some View {
        Text("Active")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(palette.completionColor.opacity(0.18))
            )
            .overlay(
                Capsule()
                    .stroke(palette.completionColor.opacity(0.6), lineWidth: 1)
            )
            .foregroundStyle(palette.completionColor)
    }

    private func shortSprintLabel(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        if words.count <= 2 { return trimmed }
        return words.suffix(2).joined(separator: " ")
    }

    private var expandedSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(config.displayTitle) — Velocity")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { showExpanded = false }
            }
            chartView(entries: Array(entries.suffix(12)))
                .frame(minHeight: 500)
        }
        .padding(24)
        .frame(width: 760, height: 620)
    }

    private func load() async {
        guard let cfg = configService.config else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await JiraService(config: cfg).fetchVelocityEntries(boardId: config.boardId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
