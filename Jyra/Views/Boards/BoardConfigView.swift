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

    init(board: Board?, onDismiss: @escaping () -> Void = {}) {
        self.initialBoard = board
        self.onDismiss = onDismiss
        _draft = State(initialValue: board ?? Board(name: "", jiraBoardId: 0, jiraBoardName: ""))
    }

    private var isNew: Bool { initialBoard == nil }
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.jiraBoardId > 0
    }

    private var screenSize: CGSize {
        let f = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(width: f.width, height: f.height)
    }

    var body: some View {
        let W = screenSize.width  * 0.6
        let H = screenSize.height * 0.78

        VStack(spacing: 0) {
            titleBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    boardSection
                    pointsSection
                    rulesSection
                }
                .padding(20)
            }
        }
        .frame(width: W, height: H)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingRule) { rule in
            RuleEditorView(rule: rule) { updated in
                if let idx = draft.metricRules.firstIndex(where: { $0.id == updated.id }) {
                    draft.metricRules[idx] = updated
                }
                editingRule = nil
            }
        }
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

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text(isNew ? "New Board" : "Edit Board")
                .font(.headline)
            Spacer()
            Button("Save") {
                if isNew { boardService.add(draft) }
                else      { boardService.update(draft) }
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Sections

    private var boardSection: some View {
        configSection("Board") {
            TextField("Board Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            BoardSearchField(selectedBoard: Binding(
                get: { selectedJiraBoard },
                set: { board in
                    selectedJiraBoard = board
                    if let b = board {
                        draft.jiraBoardId  = b.id
                        draft.jiraBoardName = b.name
                        if draft.name.isEmpty { draft.name = b.name }
                    }
                }
            ), label: "Jira Board")
        }
    }

    private var pointsSection: some View {
        configSection("Points Field") {
            FieldSearchField(
                selectedField: Binding(
                    get: { selectedPointsField },
                    set: { field in
                        selectedPointsField   = field
                        draft.pointsField     = field?.id   ?? ""
                        draft.pointsFieldName = field?.name ?? ""
                    }
                ),
                fields: availableFields.filter {
                    $0.schema?.type == "number" ||
                    $0.name.localizedCaseInsensitiveContains("point")
                }
            )
            if draft.pointsField.isEmpty {
                Text("Auto-detected if blank")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rulesSection: some View {
        configSection(
            "Highlight Rules",
            footer: "Rules are evaluated in order. The first match sets the card color. Blocked cards always appear red."
        ) {
            if draft.metricRules.isEmpty {
                Text("No rules yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(draft.metricRules) { rule in
                    ruleRow(rule)
                    if rule.id != draft.metricRules.last?.id {
                        Divider()
                    }
                }
            }

            Button {
                let newRule = BoardMetricRule(
                    conditions: [RuleCondition(field: .hoursInStatus, op: .greaterThan, value: "24")],
                    color: .neonOrange
                )
                draft.metricRules.append(newRule)
                editingRule = newRule
            } label: {
                Label("Add Rule", systemImage: "plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }

    // MARK: - Rule row

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
                    .lineLimit(2)
                if !rule.name.isEmpty {
                    Text(rule.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

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

            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                draft.metricRules.removeAll { $0.id == rule.id }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func ruleDescription(_ rule: BoardMetricRule) -> String {
        guard !rule.conditions.isEmpty else { return "(no conditions)" }
        let parts: [String] = rule.conditions.prefix(2).map { cond in
            let prefix = cond.negated ? "NOT " : ""
            if cond.field == .isBlocked { return "\(prefix)Is Blocked" }
            if cond.field == .statusCategory {
                let disp = BoardRuleField.statusCategoryOptions.first { $0.key == cond.value }?.display ?? cond.value
                return "\(prefix)Status \(cond.op.displayName) \(disp)"
            }
            let unit = cond.field.isTimeBased ? " \(cond.timeUnit.displayName)" : ""
            return "\(prefix)\(cond.field.displayName) \(cond.op.displayName) \(cond.value)\(unit)"
        }
        let suffix = rule.conditions.count > 2 ? " \(rule.connector.rawValue) …" : ""
        return parts.joined(separator: " \(rule.connector.rawValue) ") + suffix
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

// MARK: - Rule editor sheet

struct RuleEditorView: View {
    @State private var draft: BoardMetricRule
    var onSave: (BoardMetricRule) -> Void

    init(rule: BoardMetricRule, onSave: @escaping (BoardMetricRule) -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
    }

    private var screenSize: CGSize {
        let f = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(width: f.width, height: f.height)
    }

    var body: some View {
        let W = screenSize.width  * 0.55
        let H = screenSize.height * 0.72

        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button("Cancel") { onSave(draft) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Edit Rule")
                    .font(.headline)
                Spacer()
                Button("Done") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.conditions.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    labelSection
                    conditionsSection
                    colorSection
                    previewSection
                }
                .padding(20)
            }
        }
        .frame(width: W, height: H)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Label

    private var labelSection: some View {
        editorSection("Label (optional)") {
            TextField("Rule name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Conditions

    private var conditionsSection: some View {
        editorSection(
            "Conditions",
            footer: "Conditions are combined with \(draft.connector.rawValue). Use NOT to invert a condition."
        ) {
            if draft.conditions.count > 1 {
                Picker("Match", selection: $draft.connector) {
                    Text("ALL conditions (AND)").tag(RuleConnector.and)
                    Text("ANY condition (OR)").tag(RuleConnector.or)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
            }

            ForEach(draft.conditions.indices, id: \.self) { idx in
                conditionRow(idx: idx)
                if idx < draft.conditions.count - 1 {
                    Text(draft.connector.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RuleColor.neonCyan.swiftUI.opacity(0.7))
                        .padding(.leading, 2)
                }
            }

            Button {
                draft.conditions.append(
                    RuleCondition(field: .statusCategory, op: .equals, value: "indeterminate")
                )
            } label: {
                Label("Add Condition", systemImage: "plus.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(RuleColor.neonCyan.swiftUI)
            .padding(.top, 4)
        }
    }

    // MARK: - Color

    private var colorSection: some View {
        editorSection("Highlight Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(RuleColor.presets.indices, id: \.self) { i in
                    colorSwatch(RuleColor.presets[i])
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        editorSection("Preview") {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(draft.color.swiftUI)
                    .frame(width: 14, height: 14)
                    .shadow(color: draft.color.swiftUI.opacity(0.6), radius: 5)
                    .padding(.top, 2)
                Text(previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Condition row

    @ViewBuilder
    private func conditionRow(idx: Int) -> some View {
        HStack(spacing: 6) {
            // NOT toggle
            Button {
                draft.conditions[idx].negated.toggle()
            } label: {
                Text("NOT")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        draft.conditions[idx].negated
                            ? Color.orange.opacity(0.25) : Color.clear
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .foregroundStyle(draft.conditions[idx].negated ? Color.orange : Color.secondary)

            // Field picker
            Picker("", selection: $draft.conditions[idx].field) {
                ForEach(BoardRuleField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: draft.conditions[idx].field) { _, newField in
                if !newField.compatibleOperators.contains(draft.conditions[idx].op) {
                    draft.conditions[idx].op = newField.compatibleOperators.first ?? .equals
                }
                if newField == .statusCategory {
                    draft.conditions[idx].value = "indeterminate"
                } else if draft.conditions[idx].value.isEmpty || newField.isBoolean {
                    draft.conditions[idx].value = ""
                }
            }

            // Operator (hidden for boolean fields)
            if !draft.conditions[idx].field.isBoolean {
                Picker("", selection: $draft.conditions[idx].op) {
                    ForEach(draft.conditions[idx].field.compatibleOperators, id: \.self) { op in
                        Text(op.displayName).tag(op)
                    }
                }
                .labelsHidden()
                .frame(width: 70)

                // Value
                if draft.conditions[idx].field == .statusCategory {
                    Picker("", selection: $draft.conditions[idx].value) {
                        ForEach(BoardRuleField.statusCategoryOptions, id: \.key) { opt in
                            Text(opt.display).tag(opt.key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                } else {
                    TextField(draft.conditions[idx].field.isNumeric ? "0" : "value",
                              text: $draft.conditions[idx].value)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                // Time unit
                if draft.conditions[idx].field.isTimeBased {
                    Picker("", selection: $draft.conditions[idx].timeUnit) {
                        ForEach(RuleTimeUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
            }

            Spacer(minLength: 0)

            // Delete button
            if draft.conditions.count > 1 {
                Button {
                    draft.conditions.remove(at: idx)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Color swatch

    private func colorSwatch(_ color: RuleColor) -> some View {
        let isSelected = draft.color == color
        return Circle()
            .fill(color.swiftUI)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(isSelected ? Color.white : Color.clear, lineWidth: 2))
            .shadow(color: color.swiftUI.opacity(isSelected ? 0.7 : 0.3), radius: isSelected ? 6 : 2)
            .onTapGesture { draft.color = color }
    }

    // MARK: - Preview text

    private var previewText: String {
        guard !draft.conditions.isEmpty else { return "No conditions defined" }
        let parts: [String] = draft.conditions.map { cond in
            let prefix = cond.negated ? "NOT " : ""
            switch cond.field {
            case .isBlocked:
                return "\(prefix)Is Blocked"
            case .statusCategory:
                let disp = BoardRuleField.statusCategoryOptions.first { $0.key == cond.value }?.display ?? cond.value
                return "\(prefix)Status Category \(cond.op.displayName) \(disp)"
            default:
                let unit = cond.field.isTimeBased ? " \(cond.timeUnit.displayName)" : ""
                let val  = cond.value.isEmpty ? "…" : "\(cond.value)\(unit)"
                return "\(prefix)\(cond.field.displayName) \(cond.op.displayName) \(val)"
            }
        }
        return "Cards where " + parts.joined(separator: " \(draft.connector.rawValue) ")
    }

    // MARK: - Section helper

    @ViewBuilder
    private func editorSection<Content: View>(
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
