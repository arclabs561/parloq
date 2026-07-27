import Testing
@testable import ParloqMenuCore

@Test func liveTranscriptReplacesDraftsAndIgnoresTransientEmpties() {
    var buffer = LiveTranscriptBuffer()

    #expect(buffer.update(snapshot: "Hello wor")?.activeText == "Hello wor")
    #expect(buffer.update(snapshot: "") == nil)
    #expect(buffer.text == "Hello wor")
    #expect(buffer.update(snapshot: "Hello world")?.text == "Hello world")
    #expect(buffer.update(snapshot: "Hello world") == nil)
}

@Test func liveTranscriptResetStartsANewSession() {
    var buffer = LiveTranscriptBuffer()
    _ = buffer.update(snapshot: "First dictation")

    buffer.reset()

    #expect(buffer.text.isEmpty)
    #expect(
        buffer.update(snapshot: "Second dictation")?.activeText
            == "Second dictation"
    )
}

@Test func liveTranscriptSeparatesSettledContextFromRevisingTail() {
    var buffer = LiveTranscriptBuffer()

    let snapshot = buffer.update(
        snapshot: "The first sentence is settled. The ending is chang",
        finalizedText: "The first sentence is settled.",
        draftText: " The ending is chang"
    )

    #expect(snapshot?.settledText == "The first sentence is settled.")
    #expect(snapshot?.activeText == "The ending is chang")
}

@Test func longUnfinalizedSpeechKeepsOnlyTheRecentWordsActive() {
    var buffer = LiveTranscriptBuffer()
    let words = (1...20).map { "word\($0)" }.joined(separator: " ")

    let snapshot = buffer.update(snapshot: words)

    #expect(snapshot?.settledText == (1...6).map {
        "word\($0)"
    }.joined(separator: " "))
    #expect(snapshot?.activeText == (7...20).map {
        "word\($0)"
    }.joined(separator: " "))
}

@Test func activeTailSplitUsesTheOriginalWhitespaceBoundary() {
    var buffer = LiveTranscriptBuffer()
    let text = (1...6).map { "word\($0)" }.joined(separator: " ")
        + "\n\n"
        + (7...20).map { "word\($0)" }.joined(separator: "  ")

    let snapshot = buffer.update(snapshot: text)

    #expect(snapshot?.settledText == (1...6).map {
        "word\($0)"
    }.joined(separator: " "))
    #expect(snapshot?.activeText == (7...20).map {
        "word\($0)"
    }.joined(separator: "  "))
}
