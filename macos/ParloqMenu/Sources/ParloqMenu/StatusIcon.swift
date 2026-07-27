import AppKit

@MainActor
enum StatusIcon {
    private enum Terminal {
        case cursor
        case strongCursor
        case ellipsis
        case exclamation
        case xmark
    }

    static let ready = makeImage(
        description: "Parloq ready",
        terminal: .cursor
    )

    static let listening: NSImage = {
        let description = "Parloq listening"
        guard let symbol = NSImage(
            systemSymbolName: "waveform.circle.fill",
            accessibilityDescription: description
        ) else {
            return makeImage(
                description: description,
                showsRecordingDot: true,
                terminal: .strongCursor
            )
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        let image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image.isTemplate = true
        return image
    }()

    static let finishing = makeImage(
        description: "Parloq finishing",
        terminal: .ellipsis
    )

    static let offline = makeImage(
        description: "Parloq offline",
        terminal: .xmark
    )

    static let error = makeImage(
        description: "Parloq error",
        terminal: .exclamation
    )

    private static func makeImage(
        description: String,
        showsRecordingDot: Bool = false,
        terminal: Terminal
    ) -> NSImage {
        let image = NSImage(
            size: NSSize(width: 20, height: 18),
            flipped: false
        ) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            if showsRecordingDot {
                NSBezierPath(
                    ovalIn: NSRect(x: 0.6, y: 8, width: 2, height: 2)
                ).fill()
            }

            let path = NSBezierPath()
            path.lineWidth = 1.75
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: showsRecordingDot ? 4.4 : 1.5, y: 9))
            path.curve(
                to: NSPoint(x: 5.2, y: 8.2),
                controlPoint1: NSPoint(x: showsRecordingDot ? 4.7 : 2.8, y: 9),
                controlPoint2: NSPoint(x: showsRecordingDot ? 4.8 : 3.8, y: 11.8)
            )
            path.curve(
                to: NSPoint(x: 7.2, y: 11.2),
                controlPoint1: NSPoint(x: 6.1, y: 5.4),
                controlPoint2: NSPoint(x: 6.7, y: 5.4)
            )
            path.curve(
                to: NSPoint(x: 9.5, y: 7),
                controlPoint1: NSPoint(x: 7.9, y: 16.5),
                controlPoint2: NSPoint(x: 8.6, y: 16.5)
            )
            path.curve(
                to: NSPoint(x: 12.1, y: 7.8),
                controlPoint1: NSPoint(x: 10.4, y: 1.2),
                controlPoint2: NSPoint(x: 11.2, y: 1.2)
            )
            path.curve(
                to: NSPoint(x: 14.1, y: 9),
                controlPoint1: NSPoint(x: 12.8, y: 12.2),
                controlPoint2: NSPoint(x: 13.3, y: 9)
            )

            switch terminal {
            case .cursor:
                path.line(to: NSPoint(x: 18.2, y: 9))
                path.move(to: NSPoint(x: 18.2, y: 4.2))
                path.line(to: NSPoint(x: 18.2, y: 13.8))
            case .strongCursor:
                path.line(to: NSPoint(x: 18.0, y: 9))
                path.move(to: NSPoint(x: 18.0, y: 3.8))
                path.line(to: NSPoint(x: 18.0, y: 14.2))
            case .ellipsis:
                path.stroke()
                for x in [14.6, 16.6, 18.6] {
                    NSBezierPath(
                        ovalIn: NSRect(x: x - 0.75, y: 8.25, width: 1.5, height: 1.5)
                    ).fill()
                }
            case .exclamation:
                path.line(to: NSPoint(x: 15.0, y: 9))
                path.move(to: NSPoint(x: 18.0, y: 7.5))
                path.line(to: NSPoint(x: 18.0, y: 13.8))
                path.stroke()
                NSBezierPath(
                    ovalIn: NSRect(x: 17.15, y: 3.8, width: 1.7, height: 1.7)
                ).fill()
            case .xmark:
                path.line(to: NSPoint(x: 14.8, y: 9))
                path.stroke()
                let mark = NSBezierPath()
                mark.lineWidth = 1.75
                mark.lineCapStyle = .round
                mark.move(to: NSPoint(x: 16.1, y: 6.2))
                mark.line(to: NSPoint(x: 19.0, y: 11.8))
                mark.move(to: NSPoint(x: 19.0, y: 6.2))
                mark.line(to: NSPoint(x: 16.1, y: 11.8))
                mark.stroke()
            }

            if terminal != .ellipsis && terminal != .exclamation && terminal != .xmark {
                if terminal == .strongCursor {
                    path.lineWidth = 2.15
                }
                path.stroke()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
