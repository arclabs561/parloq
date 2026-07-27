import Foundation

public enum DictationDeliveryMode: Equatable, Sendable {
    case directInsertion
    case keyboardFallback
    case clipboardFallback

    public var displayName: String {
        switch self {
        case .directInsertion:
            return "LIVE INSERT"
        case .keyboardFallback:
            return "TYPE ON FINISH"
        case .clipboardFallback:
            return "COPIES FINAL"
        }
    }
}

public struct DictationHUDMetadata: Equatable, Sendable {
    public let targetApplication: String?
    public let deliveryMode: DictationDeliveryMode
    public private(set) var elapsedSeconds: Double

    public init(
        targetApplication: String?,
        deliveryMode: DictationDeliveryMode,
        elapsedSeconds: Double = 0
    ) {
        self.targetApplication = targetApplication?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.deliveryMode = deliveryMode
        self.elapsedSeconds = max(0, elapsedSeconds)
    }

    public var contextLabel: String {
        let target = targetApplication
            .flatMap { $0.isEmpty ? nil : $0.uppercased() }
        return [target, deliveryMode.displayName]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    public var elapsedLabel: String {
        let totalSeconds = Int(elapsedSeconds.rounded(.down))
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    public mutating func updateElapsed(_ seconds: Double?) {
        guard let seconds, seconds.isFinite else { return }
        elapsedSeconds = max(elapsedSeconds, max(0, seconds))
    }
}
