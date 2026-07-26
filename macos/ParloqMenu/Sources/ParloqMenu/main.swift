import AppKit
import ApplicationServices

if CommandLine.arguments.dropFirst() == ["--check-accessibility"] {
    let trusted = AXIsProcessTrusted()
    print("accessibility=\(trusted ? "granted" : "missing")")
    exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.dropFirst() == ["--check-hotkey"] {
    _ = NSApplication.shared
    do {
        let received = try GlobalHotKey.runSelfCheck()
        print("hotkey=\(received ? "working" : "not-received")")
        exit(received ? EXIT_SUCCESS : EXIT_FAILURE)
    } catch {
        print("hotkey=unavailable error=\(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
