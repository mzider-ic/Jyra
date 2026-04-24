import SwiftUI
import Charts

struct BurndownWidgetView: View {
    let config: BurndownConfig
    let widgetId: String
    @Environment(ConfigService.self) private var configService
    @Environment(MetricsStore.self) private var metricsStore

    @State private var result: BurndownResult? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading burndown…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                errorView(err)
            } else if let result {
                chartView(result: result)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .task(id: "\(config.boardId)-\(config.sprintId.displayValue)") {
            await load()
        }
        .onDisappear { metricsStore.clear(widgetId: widgetId) }
    }

    private func errorView(_ msg: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chartView(result: BurndownResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sprintHeader(result: result)
            Chart {
                ForEach(result.points) { point in
                    // Ideal line
                    LineMark(
                        x: .value("Day", point.label),
                        y: .value("Ideal", point.ideal),
                        series: .value("Series", "Ideal")
                    )
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Actual line
                    if let actual = point.actual {
                        LineMark(
                            x: .value("Day", point.label),
                            y: .value("Actual", actual),
                            series: .value("Series", "Actual")
                        )
                        .foregroundStyle(.indigo)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Day", point.label),
                            y: .value("Actual", actual)
                        )
                        .foregroundStyle(.indigo.opacity(0.1))
                    }

                    // Projected line
                    if let projected = point.projected {
                        LineMark(
                            x: .value("Day", point.label),
                            y: .value("Projected", projected),
                            series: .value("Series", "Projected")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { _ in
                    AxisValueLabel(orientation: .verticalReversed)
                        .font(.system(size: 9))
                }
            }
            summaryRow(result: result)
            legend
        }
    }

    private func sprintHeader(result: BurndownResult) -> some View {
        HStack {
            Text(result.sprintName)
                .font(.caption.bold())
            Spacer()
            Text("\(result.pointsFieldName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(result: BurndownResult) -> some View {
        HStack(spacing: 16) {
            stat("Total", value: result.initialPoints)
            stat("Done", value: result.completedPoints)
            stat("Left", value: result.remainingPoints)
            if let proj = result.projectedEndDate {
                Text("Finish: \(proj, style: .date)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func stat(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text("\(Int(value))").font(.system(size: 11).bold())
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .secondary.opacity(0.5), dash: true, label: "Ideal")
            legendItem(color: .indigo, dash: false, label: "Actual")
            legendItem(color: .orange, dash: true, label: "Projected")
        }
        .font(.system(size: 10))
    }

    private func legendItem(color: Color, dash: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 16, height: 2)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func publishMetrics(result: BurndownResult) {
        let pct = result.initialPoints > 0 ? (result.completedPoints / result.initialPoints) * 100 : 0
        var metrics = [
            WidgetMetric(id: "remaining", name: "Remaining", value: "\(Int(result.remainingPoints)) pts", icon: "chart.line.downtrend.xyaxis", rawValue: result.remainingPoints),
            WidgetMetric(id: "pct_complete", name: "% Complete", value: "\(Int(pct.rounded()))%", icon: "percent", rawValue: pct),
        ]
        if let proj = result.projectedEndDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            metrics.append(WidgetMetric(id: "projected_end", name: "Projected End", value: formatter.string(from: proj), icon: "calendar"))
        }
        metricsStore.publish(widgetId: widgetId, title: result.sprintName, type: .burndown, metrics: metrics)
    }

    private func load() async {
        guard let cfg = configService.config else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let r = try await JiraService(config: cfg).fetchBurndown(config: config)
            result = r
            publishMetrics(result: r)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
