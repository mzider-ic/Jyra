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

    @State private var sprints: [JiraSprint] = []
    @State private var fields: [JiraField] = []
    @State private var isLoading = false

    // Team management
    @State private var isAddingTeam = false
    @State private var newTeamName = ""
    @State private var newTeamBoard: JiraBoard? = nil

    init(widget: Widget, dashboard: Binding<Dashboard>) {
        self.widget = widget
        self._dashboard = dashboard
        self._size = State(initialValue: widget.size)
        switch widget.config {
        case .velocity(let c):       self._velocityConfig = State(initialValue: c)
        case .burndown(let c):       self._burndownConfig = State(initialValue: c)
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
        .frame(width: 480, height: 520)
        .task { await loadSecondaryOptions() }
    }

    @ViewBuilder
    private var configFields: some View {
        switch widget.type {
        case .velocity:       velocityFields()
        case .burndown:       burndownFields()
        case .projectBurnRate: projectFields()
        }
    }

    // MARK: - Velocity

    private func velocityFields() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Board").font(.subheadline.bold())
            BoardSearchField(
                selectedBoard: boardBinding(
                    get: { velocityConfig.map { JiraBoard(id: $0.boardId, name: $0.boardName, type: "") } },
                    set: { board in
                        guard let board else { return }
                        velocityConfig = VelocityConfig(boardId: board.id, boardName: board.name)
                    }
                )
            )
        }
    }

    // MARK: - Burndown

    private func burndownFields() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Board").font(.subheadline.bold())
                BoardSearchField(
                    selectedBoard: boardBinding(
                        get: { burndownConfig.map { JiraBoard(id: $0.boardId, name: $0.boardName, type: "") } },
                        set: { board in
                            guard let board else { return }
                            if burndownConfig?.boardId != board.id {
                                burndownConfig?.boardId = board.id
                                burndownConfig?.boardName = board.name
                                Task { await loadSprints(boardId: board.id) }
                            }
                        }
                    )
                )
            }

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

            let storyFields = fields.filter {
                $0.name.localizedCaseInsensitiveContains("point") ||
                $0.name.localizedCaseInsensitiveContains("story")
            }
            if !storyFields.isEmpty {
                Picker("Points Field", selection: Binding(
                    get: { burndownConfig?.pointsField ?? "" },
                    set: { id in
                        burndownConfig?.pointsField = id
                        burndownConfig?.pointsFieldName = fields.first(where: { $0.id == id })?.name ?? id
                    }
                )) {
                    ForEach(storyFields) { field in
                        Text(field.name).tag(field.id)
                    }
                }
            }
        }
    }

    // MARK: - Project Burn Rate

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

            Divider()

            Text("Teams").font(.subheadline.bold())

            if let teams = projectConfig?.teams, !teams.isEmpty {
                teamList(teams: teams)
            }

            if isAddingTeam {
                addTeamForm
            } else {
                Button {
                    isAddingTeam = true
                    newTeamName = ""
                    newTeamBoard = nil
                } label: {
                    Label("Add Team", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func teamList(teams: [ProjectBurnRateConfig.TeamEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(teams) { team in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.name).font(.subheadline)
                        Text("Board #\(team.boardId)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        projectConfig?.teams.removeAll { $0.id == team.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                if team.id != teams.last?.id { Divider().padding(.leading, 10) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var addTeamForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Team name", text: $newTeamName)
                .textFieldStyle(.roundedBorder)
            BoardSearchField(selectedBoard: $newTeamBoard, label: "Board")
            HStack {
                Button("Cancel") { isAddingTeam = false }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Add Team") {
                    guard let board = newTeamBoard,
                          !newTeamName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    projectConfig?.teams.append(
                        ProjectBurnRateConfig.TeamEntry(boardId: board.id, name: newTeamName)
                    )
                    isAddingTeam = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTeamBoard == nil || newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    // MARK: - Helpers

    private func boardBinding(get: @escaping () -> JiraBoard?, set: @escaping (JiraBoard?) -> Void) -> Binding<JiraBoard?> {
        Binding(get: get, set: set)
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

    private func loadSecondaryOptions() async {
        guard let cfg = configService.config, case .burndown = widget.type else { return }
        isLoading = true
        defer { isLoading = false }
        fields = (try? await JiraService(config: cfg).fetchFields()) ?? []
        if let boardId = burndownConfig?.boardId {
            await loadSprints(boardId: boardId)
        }
    }

    private func loadSprints(boardId: Int) async {
        guard let cfg = configService.config else { return }
        sprints = (try? await JiraService(config: cfg).fetchSprints(boardId: boardId)) ?? []
    }
}
