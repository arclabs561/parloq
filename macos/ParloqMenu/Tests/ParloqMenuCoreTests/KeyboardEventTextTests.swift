import ParloqMenuCore
import Testing

@Test func keyboardChunksNeverSplitASurrogatePairAtTheLimit() {
    let text = String(repeating: "a", count: 19) + "🙂b"
    let chunks = KeyboardEventText.utf16Chunks(
        for: text,
        maximumUnits: 20
    )

    #expect(chunks.map(\.count) == [19, 3])
    #expect(String(decoding: chunks.flatMap { $0 }, as: UTF16.self) == text)
    #expect(chunks.allSatisfy(hasWholeSurrogateBoundaries))
}

@Test func keyboardChunksPreserveNonBMPAndJoinedEmoji() {
    let text = "ab👩🏽‍💻cd🙂ef"
    let chunks = KeyboardEventText.utf16Chunks(
        for: text,
        maximumUnits: 4
    )

    #expect(String(decoding: chunks.flatMap { $0 }, as: UTF16.self) == text)
    #expect(chunks.allSatisfy(hasWholeSurrogateBoundaries))
}

@Test func blindKeyboardTypingRejectsCommandCapableControls() {
    #expect(KeyboardEventText.isSafeForBlindTyping("ordinary text"))
    #expect(!KeyboardEventText.isSafeForBlindTyping("line one\nline two"))
    #expect(!KeyboardEventText.isSafeForBlindTyping("line one\rline two"))
    #expect(!KeyboardEventText.isSafeForBlindTyping("column\tcompletion"))
    #expect(!KeyboardEventText.isSafeForBlindTyping("escape\u{001B}"))
    #expect(!KeyboardEventText.isSafeForBlindTyping("delete\u{007F}"))
}

private func hasWholeSurrogateBoundaries(_ chunk: [UInt16]) -> Bool {
    guard let first = chunk.first, let last = chunk.last else {
        return true
    }
    return !(0xDC00...0xDFFF).contains(first)
        && !(0xD800...0xDBFF).contains(last)
}
