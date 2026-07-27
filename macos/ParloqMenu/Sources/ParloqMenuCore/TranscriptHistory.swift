import Foundation

public struct TranscriptHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let rawText: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        rawText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.createdAt = createdAt
    }
}

public struct TranscriptHistory: Equatable, Sendable {
    public static let defaultLimit = 50

    public private(set) var entries: [TranscriptHistoryEntry]
    public let limit: Int

    public init(
        entries: [TranscriptHistoryEntry] = [],
        limit: Int = defaultLimit
    ) {
        self.limit = max(1, limit)
        self.entries = Array(entries.prefix(self.limit))
    }

    @discardableResult
    public mutating func append(
        text: String,
        rawText: String? = nil,
        id: UUID = UUID(),
        at date: Date = Date()
    ) -> TranscriptHistoryEntry? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let normalizedRaw = rawText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = TranscriptHistoryEntry(
            id: id,
            text: normalized,
            rawText: normalizedRaw?.isEmpty == false ? normalizedRaw : nil,
            createdAt: date
        )
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        return entry
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
