public struct DictationDetails: Equatable, Sendable {
    public private(set) var device: String?
    public private(set) var model: String?
    public private(set) var prosodyEnabled: Bool?
    public private(set) var polishEnabled: Bool?
    public private(set) var chimeEnabled: Bool?
    public private(set) var saveEnabled: Bool?
    public private(set) var vocabCount: Int?
    public private(set) var streamIntervalSeconds: Double?
    public private(set) var lastAudioSeconds: Double?
    public private(set) var lastASRSeconds: Double?

    public init() {}

    public var latestRealtimeFactor: Double? {
        guard let audio = lastAudioSeconds,
              audio > 0,
              let asr = lastASRSeconds
        else {
            return nil
        }
        return asr / audio
    }

    public mutating func update(from event: DictateEvent) {
        device = event.device ?? device
        model = event.model ?? model
        prosodyEnabled = event.prosodyEnabled ?? prosodyEnabled
        polishEnabled = event.polishEnabled ?? polishEnabled
        chimeEnabled = event.chimeEnabled ?? chimeEnabled
        saveEnabled = event.saveEnabled ?? saveEnabled
        vocabCount = event.vocabCount ?? vocabCount
        streamIntervalSeconds =
            event.streamIntervalSeconds ?? streamIntervalSeconds

        guard event.type == .final else { return }
        lastAudioSeconds = event.elapsedSeconds
        lastASRSeconds = event.asrSeconds
    }
}
