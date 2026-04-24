import Foundation

struct WidgetMetric: Identifiable {
    let id: String
    let name: String
    let value: String   // pre-formatted for display
    let icon: String    // SF Symbol
    var rawValue: Double?
}

struct AggregatedMetric: Identifiable {
    let id: String
    let name: String
    let value: String
    let icon: String
}

struct AggregatedTypeSection: Identifiable {
    var id: String { widgetType.rawValue }
    let widgetType: WidgetType
    let metrics: [AggregatedMetric]
    let widgetCount: Int
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

    func ordered(for widgetIds: [String]) -> [Entry] {
        widgetIds.compactMap { entries[$0] }.filter { !$0.metrics.isEmpty }
    }

    /// Groups entries by widget type and averages numeric metrics across widgets of the same type.
    func aggregatedByType(for widgetIds: [String]) -> [AggregatedTypeSection] {
        let relevant = widgetIds.compactMap { entries[$0] }.filter { !$0.metrics.isEmpty }
        let grouped = Dictionary(grouping: relevant, by: \.widgetType)

        return WidgetType.allCases.compactMap { type in
            guard let typeEntries = grouped[type], !typeEntries.isEmpty else { return nil }

            var metricOrder: [String] = []
            var metricMeta: [String: (name: String, icon: String)] = [:]
            var metricRaws: [String: [Double]] = [:]

            for entry in typeEntries {
                for metric in entry.metrics {
                    if metricMeta[metric.id] == nil {
                        metricOrder.append(metric.id)
                        metricMeta[metric.id] = (metric.name, metric.icon)
                    }
                    if let raw = metric.rawValue {
                        metricRaws[metric.id, default: []].append(raw)
                    }
                }
            }

            let aggregated: [AggregatedMetric] = metricOrder.compactMap { id in
                guard let meta = metricMeta[id],
                      let raws = metricRaws[id], !raws.isEmpty else { return nil }
                let avg = raws.reduce(0, +) / Double(raws.count)
                let formatted: String
                if id.contains("completion") || id.contains("pct") || meta.icon == "percent" {
                    formatted = "\(Int(avg.rounded()))%"
                } else {
                    formatted = "\(Int(avg.rounded())) pts"
                }
                return AggregatedMetric(id: id, name: meta.name, value: formatted, icon: meta.icon)
            }

            guard !aggregated.isEmpty else { return nil }
            return AggregatedTypeSection(widgetType: type, metrics: aggregated, widgetCount: typeEntries.count)
        }
    }
}
