import SwiftUI
import Charts

// MARK: - Widget view (data loading, navigation)

struct VelocityWidgetView: View {
    let config: VelocityConfig
    let widgetId: String
    @Environment(ConfigService.self) private var configService
    @Environment(MetricsStore.self) private var metricsStore

    @State private var entries: [VelocityEntry] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var showExpanded = false

    private let displayCount = 6

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading velocity…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                    Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }.font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView("No data", systemImage: "chart.bar")
            } else {
                VelocityChartContent(entries: displayEntries, palette: palette)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .task { await load() }
        .onDisappear { metricsStore.clear(widgetId: widgetId) }
        .onTapGesture { if !entries.isEmpty { showExpanded = true } }
        .sheet(isPresented: $showExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(config.displayTitle) — Velocity").font(.title3.bold())
                    Spacer()
                    Button("Done") { showExpanded = false }
                }
                // Fresh struct instance → own @State → positions never contaminate compact view
                VelocityChartContent(entries: expandedEntries, palette: palette)
                    .frame(minHeight: 700)
            }
            .padding(24)
            .frame(width: 760, height: 820)
        }
    }

    // MARK: - Ordering / Filtering

    private var displayEntries: [VelocityEntry] {
        Array(orderedDisplayEntries.prefix(displayCount))
    }

    private var expandedEntries: [VelocityEntry] {
        Array(orderedDisplayEntries.prefix(12))
    }

    private var orderedDisplayEntries: [VelocityEntry] {
        let activeEntries = entries.filter(\.isActive)
        let historicalEntries = entries
            .filter { !$0.isActive && ($0.committed > 0 || $0.completed > 0) }
            .sorted { lhs, rhs in
                if velocityDisplayDate(for: lhs) == velocityDisplayDate(for: rhs) {
                    return lhs.id > rhs.id
                }
                return velocityDisplayDate(for: lhs) > velocityDisplayDate(for: rhs)
            }
        return historicalEntries.reversed() + activeEntries
    }

    private func velocityDisplayDate(for entry: VelocityEntry) -> Date {
        entry.completeDate ?? entry.endDate ?? entry.startDate ?? .distantPast
    }

    private var palette: VelocityPalette {
        config.paletteOverride ?? configService.config?.velocityPalette ?? .default
    }

    // MARK: - Load

    private func publishMetrics() {
        let eligible = entries.filter { !$0.isActive && $0.committed > 0 }
        let avgVelocity: Double = eligible.isEmpty ? 0 : eligible.map(\.completed).reduce(0, +) / Double(eligible.count)
        let avgCompletion: Double = eligible.isEmpty ? 0 : eligible.map { e in
            min(100, max(0, (e.completed / e.committed) * 100))
        }.reduce(0, +) / Double(eligible.count)
        metricsStore.publish(
            widgetId: widgetId,
            title: config.displayTitle,
            type: .velocity,
            metrics: [
                WidgetMetric(id: "avg_velocity", name: "Avg Velocity", value: "\(Int(avgVelocity.rounded())) pts", icon: "chart.bar.fill", rawValue: avgVelocity),
                WidgetMetric(id: "avg_completion", name: "Avg Completion", value: "\(Int(avgCompletion.rounded()))%", icon: "percent", rawValue: avgCompletion),
            ]
        )
    }

    private func load() async {
        guard let cfg = configService.config else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await JiraService(config: cfg).fetchVelocityEntries(boardId: config.boardId)
            publishMetrics()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Chart content
// A standalone View so each instance (compact / expanded) has completely isolated @State.
// The expanded sheet creates a fresh VelocityChartContent, so label positions, hover state,
// and slot width can never bleed across the two chart instances.

private struct VelocityChartContent: View {
    let entries: [VelocityEntry]
    let palette: VelocityPalette

    @State private var labelXPositions: [String: CGFloat] = [:]
    @State private var labelSlotWidth: CGFloat = 48
    @State private var hoveredSprint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryRow

            HStack(alignment: .top, spacing: 0) {
                ZStack {
                    pointsChart
                    completionChart
                }
                completionPercentAxis
            }
            .frame(minHeight: 270)
            .padding(.top, 12)

            sprintLabelRowAligned
            legend
        }
    }

    // MARK: - Summary / Legend

    private var summaryRow: some View {
        let eligible = eligibleCompletionEntries
        let avg = averageVelocity(entries: entries)
        let avgCompletion = averageCompletion(entries: eligible)
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
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 17, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Eligibility & Calculations

    private var eligibleCompletionEntries: [VelocityEntry] {
        entries.filter { !$0.isActive && $0.committed > 0 }
    }

    private func averageVelocity(entries: [VelocityEntry]) -> Double {
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

    // MARK: - Shared Plot Style

    private func basePlotStyle(_ plot: some View) -> some View {
        plot
            .padding(.top, 10)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.32), Color.black.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Percent Axis (outside dark background)

    private var completionPercentAxis: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 22)
            Text("100%").font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Text("75%").font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Text("50%").font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Text("25%").font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Text("0%").font(.system(size: 9)).foregroundStyle(.secondary)
            Color.clear.frame(height: 4)
        }
        .padding(.leading, 6)
        .frame(width: 42)
    }

    // MARK: - Points Chart (Bar + Avg + hover)

    private var pointsChart: some View {
        let eligible = eligibleCompletionEntries
        let avg = averageVelocity(entries: eligible)
        let paddedDomain = ["__pad_l__"] + entries.map(\.sprintName) + ["__pad_r__"]

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
                .annotation(position: .overlay, alignment: .center) {
                    if entry.committed >= 1 {
                        Text("\(Int(entry.committed.rounded()))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                    }
                }
                .annotation(position: .top) {
                    if entry.isActive { activeSprintBadge }
                }

                BarMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Completed", entry.completed)
                )
                .position(by: .value("Series", "Completed"))
                .foregroundStyle(palette.completedColor.gradient)
                .cornerRadius(4)
                .annotation(position: .overlay, alignment: .center) {
                    if entry.completed >= 1 {
                        Text("\(Int(entry.completed.rounded()))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
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

            if let hovered = hoveredSprint {
                RuleMark(x: .value("Sprint", hovered))
                    .foregroundStyle(.white.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: paddedDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(.white.opacity(0.12))
                AxisTick()
                AxisValueLabel {
                    if let pts = value.as(Double.self) {
                        Text("\(Int(pts.rounded()))").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Story Points").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { plot in basePlotStyle(plot) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            refreshLabelPositions(proxy: proxy, geo: geo)
                        }
                    }
                    .onChange(of: entries) {
                        refreshLabelPositions(proxy: proxy, geo: geo)
                    }
                    .onChange(of: geo.size) {
                        refreshLabelPositions(proxy: proxy, geo: geo)
                    }

                Rectangle()
                    .fill(.white.opacity(0.001))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let plotFrame = proxy.plotFrame {
                                let frame = geo[plotFrame]
                                let relX = location.x - frame.minX
                                hoveredSprint = entries.min(by: { a, b in
                                    let ax = proxy.position(forX: a.sprintName) ?? .infinity
                                    let bx = proxy.position(forX: b.sprintName) ?? .infinity
                                    return abs(ax - relX) < abs(bx - relX)
                                })?.sprintName
                            }
                        case .ended:
                            hoveredSprint = nil
                        }
                    }
            }
        }
    }

    private func refreshLabelPositions(proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        var pos: [String: CGFloat] = [:]
        var xs: [CGFloat] = []
        for entry in entries {
            if let x = proxy.position(forX: entry.sprintName) {
                pos[entry.sprintName] = frame.minX + x
                xs.append(x)
            }
        }
        labelXPositions = pos
        if xs.count >= 2 {
            labelSlotWidth = (xs[1] - xs[0]) * 0.9
        }
    }

    // MARK: - Completion Chart (line overlay, no axes)

    private var completionChart: some View {
        let eligible = eligibleCompletionEntries
        let paddedDomain = ["__pad_l__"] + entries.map(\.sprintName) + ["__pad_r__"]

        return Chart {
            ForEach(eligible) { entry in
                LineMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Percent Complete", completionPercent(for: entry))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.completionColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                let pct = completionPercent(for: entry)
                PointMark(
                    x: .value("Sprint", entry.sprintName),
                    y: .value("Percent Complete", pct)
                )
                .foregroundStyle(palette.completionColor)
                .symbolSize(35)
                .annotation(position: pct > 80 ? .bottom : .top, alignment: .center) {
                    if entry.sprintName == hoveredSprint {
                        Text("\(Int(pct.rounded()))%")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(palette.completionColor)
                    }
                }
            }
        }
        .chartXScale(domain: paddedDomain)
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.top, 10).background(.clear)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Labels Row

    private var sprintLabelRowAligned: some View {
        GeometryReader { geo in
            ForEach(entries) { entry in
                if let x = labelXPositions[entry.sprintName] {
                    Text(shortSprintLabel(entry.sprintName))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .multilineTextAlignment(.center)
                        .frame(minWidth: labelSlotWidth, alignment: .center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.62)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
                        .position(x: x, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 36)
        .zIndex(1)
    }

    // MARK: - Palette / Badge

    private var activeSprintBadge: some View {
        Text("Active")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(palette.completionColor.opacity(0.18)))
            .overlay(Capsule().stroke(palette.completionColor.opacity(0.6), lineWidth: 1))
            .foregroundStyle(palette.completionColor)
    }

    private func shortSprintLabel(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        if words.count <= 2 { return trimmed.replacingOccurrences(of: " ", with: "\n") }
        if words.count == 3 { return "\(words[1])\n\(words[2])" }
        return "\(words[words.count - 2])\n\(words[words.count - 1])"
    }
}
