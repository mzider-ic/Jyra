import SwiftUI

struct BoardSearchField: View {
    @Binding var selectedBoard: JiraBoard?
    var label: String = "Board"
    @Environment(ConfigService.self) private var configService

    @State private var searchText = ""
    @State private var results: [JiraBoard] = []
    @State private var isSearching = false
    @State private var isChanging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let board = selectedBoard, !isChanging {
                selectedRow(board)
            } else {
                searchField
                if !results.isEmpty {
                    resultsList
                }
            }
        }
        .task(id: searchText) {
            guard !searchText.isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func selectedRow(_ board: JiraBoard) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(board.name).font(.subheadline)
            }
            Spacer()
            Button("Change") {
                isChanging = true
                searchText = board.name
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Type to search boards…", text: $searchText)
                .textFieldStyle(.plain)
            if isSearching {
                ProgressView().scaleEffect(0.6)
            }
            if selectedBoard != nil {
                Button("Cancel") {
                    isChanging = false
                    searchText = ""
                    results = []
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { board in
                    Button {
                        selectedBoard = board
                        isChanging = false
                        searchText = ""
                        results = []
                    } label: {
                        HStack(spacing: 8) {
                            Text(board.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(board.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                    if board.id != results.last?.id {
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

    private func performSearch() async {
        guard let cfg = configService.config else { return }
        isSearching = true
        defer { isSearching = false }
        results = (try? await JiraService(config: cfg).searchBoards(name: searchText)) ?? []
    }
}
