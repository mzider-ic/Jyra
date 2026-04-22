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
        VStack(alignment: .leading, spacing: 8) {
            avgLine(entries: entries)
            Chart {
                ForEach(entries) { e in
                    BarMark(x: .value("Sprint", e.sprintName), y: .value("Points", e.committed))
                        .foregroundStyle(Color.indigo.opacity(0.5))
                        .annotation(position: .top) {
                            if e.committed > 0 {
                                Text("\(Int(e.committed))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    BarMark(x: .value("Sprint", e.sprintName), y: .value("Points", e.completed))
                        .foregroundStyle(Color.mint)
                }

                let avg = average(entries: entries)
                RuleMark(y: .value("Avg", avg))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(Int(avg))")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(orientation: .verticalReversed)
                        .font(.system(size: 9))
                }
            }
            legend
        }
    }

    private func avgLine(entries: [VelocityEntry]) -> some View {
        let avg = average(entries: entries)
        return HStack {
            Text("Last \(entries.count) sprints")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Avg: \(Int(avg)) pts")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .indigo.opacity(0.5), label: "Committed")
            legendItem(color: .mint, label: "Completed")
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

    private var expandedSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(config.boardName) — Velocity")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { showExpanded = false }
            }
            chartView(entries: Array(entries.suffix(12)))
                .frame(minHeight: 400)
        }
        .padding(24)
        .frame(width: 700, height: 520)
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
