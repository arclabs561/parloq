import AppKit
import ApplicationServices

if CommandLine.arguments.dropFirst() == ["--check-accessibility"] {
    let trusted = AXIsProcessTrusted()
    print("accessibility=\(trusted ? "granted" : "missing")")
    exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
