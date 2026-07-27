import AppKit
import ApplicationServices
import CoreGraphics

enum FocusedElement {
    static func capture() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        if let focused = copyElement(
            from: systemWide,
            attribute: kAXFocusedUIElementAttribute
        ) {
            return focused
        }

        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier)
        return copyElement(
            from: applicationElement,
            attribute: kAXFocusedUIElementAttribute
        )
    }

    static func copyElement(
        from element: AXUIElement,
        attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }
}

enum FocusedTargetApplication {
    static func capture() -> NSRunningApplication? {
        if AXIsProcessTrusted(),
           let element = FocusedElement.capture()
        {
            var processIdentifier = pid_t()
            if AXUIElementGetPid(
                element,
                &processIdentifier
            ) == .success,
            let application = NSRunningApplication(
                processIdentifier: processIdentifier
            ) {
                return application
            }
        }
        return NSWorkspace.shared.frontmostApplication
    }
}

enum FocusedTargetScreen {
    static func capture() -> NSScreen? {
        guard AXIsProcessTrusted(),
              let element = FocusedElement.capture()
        else {
            return nil
        }
        if let bounds = caretBounds(of: element),
           let screen = screen(containing: bounds)
        {
            return screen
        }
        if let window = FocusedElement.copyElement(
            from: element,
            attribute: kAXWindowAttribute
        ), let bounds = frame(of: window),
           let screen = screen(containing: bounds)
        {
            return screen
        }
        if let bounds = frame(of: element) {
            return screen(containing: bounds)
        }
        return nil
    }

    private static func caretBounds(
        of element: AXUIElement
    ) -> CGRect? {
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success,
        let selectedRange
        else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &bounds) else {
            return nil
        }
        return valid(bounds)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(
            from: element,
            attribute: kAXPositionAttribute
        ), let size = size(
            from: element,
            attribute: kAXSizeAttribute
        ) else {
            return nil
        }
        return valid(CGRect(origin: origin, size: size))
    }

    private static func point(
        from element: AXUIElement,
        attribute: String
    ) -> CGPoint? {
        guard let value = value(from: element, attribute: attribute),
              AXValueGetType(value) == .cgPoint
        else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(
        from element: AXUIElement,
        attribute: String
    ) -> CGSize? {
        guard let value = value(from: element, attribute: attribute),
              AXValueGetType(value) == .cgSize
        else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func value(
        from element: AXUIElement,
        attribute: String
    ) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        return (value as! AXValue)
    }

    private static func valid(_ rect: CGRect) -> CGRect? {
        guard !rect.isNull,
              !rect.isInfinite,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite
        else {
            return nil
        }
        return rect
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(
            point,
            1,
            &display,
            &count
        ) == .success,
        count == 1
        else {
            return nil
        }
        return NSScreen.screens.first { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            let number = screen.deviceDescription[key] as? NSNumber
            return number?.uint32Value == display
        }
    }
}
