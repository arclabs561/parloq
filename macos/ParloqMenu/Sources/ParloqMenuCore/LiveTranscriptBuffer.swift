import Foundation

public struct LiveTranscriptSnapshot: Equatable, Sendable {
    public let text: String
    public let settledText: String
    public let activeText: String

    public init(text: String, settledText: String, activeText: String) {
        self.text = text
        self.settledText = settledText
        self.activeText = activeText
    }
}

public struct LiveTranscriptBuffer: Sendable {
    public private(set) var current: LiveTranscriptSnapshot?

    public var text: String {
        current?.text ?? ""
    }

    public init() {}

    public mutating func reset() {
        current = nil
    }

    public mutating func update(
        snapshot: String,
        finalizedText: String? = nil,
        draftText: String? = nil
    ) -> LiveTranscriptSnapshot? {
        guard !snapshot.isEmpty else {
            return nil
        }

        let partition = Self.partition(
            text: snapshot,
            finalizedText: finalizedText ?? "",
            draftText: draftText ?? ""
        )
        guard partition != current else { return nil }
        current = partition
        return partition
    }

    private static func partition(
        text: String,
        finalizedText: String,
        draftText: String
    ) -> LiveTranscriptSnapshot {
        var settled = finalizedText.trimmingCharacters(
            in: .whitespacesAndNewlines)
        var active = draftText.trimmingCharacters(
            in: .whitespacesAndNewlines)

        if !settled.isEmpty, text.hasPrefix(settled) {
            active = String(text.dropFirst(settled.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if active.isEmpty {
            active = text
            settled = ""
        }

        if active.isEmpty {
            (settled, active) = splitBeforeActiveTail(text)
        } else {
            let (olderDraft, activeTail) = splitBeforeActiveTail(active)
            if !olderDraft.isEmpty {
                settled = join(settled, olderDraft)
                active = activeTail
            }
        }

        return LiveTranscriptSnapshot(
            text: text,
            settledText: settled,
            activeText: active
        )
    }

    private static func splitBeforeActiveTail(
        _ text: String
    ) -> (String, String) {
        let characters = Array(text)
        guard !characters.isEmpty else { return ("", "") }

        var sentenceStart: Int?
        for index in 0..<(characters.count - 1) {
            guard ".!?".contains(characters[index]),
                  characters[index + 1].isWhitespace
            else {
                continue
            }
            var next = index + 1
            while next < characters.count, characters[next].isWhitespace {
                next += 1
            }
            if next < characters.count {
                sentenceStart = next
            }
        }
        if let sentenceStart {
            return (
                String(characters[..<sentenceStart])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                String(characters[sentenceStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        var wordStarts: [String.Index] = []
        var insideWord = false
        for index in text.indices {
            if text[index].isWhitespace {
                insideWord = false
            } else if !insideWord {
                wordStarts.append(index)
                insideWord = true
            }
        }
        let activeWordCount = 14
        guard wordStarts.count > activeWordCount else {
            return ("", text)
        }
        let splitIndex = wordStarts[wordStarts.count - activeWordCount]
        return (
            String(text[..<splitIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            String(text[splitIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func join(_ left: String, _ right: String) -> String {
        [left, right]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
