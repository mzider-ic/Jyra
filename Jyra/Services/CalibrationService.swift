import Foundation

@Observable
final class CalibrationService {
    var calibrations: [CalibrationConfig] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Jyra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("calibrations.json")
        load()
    }

    func add(_ config: CalibrationConfig) {
        calibrations.append(config)
        persist()
    }

    func update(_ config: CalibrationConfig) {
        guard let idx = calibrations.firstIndex(where: { $0.id == config.id }) else { return }
        calibrations[idx] = config
        persist()
    }

    func delete(_ config: CalibrationConfig) {
        calibrations.removeAll { $0.id == config.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        calibrations = (try? JSONDecoder().decode([CalibrationConfig].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(calibrations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
