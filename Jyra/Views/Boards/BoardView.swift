import SwiftUI

struct BoardView: View {
    let board: Board
    @Environment(ConfigService.self)  private var configService
    @Environment(JiraDataCache.self)  private var dataCache

    @State private var issues: [BoardIssue] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedIssue: BoardIssue? = nil
    @State private var isConfiguringBoard = false

    private var cacheKey: String { "board:\(board.id):\(board.jiraBoardId)" }

    // Group issues into ordered columns: todo → in-progress → done
    private var columns: [BoardColumn] {
        let order: [(String, String)] = [
            ("new",           "To Do"),
            ("indeterminate", "In Progress"),
            ("done",          "Done"),
        ]
        return order.map { (key, title) in
            BoardColumn(
                id: key, title: title, statusCategoryKey: key,
                issues: issues.filter { $0.statusCategoryKey == key }
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            boardToolbar
            Divider()
            if isLoading && issues.isEmpty {
                ProgressView("Loading board…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error, issues.isEmpty {
                errorView(err)
            } else {
                columnsView
            }
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.09))
        .task(id: "\(board.jiraBoardId)-\(dataCache.refreshVersion(for: board.id))") {
            await load()
        }
        .sheet(item: $selectedIssue) { issue in
            NavigationStack {
                BoardCardDetailView(issue: issue, jiraBaseURL: configService.config?.jiraURL ?? "")
                    .navigationTitle(issue.key)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { selectedIssue = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $isConfiguringBoard) {
            BoardConfigView(board: board) { isConfiguringBoard = false }
                .environment(configService)
        }
    }

    // MARK: - Toolbar

    private var boardToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(board.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(board.jiraBoardName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoading {
                ProgressView().scaleEffect(0.7)
            }

            Button {
                dataCache.forceRefresh(widgetId: board.id)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(RuleColor.neonCyan.swiftUI)
            }
            .buttonStyle(.borderless)
            .help("Refresh board")

            Button { isConfiguringBoard = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Configure board")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.07, green: 0.07, blue: 0.11))
    }

    // MARK: - Columns

    private var columnsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 1) {
                ForEach(columns) { column in
                    BoardColumnView(
                        column: column,
                        rules: board.metricRules,
                        onSelectIssue: { selectedIssue = $0 }
                    )
                    if column.id != columns.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(RuleColor.neonOrange.swiftUI)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.borderless)
                .foregroundStyle(RuleColor.neonCyan.swiftUI)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func load() async {
        if let cached = dataCache.cachedBoardIssues(key: cacheKey) {
            issues = cached
            return
        }
        guard let cfg = configService.config else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await JiraService(config: cfg).fetchBoardIssues(
                boardId: board.jiraBoardId,
                pointsField: board.pointsField.isEmpty ? nil : board.pointsField
            )
            dataCache.store(boardIssues: fetched, key: cacheKey)
            issues = fetched
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Column view

private struct BoardColumnView: View {
    let column: BoardColumn
    let rules: [BoardMetricRule]
    var onSelectIssue: (BoardIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(column.issues) { issue in
                        BoardCardView(issue: issue, rules: rules) {
                            onSelectIssue(issue)
                        }
                    }
                    if column.issues.isEmpty {
                        emptyColumn
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.06, green: 0.06, blue: 0.10))
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(column.neonColor)
                .frame(width: 3, height: 16)
                .shadow(color: column.neonColor.opacity(0.6), radius: 4)

            Text(column.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(column.neonColor)
                .tracking(1.2)

            Text("(\(column.issues.count))")
                .font(.system(size: 11))
                .foregroundStyle(column.neonColor.opacity(0.6))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(column.neonColor.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(column.neonColor.opacity(0.15))
                .frame(height: 1)
        }
    }

    private var emptyColumn: some View {
        Text("No issues")
            .font(.caption)
            .foregroundStyle(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}
