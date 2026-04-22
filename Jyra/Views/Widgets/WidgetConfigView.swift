import SwiftUI

struct WidgetConfigView: View {
    let widget: Widget
    @Binding var dashboard: Dashboard
    @Environment(ConfigService.self) private var configService
    @Environment(DashboardService.self) private var dashboardService
    @Environment(\.dismiss) private var dismiss

    @State private var size: WidgetSize
    @State private var velocityConfig: VelocityConfig?
    @State private var burndownConfig: BurndownConfig?
    @State private var projectConfig: ProjectBurnRateConfig?

    @State private var boards: [JiraBoard] = []
    @State private var sprints: [JiraSprint] = []
    @State private var fields: [JiraField] = []
    @State private var isLoading = false

    init(widget: Widget, dashboard: Binding<Dashboard>) {
        self.widget = widget
        self._dashboard = dashboard
        self._size = State(initialValue: widget.size)
        switch widget.config {
        case .velocity(let c): self._velocityConfig = State(initialValue: c)
        case .burndown(let c): self._burndownConfig = State(initialValue: c)
        case .projectBurnRate(let c): self._projectConfig = State(initialValue: c)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure Widget").font(.headline)

            Picker("Size", selection: $size) {
                ForEach(WidgetSize.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)

            if isLoading {
                ProgressView("Loading…")
            } else {
                configFields
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
        .task { await loadOptions() }
    }

    @ViewBuilder
    private var configFields: some View {
        switch widget.type {
        case .velocity:
            if velocityConfig != nil {
                velocityFields()
            }
        case .burndown:
            if burndownConfig != nil {
                burndownFields()
            }
        case .projectBurnRate:
            if projectConfig != nil {
                projectFields()
            }
        }
    }

    private func velocityFields() -> some View {
        boardPicker(selectedBoardId: Binding(
            get: { velocityConfig?.boardId ?? 0 },
            set: { id in
                if let board = boards.first(where: { $0.id == id }) {
                    velocityConfig = VelocityConfig(boardId: board.id, boardName: board.name)
                }
            }
        ))
    }

    private func burndownFields() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            boardPicker(selectedBoardId: Binding(
                get: { burndownConfig?.boardId ?? 0 },
                set: { id in
                    if let board = boards.first(where: { $0.id == id }) {
                        burndownConfig?.boardId = board.id
                        burndownConfig?.boardName = board.name
                        Task { await loadSprints(boardId: board.id) }
                    }
                }
            ))

            Picker("Sprint", selection: Binding(
                get: { burndownConfig?.sprintId.displayValue ?? "active" },
                set: { val in
                    if val == "active" {
                        burndownConfig?.sprintId = .active
                        burndownConfig?.sprintName = "Active sprint"
                    } else if let id = Int(val) {
                        burndownConfig?.sprintId = .specific(id)
                        burndownConfig?.sprintName = sprints.first(where: { $0.id == id })?.name ?? val
                    }
                }
            )) {
                Text("Active Sprint").tag("active")
                ForEach(sprints) { sprint in
                    Text(sprint.name).tag("\(sprint.id)")
                }
            }

            pointsFieldPicker(selectedField: Binding(
                get: { burndownConfig?.pointsField ?? "" },
                set: { id in
                    burndownConfig?.pointsField = id
                    burndownConfig?.pointsFieldName = fields.first(where: { $0.id == id })?.name ?? id
                }
            ))
        }
    }

    private func projectFields() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Project Name", text: Binding(
                get: { projectConfig?.projectName ?? "" },
                set: { projectConfig?.projectName = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Text("Total Points")
                TextField("e.g. 500", value: Binding(
                    get: { projectConfig?.totalPoints ?? 0 },
                    set: { projectConfig?.totalPoints = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            }

            Text("Teams: \(projectConfig?.teams.count ?? 0) configured")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Add teams by editing widget configuration in future updates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func boardPicker(selectedBoardId: Binding<Int>) -> some View {
        Picker("Board", selection: selectedBoardId) {
            ForEach(boards) { board in
                Text(board.name).tag(board.id)
            }
        }
    }

    private func pointsFieldPicker(selectedField: Binding<String>) -> some View {
        let storyFields = fields.filter { $0.name.localizedCaseInsensitiveContains("point") || $0.name.localizedCaseInsensitiveContains("story") }
        return Picker("Points Field", selection: selectedField) {
            ForEach(storyFields) { field in
                Text(field.name).tag(field.id)
            }
        }
    }

    private func save() {
        var updated = widget
        updated.size = size
        switch widget.type {
        case .velocity:
            if let cfg = velocityConfig { updated.config = .velocity(cfg) }
        case .burndown:
            if let cfg = burndownConfig { updated.config = .burndown(cfg) }
        case .projectBurnRate:
            if let cfg = projectConfig { updated.config = .projectBurnRate(cfg) }
        }
        dashboardService.updateWidget(updated, in: dashboard)
    }

    private func loadOptions() async {
        guard let cfg = configService.config else { return }
        isLoading = true
        defer { isLoading = false }
        let service = JiraService(config: cfg)
        async let b = service.fetchBoards()
        async let f = service.fetchFields()
        boards = (try? await b) ?? []
        fields = (try? await f) ?? []

        let boardId: Int?
        switch widget.config {
        case .velocity(let c): boardId = c.boardId
        case .burndown(let c): boardId = c.boardId
        case .projectBurnRate: boardId = nil
        }
        if let bid = boardId {
            await loadSprints(boardId: bid)
        }
    }

    private func loadSprints(boardId: Int) async {
        guard let cfg = configService.config else { return }
        sprints = (try? await JiraService(config: cfg).fetchSprints(boardId: boardId)) ?? []
    }
}
