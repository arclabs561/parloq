import Foundation
import Testing
@testable import ParloqMenuCore

@Test func historyAppendsEveryCompletedDictationNewestFirst() {
    var history = TranscriptHistory(limit: 3)
    let firstID = UUID()
    let secondID = UUID()

    #expect(history.append(
        text: "  Same words  ",
        id: firstID,
        at: Date(timeIntervalSince1970: 1)
    )?.text == "Same words")
    #expect(history.append(
        text: "Same words",
        id: secondID,
        at: Date(timeIntervalSince1970: 2)
    )?.id == secondID)

    #expect(history.entries.map(\.id) == [secondID, firstID])
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
        createdAt: Date(timeIntervalSince1970: 123)
    )

    let data = try JSONEncoder().encode([entry])
    let decoded = try JSONDecoder().decode(
        [TranscriptHistoryEntry].self,
        from: data
    )

    #expect(decoded == [entry])
}
