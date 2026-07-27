@preconcurrency import CIOKitHID
import Darwin
import Foundation

private let mappingSourceKey = "HIDKeyboardModifierMappingSrc"
private let mappingDestinationKey = "HIDKeyboardModifierMappingDst"
private var userKeyMappingKey: CFString {
    "UserKeyMapping" as CFString
}

private enum DictationKeyOverrideError: LocalizedError {
    case alreadyOwned
    case noKeyboard
    case mappingFailed

    var errorDescription: String? {
        switch self {
        case .alreadyOwned:
            return "Another Parloq process owns the Dictation key"
        case .noKeyboard:
            return "Could not find a keyboard for the Dictation key"
        case .mappingFailed:
            return "Could not override the Dictation key"
        }
    }
}

/// Routes the hardware Voice Command usage to F18 before macOS consumes it.
///
/// The previous HID mapping is persisted before the override is installed so a
/// new Parloq process can recover it after an interrupted prior run.
final class DictationKeyOverride {
    static let keyCode: Int64 = 79 // kVK_F18

    private static let backupDefaultsKey =
        "DictationKeyOverride.previousUserKeyMapping"
    private static let ownerDefaultsKey =
        "DictationKeyOverride.ownerProcessIdentifier"
    private static let voiceCommandUsage: UInt64 = 0x0000_000C_0000_00CF
    private static let f18Usage: UInt64 = 0x0000_0007_0000_006D

    private let client: IOHIDEventSystemClient
    private var previousMapping: [[String: NSNumber]]?
    private var restored = false

    init() throws {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

        if let interruptedMapping = Self.loadBackup() {
            let owner = UserDefaults.standard.integer(
                forKey: Self.ownerDefaultsKey)
            if owner != 0,
               owner != ProcessInfo.processInfo.processIdentifier,
               kill(pid_t(owner), 0) == 0 {
                throw DictationKeyOverrideError.alreadyOwned
            }
            try Self.setMapping(interruptedMapping, using: client)
            Self.clearBackup()
        }

        let currentMapping = Self.copyMapping(using: client)
        try Self.saveBackup(currentMapping)
        UserDefaults.standard.set(
            ProcessInfo.processInfo.processIdentifier,
            forKey: Self.ownerDefaultsKey
        )

        var replacement = currentMapping.filter {
            Self.mappingValue($0[mappingSourceKey])
                != Self.voiceCommandUsage
        }
        replacement.append([
            mappingSourceKey: NSNumber(value: Self.voiceCommandUsage),
            mappingDestinationKey: NSNumber(value: Self.f18Usage),
        ])

        do {
            try Self.setMapping(replacement, using: client)
            previousMapping = currentMapping
        } catch {
            try? Self.setMapping(currentMapping, using: client)
            Self.clearBackup()
            throw error
        }
    }

    deinit {
        restore()
    }

    func restore() {
        guard !restored, let previousMapping else { return }
        restored = true
        do {
            try Self.setMapping(previousMapping, using: client)
            Self.clearBackup()
        } catch {
            // Keep the persisted backup for recovery by the next process.
        }
    }

    private static func keyboardServices(
        using client: IOHIDEventSystemClient
    ) -> [IOHIDServiceClient] {
        guard let services = IOHIDEventSystemClientCopyServices(client)
        else {
            return []
        }
        return (services as NSArray).compactMap { value in
            let service = value as! IOHIDServiceClient
            guard IOHIDServiceClientConformsTo(
                service,
                UInt32(kHIDPage_GenericDesktop),
                UInt32(kHIDUsage_GD_Keyboard)
            ) != 0 else {
                return nil
            }
            return service
        }
    }

    private static func copyMapping(
        using client: IOHIDEventSystemClient
    ) -> [[String: NSNumber]] {
        guard let service = keyboardServices(using: client).first,
              let property = IOHIDServiceClientCopyProperty(
                  service,
                  userKeyMappingKey
              ),
              let mapping = property as? [[String: NSNumber]]
        else {
            return []
        }
        return mapping
    }

    private static func setMapping(
        _ mapping: [[String: NSNumber]],
        using client: IOHIDEventSystemClient
    ) throws {
        let services = keyboardServices(using: client)
        guard !services.isEmpty else {
            throw DictationKeyOverrideError.noKeyboard
        }
        for service in services {
            guard IOHIDServiceClientSetProperty(
                service,
                userKeyMappingKey,
                mapping as CFArray
            ) else {
                throw DictationKeyOverrideError.mappingFailed
            }
        }
    }

    private static func saveBackup(
        _ mapping: [[String: NSNumber]]
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: mapping,
            format: .binary,
            options: 0
        )
        UserDefaults.standard.set(data, forKey: backupDefaultsKey)
    }

    private static func loadBackup() -> [[String: NSNumber]]? {
        guard let data = UserDefaults.standard.data(
            forKey: backupDefaultsKey),
              let value = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              )
        else {
            return nil
        }
        return value as? [[String: NSNumber]]
    }

    private static func clearBackup() {
        UserDefaults.standard.removeObject(forKey: backupDefaultsKey)
        UserDefaults.standard.removeObject(forKey: ownerDefaultsKey)
    }

    private static func mappingValue(_ value: NSNumber?) -> UInt64? {
        value?.uint64Value
    }
}
