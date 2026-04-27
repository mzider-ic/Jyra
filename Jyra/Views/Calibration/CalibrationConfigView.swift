import SwiftUI

struct CalibrationConfigView: View {
    @Environment(ConfigService.self)      private var configService
    @Environment(CalibrationService.self) private var calibrationService

    let initialConfig: CalibrationConfig
    var onDismiss: (CalibrationConfig?) -> Void

    @State private var draft: CalibrationConfig
    @State private var availableFields: [JiraField] = []
    @State private var isAddingBoard   = false
    @State private var isDiscovering   = false
    @State private var discoverError: String? = nil

    init(calibration: CalibrationConfig, onDismiss: @escaping (CalibrationConfig?) -> Void) {
        self.initialConfig = calibration
        self.onDismiss     = onDismiss
        _draft = State(initialValue: calibration)
    }

    private var isNew: Bool { initialConfig.name.isEmpty }
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.boards.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Calibration name", text: $draft.name)
                }

                Section {
                    ForEach(draft.boards.indices, id: \.self) { i in
                        HStack {
                            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.boards[i].boardName)
                                    .font(.system(size: 13))
                                Text(draft.boards[i].pointsFieldName.isEmpty
                                     ? "Auto-detect points field"
                                     : draft.boards[i].pointsFieldName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in draft.boards.remove(atOffsets: offsets) }

                    Button {
                        isAddingBoard = true
                    } label: {
                        Label("Add Board", systemImage: "plus")
                    }
                } header: {
                    Text("Boards")
                } footer: {
                    Text("Add the Jira boards whose sprint data will be analyzed. Engineers are discovered per board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sprint Window") {
                    Stepper(
                        "Analyze last \(draft.sprintCount) sprint\(draft.sprintCount == 1 ? "" : "s")",
                        value: $draft.sprintCount,
                        in: 1...10
                    )
                    Text("Includes up to \(draft.sprintCount) closed sprints plus any active sprint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if draft.engineers.isEmpty {
                        Text("No engineers configured yet. Use \"Discover\" to find assignees from recent sprint data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(draft.engineers) { eng in
                            engineerRow(eng)
                        }
                        .onDelete { offsets in draft.engineers.remove(atOffsets: offsets) }
                    }

                    Button {
                        Task { await discoverEngineers() }
                    } label: {
                        if isDiscovering {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Discovering from sprint data…")
                            }
                        } else {
                            Label("Discover Engineers", systemImage: "person.badge.magnifyingglass")
                        }
                    }
                    .disabled(draft.boards.isEmpty || isDiscovering)

                    if let err = discoverError {
                        Text(err).font(.caption).foregroundStyle(RuleColor.neonRed.swiftUI)
                    }
                } header: {
                    Text("Engineers")
                } footer: {
                    Text("Discover automatically finds all Jira assignees from recent sprint data. Assign grade levels to enable cross-team normalization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "New Calibration" : "Edit Calibration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onDismiss(draft) }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isAddingBoard) {
                CalibrationAddBoardSheet(availableFields: availableFields) { ref in
                    if !draft.boards.contains(where: { $0.boardId == ref.boardId }) {
                        draft.boards.append(ref)
                    }
                    isAddingBoard = false
                } onCancel: {
                    isAddingBoard = false
                }
                .environment(configService)
            }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 500)
        .task {
            guard let cfg = configService.config else { return }
            availableFields = (try? await JiraService(config: cfg).fetchFields()) ?? []
        }
    }

    private func engineerRow(_ eng: EngineerAssignment) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(eng.gradeLevel.neonColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(String(eng.displayName.prefix(2)))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(eng.gradeLevel.neonColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(eng.displayName).font(.system(size: 13))
                Text(eng.jiraAccountId).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { eng.gradeLevel },
                set: { grade in
                    if let idx = draft.engineers.firstIndex(where: { $0.id == eng.id }) {
                        draft.engineers[idx].gradeLevel = grade
                    }
                }
            )) {
                ForEach(GradeLevel.allCases, id: \.self) { grade in
                    Text(grade.rawValue).tag(grade)
                }
            }
            .frame(width: 170)
        }
        .padding(.vertical, 2)
    }

    private func discoverEngineers() async {
        guard let cfg = configService.config else { return }
        isDiscovering = true
        discoverError = nil
        defer { isDiscovering = false }

        var found: [EngineerAssignment] = []
        let existingIds = Set(draft.engineers.map(\.jiraAccountId))

        do {
            for boardRef in draft.boards {
                let svc = JiraService(config: cfg)
                let fields = (try? await svc.fetchFields()) ?? []
                let pf = boardRef.pointsField.isEmpty
                    ? (fields.first(where: { $0.name.localizedCaseInsensitiveContains("story point") })?.id ?? "story_points")
                    : boardRef.pointsField

                let sprints = try await svc.fetchCalibrationSprints(
                    boardId: boardRef.boardId,
                    sprintCount: draft.sprintCount,
                    pointsField: pf
                )
                for sprint in sprints {
                    for issue in sprint.issues {
                        guard let aid  = issue.accountId,
                              let name = issue.displayName,
                              !existingIds.contains(aid),
                              !found.contains(where: { $0.jiraAccountId == aid }) else { continue }
                        found.append(EngineerAssignment(
                            jiraAccountId: aid,
                            displayName: name,
                            gradeLevel: .engineer
                        ))
                    }
                }
            }
            draft.engineers.append(contentsOf: found)
            if found.isEmpty {
                discoverError = "No new engineers found in the last \(draft.sprintCount) sprint\(draft.sprintCount == 1 ? "" : "s")."
            }
        } catch {
            discoverError = error.localizedDescription
        }
    }
}

// MARK: - Add board sheet

private struct CalibrationAddBoardSheet: View {
    @Environment(ConfigService.self) private var configService
    let availableFields: [JiraField]
    var onAdd:    (CalibrationBoardRef) -> Void
    var onCancel: () -> Void

    @State private var selectedBoard: JiraBoard? = nil
    @State private var selectedField: JiraField? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Board") {
                    BoardSearchField(selectedBoard: $selectedBoard, label: "Jira Board")
                }
                Section("Points Field") {
                    FieldSearchField(
                        selectedField: $selectedField,
                        fields: availableFields.filter {
                            $0.schema?.type == "number"
                            || $0.name.localizedCaseInsensitiveContains("point")
                        }
                    )
                    if selectedField == nil {
                        Text("Auto-detected if left blank")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let board = selectedBoard else { return }
                        onAdd(CalibrationBoardRef(
                            boardId: board.id,
                            boardName: board.name,
                            pointsField: selectedField?.id ?? "",
                            pointsFieldName: selectedField?.name ?? ""
                        ))
                    }
                    .disabled(selectedBoard == nil)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 260)
    }
}
