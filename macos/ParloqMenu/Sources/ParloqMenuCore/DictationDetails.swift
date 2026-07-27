public struct DictationDetails: Equatable, Sendable {
    public private(set) var device: String?
    public private(set) var deviceName: String?
    public private(set) var deviceAvailable: Bool?
    public private(set) var availableDevices: [DictationDevice]?
    public private(set) var configurationWarning: String?
    public private(set) var model: String?
    public private(set) var prosodyEnabled: Bool?
    public private(set) var latestProsodyState: DictationProsodyState?
    public private(set) var latestProsodyEnergyZ: Double?
    public private(set) var prosodyBaselineCount: Int?
    public private(set) var latestProsodyRMSDB: Double?
    public private(set) var polishEnabled: Bool?
    public private(set) var chimeEnabled: Bool?
    public private(set) var saveEnabled: Bool?
    public private(set) var recordingsPath: String?
    public private(set) var vocabCount: Int?
    public private(set) var vocabPath: String?
    public private(set) var vocabWarning: String?
    public private(set) var streamIntervalSeconds: Double?
    public private(set) var lastAudioSeconds: Double?
    public private(set) var lastASRSeconds: Double?

    public init(
        device: String? = nil,
        deviceName: String? = nil,
        deviceAvailable: Bool? = nil,
        availableDevices: [DictationDevice]? = nil,
        configurationWarning: String? = nil,
        model: String? = nil,
        prosodyEnabled: Bool? = nil,
        latestProsodyState: DictationProsodyState? = nil,
        latestProsodyEnergyZ: Double? = nil,
        prosodyBaselineCount: Int? = nil,
        latestProsodyRMSDB: Double? = nil,
        polishEnabled: Bool? = nil,
        chimeEnabled: Bool? = nil,
        saveEnabled: Bool? = nil,
        recordingsPath: String? = nil,
        vocabCount: Int? = nil,
        vocabPath: String? = nil,
        vocabWarning: String? = nil,
        streamIntervalSeconds: Double? = nil,
        lastAudioSeconds: Double? = nil,
        lastASRSeconds: Double? = nil
    ) {
        self.device = device
        self.deviceName = deviceName
        self.deviceAvailable = deviceAvailable
        self.availableDevices = availableDevices
        self.configurationWarning = configurationWarning
        self.model = model
        self.prosodyEnabled = prosodyEnabled
        self.latestProsodyState = latestProsodyState
        self.latestProsodyEnergyZ = latestProsodyEnergyZ
        self.prosodyBaselineCount = prosodyBaselineCount
        self.latestProsodyRMSDB = latestProsodyRMSDB
        self.polishEnabled = polishEnabled
        self.chimeEnabled = chimeEnabled
        self.saveEnabled = saveEnabled
        self.recordingsPath = recordingsPath
        self.vocabCount = vocabCount
        self.vocabPath = vocabPath
        self.vocabWarning = vocabWarning
        self.streamIntervalSeconds = streamIntervalSeconds
        self.lastAudioSeconds = lastAudioSeconds
        self.lastASRSeconds = lastASRSeconds
    }

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
        deviceName = event.deviceName ?? deviceName
        if event.deviceAvailable != nil {
            deviceAvailable = event.deviceAvailable
            configurationWarning = event.configurationWarning
        }
        availableDevices = event.availableDevices ?? availableDevices
        model = event.model ?? model
        prosodyEnabled = event.prosodyEnabled ?? prosodyEnabled
        latestProsodyState = event.prosodyState ?? latestProsodyState
        latestProsodyEnergyZ =
            event.prosodyEnergyZ ?? latestProsodyEnergyZ
        prosodyBaselineCount =
            event.prosodyBaselineCount ?? prosodyBaselineCount
        latestProsodyRMSDB = event.prosodyRMSDB ?? latestProsodyRMSDB
        polishEnabled = event.polishEnabled ?? polishEnabled
        chimeEnabled = event.chimeEnabled ?? chimeEnabled
        saveEnabled = event.saveEnabled ?? saveEnabled
        recordingsPath = event.recordingsPath ?? recordingsPath
        vocabCount = event.vocabCount ?? vocabCount
        vocabPath = event.vocabPath ?? vocabPath
        if event.vocabPath != nil {
            vocabWarning = event.vocabWarning
        }
        streamIntervalSeconds =
            event.streamIntervalSeconds ?? streamIntervalSeconds

        guard event.type == .final else { return }
        lastAudioSeconds = event.elapsedSeconds
        lastASRSeconds = event.asrSeconds
    }
}
