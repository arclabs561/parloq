import ParloqMenuCore
import Testing

@Test func diagnosticsReportRuntimeFactsWithoutPrivateText() {
    let diagnostics = DictationDiagnostics.render(
        appVersion: "0.1.0 (1)",
        systemVersion: "macOS 26.0",
        connected: true,
        phase: .idle,
        accessibilityGranted: true,
        details: DictationDetails(
            device: ":2",
            deviceName: "Studio Display Microphone",
            deviceAvailable: true,
            availableDevices: [
                DictationDevice(
                    id: ":2",
                    name: "Studio Display Microphone"
                ),
            ],
            model: "mlx-community/parakeet-tdt-0.6b-v3",
            prosodyEnabled: true,
            latestProsodyState: .baseline,
            prosodyBaselineCount: 4,
            latestProsodyRMSDB: -24.5,
            polishEnabled: false,
            chimeEnabled: false,
            saveEnabled: false,
            vocabCount: 7,
            streamIntervalSeconds: 0.5,
            lastAudioSeconds: 4.25,
            lastASRSeconds: 0.75
        )
    )

    #expect(diagnostics.contains("Daemon: connected"))
    #expect(diagnostics.contains("Accessibility: granted"))
    #expect(
        diagnostics.contains(
            "Microphone: Studio Display Microphone · :2"
        )
    )
    #expect(diagnostics.contains("Microphone available: yes"))
    #expect(diagnostics.contains("Audio inputs found: 1"))
    #expect(diagnostics.contains("Latest voice state: typical"))
    #expect(diagnostics.contains("Latest ASR speed: 0.18× realtime"))
    #expect(!diagnostics.localizedCaseInsensitiveContains("transcript"))
    #expect(!diagnostics.localizedCaseInsensitiveContains("target app"))
}

@Test func diagnosticsStayUsefulWhenDaemonIsUnavailable() {
    let diagnostics = DictationDiagnostics.render(
        appVersion: nil,
        systemVersion: nil,
        connected: false,
        phase: nil,
        accessibilityGranted: false,
        details: DictationDetails()
    )

    #expect(
        diagnostics
            == """
            Parloq diagnostics
            Daemon: unavailable
            Phase: unknown
            Accessibility: missing
            """
    )
}
