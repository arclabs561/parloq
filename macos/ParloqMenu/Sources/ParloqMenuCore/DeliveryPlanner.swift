import Foundation

public enum DeliveryStrategy: Sendable {
    case rangeReplacement
    case finalOnly
    case disabled
}

public enum DeliveryAction: Equatable, Sendable {
    case replace(String)
    case append(String)
    case copy(String)
    case none
}

public struct DeliveryPlanner: Sendable {
    public private(set) var strategy: DeliveryStrategy

    public init(strategy: DeliveryStrategy) {
        self.strategy = strategy
    }

    public mutating func plan(
        text: String,
        finalizedText: String,
        isFinal: Bool
    ) -> DeliveryAction {
        switch strategy {
        case .rangeReplacement:
            return .replace(text)

        case .finalOnly:
            return isFinal && !text.isEmpty ? .append(text) : .none

        case .disabled:
            return isFinal ? .copy(text) : .none
        }
    }

    public mutating func disableReplacement() {
        strategy = .disabled
    }

    public mutating func invalidateFinalOnly() -> Bool {
        guard case .finalOnly = strategy else {
            return false
        }
        strategy = .disabled
        return true
    }
}
