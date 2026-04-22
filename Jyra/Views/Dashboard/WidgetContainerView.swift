import SwiftUI

struct WidgetContainerView: View {
    @Binding var dashboard: Dashboard
    @Environment(ConfigService.self) private var configService
    @Environment(DashboardService.self) private var dashboardService
    @State private var isAddingWidget = false
    @State private var configuringWidget: Widget? = nil

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            if dashboard.widgets.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(dashboard.widgets) { widget in
                        widgetCard(widget)
                            .gridCellColumns(widget.size == .full ? 2 : 1)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(dashboard.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingWidget = true
                } label: {
                    Label("Add Widget", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingWidget) {
            AddWidgetSheet(dashboard: $dashboard)
                .environment(configService)
                .environment(dashboardService)
        }
        .sheet(item: $configuringWidget) { widget in
            WidgetConfigView(widget: widget, dashboard: $dashboard)
                .environment(configService)
                .environment(dashboardService)
        }
    }

    @ViewBuilder
    private func widgetCard(_ widget: Widget) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(widget)
            Divider()
            widgetBody(widget)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    @ViewBuilder
    private func widgetHeader(_ widget: Widget) -> some View {
        HStack {
            Label(widget.type.displayName, systemImage: widgetIcon(widget.type))
                .font(.subheadline.bold())
            Spacer()
            Menu {
                Button("Configure…") { configuringWidget = widget }
                Divider()
                Button("Delete", role: .destructive) {
                    dashboardService.deleteWidget(widget, from: dashboard)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func widgetBody(_ widget: Widget) -> some View {
        Group {
            switch widget.config {
            case .velocity(let cfg):
                VelocityWidgetView(config: cfg)
                    .environment(configService)
            case .burndown(let cfg):
                BurndownWidgetView(config: cfg)
                    .environment(configService)
            case .projectBurnRate(let cfg):
                ProjectBurnRateWidgetView(config: cfg)
                    .environment(configService)
            }
        }
        .frame(minHeight: 260)
    }

    private func widgetIcon(_ type: WidgetType) -> String {
        switch type {
        case .velocity: return "chart.bar.fill"
        case .burndown: return "chart.line.downtrend.xyaxis"
        case .projectBurnRate: return "chart.xyaxis.line"
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Widgets", systemImage: "square.dashed")
        } description: {
            Text("Add a widget to start tracking your team's metrics.")
        } actions: {
            Button("Add Widget") { isAddingWidget = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Add widget sheet

struct AddWidgetSheet: View {
    @Binding var dashboard: Dashboard
    @Environment(ConfigService.self) private var configService
    @Environment(DashboardService.self) private var dashboardService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: WidgetType = .velocity
    @State private var size: WidgetSize = .half
    @State private var boards: [JiraBoard] = []
    @State private var selectedBoard: JiraBoard? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Widget").font(.headline)

            Picker("Type", selection: $selectedType) {
                ForEach(WidgetType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedType.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Size", selection: $size) {
                ForEach(WidgetSize.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)

            if isLoading {
                ProgressView("Loading boards…")
            } else if let err = error {
                Text(err).foregroundStyle(.red).font(.caption)
            } else if !boards.isEmpty {
                Picker("Board", selection: $selectedBoard) {
                    Text("Select a board").tag(Optional<JiraBoard>.none)
                    ForEach(boards) { board in
                        Text(board.name).tag(Optional(board))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { addWidget(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBoard == nil && selectedType != .projectBurnRate)
            }
        }
        .padding(24)
        .frame(width: 420)
        .task { await loadBoards() }
    }

    private func loadBoards() async {
        guard let cfg = configService.config else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            boards = try await JiraService(config: cfg).fetchBoards()
            selectedBoard = boards.first
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addWidget() {
        let config: WidgetConfig
        switch selectedType {
        case .velocity:
            guard let board = selectedBoard else { return }
            config = .velocity(VelocityConfig(boardId: board.id, boardName: board.name))
        case .burndown:
            guard let board = selectedBoard else { return }
            config = .burndown(BurndownConfig(boardId: board.id, boardName: board.name))
        case .projectBurnRate:
            config = .projectBurnRate(ProjectBurnRateConfig(
                projectName: "My Project",
                totalPoints: 100,
                teams: []
            ))
        }
        let widget = Widget(type: selectedType, size: size, config: config)
        dashboardService.addWidget(widget, to: dashboard)
    }
}
