import AppKit
import Darwin
import ParloqMenuCore

@MainActor
enum DeliveryE2ERunner {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static var targetWindow: NSWindow?

    static func runTarget(readyFile: URL) {
        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        textView.string = "before [] after"
        textView.setSelectedRange(NSRange(location: 7, length: 2))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        targetWindow = window
        window.contentView = textView
        window.title = "Parloq delivery E2E target"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            try? Data("ready".utf8).write(to: readyFile, options: .atomic)
        }
    }

    static func run() throws {
        guard AXIsProcessTrusted() else {
            throw Failure(message: "Accessibility permission is missing")
        }
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)
        let readyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("parloq-delivery-\(UUID().uuidString)")
        let target = Process()
        target.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        target.arguments = ["--e2e-target", readyFile.path]
        try target.run()
        defer {
            if target.isRunning {
                target.terminate()
                let deadline = Date(timeIntervalSinceNow: 2)
                while target.isRunning, Date() < deadline {
                    RunLoop.current.run(
                        until: Date(timeIntervalSinceNow: 0.05))
                }
                if target.isRunning {
                    kill(target.processIdentifier, SIGKILL)
                    target.waitUntilExit()
                }
            }
            try? FileManager.default.removeItem(at: readyFile)
            pasteboard.clearContents()
            if let previousClipboard {
                pasteboard.setString(previousClipboard, forType: .string)
            }
            previousApplication?.activate()
        }

        let deadline = Date(timeIntervalSinceNow: 5)
        while !FileManager.default.fileExists(atPath: readyFile.path),
              Date() < deadline
        {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        guard FileManager.default.fileExists(atPath: readyFile.path) else {
            throw Failure(message: "editable target did not become ready")
        }
        guard TextDeliverySession.focusedTargetDiagnostics.contains(
            "target=range-replacement")
        else {
            throw Failure(message: TextDeliverySession.focusedTargetDiagnostics)
        }

        let cancellation = TextDeliverySession()
        cancellation.deliver(event: try event(
            type: "transcript",
            sequence: 1,
            text: "temporary",
            finalized: "temporary"
        ))
        guard try focusedValue() == "before temporary after" else {
            throw Failure(message: "live range replacement did not occur")
        }
        guard cancellation.cancel() == nil,
              try focusedValue() == "before [] after"
        else {
            throw Failure(message: "cancellation did not restore selected text")
        }

        try selectFixtureRange()
        let completion = TextDeliverySession()
        completion.deliver(event: try event(
            type: "transcript",
            sequence: 2,
            text: "hello wor",
            finalized: "hello"
        ))
        completion.deliver(event: try event(
            type: "final",
            sequence: 3,
            text: "Hello world.",
            finalized: "Hello world."
        ))
        guard try focusedValue() == "before Hello world. after" else {
            throw Failure(message: "final range replacement did not match")
        }
        guard completion.publishFinalToPasteboard(),
              pasteboard.string(forType: .string) == "Hello world."
        else {
            throw Failure(message: "final transcript was not published")
        }
        print("PASS: signed cross-process delivery replaced, cancelled, finalized, and copied")
    }

    private static func focusedValue() throws -> String {
        guard let element = FocusedElement.capture() else {
            throw Failure(message: "focused element disappeared")
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
        let string = value as? String
        else {
            throw Failure(message: "focused element has no text value")
        }
        return string
    }

    private static func selectFixtureRange() throws {
        guard let element = FocusedElement.capture() else {
            throw Failure(message: "focused element disappeared")
        }
        var range = CFRange(location: 7, length: 2)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                value
              ) == .success
        else {
            throw Failure(message: "could not reset fixture selection")
        }
    }

    private static func event(
        type: String,
        sequence: Int,
        text: String,
        finalized: String
    ) throws -> DictateEvent {
        let body: [String: Any] = [
            "version": dictateProtocolVersion,
            "type": type,
            "phase": type == "final" ? "finalizing" : "recording",
            "sequence": sequence,
            "text": text,
            "finalized_text": finalized,
            "draft_text": "",
        ]
        return try JSONDecoder().decode(
            DictateEvent.self,
            from: JSONSerialization.data(withJSONObject: body)
        )
    }
}
