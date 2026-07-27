import AppKit
import ApplicationServices

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--render-ui-fixtures" {
    guard arguments.count == 2 else {
        fputs(
            "usage: ParloqMenu --render-ui-fixtures OUTPUT_DIRECTORY\n",
            stderr
        )
        exit(EXIT_FAILURE)
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    do {
        let directory = URL(fileURLWithPath: arguments[1])
            .standardizedFileURL
        let rendered = try UIFixtureRenderer.render(to: directory)
        for url in rendered {
            print(url.path)
        }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("fixture rendering failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if arguments == ["--check-accessibility"] {
    let trusted = AXIsProcessTrusted()
    print("accessibility=\(trusted ? "granted" : "missing")")
    exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
}

if arguments == ["--request-accessibility"] {
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

if arguments == ["--check-hotkey"] {
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

if arguments == ["--diagnose-text-target"] {
    print(TextDeliverySession.focusedTargetDiagnostics)
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
