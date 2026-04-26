import SwiftUI

// Unified selection for dashboards, boards, and calibrations
enum AppSelection: Hashable {
    case dashboard(String)
    case board(String)
    case calibration(String)
}

struct DashboardView: View {
    @Environment(ConfigService.self)      private var configService
    @Environment(BoardService.self)       private var boardService
    @Environment(CalibrationService.self) private var calibrationService
    @State private var dashboardService = DashboardService()
    @State private var selection: AppSelection? = nil

    // Dashboard sheet state
    @State private var isAddingDashboard = false
    @State private var newDashboardName = ""
    @State private var renamingDashboard: Dashboard? = nil
    @State private var renameText = ""

    // Board sheet state
    @State private var isAddingBoard = false
    @State private var configuringBoard: Board? = nil

    // Calibration sheet state
    @State private var isAddingCalibration   = false
    @State private var configuringCalibration: CalibrationConfig? = nil

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .environment(dashboardService)
        }
        .onAppear { selectFirstIfNeeded() }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard(let id):
            if let idx = dashboardService.dashboards.firstIndex(where: { $0.id == id }) {
                WidgetContainerView(dashboard: Bindable(dashboardService).dashboards[idx])
                    .id(id)
            } else {
                emptyState(icon: "chart.bar.doc.horizontal", label: "No Dashboard Selected")
            }
        case .board(let id):
            if let board = boardService.boards.first(where: { $0.id == id }) {
                BoardView(board: board)
                    .id(id)
            } else {
                emptyState(icon: "square.grid.3x1.below.line.grid.1x2", label: "No Board Selected")
            }
        case .calibration(let id):
            if let cal = calibrationService.calibrations.first(where: { $0.id == id }) {
                CalibrationView(calibration: cal)
                    .id(id)
                    .environment(calibrationService)
            } else {
                emptyState(icon: "chart.bar.xaxis.ascending", label: "No Calibration Selected")
            }
        case nil:
            emptyState(icon: "chart.bar.doc.horizontal", label: "Select an item from the sidebar")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Dashboards") {
                ForEach(dashboardService.dashboards) { dash in
                    Label(dash.name, systemImage: "chart.bar.doc.horizontal")
                        .tag(AppSelection.dashboard(dash.id))
                        .contextMenu {
                            Button("Rename…") {
                                renamingDashboard = dash
                                renameText = dash.name
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                let wasSelected = selection == .dashboard(dash.id)
                                dashboardService.delete(dash)
                                if wasSelected { selectFirstIfNeeded(force: true) }
                            }
                        }
                }
            }

            Section("Boards") {
                ForEach(boardService.boards) { board in
                    Label(board.name, systemImage: "square.grid.3x1.below.line.grid.1x2")
                        .tag(AppSelection.board(board.id))
                        .contextMenu {
                            Button("Configure…") { configuringBoard = board }
                            Divider()
                            Button("Delete", role: .destructive) {
                                let wasSelected = selection == .board(board.id)
                                boardService.delete(board)
                                if wasSelected { selectFirstIfNeeded(force: true) }
                            }
                        }
                }
            }

            Section("Calibration") {
                ForEach(calibrationService.calibrations) { cal in
                    Label(cal.name, systemImage: "chart.bar.xaxis.ascending")
                        .tag(AppSelection.calibration(cal.id))
                        .contextMenu {
                            Button("Configure…") { configuringCalibration = cal }
                            Divider()
                            Button("Delete", role: .destructive) {
                                let wasSelected = selection == .calibration(cal.id)
                                calibrationService.delete(cal)
                                if wasSelected { selectFirstIfNeeded(force: true) }
                            }
                        }
                }
            }
        }
        .navigationTitle("Jyra")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                addButtons
            }
        }
        // Dashboard sheets
        .sheet(isPresented: $isAddingDashboard) {
            nameSheet(
                title: "New Dashboard",
                text: $newDashboardName,
                onCommit: {
                    let name = newDashboardName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    dashboardService.add(name: name)
                    selection = dashboardService.dashboards.last.map { .dashboard($0.id) }
                    isAddingDashboard = false
                },
                onCancel: { isAddingDashboard = false }
            )
        }
        .sheet(item: $renamingDashboard) { dash in
            nameSheet(
                title: "Rename Dashboard",
                text: $renameText,
                onCommit: {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    dashboardService.rename(dash, to: name)
                    renamingDashboard = nil
                },
                onCancel: { renamingDashboard = nil }
            )
        }
        // Board sheets
        .sheet(isPresented: $isAddingBoard) {
            BoardConfigView(board: nil) {
                isAddingBoard = false
                selection = boardService.boards.last.map { .board($0.id) }
            }
            .environment(configService)
            .environment(boardService)
        }
        .sheet(item: $configuringBoard) { board in
            BoardConfigView(board: board) { configuringBoard = nil }
                .environment(configService)
                .environment(boardService)
        }
        // Calibration sheets
        .sheet(isPresented: $isAddingCalibration) {
            CalibrationConfigView(calibration: CalibrationConfig(name: "")) { updated in
                if let u = updated {
                    calibrationService.add(u)
                    selection = .calibration(u.id)
                }
                isAddingCalibration = false
            }
            .environment(configService)
            .environment(calibrationService)
        }
        .sheet(item: $configuringCalibration) { cal in
            CalibrationConfigView(calibration: cal) { updated in
                if let u = updated { calibrationService.update(u) }
                configuringCalibration = nil
            }
            .environment(configService)
            .environment(calibrationService)
        }
    }

    // MARK: - Add buttons

    private var addButtons: some View {
        VStack(spacing: 0) {
            addButton(label: "New Dashboard", icon: "chart.bar.doc.horizontal.fill") {
                isAddingDashboard = true
                newDashboardName = ""
            }
            Divider().padding(.leading, 16)
            addButton(label: "New Board", icon: "square.grid.3x1.below.line.grid.1x2.fill") {
                isAddingBoard = true
            }
            Divider().padding(.leading, 16)
            addButton(label: "New Calibration", icon: "chart.bar.xaxis.ascending.badge.clock") {
                isAddingCalibration = true
            }
        }
        .padding(8)
    }

    private func addButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private func emptyState(icon: String, label: String) -> some View {
        ContentUnavailableView(label, systemImage: icon)
    }

    // MARK: - Helpers

    private func selectFirstIfNeeded(force: Bool = false) {
        guard selection == nil || force else { return }
        if let first = dashboardService.dashboards.first {
            selection = .dashboard(first.id)
        } else if let first = boardService.boards.first {
            selection = .board(first.id)
        } else if let first = calibrationService.calibrations.first {
            selection = .calibration(first.id)
        } else {
            selection = nil
        }
    }

    private func nameSheet(
        title: String,
        text: Binding<String>,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            Text(title).font(.headline)
            TextField("Name", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(onCommit)
            HStack {
                Button("Cancel", action: onCancel)
                Button("OK", action: onCommit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
