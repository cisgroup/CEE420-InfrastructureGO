import Foundation

/// Where the player's catches are kept on the phone, one small file. Until a server exists this file is the
/// whole score, and deleting the app deletes it.
nonisolated struct ProgressStore: Sendable {
    let file: URL

    init(file: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.file = file ?? folder.appending(path: "progress.json")
    }

    func load() -> PlayerProgress {
        guard let data = try? Data(contentsOf: file), let saved = try? decoder.decode(PlayerProgress.self, from: data) else { return PlayerProgress() }
        return saved
    }

    func save(_ progress: PlayerProgress) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(progress).write(to: file, options: .atomic)
        } catch {
            print("The progress could not be saved, \(error)")
        }
    }

    func erase() {
        try? FileManager.default.removeItem(at: file)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
