import Carbon.HIToolbox
import Foundation

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
                userInfo: [NSLocalizedDescriptionKey: "Could not install hotkey handler"]
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
                userInfo: [NSLocalizedDescriptionKey: "Could not register ⌃⌥Space"]
            )
        }
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
}
