import AppKit
import ParloqMenuCore
import ServiceManagement
import os

private let appLogger = Logger(
    subsystem: "net.attobop.parloq.menu",
    category: "app"
)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum IconState: Equatable {
        case idle
        case offline
        case listening
        case finishing
        case error
    }

    private let client = UnixSocketClient()
    private var hotKey: GlobalHotKey?
    private var hotKeyRetry: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var copyMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var phase: DictatePhase?
    private var connected = false
    private var deliverySession: TextDeliverySession?
    private var lastTranscript = ""
    private var lastSequence = 0
    private var lastDeliveryWarning: String?
    private var hotKeyWarning: String?
    private var iconState: IconState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        configureClient()
        installHotKey()
        client.startSubscription()
        requestAccessibilityPermission(prompt: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyRetry?.cancel()
        hotKey = nil
        client.cancel()
    }

    private func configureClient() {
        client.onEvent = { [weak self] event in
            self?.handle(event)
        }
        client.onConnectionChange = { [weak self] connected, message in
            guard let self else { return }
            self.connected = connected
            if connected {
                self.updateStatus(self.hotKeyWarning ?? "Connected")
            } else {
                self.phase = nil
                self.lastSequence = 0
                self.deliverySession = nil
                self.updateStatus(message ?? "Daemon unavailable")
            }
            self.updateIcon()
        }
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)
        item.autosaveName = "Parloq.StatusItem"
        statusItem = item
        item.button?.image = StatusIcon.ready

        let menu = NSMenu()
        let status = NSMenuItem(title: "Connecting…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)

        let toggle = NSMenuItem(
            title: "Toggle Dictation (Microphone key)",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let copy = NSMenuItem(
            title: "Copy Last Transcript",
            action: #selector(copyLastTranscript),
            keyEquivalent: ""
        )
        copy.target = self
        copy.isEnabled = false
        copyMenuItem = copy
        menu.addItem(copy)

        menu.addItem(.separator())
        let permission = NSMenuItem(
            title: "Request Accessibility Permission",
            action: #selector(requestPermission),
            keyEquivalent: ""
        )
        permission.target = self
        menu.addItem(permission)

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLoginMenuItem = launchAtLogin
        menu.addItem(launchAtLogin)
        refreshLaunchAtLogin()

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Parloq",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func toggleFromMenu() {
        toggleDictation()
    }

    private func toggleDictation() {
        guard connected else {
            updateStatus("Daemon unavailable")
            return
        }
        switch phase {
        case .recording:
            client.send(.stop)
        case .finalizing, .polishing:
            updateStatus("Finishing current dictation…")
        default:
            lastDeliveryWarning = nil
            deliverySession = TextDeliverySession()
            client.send(.start)
        }
    }

    private func handle(_ event: DictateEvent) {
        guard event.sequence > lastSequence else { return }
        lastSequence = event.sequence
        phase = event.phase
        switch event.type {
        case .transcript:
            deliverySession?.deliver(event: event)
            updateStatus(statusText(for: event))

        case .final:
            deliverySession?.deliver(event: event)
            if let text = event.text, !text.isEmpty {
                lastTranscript = text
                copyMenuItem?.isEnabled = true
            }
            if let message = event.message {
                lastDeliveryWarning = message
                updateStatus(message)
            } else if let warning = deliverySession?.warning {
                lastDeliveryWarning = warning
                updateStatus(warning)
            } else {
                updateStatus("Dictation complete")
            }
            deliverySession = nil

        case .error:
            updateStatus(event.message ?? "Dictation error")
            deliverySession = nil

        case .ack, .status:
            if event.phase == .idle, let lastDeliveryWarning {
                updateStatus(lastDeliveryWarning)
            } else {
                updateStatus(statusText(for: event))
            }
        }
        updateIcon()
    }

    private func statusText(for event: DictateEvent) -> String {
        switch event.phase {
        case .warming:
            return "Warming model…"
        case .idle:
            return hotKeyWarning ?? "Ready — Microphone key"
        case .recording:
            return "Recording…"
        case .finalizing:
            return "Finalizing…"
        case .polishing:
            return "Polishing…"
        case .error:
            return event.message ?? "Dictation error"
        }
    }

    private func updateStatus(_ text: String) {
        statusMenuItem?.title = text
        statusItem?.button?.toolTip = "Parloq — \(text)"
    }

    private func updateIcon() {
        let state: IconState
        if !connected {
            state = .offline
        } else {
            switch phase {
            case .recording:
                state = .listening
            case .finalizing, .polishing:
                state = .finishing
            case .error:
                state = .error
            default:
                state = .idle
            }
        }
        guard iconState != state else { return }
        iconState = state
        guard let button = statusItem?.button else { return }
        button.image = statusIcon(for: state)
        button.imagePosition = .imageOnly
        button.contentTintColor = nil
        button.title = ""
        button.setAccessibilityLabel("Parloq")
        button.setAccessibilityValue(accessibilityValue(for: state))
    }

    private func statusIcon(for state: IconState) -> NSImage {
        switch state {
        case .idle:
            return StatusIcon.ready
        case .offline:
            return StatusIcon.offline
        case .listening:
            return StatusIcon.listening
        case .finishing:
            return StatusIcon.finishing
        case .error:
            return StatusIcon.error
        }
    }

    private func accessibilityValue(for state: IconState) -> String {
        switch state {
        case .idle:
            return "Ready"
        case .offline:
            return "Offline"
        case .listening:
            return "Listening"
        case .finishing:
            return "Finishing"
        case .error:
            return "Error"
        }
    }

    @objc private func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
        updateStatus("Copied last transcript")
    }

    @objc private func requestPermission() {
        if requestAccessibilityPermission(prompt: true) {
            updateStatus("Accessibility permission granted")
        } else {
            updateStatus("Grant Parloq access in Privacy & Security")
        }
    }

    private func installHotKey() {
        hotKeyRetry?.cancel()
        hotKeyRetry = nil
        do {
            hotKey = try GlobalHotKey { [weak self] in
                self?.toggleDictation()
            }
            hotKeyWarning = nil
            updateStatus(connected ? "Ready — Microphone key" : "Connecting…")
        } catch {
            hotKey = nil
            let warning = "Hotkey unavailable: \(error.localizedDescription)"
            let warningChanged = hotKeyWarning != warning
            hotKeyWarning = warning
            updateStatus(warning)
            if warningChanged {
                appLogger.error(
                    "Dictation key setup failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            let retry = DispatchWorkItem { [weak self] in
                self?.installHotKey()
            }
            hotKeyRetry = retry
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 5,
                execute: retry
            )
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            refreshLaunchAtLogin()
        } catch {
            updateStatus("Login item: \(error.localizedDescription)")
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginMenuItem?.state = (
            SMAppService.mainApp.status == .enabled ? .on : .off)
    }
}
