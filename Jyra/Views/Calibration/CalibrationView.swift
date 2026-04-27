import SwiftUI

struct CalibrationView: View {
    let calibration: CalibrationConfig
    @Environment(ConfigService.self)      private var configService
    @Environment(CalibrationService.self) private var calibrationService

    @State private var allMetrics:     [EngineerMetrics]    = []
    @State private var gradeSummaries: [GradeLevelSummary]  = []
    @State private var isLoading    = false
    @State private var error: String? = nil
    @State private var isConfiguring  = false
    @State private var refreshToken   = 0
    @State private var selectedTab    = CalibrationTab.engineers
    @State private var gradeFilter: GradeLevel? = nil
    @State private var sortField      = EngineerSortField.relativeWorkload

    enum CalibrationTab: String, CaseIterable {
        case engineers = "Engineers"
        case rankings  = "Grade Rankings"
    }

    enum EngineerSortField: String, CaseIterable {
        case relativeWorkload = "Relative Workload"
        case completedPoints  = "Completed Pts"
        case cycleTime        = "Cycle Time"
        case name             = "Name"
    }

    private var filteredSorted: [EngineerMetrics] {
        var m = gradeFilter == nil ? allMetrics : allMetrics.filter { $0.gradeLevel == gradeFilter }
        switch sortField {
        case .relativeWorkload: m.sort { $0.relativeWorkload > $1.relativeWorkload }
        case .completedPoints:  m.sort { $0.completedPoints  > $1.completedPoints }
        case .cycleTime:        m.sort { ($0.avgCycleTimeDays ?? .infinity) < ($1.avgCycleTimeDays ?? .infinity) }
        case .name:             m.sort { $0.displayName < $1.displayName }
        }
        return m
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading && allMetrics.isEmpty {
                ProgressView("Analyzing sprints…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error, allMetrics.isEmpty {
                errorView(err)
            } else {
                filterBar
                Divider()
                Picker("", selection: $selectedTab) {
                    ForEach(CalibrationTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch selectedTab {
                case .engineers: engineersTab
                case .rankings:  rankingsTab
                }
            }
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.09))
        .task(id: "\(calibration.id)-\(refreshToken)") { await load() }
        .sheet(isPresented: $isConfiguring) {
            CalibrationConfigView(calibration: calibration) { updated in
                if let u = updated { calibrationService.update(u) }
                isConfiguring = false
                refreshToken += 1
            }
            .environment(configService)
            .environment(calibrationService)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(calibration.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Last \(calibration.sprintCount) sprint\(calibration.sprintCount == 1 ? "" : "s")  ·  \(calibration.boards.count) board\(calibration.boards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading { ProgressView().scaleEffect(0.7) }
            Button { refreshToken += 1 } label: {
                Image(systemName: "arrow.clockwise").foregroundStyle(RuleColor.neonCyan.swiftUI)
            }
            .buttonStyle(.borderless)
            .help("Refresh calibration data")
            Button { isConfiguring = true } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Configure calibration")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.07, green: 0.07, blue: 0.11))
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 16) {
            Text("Grade:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Picker("Grade", selection: $gradeFilter) {
                Text("All").tag(GradeLevel?.none)
                ForEach(GradeLevel.allCases, id: \.self) { g in
                    Text(g.shortName).tag(GradeLevel?.some(g))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()

            Text("Sort:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $sortField) {
                ForEach(EngineerSortField.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.11))
    }

    // MARK: - Engineers tab

    private var engineersTab: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredSorted.isEmpty {
                    Text(allMetrics.isEmpty ? "No data — configure boards and discover engineers." : "No engineers match the current filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(32)
                } else {
                    ForEach(filteredSorted) { metrics in
                        EngineerMetricsCard(metrics: metrics) {
                            removeEngineer(accountId: metrics.accountId)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Rankings tab

    private var rankingsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                let summaries = gradeSummaries.filter {
                    gradeFilter == nil || $0.gradeLevel == gradeFilter
                }
                if summaries.isEmpty {
                    Text("No data yet — configure boards and discover engineers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(32)
                } else {
                    ForEach(summaries) { summary in
                        GradeLevelRankingSection(summary: summary)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                .foregroundStyle(RuleColor.neonOrange.swiftUI)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { refreshToken += 1 }.buttonStyle(.borderless)
                .foregroundStyle(RuleColor.neonCyan.swiftUI)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Roster removal

    private func removeEngineer(accountId: String) {
        allMetrics.removeAll     { $0.accountId == accountId }
        gradeSummaries = normalizeByGrade(allMetrics)
        var updated = calibration
        updated.engineers.removeAll { $0.jiraAccountId == accountId }
        calibrationService.update(updated)
    }

    // MARK: - Load

    private func load() async {
        guard let cfg = configService.config else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            var collected: [EngineerMetrics] = []
            for boardRef in calibration.boards {
                let svc = JiraService(config: cfg)
                let pf: String
                if !boardRef.pointsField.isEmpty {
                    pf = boardRef.pointsField
                } else {
                    let fields = (try? await svc.fetchFields()) ?? []
                    pf = fields.first(where: {
                        $0.name == "Story Points"
                        || $0.name.localizedCaseInsensitiveContains("story point")
                    })?.id
                    ?? fields.first(where: { $0.name.localizedCaseInsensitiveContains("point") })?.id
                    ?? "story_points"
                }
                let sprints = try await svc.fetchCalibrationSprints(
                    boardId: boardRef.boardId,
                    sprintCount: calibration.sprintCount,
                    pointsField: pf
                )
                let m = computeEngineerMetrics(sprints: sprints, boardRef: boardRef, assignments: calibration.engineers)
                collected.append(contentsOf: m)
            }
            allMetrics     = collected
            gradeSummaries = normalizeByGrade(collected)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Engineer card

private struct EngineerMetricsCard: View {
    let metrics: EngineerMetrics
    var onRemove: () -> Void = {}

    private var workloadColor: Color {
        switch metrics.relativeWorkload {
        case ..<0.10: return RuleColor.neonOrange.swiftUI
        case ..<0.20: return RuleColor.neonCyan.swiftUI
        default:      return RuleColor.neonGreen.swiftUI
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Text(metrics.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                gradeBadge
                Spacer()
                Text(metrics.boardName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Relative workload bar
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metrics.relativeWorkloadPct)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(workloadColor)
                    Text("relative workload")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if metrics.gradeRank > 0 {
                        Text("#\(metrics.gradeRank) in \(metrics.gradeLevel.shortName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(metrics.gradeLevel.neonColor.opacity(0.8))
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(workloadColor.opacity(0.7))
                            .frame(width: geo.size.width * min(metrics.relativeWorkload * 3, 1.0))
                    }
                }
                .frame(height: 4)
            }

            // Metric cells
            HStack(spacing: 8) {
                metricCell("Avg Pts/Sprint", value: String(format: "%.1f pts", metrics.avgPointsPerSprint))
                metricCell("Total Completed", value: String(format: "%.0f pts", metrics.completedPoints))
                metricCell("Team Committed", value: String(format: "%.0f pts", metrics.teamCommittedPoints))
                metricCell("Stories Done", value: "\(metrics.completedIssueCount)")
                metricCell("Avg Cycle", value: metrics.cycleTimeFormatted)
                metricCell("Sprints", value: "\(metrics.sprintsAnalyzed)")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(metrics.gradeLevel.neonColor.opacity(0.15), lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove from Roster", systemImage: "person.fill.xmark")
            }
        }
    }

    private var gradeBadge: some View {
        Text(metrics.gradeLevel.shortName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(metrics.gradeLevel.neonColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(metrics.gradeLevel.neonColor.opacity(0.4), lineWidth: 1))
            .foregroundStyle(metrics.gradeLevel.neonColor)
    }

    private func metricCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Grade level ranking section

private struct GradeLevelRankingSection: View {
    let summary: GradeLevelSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(summary.gradeLevel.neonColor)
                    .frame(width: 3, height: 16)
                    .shadow(color: summary.gradeLevel.neonColor.opacity(0.6), radius: 4)
                Text(summary.gradeLevel.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(summary.gradeLevel.neonColor)
                    .tracking(1.2)
                Text("avg \(summary.avgRelativeWorkloadPct)")
                    .font(.system(size: 11))
                    .foregroundStyle(summary.gradeLevel.neonColor.opacity(0.6))
                Spacer()
                Text("\(summary.engineers.count) engineer\(summary.engineers.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(summary.gradeLevel.neonColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Ranked engineer rows
            ForEach(summary.engineers) { eng in
                RankingRow(metrics: eng, maxWorkload: summary.engineers.first?.relativeWorkload ?? 1)
            }
        }
    }
}

private struct RankingRow: View {
    let metrics: EngineerMetrics
    let maxWorkload: Double

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(metrics.gradeLevel.neonColor.opacity(metrics.gradeRank == 1 ? 0.25 : 0.08))
                    .frame(width: 32, height: 32)
                Text("#\(metrics.gradeRank)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(metrics.gradeLevel.neonColor)
            }

            // Name + board
            VStack(alignment: .leading, spacing: 2) {
                Text(metrics.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(metrics.boardName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 130, alignment: .leading)

            // Workload bar + pct
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(metrics.gradeLevel.neonColor.opacity(0.65))
                            .frame(width: geo.size.width * (maxWorkload > 0 ? metrics.relativeWorkload / maxWorkload : 0))
                    }
                }
                .frame(height: 5)
                Text(metrics.relativeWorkloadPct)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(metrics.gradeLevel.neonColor)
            }
            .frame(minWidth: 120)

            Spacer()

            // Secondary metrics
            HStack(spacing: 16) {
                labeledValue("avg pts", value: String(format: "%.1f", metrics.avgPointsPerSprint))
                labeledValue("total", value: String(format: "%.0f", metrics.completedPoints))
                labeledValue("cycle", value: metrics.cycleTimeFormatted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(metrics.gradeLevel.neonColor.opacity(0.1), lineWidth: 1))
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
