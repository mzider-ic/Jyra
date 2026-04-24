import SwiftUI
import Charts

struct ProjectBurnRateWidgetView: View {
    let config: ProjectBurnRateConfig
    let widgetId: String
    @Environment(ConfigService.self) private var configService
    @Environment(MetricsStore.self) private var metricsStore

    @State private var result: BurnUpResult? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                errorView(err)
            } else if config.parentIssues.isEmpty {
                ContentUnavailableView("No scope selected", systemImage: "list.bullet.rectangle")
            } else if let result {
                if result.points.isEmpty {
                    ContentUnavailableView("No sprint assignments", systemImage: "calendar.badge.exclamationmark")
                } else {
                    chartView(result)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .task(id: taskKey) { await load() }
        .onDisappear { metricsStore.clear(widgetId: widgetId) }
    }

    // MARK: - Views

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chartView(_ result: BurnUpResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow(result)
            burnUpChart(result)
        }
    }

    private func summaryRow(_ result: BurnUpResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.projectName).font(.caption.bold())
                Text("\(Int(result.completedPoints)) / \(Int(result.totalScope)) \(config.pointsFieldName.lowercased()) complete")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let pct = result.totalScope > 0 ? Int(result.completedPoints / result.totalScope * 100) : 0
            Text("\(pct)%")
                .font(.subheadline.bold())
                .foregroundStyle(pct == 100 ? .green : .orange)
        }
    }

    @ViewBuilder
    private func burnUpChart(_ result: BurnUpResult) -> some View {
        let yMax = result.totalScope > 0 ? result.totalScope * 1.1 : 10
        Chart {
            ForEach(result.points) { point in
                // Scope line — flat at total
                LineMark(
                    x: .value("Sprint", point.label),
                    y: .value("Scope", point.totalScope),
                    series: .value("S", "Scope")
                )
                .foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))

                // Completed area fill
                AreaMark(
                    x: .value("Sprint", point.label),
                    y: .value("Completed", point.cumulativeCompleted)
                )
                .foregroundStyle(.green.opacity(point.sprintState == "future" ? 0.05 : 0.15))
                .interpolationMethod(.linear)

                // Completed line
                LineMark(
                    x: .value("Sprint", point.label),
                    y: .value("Completed", point.cumulativeCompleted),
                    series: .value("S", "Completed")
                )
                .foregroundStyle(completedColor(for: point.sprintState))
                .lineStyle(StrokeStyle(lineWidth: 2,
                                       dash: point.sprintState == "future" ? [4, 3] : []))
                .interpolationMethod(.linear)

                // Dot for active sprint
                if point.sprintState == "active" {
                    PointMark(
                        x: .value("Sprint", point.label),
                        y: .value("Completed", point.cumulativeCompleted)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(36)
                }
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(orientation: .verticalReversed).font(.system(size: 8))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legendSwatch(color: .secondary.opacity(0.6), dashed: true, label: "Scope")
                legendSwatch(color: .green, dashed: false, label: "Completed")
            }
            .font(.system(size: 9))
        }
    }

    private func legendSwatch(color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 14, height: dashed ? 1 : 2)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func completedColor(for state: String?) -> Color {
        switch state {
        case "closed": return .green
        case "active": return .green.opacity(0.7)
        default:       return .green.opacity(0.4)
        }
    }

    // MARK: - Data

    private var taskKey: String {
        config.parentIssues.map(\.key).joined(separator: ",") + "|" + config.pointsField
    }

    private func publishMetrics(result: BurnUpResult) {
        let pct = result.totalScope > 0 ? Int(result.completedPoints / result.totalScope * 100) : 0
        metricsStore.publish(
            widgetId: widgetId,
            title: config.projectName,
            type: .projectBurnRate,
            metrics: [
                WidgetMetric(id: "total_scope", name: "Total Scope", value: "\(Int(result.totalScope)) pts", icon: "chart.xyaxis.line"),
                WidgetMetric(id: "pct_complete", name: "% Complete", value: "\(pct)%", icon: "percent"),
            ]
        )
    }

    private func load() async {
        guard let cfg = configService.config, !config.parentIssues.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let r = try await JiraService(config: cfg).fetchBurnUp(config: config)
            result = r
            publishMetrics(result: r)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
