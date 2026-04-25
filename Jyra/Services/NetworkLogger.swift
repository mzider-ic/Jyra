import Foundation

@Observable
final class NetworkLogger: @unchecked Sendable {
    nonisolated(unsafe) static let shared = NetworkLogger()
    nonisolated(unsafe) static var isEnabledGlobal: Bool =
        ProcessInfo.processInfo.environment["JYRA_DEBUG_NETWORK"] == "1"

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let method: String
        let url: String
        let statusCode: Int?
        let duration: TimeInterval
        let requestBody: String?
        let responseBody: String?
        let error: String?

        var isSuccess: Bool {
            guard let code = statusCode, error == nil else { return false }
            return (200..<300).contains(code)
        }

        var durationText: String {
            duration >= 1
                ? String(format: "%.2fs", duration)
                : String(format: "%.0fms", duration * 1000)
        }

        var shortURL: String {
            guard let u = URL(string: url) else { return url }
            var s = u.path
            if let q = u.query { s += "?" + q }
            return s
        }
    }

    private(set) var entries: [Entry] = []
    var isEnabled: Bool = NetworkLogger.isEnabledGlobal {
        didSet { NetworkLogger.isEnabledGlobal = isEnabled }
    }

    nonisolated func enqueue(_ entry: Entry) {
        let statusStr = entry.statusCode.map { "\($0)" } ?? (entry.error != nil ? "ERR" : "?")
        print("[Network] \(entry.method) \(statusStr) \(entry.durationText)  \(entry.shortURL)")

        Task { @MainActor in
            guard NetworkLogger.isEnabledGlobal else { return }
            NetworkLogger.shared.entries.insert(entry, at: 0)
            if NetworkLogger.shared.entries.count > 500 {
                NetworkLogger.shared.entries.removeLast()
            }
        }
    }

    func clear() { entries.removeAll() }
}
