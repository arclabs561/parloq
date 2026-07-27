import Foundation

public let dictateProtocolVersion = 1

public enum DictateCommand: String, Encodable, Sendable {
    case status
    case start
    case stop
    case cancel
    case subscribe
}

public enum DictatePhase: String, Decodable, Sendable {
    case warming
    case idle
    case recording
    case finalizing
    case polishing
    case error
}

public enum DictateEventType: String, Decodable, Sendable {
    case ack
    case status
    case transcript
    case final
    case error
}

public enum DictationProsodyState: Equatable, Sendable {
    case calibrating
    case baseline
    case elevated
    case insufficientAudio
    case unknown(String)
}

extension DictationProsodyState: Decodable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "calibrating":
            self = .calibrating
        case "baseline":
            self = .baseline
        case "elevated":
            self = .elevated
        case "insufficient_audio":
            self = .insufficientAudio
        default:
            self = .unknown(value)
        }
    }
}

public struct DictateRequest: Encodable, Sendable {
    public let version: Int
    public let command: DictateCommand

    public init(command: DictateCommand) {
        self.version = dictateProtocolVersion
        self.command = command
    }
}

public struct DictateEvent: Decodable, Sendable {
    public let version: Int
    public let type: DictateEventType
    public let phase: DictatePhase
    public let sequence: Int
    public let sessionID: String?
    public let text: String?
    public let finalizedText: String?
    public let draftText: String?
    public let message: String?
    public let elapsedSeconds: Double?
    public let inputPeakDB: Double?
    public let inputSpectrumDB: [Double]?
    public let asrSeconds: Double?
    public let device: String?
    public let deviceName: String?
    public let model: String?
    public let prosodyEnabled: Bool?
    public let prosodyState: DictationProsodyState?
    public let prosodyEnergyZ: Double?
    public let prosodyBaselineCount: Int?
    public let prosodyRMSDB: Double?
    public let polishEnabled: Bool?
    public let chimeEnabled: Bool?
    public let saveEnabled: Bool?
    public let vocabCount: Int?
    public let streamIntervalSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case version
        case type
        case phase
        case sequence
        case sessionID = "session_id"
        case text
        case finalizedText = "finalized_text"
        case draftText = "draft_text"
        case message
        case elapsedSeconds = "elapsed_seconds"
        case inputPeakDB = "input_peak_db"
        case inputSpectrumDB = "input_spectrum_db"
        case asrSeconds = "asr_seconds"
        case device
        case deviceName = "device_name"
        case model
        case prosodyEnabled = "prosody_enabled"
        case prosodyState = "prosody_state"
        case prosodyEnergyZ = "prosody_energy_z"
        case prosodyBaselineCount = "prosody_baseline_count"
        case prosodyRMSDB = "prosody_rms_db"
        case polishEnabled = "polish_enabled"
        case chimeEnabled = "chime_enabled"
        case saveEnabled = "save_enabled"
        case vocabCount = "vocab_count"
        case streamIntervalSeconds = "stream_interval_seconds"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == dictateProtocolVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: values,
                debugDescription: "Unsupported dictation protocol version \(version)"
            )
        }
        type = try values.decode(DictateEventType.self, forKey: .type)
        phase = try values.decode(DictatePhase.self, forKey: .phase)
        sequence = try values.decode(Int.self, forKey: .sequence)
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        finalizedText = try values.decodeIfPresent(
            String.self, forKey: .finalizedText)
        draftText = try values.decodeIfPresent(String.self, forKey: .draftText)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        elapsedSeconds = try values.decodeIfPresent(
            Double.self, forKey: .elapsedSeconds)
        inputPeakDB = try values.decodeIfPresent(
            Double.self, forKey: .inputPeakDB)
        inputSpectrumDB = try values.decodeIfPresent(
            [Double].self, forKey: .inputSpectrumDB)
        asrSeconds = try values.decodeIfPresent(
            Double.self, forKey: .asrSeconds)
        device = try values.decodeIfPresent(String.self, forKey: .device)
        deviceName = try values.decodeIfPresent(
            String.self, forKey: .deviceName)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        prosodyEnabled = try values.decodeIfPresent(
            Bool.self, forKey: .prosodyEnabled)
        prosodyState = try values.decodeIfPresent(
            DictationProsodyState.self, forKey: .prosodyState)
        prosodyEnergyZ = try values.decodeIfPresent(
            Double.self, forKey: .prosodyEnergyZ)
        prosodyBaselineCount = try values.decodeIfPresent(
            Int.self, forKey: .prosodyBaselineCount)
        prosodyRMSDB = try values.decodeIfPresent(
            Double.self, forKey: .prosodyRMSDB)
        polishEnabled = try values.decodeIfPresent(
            Bool.self, forKey: .polishEnabled)
        chimeEnabled = try values.decodeIfPresent(
            Bool.self, forKey: .chimeEnabled)
        saveEnabled = try values.decodeIfPresent(
            Bool.self, forKey: .saveEnabled)
        vocabCount = try values.decodeIfPresent(
            Int.self, forKey: .vocabCount)
        streamIntervalSeconds = try values.decodeIfPresent(
            Double.self, forKey: .streamIntervalSeconds)
    }
}
