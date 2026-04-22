import Foundation

@Observable
final class DashboardService {
    var dashboards: [Dashboard] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Jyra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dashboards.json")
        load()
    }

    func add(name: String) {
        dashboards.append(Dashboard(name: name))
        persist()
    }

    func rename(_ dashboard: Dashboard, to name: String) {
        guard let idx = dashboards.firstIndex(where: { $0.id == dashboard.id }) else { return }
        dashboards[idx].name = name
        persist()
    }

    func delete(_ dashboard: Dashboard) {
        dashboards.removeAll { $0.id == dashboard.id }
        persist()
    }

    func addWidget(_ widget: Widget, to dashboard: Dashboard) {
        guard let idx = dashboards.firstIndex(where: { $0.id == dashboard.id }) else { return }
        dashboards[idx].widgets.append(widget)
        persist()
    }

    func updateWidget(_ widget: Widget, in dashboard: Dashboard) {
        guard let di = dashboards.firstIndex(where: { $0.id == dashboard.id }),
              let wi = dashboards[di].widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        dashboards[di].widgets[wi] = widget
        persist()
    }

    func deleteWidget(_ widget: Widget, from dashboard: Dashboard) {
        guard let di = dashboards.firstIndex(where: { $0.id == dashboard.id }) else { return }
        dashboards[di].widgets.removeAll { $0.id == widget.id }
        persist()
    }

    func moveWidget(in dashboard: Dashboard, from source: IndexSet, to destination: Int) {
        guard let di = dashboards.firstIndex(where: { $0.id == dashboard.id }) else { return }
        dashboards[di].widgets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        dashboards = (try? JSONDecoder().decode([Dashboard].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(dashboards) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
