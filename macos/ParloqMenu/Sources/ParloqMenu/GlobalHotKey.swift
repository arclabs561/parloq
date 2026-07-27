import AppKit
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
            return "Accessibility permission is required for the Dictation key"
        case .tapCreationFailed:
            return "Could not create the Dictation key event tap"
        case .sourceCreationFailed:
            return "Could not attach the Dictation key event tap"
        case .tapEnableFailed:
            return "Could not enable the Dictation key event tap"
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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: DispatchSourceTimer?
    private var keyOverride: DictationKeyOverride?
    private let actionBox: HotKeyActionBox
    private var keyIsPressed = false

    init(
        installKeyOverride: Bool = true,
        action: @escaping Action
    ) throws {
        actionBox = HotKeyActionBox(action: action)

        guard AXIsProcessTrusted() else {
            throw GlobalHotKeyError.accessibilityMissing
        }
        if installKeyOverride {
            keyOverride = try DictationKeyOverride()
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
        hotKeyLogger.info("Listening for the Dictation key")
    }

    deinit {
        cleanup()
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            keyIsPressed = false
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            hotKeyLogger.notice("Event tap recovered")
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventKeycode)
                == DictationKeyOverride.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, !keyIsPressed {
            keyIsPressed = true
            hotKeyLogger.info(
                "Received remapped Dictation key"
            )
            actionBox.invoke()
        } else if type == .keyUp {
            keyIsPressed = false
        }
        return type == .keyDown || type == .keyUp
            ? nil
            : Unmanaged.passUnretained(event)
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
