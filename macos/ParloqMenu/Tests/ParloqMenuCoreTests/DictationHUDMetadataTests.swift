import ParloqMenuCore
import Testing

@Test func hudMetadataNamesTargetModeAndElapsedTime() {
    var metadata = DictationHUDMetadata(
        targetApplication: "Notes",
        deliveryMode: .directInsertion
    )

    #expect(metadata.contextLabel == "Notes · Live insert")
    #expect(metadata.elapsedLabel == "0:00")

    metadata.updateElapsed(65.9)

    #expect(metadata.elapsedLabel == "1:05")

    metadata.updateDeliveryMode(.targetChanged)

    #expect(
        metadata.contextLabel
            == "Safe copy · final goes to clipboard"
    )
}

@Test func hudMetadataHandlesFallbackAndMonotonicElapsedUpdates() {
    var metadata = DictationHUDMetadata(
        targetApplication: "  ",
        deliveryMode: .clipboardFallback,
        elapsedSeconds: 8
    )

    #expect(metadata.contextLabel == "Final goes to clipboard")
    metadata.updateElapsed(4)
    metadata.updateElapsed(nil)
    metadata.updateElapsed(.infinity)

    #expect(metadata.elapsedLabel == "0:08")
}
