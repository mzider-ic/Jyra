import SwiftUI

struct BoardConfigView: View {
    @Environment(ConfigService.self) private var configService
    @Environment(BoardService.self) private var boardService

    let initialBoard: Board?
    var onDismiss: () -> Void = {}

    @State private var draft: Board
    @State private var selectedJiraBoard: JiraBoard? = nil
    @State private var selectedPointsField: JiraField? = nil
    @State private var availableFields: [JiraField] = []
    @State private var editingRule: BoardMetricRule? = nil
    @State private var isAddingRule = false

    init(board: Board?, onDismiss: @escaping () -> Void = {}) {
        self.initialBoard = board
        self.onDismiss = onDismiss
        _draft = State(initialValue: board ?? Board(name: "", jiraBoardId: 0, jiraBoardName: ""))
    }

    private var isNew: Bool { initialBoard == nil }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.jiraBoardId > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Board") {
                    TextField("Board Name", text: $draft.name)

                    BoardSearchField(selectedBoard: Binding(
                        get: { selectedJiraBoard },
                        set: { board in
                            selectedJiraBoard = board
                            if let b = board {
                                draft.jiraBoardId = b.id
                                draft.jiraBoardName = b.name
                                if draft.name.isEmpty { draft.name = b.name }
                            }
                        }
                    ), label: "Jira Board")
                }

                Section("Points Field") {
                    FieldSearchField(
                        selectedField: Binding(
                            get: { selectedPointsField },
                            set: { field in
                                selectedPointsField = field
                                draft.pointsField = field?.id ?? ""
                                draft.pointsFieldName = field?.name ?? ""
                            }
                        ),
                        fields: availableFields.filter { $0.schema?.type == "number" || $0.name.localizedCaseInsensitiveContains("point") }
                    )
                    if draft.pointsField.isEmpty {
                        Text("Auto-detected if blank")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(draft.metricRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete { offsets in
                        draft.metricRules.remove(atOffsets: offsets)
                    }

                    Button {
                        let newRule = BoardMetricRule(
                            field: .hoursInStatus, op: .greaterThan,
                            value: "24", color: .neonOrange
                        )
                        draft.metricRules.append(newRule)
                        editingRule = newRule
                        isAddingRule = true
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                } header: {
                    Text("Highlight Rules")
                } footer: {
                    Text("Rules are evaluated in order. The first match sets the card color. Blocked cards always appear red.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "New Board" : "Edit Board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew { boardService.add(draft) }
                        else     { boardService.update(draft) }
                        onDismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditorView(rule: rule) { updated in
                    if let idx = draft.metricRules.firstIndex(where: { $0.id == updated.id }) {
                        draft.metricRules[idx] = updated
                    }
                    editingRule = nil
                }
            }
        }
        .frame(width: 480, height: 580)
        .onAppear {
            if !draft.jiraBoardName.isEmpty {
                selectedJiraBoard = JiraBoard(id: draft.jiraBoardId, name: draft.jiraBoardName, type: "scrum")
            }
            if !draft.pointsField.isEmpty {
                selectedPointsField = JiraField(id: draft.pointsField, name: draft.pointsFieldName, custom: true, schema: nil)
            }
        }
        .task {
            guard let cfg = configService.config else { return }
            availableFields = (try? await JiraService(config: cfg).fetchFields()) ?? []
        }
    }

    private func ruleRow(_ rule: BoardMetricRule) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(rule.color.swiftUI)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                .shadow(color: rule.color.swiftUI.opacity(0.5), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(ruleDescription(rule))
                    .font(.system(size: 12, weight: .medium))
                if !rule.name.isEmpty {
                    Text(rule.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    if let idx = draft.metricRules.firstIndex(where: { $0.id == rule.id }) {
                        draft.metricRules[idx].isEnabled = enabled
                    }
                }
            ))
            .labelsHidden()
            .scaleEffect(0.8)

            Button { editingRule = rule } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func ruleDescription(_ rule: BoardMetricRule) -> String {
        if rule.field == .isBlocked { return "Is Blocked" }
        let field = rule.field.displayName
        let op    = rule.op.displayName
        let val   = rule.value
        return "\(field) \(op) \(val)"
    }
}

// MARK: - Rule editor sheet

struct RuleEditorView: View {
    @State private var draft: BoardMetricRule
    var onSave: (BoardMetricRule) -> Void

    init(rule: BoardMetricRule, onSave: @escaping (BoardMetricRule) -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Rule name (optional)", text: $draft.name)
                }

                Section("Condition") {
                    Picker("Field", selection: $draft.field) {
                        ForEach(BoardRuleField.allCases, id: \.self) { field in
                            Text(field.displayName).tag(field)
                        }
                    }
                    .onChange(of: draft.field) { _, newField in
                        if !newField.compatibleOperators.contains(draft.op) {
                            draft.op = newField.compatibleOperators.first ?? .equals
                        }
                    }

                    if !draft.field.isBoolean {
                        Picker("Operator", selection: $draft.op) {
                            ForEach(draft.field.compatibleOperators, id: \.self) { op in
                                Text(op.displayName).tag(op)
                            }
                        }

                        TextField(draft.field.isNumeric ? "Number" : "Value", text: $draft.value)
                    }
                }

                Section("Highlight Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(RuleColor.presets.indices, id: \.self) { i in
                            let preset = RuleColor.presets[i]
                            colorSwatch(preset)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Preview") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(draft.color.swiftUI)
                            .frame(width: 16, height: 16)
                            .shadow(color: draft.color.swiftUI.opacity(0.6), radius: 5)
                        Text(previewText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Rule")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(draft) }
                }
            }
        }
        .frame(width: 400, height: 460)
    }

    private func colorSwatch(_ color: RuleColor) -> some View {
        let isSelected = draft.color == color
        return Circle()
            .fill(color.swiftUI)
            .frame(width: 28, height: 28)
            .overlay(
                Circle().stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .shadow(color: color.swiftUI.opacity(isSelected ? 0.7 : 0.3), radius: isSelected ? 6 : 2)
            .onTapGesture { draft.color = color }
    }

    private var previewText: String {
        if draft.field == .isBlocked { return "Cards that are blocked" }
        let field = draft.field.displayName
        let op    = draft.op.displayName
        let val   = draft.value.isEmpty ? "…" : draft.value
        return "Cards where \(field) \(op) \(val)"
    }
}
