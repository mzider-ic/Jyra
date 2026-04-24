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
        VStack(alignment: .leading, spacing: 12) {
            Text("Board").font(.subheadline.bold())
            BoardSearchField(
                selectedBoard: boardBinding(
                    get: { velocityConfig.map { JiraBoard(id: $0.boardId, name: $0.boardName, type: "") } },
                    set: { board in
                        guard let board else { return }
                        let currentTitle = velocityConfig?.title ?? ""
                        velocityConfig = VelocityConfig(boardId: board.id, boardName: board.name, title: currentTitle)
                    }
                )
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.subheadline.bold())
                TextField("Defaults to board name", text: Binding(
                    get: { velocityConfig?.title ?? "" },
                    set: { velocityConfig?.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Toggle("Use custom colors", isOn: Binding(
                get: { velocityConfig?.paletteOverride != nil },
                set: { isEnabled in
                    guard let current = velocityConfig else { return }
                    velocityConfig?.paletteOverride = isEnabled ? (current.paletteOverride ?? .default) : nil
                }
            ))

            if velocityConfig?.paletteOverride != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Widget Colors").font(.subheadline.bold())
                    ColorPicker("Committed", selection: velocityPaletteBinding(\.committedHex))
                    ColorPicker("Completed", selection: velocityPaletteBinding(\.completedHex))
                    ColorPicker("Percent Complete", selection: velocityPaletteBinding(\.completionHex))
                    ColorPicker("Average Line", selection: velocityPaletteBinding(\.averageHex))
                }
            }
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Story Points Field").font(.subheadline.bold())
                FieldSearchField(
                    selectedField: Binding(
                        get: {
                            guard let config = projectConfig, !config.pointsField.isEmpty else { return nil }
                            return fields.first(where: { $0.id == config.pointsField }) ??
                                JiraField(id: config.pointsField, name: config.pointsFieldName, custom: true, schema: nil)
                        },
                        set: { field in
                            projectConfig?.pointsField = field?.id ?? ""
                            projectConfig?.pointsFieldName = field?.name ?? ""
                        }
                    ),
                    fields: fields
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Epics / Scope").font(.subheadline.bold())
                IssueSearchField(selectedIssues: Binding(
                    get: { projectConfig?.parentIssues ?? [] },
                    set: { projectConfig?.parentIssues = $0 }
                ))
            }
        }
    }

    // MARK: - Helpers

    private func boardBinding(
        get: @escaping () -> JiraBoard?,
        set: @escaping (JiraBoard?) -> Void
    ) -> Binding<JiraBoard?> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    get()
                }
            },
            set: { value in
                MainActor.assumeIsolated {
                    set(value)
                }
            }
        )
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
        guard let cfg = configService.config else { return }
        let needsFields = widget.type == .burndown || widget.type == .projectBurnRate
        guard needsFields else { return }
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

    private func velocityPaletteBinding(_ keyPath: WritableKeyPath<VelocityPalette, String>) -> Binding<Color> {
        Binding(
            get: {
                let palette = velocityConfig?.paletteOverride ?? .default
                return Color(hex: palette[keyPath: keyPath])
            },
            set: { color in
                if velocityConfig?.paletteOverride == nil {
                    velocityConfig?.paletteOverride = .default
                }
                guard var palette = velocityConfig?.paletteOverride else { return }
                palette[keyPath: keyPath] = color.hexString
                velocityConfig?.paletteOverride = palette
            }
        )
    }
}
