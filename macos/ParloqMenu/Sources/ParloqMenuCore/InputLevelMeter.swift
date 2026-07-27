import Foundation

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

public struct InputSpectrum: Equatable, Sendable {
    public static let bandCount = 9
    public let bandDBFS: [Double]
    public let hasTelemetry: Bool

    public init(dbFS: [Double]?) {
        hasTelemetry = dbFS != nil
        let finiteBands = (dbFS ?? []).prefix(Self.bandCount).map {
            $0.isFinite ? min(0, max(-120, $0)) : -120
        }
        bandDBFS = finiteBands
            + Array(
                repeating: -120,
                count: Self.bandCount - finiteBands.count
            )
    }

    public var normalizedBands: [Double] {
        bandDBFS.map { dbFS in
            let linear = min(1, max(0, (dbFS + 72) / 72))
            return pow(linear, 0.72)
        }
    }

    public var isSilent: Bool {
        normalizedBands.allSatisfy { $0 == 0 }
    }

    public var iconBands: [Double] {
        let groups = [[0, 1], [2, 3], [4, 5], [6, 7, 8]]
        return groups.map { indices in
            indices.map { normalizedBands[$0] }.max() ?? 0
        }
    }
}
