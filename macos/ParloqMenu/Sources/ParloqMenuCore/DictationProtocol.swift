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
    public let device: String?
    public let model: String?

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
        case device
        case model
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
        device = try values.decodeIfPresent(String.self, forKey: .device)
        model = try values.decodeIfPresent(String.self, forKey: .model)
    }
}
