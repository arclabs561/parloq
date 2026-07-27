import AppKit

@MainActor
enum StatusIcon {
    static let parloq: NSImage = {
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
            path.line(to: NSPoint(x: 18.2, y: 9))
            path.move(to: NSPoint(x: 18.2, y: 4.2))
            path.line(to: NSPoint(x: 18.2, y: 13.8))
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Parloq"
        return image
    }()
}
