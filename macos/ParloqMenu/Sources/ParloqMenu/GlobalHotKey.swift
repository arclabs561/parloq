import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

private let hotKeyLogger = Logger(
    subsystem: "net.attobop.parloq.menu",
    category: "hotkey"
)

private enum GlobalHotKeyError: LocalizedError {
    case accessibilityMissing
    case tapCreationFailed
    case sourceCreationFailed
    case tapEnableFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityMissing:
            return "Accessibility permission is required for dictation shortcuts"
        case .tapCreationFailed:
            return "Could not create the dictation shortcut event tap"
        case .sourceCreationFailed:
            return "Could not attach the dictation shortcut event tap"
        case .tapEnableFailed:
            return "Could not enable the dictation shortcut event tap"
        }
    }
}

private final class HotKeyActionBox: @unchecked Sendable {
    let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    func invoke() {
        Task { @MainActor [action] in
            action()
        }
    }
}

final class GlobalHotKey: @unchecked Sendable {
    typealias Action = @MainActor @Sendable () -> Void

    private enum Trigger: Hashable {
        case dictationKey
        case optionSpace
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: DispatchSourceTimer?
    private var keyOverride: DictationKeyOverride?
    private let actionBox: HotKeyActionBox
    private var pressedTriggers: Set<Trigger> = []
    private(set) var warning: String?

    init(
        installKeyOverride: Bool = true,
        action: @escaping Action
    ) throws {
        actionBox = HotKeyActionBox(action: action)

        guard AXIsProcessTrusted() else {
            throw GlobalHotKeyError.accessibilityMissing
        }
        if installKeyOverride {
            do {
                keyOverride = try DictationKeyOverride()
            } catch {
                warning = "⌥Space ready; Dictation key unavailable"
                hotKeyLogger.error(
                    "Dictation key override failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let eventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else {
                    return Unmanaged.passUnretained(event)
                }
                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return hotKey.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw GlobalHotKeyError.tapCreationFailed
        }
        self.eventTap = eventTap

        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            throw GlobalHotKeyError.sourceCreationFailed
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        guard CGEvent.tapIsEnabled(tap: eventTap) else {
            cleanup()
            throw GlobalHotKeyError.tapEnableFailed
        }
        startHealthTimer()
        hotKeyLogger.info("Listening for Option-Space and the Dictation key")
    }

    deinit {
        cleanup()
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pressedTriggers.removeAll()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            hotKeyLogger.notice("Event tap recovered")
            return Unmanaged.passUnretained(event)
        }

        guard let trigger = trigger(for: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if pressedTriggers.insert(trigger).inserted {
                hotKeyLogger.info("Received dictation shortcut")
                actionBox.invoke()
            }
        } else if type == .keyUp {
            pressedTriggers.remove(trigger)
        }
        return type == .keyDown || type == .keyUp
            ? nil
            : Unmanaged.passUnretained(event)
    }

    private func trigger(
        for type: CGEventType,
        event: CGEvent
    ) -> Trigger? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == DictationKeyOverride.keyCode {
            return .dictationKey
        }
        guard keyCode == Int64(kVK_Space) else {
            return nil
        }
        if type == .keyUp, pressedTriggers.contains(.optionSpace) {
            return .optionSpace
        }

        let shortcutModifiers: CGEventFlags = [
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskCommand,
        ]
        return event.flags.intersection(shortcutModifiers) == .maskAlternate
            ? .optionSpace
            : nil
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + 5,
            repeating: 5,
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            guard let self, let eventTap = self.eventTap else {
                return
            }
            guard !CGEvent.tapIsEnabled(tap: eventTap) else {
                return
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            hotKeyLogger.notice("Health check re-enabled event tap")
        }
        healthTimer = timer
        timer.resume()
    }

    private func cleanup() {
        healthTimer?.cancel()
        healthTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        keyOverride?.restore()
        keyOverride = nil
    }

    @MainActor
    static func checkAvailability() throws {
        let hotKey = try GlobalHotKey(installKeyOverride: false) {
            // Registration is the check; physical event delivery is intentionally
            // not synthesized because session taps ignore injected events.
        }
        withExtendedLifetime(hotKey) {}
    }
}
