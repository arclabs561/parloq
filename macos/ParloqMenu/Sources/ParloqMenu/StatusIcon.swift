import AppKit

@MainActor
enum StatusIcon {
    static let ready = makeReady(description: "Parloq ready")

    static let listening = makeListening(description: "Parloq listening")

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

    private static func makeListening(description: String) -> NSImage {
        let image = NSImage(
            size: NSSize(width: 20, height: 18),
            flipped: false
        ) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSBezierPath(
                ovalIn: NSRect(x: 0.8, y: 6.7, width: 4.6, height: 4.6)
            ).fill()

            let waveform = NSBezierPath()
            waveform.lineWidth = 1.9
            waveform.lineCapStyle = .round
            waveform.lineJoinStyle = .round
            waveform.move(to: NSPoint(x: 6.5, y: 9))
            waveform.curve(
                to: NSPoint(x: 8.5, y: 7.5),
                controlPoint1: NSPoint(x: 7.1, y: 9),
                controlPoint2: NSPoint(x: 7.8, y: 11.8)
            )
            waveform.curve(
                to: NSPoint(x: 10.5, y: 11.5),
                controlPoint1: NSPoint(x: 9.2, y: 4.6),
                controlPoint2: NSPoint(x: 9.8, y: 4.0)
            )
            waveform.curve(
                to: NSPoint(x: 12.9, y: 6.0),
                controlPoint1: NSPoint(x: 11.2, y: 15.4),
                controlPoint2: NSPoint(x: 12.0, y: 14.7)
            )
            waveform.curve(
                to: NSPoint(x: 15.2, y: 9),
                controlPoint1: NSPoint(x: 13.7, y: 2.9),
                controlPoint2: NSPoint(x: 14.2, y: 9)
            )
            waveform.line(to: NSPoint(x: 18.1, y: 9))
            waveform.stroke()

            let cursor = NSBezierPath()
            cursor.lineWidth = 2.5
            cursor.lineCapStyle = .round
            cursor.move(to: NSPoint(x: 18.2, y: 3.7))
            cursor.line(to: NSPoint(x: 18.2, y: 14.3))
            cursor.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
