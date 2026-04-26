import Foundation

@Observable
final class BoardService {
    var boards: [Board] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Jyra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("boards.json")
        load()
    }

    func add(_ board: Board) {
        boards.append(board)
        persist()
    }

    func update(_ board: Board) {
        guard let idx = boards.firstIndex(where: { $0.id == board.id }) else { return }
        boards[idx] = board
        persist()
    }

    func delete(_ board: Board) {
        boards.removeAll { $0.id == board.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        boards = (try? JSONDecoder().decode([Board].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(boards) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
