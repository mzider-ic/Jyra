import SwiftUI

struct IssueSearchField: View {
    @Binding var selectedIssues: [ProjectBurnRateConfig.ScopeIssue]
    var fields: [JiraField] = []
    @Environment(ConfigService.self) private var configService

    @State private var searchText = ""
    @State private var results: [JiraIssuePickerResponse.Issue] = []
    @State private var isSearching = false

    private var pointsFields: [JiraField] {
        fields.filter {
            $0.name.localizedCaseInsensitiveContains("point") ||
            $0.name.localizedCaseInsensitiveContains("story")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedIssues.isEmpty {
                selectedList
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search epics or parent issues by key or summary…", text: $searchText)
                    .textFieldStyle(.plain)
                if isSearching {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results, id: \.id) { issue in
                        Button {
                            let scopeIssue = ProjectBurnRateConfig.ScopeIssue(key: issue.key, summary: issue.summary)
                            if !selectedIssues.contains(where: { $0.key == scopeIssue.key }) {
                                selectedIssues.append(scopeIssue)
                            }
                            searchText = ""
                            results = []
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(issue.key).font(.subheadline.monospaced())
                                        if let sub = issue.subtitle, !sub.isEmpty {
                                            Text(sub)
                                                .font(.caption2)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(issue.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)

                        if issue.id != results.last?.id {
                            Divider().padding(.leading, 10)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2 else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    private var selectedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(selectedIssues.indices, id: \.self) { idx in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedIssues[idx].key).font(.subheadline.monospaced())
                        Text(selectedIssues[idx].summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !pointsFields.isEmpty {
                            fieldPicker(at: idx)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        let key = selectedIssues[idx].key
                        selectedIssues.removeAll { $0.key == key }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if idx < selectedIssues.count - 1 {
                    Divider().padding(.leading, 10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func fieldPicker(at idx: Int) -> some View {
        let hasField = !selectedIssues[idx].pointsField.isEmpty
        let label = hasField ? selectedIssues[idx].pointsFieldName : "Select points field"
        return Menu {
            Button("None") { setField(at: idx, field: nil) }
            ForEach(pointsFields) { field in
                Button(field.name) { setField(at: idx, field: field) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "number").font(.system(size: 9))
                Text(label).font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(hasField ? .secondary : .orange)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func setField(at idx: Int, field: JiraField?) {
        guard idx < selectedIssues.count else { return }
        var copy = selectedIssues
        copy[idx].pointsField = field?.id ?? ""
        copy[idx].pointsFieldName = field?.name ?? ""
        selectedIssues = copy
    }

    private func performSearch(query: String) async {
        guard let cfg = configService.config else { return }
        isSearching = true
        defer { isSearching = false }

        let fetched = (try? await JiraService(config: cfg).searchIssuePicker(query: query)) ?? []
        let existingKeys = Set(selectedIssues.map(\.key))
        results = fetched.filter { !existingKeys.contains($0.key) }
    }
}
