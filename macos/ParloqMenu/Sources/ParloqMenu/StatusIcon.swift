import AppKit
import ParloqMenuCore

@MainActor
enum StatusIcon {
    static let ready = makeReady(description: "Parloq ready")

    static let listening = makeListening(description: "Parloq listening")

    static func listening(
        level: InputLevelMeter,
        spectrum: InputSpectrum
    ) -> NSImage {
        makeListening(
            description: "Parloq listening",
            normalizedLevel: level.normalizedLevel,
            spectrum: spectrum.hasTelemetry ? spectrum.iconBands : nil
        )
    }

    static let finishing = makeFinishing(description: "Parloq finishing")

    static let offline = makeWaveform(
        description: "Parloq offline",
        modifier: .slash
    )

    static let error = makeWaveform(
        description: "Parloq error",
        modifier: .alert
    )

    private enum Modifier {
        case cursor
        case listening
        case finishing
        case slash
        case alert
    }

    private static func makeReady(description: String) -> NSImage {
        makeWaveform(description: description, modifier: .cursor)
    }

    private static func makeWaveform(
        description: String,
        modifier: Modifier
    ) -> NSImage {
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
            path.line(to: NSPoint(x: 15.7, y: 9))
            path.stroke()

            switch modifier {
            case .cursor:
                let cursor = NSBezierPath()
                cursor.lineWidth = 2.0
                cursor.lineCapStyle = .round
                cursor.move(to: NSPoint(x: 18.0, y: 4.5))
                cursor.line(to: NSPoint(x: 18.0, y: 13.5))
                cursor.stroke()
            case .listening:
                NSColor.black.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: 16.2, y: 6.7, width: 4.6, height: 4.6)
                ).fill()
            case .finishing:
                NSColor.black.setFill()
                for x in [15.8, 18.4] {
                    NSBezierPath(
                        ovalIn: NSRect(x: x, y: 7.7, width: 2.4, height: 2.4)
                    ).fill()
                }
            case .slash:
                let slash = NSBezierPath()
                slash.lineWidth = 2.2
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 3.0, y: 15.0))
                slash.line(to: NSPoint(x: 17.0, y: 3.0))
                slash.stroke()
            case .alert:
                NSColor.black.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: 16.2, y: 2.8, width: 3.6, height: 3.6)
                ).fill()
                let alert = NSBezierPath()
                alert.lineWidth = 2.0
                alert.lineCapStyle = .round
                alert.move(to: NSPoint(x: 18.0, y: 8.3))
                alert.line(to: NSPoint(x: 18.0, y: 14.0))
                alert.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    private static func makeListening(
        description: String,
        normalizedLevel: Double = 0.18,
        spectrum: [Double]? = nil
    ) -> NSImage {
        _ = normalizedLevel
        _ = spectrum
        return makeWaveform(description: description, modifier: .listening)
    }

    private static func makeFinishing(description: String) -> NSImage {
        makeWaveform(description: description, modifier: .finishing)
    }
}
