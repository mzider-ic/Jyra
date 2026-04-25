import Foundation

@Observable
final class JiraDataCache {
    private struct Entry<T> {
        let value: T
        let date: Date
    }

    private var velocityCache: [String: Entry<[VelocityEntry]>] = [:]
    private var burndownCache: [String: Entry<BurndownResult>] = [:]
    private var burnUpCache: [String: Entry<BurnUpResult>] = [:]
    private(set) var refreshVersions: [String: Int] = [:]

    private let ttl: TimeInterval = 300  // 5 minutes

    // MARK: - Refresh tokens

    func refreshVersion(for widgetId: String) -> Int {
        refreshVersions[widgetId, default: 0]
    }

    func forceRefresh(widgetId: String) {
        refreshVersions[widgetId, default: 0] += 1
        let prefix = widgetId + ":"
        velocityCache = velocityCache.filter { !$0.key.hasPrefix(prefix) }
        burndownCache = burndownCache.filter { !$0.key.hasPrefix(prefix) }
        burnUpCache   = burnUpCache.filter   { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - Velocity

    func cachedVelocity(key: String) -> [VelocityEntry]? {
        guard let e = velocityCache[key], Date().timeIntervalSince(e.date) < ttl else { return nil }
        return e.value
    }

    func store(velocity: [VelocityEntry], key: String) {
        velocityCache[key] = Entry(value: velocity, date: Date())
    }

    // MARK: - Burndown

    func cachedBurndown(key: String) -> BurndownResult? {
        guard let e = burndownCache[key], Date().timeIntervalSince(e.date) < ttl else { return nil }
        return e.value
    }

    func store(burndown: BurndownResult, key: String) {
        burndownCache[key] = Entry(value: burndown, date: Date())
    }

    // MARK: - BurnUp

    func cachedBurnUp(key: String) -> BurnUpResult? {
        guard let e = burnUpCache[key], Date().timeIntervalSince(e.date) < ttl else { return nil }
        return e.value
    }

    func store(burnUp: BurnUpResult, key: String) {
        burnUpCache[key] = Entry(value: burnUp, date: Date())
    }
}
