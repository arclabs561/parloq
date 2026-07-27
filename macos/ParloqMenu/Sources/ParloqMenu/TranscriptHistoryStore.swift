import Foundation
import ParloqMenuCore

final class TranscriptHistoryStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private(set) var history: TranscriptHistory
    private(set) var loadError: Error?

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        limit: Int = TranscriptHistory.defaultLimit
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(
            fileManager: fileManager)

        do {
            let data = try Data(contentsOf: self.fileURL)
            let entries = try JSONDecoder().decode(
                [TranscriptHistoryEntry].self,
                from: data
            )
            history = TranscriptHistory(entries: entries, limit: limit)
        } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile {
            history = TranscriptHistory(limit: limit)
        } catch {
            history = TranscriptHistory(limit: limit)
            loadError = error
        }
    }

    @discardableResult
    func append(_ text: String) throws -> TranscriptHistoryEntry? {
        if let loadError {
            throw loadError
        }
        guard let entry = history.append(text: text) else { return nil }
        try persist()
        return entry
    }

    func removeAll() throws {
        history.removeAll()
        loadError = nil
        try persist()
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(history.entries)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("Parloq", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("dictation-history.json")
    }
}
