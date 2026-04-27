import SwiftUI

struct FieldSearchField: View {
    @Binding var selectedField: JiraField?
    let fields: [JiraField]
    var label: String = "Field"

    @State private var searchText = ""
    @State private var isChanging = false

    private var filteredFields: [JiraField] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(fields.prefix(20)) }
        return fields
            .filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
            }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let field = selectedField, !isChanging {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                        Text(field.name).font(.subheadline)
                    }
                    Spacer()
                    Button("Change") {
                        isChanging = true
                        searchText = field.name
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search fields…", text: $searchText)
                        .textFieldStyle(.plain)
                    if selectedField != nil {
                        Button("Cancel") {
                            isChanging = false
                            searchText = ""
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                if !filteredFields.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredFields) { field in
                                Button {
                                    selectedField = field
                                    isChanging = false
                                    searchText = ""
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(field.name)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(field.id)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: 140, alignment: .trailing)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)

                                if field.id != filteredFields.last?.id {
                                    Divider().padding(.leading, 10)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
            }
        }
    }
}
