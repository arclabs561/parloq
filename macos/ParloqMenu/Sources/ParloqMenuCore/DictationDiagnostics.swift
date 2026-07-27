import Foundation

public enum DictationDiagnostics {
    public static func render(
        appVersion: String?,
        systemVersion: String?,
        connected: Bool,
        phase: DictatePhase?,
        accessibilityGranted: Bool,
        details: DictationDetails
    ) -> String {
        var lines = ["Parloq diagnostics"]

        append("App", appVersion, to: &lines)
        append("System", systemVersion, to: &lines)
        lines.append("Daemon: \(connected ? "connected" : "unavailable")")
        lines.append("Phase: \(phase?.rawValue ?? "unknown")")
        lines.append(
            "Accessibility: \(accessibilityGranted ? "granted" : "missing")"
        )

        let microphone = [details.deviceName, details.device]
            .compactMap(nonempty)
            .joined(separator: " · ")
        append("Microphone", microphone, to: &lines)
        append("Model", details.model, to: &lines)

        append(
            "Vocabulary corrections",
            details.vocabCount.map(String.init),
            to: &lines
        )
        append(
            "Live update interval",
            details.streamIntervalSeconds.map {
                "\(format($0, digits: 2)) s"
            },
            to: &lines
        )
        appendMode("Polish final text", details.polishEnabled, to: &lines)
        appendMode(
            "Voice level analysis",
            details.prosodyEnabled,
            to: &lines
        )
        appendMode("Save recordings", details.saveEnabled, to: &lines)
        appendMode("Chimes", details.chimeEnabled, to: &lines)

        append(
            "Voice baseline samples",
            details.prosodyBaselineCount.map(String.init),
            to: &lines
        )
        append(
            "Latest voice state",
            details.latestProsodyState.map(prosodyState),
            to: &lines
        )
        append(
            "Latest voice RMS",
            details.latestProsodyRMSDB.map {
                "\(format($0, digits: 1)) dBFS"
            },
            to: &lines
        )
        append(
            "Latest audio",
            details.lastAudioSeconds.map {
                "\(format($0, digits: 2)) s"
            },
            to: &lines
        )
        append(
            "Latest ASR",
            details.lastASRSeconds.map {
                "\(format($0, digits: 2)) s"
            },
            to: &lines
        )
        append(
            "Latest ASR speed",
            details.latestRealtimeFactor.map {
                "\(format($0, digits: 2))× realtime"
            },
            to: &lines
        )

        return lines.joined(separator: "\n")
    }

    private static func append(
        _ label: String,
        _ value: String?,
        to lines: inout [String]
    ) {
        guard let value = nonempty(value) else { return }
        lines.append("\(label): \(value)")
    }

    private static func appendMode(
        _ label: String,
        _ enabled: Bool?,
        to lines: inout [String]
    ) {
        guard let enabled else { return }
        lines.append("\(label): \(enabled ? "on" : "off")")
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func prosodyState(
        _ state: DictationProsodyState
    ) -> String {
        switch state {
        case .calibrating:
            return "learning baseline"
        case .baseline:
            return "typical"
        case .elevated:
            return "above usual"
        case .insufficientAudio:
            return "insufficient speech"
        case let .unknown(value):
            return "unknown (\(value))"
        }
    }

    private static func format(_ value: Double, digits: Int) -> String {
        value.formatted(
            .number.precision(.fractionLength(digits))
        )
    }
}
