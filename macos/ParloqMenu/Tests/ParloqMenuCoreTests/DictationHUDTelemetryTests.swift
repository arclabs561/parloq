import ParloqMenuCore
import Testing

@Test func hudTelemetryFormatsUsefulLiveSignals() {
    var telemetry = DictationHUDTelemetry(details: DictationDetails(
        device: ":0",
        deviceName: "Studio Display Microphone",
        model: "mlx-community/parakeet-tdt-0.6b-v3",
        prosodyEnabled: true,
        prosodyBaselineCount: 2,
        saveEnabled: true
    ))

    telemetry.updateTranscript(
        "One two three four five six seven eight.",
        elapsedSeconds: 8
    )
    telemetry.updateInputPeak(-17.4)

    #expect(
        telemetry.summaryLabel
            == "Studio Display Mic  ·  Saving audio  ·  60 wpm  ·  −17 dBFS"
    )
    #expect(
        telemetry.prosodyLabel == "Learning typical voice level · 2/3"
    )
}

@Test func hudTelemetryKeepsFinalProsodyNarrowAndHonest() {
    var telemetry = DictationHUDTelemetry()
    telemetry.updateDetails(
        DictationDetails(
            prosodyEnabled: true,
            latestProsodyState: .elevated,
            latestProsodyEnergyZ: 1.36,
            prosodyBaselineCount: 7,
            lastAudioSeconds: 12,
            lastASRSeconds: 1.8
        ),
        showLatestProsodyResult: true
    )

    #expect(telemetry.prosodyLabel == "Voice level · above usual")
    #expect(telemetry.completionPerformanceLabel == "0.15× realtime")
    #expect(telemetry.hasElevatedEnergy)
}

@Test func hudTelemetryHidesNonActionableReadyState() {
    let telemetry = DictationHUDTelemetry(details: DictationDetails(
        prosodyEnabled: true,
        prosodyBaselineCount: 3
    ))

    #expect(telemetry.prosodyLabel == nil)
}

@Test func hudTelemetryDoesNotPretendUnknownProsodyIsEmotion() {
    var telemetry = DictationHUDTelemetry()
    telemetry.updateDetails(
        DictationDetails(
            prosodyEnabled: true,
            latestProsodyState: .unknown("future_measure")
        ),
        showLatestProsodyResult: true
    )

    #expect(telemetry.prosodyLabel == "Voice level measured")
}
