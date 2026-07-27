public enum DictationOverlayPhase: Equatable, Sendable {
    case idle
    case listening
    case finishing
    case recovering(message: String)
}

public struct DictationOverlayModel: Sendable {
    public private(set) var phase: DictationOverlayPhase = .idle
    public private(set) var snapshot: LiveTranscriptSnapshot?
    private var buffer = LiveTranscriptBuffer()

    public var text: String {
        snapshot?.text ?? ""
    }

    public init() {}

    public mutating func begin() {
        buffer.reset()
        snapshot = nil
        phase = .listening
    }

    @discardableResult
    public mutating func update(
        snapshot text: String,
        finalizedText: String? = nil,
        draftText: String? = nil
    ) -> LiveTranscriptSnapshot? {
        guard phase == .listening || phase == .finishing else {
            return nil
        }
        guard let update = buffer.update(
            snapshot: text,
            finalizedText: finalizedText,
            draftText: draftText
        ) else {
            return nil
        }
        snapshot = update
        return update
    }

    public mutating func markFinishing() {
        guard phase == .listening else { return }
        phase = .finishing
    }

    @discardableResult
    public mutating func fail(
        message: String
    ) -> LiveTranscriptSnapshot? {
        guard let snapshot else {
            complete()
            return nil
        }
        phase = .recovering(message: message)
        return snapshot
    }

    public mutating func complete() {
        buffer.reset()
        snapshot = nil
        phase = .idle
    }
}
