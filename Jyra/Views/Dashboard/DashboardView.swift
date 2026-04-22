import SwiftUI

struct DashboardView: View {
    @Environment(ConfigService.self) private var configService
    @State private var dashboardService = DashboardService()
    @State private var selectedId: String? = nil
    @State private var isAddingDashboard = false
    @State private var newDashboardName = ""
    @State private var renamingDashboard: Dashboard? = nil
    @State private var renameText = ""

    private var selectedIndex: Int? {
        dashboardService.dashboards.firstIndex(where: { $0.id == selectedId })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let idx = selectedIndex {
                WidgetContainerView(dashboard: Bindable(dashboardService).dashboards[idx])
                    .environment(configService)
                    .environment(dashboardService)
                    .id(selectedId)
            } else {
                emptyState
            }
        }
        .onAppear {
            if selectedId == nil {
                selectedId = dashboardService.dashboards.first?.id
            }
        }
    }

    private var sidebar: some View {
        List(dashboardService.dashboards, selection: $selectedId) { dash in
            Label(dash.name, systemImage: "chart.bar.doc.horizontal")
                .tag(dash.id)
                .contextMenu {
                    Button("Rename…") {
                        renamingDashboard = dash
                        renameText = dash.name
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        let wasSelected = selectedId == dash.id
                        dashboardService.delete(dash)
                        if wasSelected {
                            selectedId = dashboardService.dashboards.first?.id
                        }
                    }
                }
        }
        .navigationTitle("Jyra")
        .safeAreaInset(edge: .bottom) {
            Button {
                isAddingDashboard = true
                newDashboardName = ""
            } label: {
                Label("New Dashboard", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .sheet(isPresented: $isAddingDashboard) {
            nameSheet(
                title: "New Dashboard",
                text: $newDashboardName,
                onCommit: {
                    let name = newDashboardName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    dashboardService.add(name: name)
                    selectedId = dashboardService.dashboards.last?.id
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
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Dashboard Selected",
            systemImage: "chart.bar.doc.horizontal",
            description: Text("Create a dashboard from the sidebar to get started.")
        )
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
