import Foundation
import Testing
@testable import ParloqMenuCore

@Test func historyAppendsEveryCompletedDictationNewestFirst() {
    var history = TranscriptHistory(limit: 3)
    let firstID = UUID()
    let secondID = UUID()

    #expect(history.append(
        text: "  Same words  ",
        rawText: "  same words  ",
        id: firstID,
        at: Date(timeIntervalSince1970: 1)
    )?.text == "Same words")
    #expect(history.append(
        text: "Same words",
        id: secondID,
        at: Date(timeIntervalSince1970: 2)
    )?.id == secondID)

    #expect(history.entries.map(\.id) == [secondID, firstID])
    #expect(history.entries[1].rawText == "same words")
}

@Test func historyRejectsEmptyTextAndStaysBounded() {
    var history = TranscriptHistory(limit: 2)

    #expect(history.append(text: " \n ") == nil)
    _ = history.append(text: "one")
    _ = history.append(text: "two")
    _ = history.append(text: "three")

    #expect(history.entries.map(\.text) == ["three", "two"])
}

@Test func historyEntriesRoundTripWithoutLosingIdentityOrTime() throws {
    let entry = TranscriptHistoryEntry(
        id: UUID(),
        text: "A saved dictation.",
        rawText: "a saved dictation",
        createdAt: Date(timeIntervalSince1970: 123)
    )

    let data = try JSONEncoder().encode([entry])
    let decoded = try JSONDecoder().decode(
        [TranscriptHistoryEntry].self,
        from: data
    )

    #expect(decoded == [entry])
}

@Test func legacyHistoryEntryDecodesWithoutInventingRawText() throws {
    let id = UUID()
    let data = Data("""
        [{
          "id": "\(id.uuidString)",
          "text": "Previously saved final.",
          "createdAt": 123
        }]
        """.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let entries = try decoder.decode([TranscriptHistoryEntry].self, from: data)

    #expect(entries.count == 1)
    #expect(entries[0].id == id)
    #expect(entries[0].text == "Previously saved final.")
    #expect(entries[0].rawText == nil)
}
