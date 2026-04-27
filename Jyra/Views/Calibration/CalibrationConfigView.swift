import SwiftUI

struct CalibrationConfigView: View {
    @Environment(ConfigService.self)      private var configService
    @Environment(CalibrationService.self) private var calibrationService

    let initialConfig: CalibrationConfig
    var onDismiss: (CalibrationConfig?) -> Void

    @State private var draft: CalibrationConfig
    @State private var availableFields: [JiraField] = []
    @State private var isAddingBoard = false
    @State private var isDiscovering = false
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

    private var screenSize: CGSize {
        let f = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(width: f.width, height: f.height)
    }

    var body: some View {
        let W = screenSize.width  * 0.6
        let H = screenSize.height * 0.78

        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button("Cancel") { onDismiss(nil) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(isNew ? "New Calibration" : "Edit Calibration")
                    .font(.headline)
                Spacer()
                Button("Save") { onDismiss(draft) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    boardsSection
                    sprintSection
                    engineersSection
                }
                .padding(20)
            }
        }
        .frame(width: W, height: H)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .task {
            guard let cfg = configService.config else { return }
            availableFields = (try? await JiraService(config: cfg).fetchFields()) ?? []
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        configSection("Name") {
            TextField("Calibration name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var boardsSection: some View {
        configSection(
            "Boards",
            footer: "Add the Jira boards whose sprint data will be analyzed."
        ) {
            if draft.boards.isEmpty {
                Text("No boards added yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.boards.indices, id: \.self) { i in
                    HStack(spacing: 10) {
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
                        Spacer()
                        Button {
                            draft.boards.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                    if i < draft.boards.count - 1 { Divider() }
                }
            }

            Button {
                isAddingBoard = true
            } label: {
                Label("Add Board", systemImage: "plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .padding(.top, draft.boards.isEmpty ? 0 : 4)
        }
    }

    private var sprintSection: some View {
        configSection("Sprint Window") {
            Stepper(
                "Analyze last \(draft.sprintCount) sprint\(draft.sprintCount == 1 ? "" : "s")",
                value: $draft.sprintCount,
                in: 1...10
            )
            Text("Includes up to \(draft.sprintCount) closed sprints plus any active sprint.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var engineersSection: some View {
        configSection(
            "Engineers",
            footer: "Discover automatically finds all Jira assignees from recent sprint data. Assign grade levels to enable cross-team normalization."
        ) {
            if draft.engineers.isEmpty {
                Text("No engineers configured yet. Use \"Discover\" to find assignees from recent sprint data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(draft.engineers) { eng in
                    engineerRow(eng)
                    if eng.id != draft.engineers.last?.id { Divider() }
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await discoverEngineers() }
                } label: {
                    if isDiscovering {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Discovering…")
                        }
                    } else {
                        Label("Discover Engineers", systemImage: "person.badge.magnifyingglass")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(draft.boards.isEmpty || isDiscovering)
                .padding(.top, 4)

                if let err = discoverError {
                    Text(err).font(.caption).foregroundStyle(RuleColor.neonRed.swiftUI)
                }
            }
        }
    }

    // MARK: - Engineer row

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
                Text(eng.jiraAccountId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up.on.square")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    TextField("GitLab @username", text: Binding(
                        get: { eng.gitlabUsername },
                        set: { val in
                            if let idx = draft.engineers.firstIndex(where: { $0.id == eng.id }) {
                                draft.engineers[idx].gitlabUsername = val
                            }
                        }
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
                }
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
            .frame(width: 180)

            Button {
                draft.engineers.removeAll { $0.id == eng.id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Discover

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

    // MARK: - Section helper

    @ViewBuilder
    private func configSection<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
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

    private var screenSize: CGSize {
        let f = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(width: f.width, height: f.height)
    }

    var body: some View {
        let W = screenSize.width  * 0.4
        let H = screenSize.height * 0.42

        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Add Board")
                    .font(.headline)
                Spacer()
                Button("Add") {
                    guard let board = selectedBoard else { return }
                    onAdd(CalibrationBoardRef(
                        boardId: board.id,
                        boardName: board.name,
                        pointsField: selectedField?.id ?? "",
                        pointsFieldName: selectedField?.name ?? ""
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedBoard == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sheetSection("Board") {
                        BoardSearchField(selectedBoard: $selectedBoard, label: "Jira Board")
                    }
                    sheetSection("Points Field") {
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
                .padding(20)
            }
        }
        .frame(width: W, height: H)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func sheetSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
        }
    }
}
