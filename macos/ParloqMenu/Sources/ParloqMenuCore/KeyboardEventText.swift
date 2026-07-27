public enum KeyboardEventText {
    public static func isSafeForBlindTyping(_ text: String) -> Bool {
        text.utf16.allSatisfy { unit in
            unit >= 0x0020 && unit != 0x007F
        }
    }

    public static func utf16Chunks(
        for text: String,
        maximumUnits: Int = 20
    ) -> [[UInt16]] {
        precondition(maximumUnits >= 2)
        let units = Array(text.utf16)
        var chunks: [[UInt16]] = []
        var start = 0

        while start < units.count {
            var end = min(start + maximumUnits, units.count)
            if end < units.count,
               isHighSurrogate(units[end - 1]),
               isLowSurrogate(units[end])
            {
                end -= 1
            }
            chunks.append(Array(units[start..<end]))
            start = end
        }
        return chunks
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }
}
