import Testing
@testable import ParloqMenuCore

@Test func liveTranscriptReplacesDraftsAndIgnoresTransientEmpties() {
    var buffer = LiveTranscriptBuffer()

    #expect(buffer.update(snapshot: "Hello wor") == "Hello wor")
    #expect(buffer.update(snapshot: "") == nil)
    #expect(buffer.text == "Hello wor")
    #expect(buffer.update(snapshot: "Hello world") == "Hello world")
    #expect(buffer.update(snapshot: "Hello world") == nil)
}

@Test func liveTranscriptResetStartsANewSession() {
    var buffer = LiveTranscriptBuffer()
    _ = buffer.update(snapshot: "First dictation")

    buffer.reset()

    #expect(buffer.text.isEmpty)
    #expect(buffer.update(snapshot: "Second dictation") == "Second dictation")
}
