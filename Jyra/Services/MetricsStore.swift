import Foundation

struct WidgetMetric: Identifiable {
    let id: String      // stable key within a widget, e.g. "avg_velocity"
    let name: String
    let value: String   // pre-formatted for display
    let icon: String    // SF Symbol
}

@Observable
final class MetricsStore {
    struct Entry: Identifiable {
        let id: String          // widget id
        let title: String
        let widgetType: WidgetType
        let metrics: [WidgetMetric]
    }

    private(set) var entries: [String: Entry] = [:]

    func publish(widgetId: String, title: String, type: WidgetType, metrics: [WidgetMetric]) {
        entries[widgetId] = Entry(id: widgetId, title: title, widgetType: type, metrics: metrics)
    }

    func clear(widgetId: String) {
        entries.removeValue(forKey: widgetId)
    }

    /// Returns entries in the order widgets appear on the dashboard.
    func ordered(for widgetIds: [String]) -> [Entry] {
        widgetIds.compactMap { entries[$0] }.filter { !$0.metrics.isEmpty }
    }
}
