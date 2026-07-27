public struct InputLevelMeter: Equatable, Sendable {
    public let dbFS: Double?

    public init(dbFS: Double?) {
        self.dbFS = dbFS?.isFinite == true ? dbFS : nil
    }

    public var normalizedLevel: Double {
        guard let dbFS else { return 0 }
        return min(1, max(0, (dbFS + 60) / 60))
    }

    public var activeBars: Int {
        guard normalizedLevel > 0 else { return 0 }
        return min(5, Int((normalizedLevel * 5).rounded(.up)))
    }
}
