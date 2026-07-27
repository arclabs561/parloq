import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ParloqMenuCore

enum DeliveryError: LocalizedError {
    case accessibilityNotTrusted
    case noEditableTarget
    case ownershipLost
    case cancelOwnershipLost
    case secureInput
    case commandCharacter
    case keyboardEventFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is required"
        case .noEditableTarget:
            return "The focused control does not expose editable text"
        case .ownershipLost:
            return "Text or focus changed; final transcript copied"
        case .cancelOwnershipLost:
            return "Cancelled; live text could not be removed safely"
        case .secureInput:
            return "Secure input is active; final transcript copied"
        case .commandCharacter:
            return "Line breaks or controls cannot be typed safely; final transcript copied"
        case .keyboardEventFailed:
            return "macOS could not create a text event"
        }
    }
}

final class TextDeliverySession {
    private enum Target {
        case accessibility(OwnedTextRange)
        case keyboard(FocusedTextTarget)
        case unavailable
    }

    private let target: Target
    private var planner: DeliveryPlanner
    private var didDeliverText = false
    private(set) var lastTranscript = ""
    private(set) var warning: String?

    static var focusedTargetDiagnostics: String {
        guard AXIsProcessTrusted() else {
            return "target=unavailable accessibility=missing"
        }
        let secureInput = IsSecureEventInputEnabled() ? "on" : "off"
        if OwnedTextRange.capture() != nil {
            return "target=range-replacement secure-input=\(secureInput)"
        }
        if FocusedTextTarget.capture() != nil {
            return "target=keyboard-fallback secure-input=\(secureInput)"
        }
        return "target=unavailable secure-input=\(secureInput)"
    }

    init() {
        if !AXIsProcessTrusted() {
            target = .unavailable
            planner = DeliveryPlanner(strategy: .disabled)
        } else if let ownedRange = OwnedTextRange.capture() {
            target = .accessibility(ownedRange)
            planner = DeliveryPlanner(strategy: .rangeReplacement)
        } else if let focusedTarget = FocusedTextTarget.capture() {
            target = .keyboard(focusedTarget)
            planner = DeliveryPlanner(strategy: .finalizedAppend)
        } else {
            target = .unavailable
            planner = DeliveryPlanner(strategy: .disabled)
        }
    }

    func deliver(event: DictateEvent) {
        guard event.type == .transcript || event.type == .final else {
            return
        }
        let text = event.text ?? ""
        let finalized = event.finalizedText ?? ""
        let isFinal = event.type == .final
        if isFinal, text.isEmpty {
            return
        }
        if isFinal {
            lastTranscript = text
        }

        let action = planner.plan(
            text: text,
            finalizedText: finalized,
            isFinal: isFinal
        )
        do {
            try perform(action)
            switch action {
            case .replace, .append:
                didDeliverText = true
            case .copy, .none:
                break
            }
        } catch {
            warning = error.localizedDescription
            planner.disableReplacement()
            if isFinal, !text.isEmpty {
                copyToPasteboard(text)
            }
        }
    }

    func cancel() -> String? {
        guard didDeliverText else { return nil }
        switch target {
        case let .accessibility(range):
            do {
                try range.restoreOriginalText()
                return nil
            } catch {
                return DeliveryError.cancelOwnershipLost.localizedDescription
            }
        case .keyboard:
            return "Cancelled; finalized text already inserted"
        case .unavailable:
            return nil
        }
    }

    private func perform(_ action: DeliveryAction) throws {
        switch action {
        case let .replace(text):
            guard case let .accessibility(range) = target else {
                throw DeliveryError.noEditableTarget
            }
            try range.replaceOwnedText(with: text)

        case let .append(text):
            guard !text.isEmpty else { return }
            guard case let .keyboard(focusedTarget) = target else {
                throw DeliveryError.accessibilityNotTrusted
            }
            guard focusedTarget.isStillFocused else {
                throw DeliveryError.ownershipLost
            }
            guard !IsSecureEventInputEnabled() else {
                throw DeliveryError.secureInput
            }
            try KeyboardWriter.write(text)

        case let .copy(text):
            copyToPasteboard(text)
            if warning == nil {
                if case .unavailable = target {
                    warning = DeliveryError.accessibilityNotTrusted
                        .localizedDescription
                } else {
                    warning = DeliveryError.ownershipLost.localizedDescription
                }
            }

        case .none:
            return
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private final class FocusedTextTarget {
    private enum Identity {
        case element(AXUIElement)
        case application(pid_t)
    }

    private let identity: Identity

    private init(identity: Identity) {
        self.identity = identity
    }

    static func capture() -> FocusedTextTarget? {
        if let element = FocusedElement.capture() {
            return FocusedTextTarget(
                identity: .element(element))
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return FocusedTextTarget(
            identity: .application(application.processIdentifier))
    }

    var isStillFocused: Bool {
        switch identity {
        case let .element(element):
            guard let focused = FocusedElement.capture() else {
                return false
            }
            return CFEqual(focused, element)
        case let .application(processIdentifier):
            return NSWorkspace.shared.frontmostApplication?
                .processIdentifier == processIdentifier
        }
    }
}

private final class OwnedTextRange {
    private let element: AXUIElement
    private let originalRange: CFRange
    private let originalText: String
    private var ownedRange: CFRange
    private var expectedSelection: CFRange
    private var expectedText: String

    private init(
        element: AXUIElement,
        selectedRange: CFRange,
        selectedText: String
    ) {
        self.element = element
        self.originalRange = selectedRange
        self.originalText = selectedText
        self.ownedRange = selectedRange
        self.expectedSelection = selectedRange
        self.expectedText = selectedText
    }

    static func capture() -> OwnedTextRange? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = FocusedElement.capture() else {
            return nil
        }

        var selectedTextSettable = DarwinBoolean(false)
        var selectedRangeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        ) == .success,
        selectedTextSettable.boolValue,
        AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeSettable
        ) == .success,
        selectedRangeSettable.boolValue,
        let range = copyRange(
            from: element,
            attribute: kAXSelectedTextRangeAttribute
        ),
        let value = copyString(from: element, attribute: kAXValueAttribute)
        else {
            return nil
        }

        let string = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard NSMaxRange(nsRange) <= string.length else { return nil }
        return OwnedTextRange(
            element: element,
            selectedRange: range,
            selectedText: string.substring(with: nsRange)
        )
    }

    func replaceOwnedText(with text: String) throws {
        guard let focused = FocusedElement.capture(),
              CFEqual(focused, element)
        else {
            throw DeliveryError.ownershipLost
        }
        guard let value = Self.copyString(
            from: element,
            attribute: kAXValueAttribute
        ), let selection = Self.copyRange(
            from: element,
            attribute: kAXSelectedTextRangeAttribute
        ) else {
            throw DeliveryError.ownershipLost
        }

        guard selection.location == expectedSelection.location,
              selection.length == expectedSelection.length
        else {
            throw DeliveryError.ownershipLost
        }

        let string = value as NSString
        let nsRange = NSRange(
            location: ownedRange.location,
            length: ownedRange.length
        )
        guard NSMaxRange(nsRange) <= string.length,
              string.substring(with: nsRange) == expectedText
        else {
            throw DeliveryError.ownershipLost
        }

        var replacementRange = ownedRange
        guard let rangeValue = AXValueCreate(.cfRange, &replacementRange),
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
              ) == .success,
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFString
              ) == .success
        else {
            throw DeliveryError.noEditableTarget
        }

        ownedRange.length = text.utf16.count
        expectedText = text
        var cursor = CFRange(
            location: ownedRange.location + ownedRange.length,
            length: 0
        )
        if let cursorValue = AXValueCreate(.cfRange, &cursor) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                cursorValue
            )
        }
        expectedSelection = cursor
    }

    func restoreOriginalText() throws {
        try replaceOwnedText(with: originalText)
        var selection = CFRange(
            location: originalRange.location,
            length: originalText.utf16.count
        )
        guard let selectionValue = AXValueCreate(.cfRange, &selection),
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                selectionValue
              ) == .success
        else {
            throw DeliveryError.noEditableTarget
        }
        expectedSelection = selection
    }

    private static func copyString(
        from element: AXUIElement,
        attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyRange(
        from element: AXUIElement,
        attribute: String
    ) -> CFRange? {
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
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }
}

private enum KeyboardWriter {
    static func write(_ text: String) throws {
        guard KeyboardEventText.isSafeForBlindTyping(text) else {
            throw DeliveryError.commandCharacter
        }
        for chunk in KeyboardEventText.utf16Chunks(for: text) {
            guard let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: true
            ), let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: false
            ) else {
                throw DeliveryError.keyboardEventFailed
            }
            chunk.withUnsafeBufferPointer { pointer in
                down.keyboardSetUnicodeString(
                    stringLength: chunk.count,
                    unicodeString: pointer.baseAddress!
                )
                up.keyboardSetUnicodeString(
                    stringLength: chunk.count,
                    unicodeString: pointer.baseAddress!
                )
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

@discardableResult
func requestAccessibilityPermission(prompt: Bool) -> Bool {
    guard prompt else { return AXIsProcessTrusted() }
    let options = [
        "AXTrustedCheckOptionPrompt": true
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
