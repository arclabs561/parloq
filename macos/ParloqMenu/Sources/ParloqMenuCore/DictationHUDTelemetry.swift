import Foundation

public struct DictationHUDTelemetry: Equatable, Sendable {
    public private(set) var details: DictationDetails
    public private(set) var transcript = ""
    public private(set) var elapsedSeconds = 0.0
    public private(set) var inputPeakDB: Double?
    public private(set) var showsLatestProsodyResult = false

    public init(details: DictationDetails = DictationDetails()) {
        self.details = details
    }

    public mutating func updateDetails(
        _ details: DictationDetails,
        showLatestProsodyResult: Bool = false
    ) {
        self.details = details
        showsLatestProsodyResult = showLatestProsodyResult
    }

    public mutating func updateTranscript(
        _ text: String,
        elapsedSeconds: Double?
    ) {
        transcript = text
        if let elapsedSeconds, elapsedSeconds.isFinite {
            self.elapsedSeconds = max(
                self.elapsedSeconds,
                max(0, elapsedSeconds)
            )
        }
    }

    public mutating func updateInputPeak(_ dbFS: Double?) {
        guard let dbFS, dbFS.isFinite else { return }
        inputPeakDB = max(-120, min(0, dbFS))
    }

    public var summaryLabel: String {
        [
            microphoneLabel,
            modelLabel,
            speakingRateLabel,
            signalLabel,
        ]
        .compactMap(\.self)
        .joined(separator: "  ·  ")
    }

    public var prosodyLabel: String? {
        guard let enabled = details.prosodyEnabled else { return nil }
        guard enabled else { return "Prosody off" }

        if showsLatestProsodyResult, let state = details.latestProsodyState {
            switch state {
            case .elevated:
                if let score = formattedSigma {
                    return "Elevated energy  +\(score)σ"
                }
                return "Elevated energy"
            case .baseline:
                return "Baseline energy"
            case .calibrating:
                return calibrationLabel
            case .insufficientAudio:
                return "Prosody needs more audio"
            case .unknown:
                return "Prosody measured"
            }
        }

        let count = details.prosodyBaselineCount ?? 0
        return count < 3 ? calibrationLabel : "Prosody ready"
    }

    public var completionPerformanceLabel: String? {
        guard let factor = details.latestRealtimeFactor, factor.isFinite else {
            return nil
        }
        return "\(format(factor, fractionDigits: 2))× realtime"
    }

    public var hasElevatedEnergy: Bool {
        showsLatestProsodyResult
            && details.latestProsodyState == .elevated
    }

    private var microphoneLabel: String? {
        let raw = details.deviceName ?? details.device
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "Microphone", with: "Mic")
    }

    private var modelLabel: String? {
        guard let model = details.model else { return nil }
        let short = model.split(separator: "/").last.map(String.init) ?? model
        if short.lowercased() == "parakeet-tdt-0.6b-v3" {
            return "Parakeet 0.6B v3"
        }
        return short
    }

    private var speakingRateLabel: String? {
        guard elapsedSeconds >= 2 else { return nil }
        let words = transcript.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        let wordsPerMinute = Int(
            (Double(words) * 60 / elapsedSeconds).rounded()
        )
        return "\(wordsPerMinute) wpm"
    }

    private var signalLabel: String? {
        guard let inputPeakDB else { return nil }
        let rounded = Int(inputPeakDB.rounded())
        return "\(rounded < 0 ? "−" : "")\(abs(rounded)) dBFS"
    }

    private var calibrationLabel: String {
        let count = min(3, max(0, details.prosodyBaselineCount ?? 0))
        return "Prosody calibrating \(count)/3"
    }

    private var formattedSigma: String? {
        guard let score = details.latestProsodyEnergyZ, score.isFinite else {
            return nil
        }
        return format(abs(score), fractionDigits: 1)
    }

    private func format(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(
            .number.precision(.fractionLength(fractionDigits))
        )
    }
}
