import ParloqMenuCore
import Testing

@Test func overlayFailureRetainsTheLatestTranscriptUntilDismissed() {
    var overlay = DictationOverlayModel()
    overlay.begin()
    _ = overlay.update(
        snapshot: "Keep this partial transcript",
        finalizedText: "Keep this",
        draftText: " partial transcript"
    )
    overlay.markFinishing()

    let recovery = overlay.fail(message: "Daemon disconnected")

    #expect(overlay.phase == .recovering(message: "Daemon disconnected"))
    #expect(recovery?.text == "Keep this partial transcript")
    #expect(overlay.text == "Keep this partial transcript")

    overlay.complete()

    #expect(overlay.phase == .idle)
    #expect(overlay.snapshot == nil)
}

@Test func overlayFailureWithoutSpeechHasNothingToRecover() {
    var overlay = DictationOverlayModel()
    overlay.begin()

    #expect(overlay.fail(message: "Microphone unavailable") == nil)
    #expect(overlay.phase == .idle)
}

@Test func aNewOverlaySessionClearsAnOlderRecovery() {
    var overlay = DictationOverlayModel()
    overlay.begin()
    _ = overlay.update(snapshot: "Old partial")
    _ = overlay.fail(message: "Connection lost")

    overlay.begin()

    #expect(overlay.phase == .listening)
    #expect(overlay.snapshot == nil)
    #expect(overlay.text.isEmpty)
}
