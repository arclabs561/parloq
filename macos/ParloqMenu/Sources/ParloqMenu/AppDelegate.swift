import AppKit
import ParloqMenuCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = UnixSocketClient()
    private var hotKey: GlobalHotKey?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        configureClient()
        do {
            hotKey = try GlobalHotKey { [weak self] in
                self?.toggleDictation()
            }
        } catch {
            updateStatus("Hotkey unavailable: \(error.localizedDescription)")
        }
        client.startSubscription()
        requestAccessibilityPermission(prompt: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
                self.updateStatus("Connected")
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
            withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Parloq"
        )

        let menu = NSMenu()
        let status = NSMenuItem(title: "Connecting…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)

        let toggle = NSMenuItem(
            title: "Toggle Dictation (⌃⌥Space)",
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
            return "Ready — ⌃⌥Space"
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
        let symbol: String
        if !connected {
            symbol = "waveform.slash"
        } else {
            switch phase {
            case .recording:
                symbol = "record.circle.fill"
            case .finalizing, .polishing:
                symbol = "ellipsis.circle"
            case .error:
                symbol = "exclamationmark.triangle"
            default:
                symbol = "waveform"
            }
        }
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Parloq"
        )
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
