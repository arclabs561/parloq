import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

private let hotKeyLogger = Logger(
    subsystem: "net.attobop.parloq.menu",
    category: "hotkey"
)

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

final class GlobalHotKey {
    typealias Action = @MainActor @Sendable () -> Void

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let actionBox: HotKeyActionBox

    init(action: @escaping Action) throws {
        let actionBox = HotKeyActionBox(action: action)
        self.actionBox = actionBox

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let box = Unmanaged<HotKeyActionBox>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                hotKeyLogger.debug("Received ⌃⌥Space")
                box.invoke()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(actionBox).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(handlerStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not install hotkey handler (OSStatus \(handlerStatus))",
                ]
            )
        }

        let identifier = EventHotKeyID(
            signature: fourCharacterCode("PRLQ"),
            id: 1
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(registerStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not register ⌃⌥Space (OSStatus \(registerStatus))",
                ]
            )
        }
        hotKeyLogger.info("Registered ⌃⌥Space")
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func fourCharacterCode(_ value: String) -> FourCharCode {
        value.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }

    @MainActor
    static func runSelfCheck(timeout: TimeInterval = 1) throws -> Bool {
        let state = HotKeyCheckState()
        let hotKey = try GlobalHotKey {
            state.received = true
            NSApp.stop(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postShortcut()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            NSApp.stop(nil)
        }
        NSApp.run()
        withExtendedLifetime(hotKey) {}
        return state.received
    }

    @MainActor
    private static func postShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_Space),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_Space),
                  keyDown: false
              )
        else {
            return
        }
        keyDown.flags = [.maskControl, .maskAlternate]
        keyUp.flags = [.maskControl, .maskAlternate]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

@MainActor
private final class HotKeyCheckState {
    var received = false
}
