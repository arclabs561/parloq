import AppKit

@MainActor
enum StatusIcon {
    static let ready = makeReady(description: "Parloq ready")

    static let listening = symbol(
        named: "waveform.circle.fill",
        description: "Parloq listening",
        pointSize: 15,
        weight: .semibold
    )

    static let finishing = symbol(
        named: "ellipsis.circle",
        description: "Parloq finishing",
        pointSize: 15,
        weight: .semibold
    )

    static let offline = symbol(
        named: "waveform.slash",
        description: "Parloq offline",
        pointSize: 16,
        weight: .medium
    )

    static let error = symbol(
        named: "exclamationmark.triangle.fill",
        description: "Parloq error",
        pointSize: 14,
        weight: .semibold
    )

    private static func symbol(
        named name: String,
        description: String,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) -> NSImage {
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        ) else {
            return makeReady(description: description)
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: weight
        )
        let image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image.isTemplate = true
        return image
    }

    private static func makeReady(description: String) -> NSImage {
        let image = NSImage(
            size: NSSize(width: 20, height: 18),
            flipped: false
        ) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.75
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 1.5, y: 9))
            path.curve(
                to: NSPoint(x: 5.2, y: 8.2),
                controlPoint1: NSPoint(x: 2.8, y: 9),
                controlPoint2: NSPoint(x: 3.8, y: 11.8)
            )
            path.curve(
                to: NSPoint(x: 7.2, y: 11.2),
                controlPoint1: NSPoint(x: 6.0, y: 5.6),
                controlPoint2: NSPoint(x: 6.5, y: 3.8)
            )
            path.curve(
                to: NSPoint(x: 10.0, y: 6.3),
                controlPoint1: NSPoint(x: 8.0, y: 15.2),
                controlPoint2: NSPoint(x: 9.2, y: 15.0)
            )
            path.curve(
                to: NSPoint(x: 12.0, y: 9.8),
                controlPoint1: NSPoint(x: 10.6, y: 2.8),
                controlPoint2: NSPoint(x: 11.3, y: 4.0)
            )
            path.curve(
                to: NSPoint(x: 14.5, y: 9),
                controlPoint1: NSPoint(x: 12.8, y: 12.2),
                controlPoint2: NSPoint(x: 13.3, y: 9)
            )
            path.line(to: NSPoint(x: 18.2, y: 9))
            path.move(to: NSPoint(x: 18.2, y: 4.2))
            path.line(to: NSPoint(x: 18.2, y: 13.8))
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
