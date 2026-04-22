import SwiftUI
import Charts

struct ProjectBurnRateWidgetView: View {
    let config: ProjectBurnRateConfig
    @Environment(ConfigService.self) private var configService

    @State private var result: ProjectBurnResult? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading project data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                errorView(err)
            } else if let result {
                chartView(result: result)
            } else if config.teams.isEmpty {
                ContentUnavailableView("No teams configured", systemImage: "person.3")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .task(id: config.projectName) { await load() }
    }

    private func errorView(_ msg: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chartView(result: ProjectBurnResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(result: result)
            Chart {
                ForEach(result.points) { point in
                    if let remaining = point.remaining {
                        AreaMark(
                            x: .value("Sprint", point.label),
                            y: .value("Remaining", remaining)
                        )
                        .foregroundStyle(.indigo.opacity(0.2))
                        LineMark(
                            x: .value("Sprint", point.label),
                            y: .value("Remaining", remaining),
                            series: .value("Series", "Actual")
                        )
                        .foregroundStyle(.indigo)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let projected = point.projected {
                        LineMark(
                            x: .value("Sprint", point.label),
                            y: .value("Projected", projected),
                            series: .value("Series", "Projected")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(orientation: .verticalReversed).font(.system(size: 9))
                }
            }
            teamList(result: result)
        }
    }

    private func header(result: ProjectBurnResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.projectName).font(.caption.bold())
                Text("\(Int(result.totalPoints)) total pts").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(result.sprintsRemaining) sprints left")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("Combined vel: \(Int(result.combinedVelocity)) pts/sprint")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func teamList(result: ProjectBurnResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(result.teams) { team in
                HStack {
                    Text(team.name).font(.system(size: 10))
                    Spacer()
                    Text("avg \(Int(team.avgVelocity)) pts")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func load() async {
        guard let cfg = configService.config, !config.teams.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            result = try await JiraService(config: cfg).fetchProjectBurnRate(config: config)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
