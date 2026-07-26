import Foundation

public enum DeliveryStrategy: Sendable {
    case rangeReplacement
    case finalizedAppend
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
    private var emittedFinalized = ""

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

        case .finalizedAppend:
            let candidate = isFinal ? text : finalizedText
            guard candidate != emittedFinalized else {
                return .none
            }
            guard candidate.hasPrefix(emittedFinalized) else {
                if isFinal {
                    strategy = .disabled
                    return .copy(text)
                }
                return .none
            }
            let boundary = candidate.index(
                candidate.startIndex,
                offsetBy: emittedFinalized.count
            )
            let suffix = String(candidate[boundary...])
            emittedFinalized = candidate
            return suffix.isEmpty ? .none : .append(suffix)

        case .disabled:
            return isFinal ? .copy(text) : .none
        }
    }

    public mutating func disableReplacement() {
        strategy = .disabled
    }
}
