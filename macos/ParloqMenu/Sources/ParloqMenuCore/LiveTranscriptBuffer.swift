public struct LiveTranscriptBuffer: Sendable {
    public private(set) var text = ""

    public init() {}

    public mutating func reset() {
        text = ""
    }

    public mutating func update(snapshot: String) -> String? {
        guard !snapshot.isEmpty, snapshot != text else {
            return nil
        }
        text = snapshot
        return snapshot
    }
}
