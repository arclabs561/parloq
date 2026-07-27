import AppKit
import ApplicationServices

if CommandLine.arguments.dropFirst() == ["--check-accessibility"] {
    let trusted = AXIsProcessTrusted()
    print("accessibility=\(trusted ? "granted" : "missing")")
    exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.dropFirst() == ["--request-accessibility"] {
    _ = NSApplication.shared
    _ = requestAccessibilityPermission(prompt: true)
    let deadline = Date(timeIntervalSinceNow: 120)
    while !AXIsProcessTrusted(), Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
    }
    let granted = AXIsProcessTrusted()
    print("accessibility=\(granted ? "granted" : "missing")")
    exit(granted ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.dropFirst() == ["--check-hotkey"] {
    _ = NSApplication.shared
    do {
        try GlobalHotKey.checkAvailability()
        print("hotkey=armed")
        exit(EXIT_SUCCESS)
    } catch {
        print("hotkey=unavailable error=\(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

if CommandLine.arguments.dropFirst() == ["--diagnose-text-target"] {
    print(TextDeliverySession.focusedTargetDiagnostics)
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
