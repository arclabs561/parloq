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
    private var liveTranscriptPanel: LiveTranscriptPanel?
    private var hotKey: GlobalHotKey?
    private var hotKeyRetry: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var cancelMenuItem: NSMenuItem?
    private var historyMenuItem: NSMenuItem?
    private let historyMenu = NSMenu()
    private let historyStore = TranscriptHistoryStore()
    private var launchAtLoginMenuItem: NSMenuItem?
    private var phase: DictatePhase?
    private var connected = false
    private var deliverySession: TextDeliverySession?
    private var liveTranscript = LiveTranscriptBuffer()
    private var lastSequence = 0
    private var lastDeliveryWarning: String?
    private var cancellationWarning: String?
    private var cancelRequested = false
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
        liveTranscriptPanel?.hide()
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
                self.cancelRequested = false
                self.cancellationWarning = nil
                self.hotKey?.setEscapeEnabled(false)
                self.liveTranscript.reset()
                self.liveTranscriptPanel?.hide()
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
            title: "Toggle Dictation (⌥Space or Microphone key)",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggle.target = self
        toggleMenuItem = toggle
        menu.addItem(toggle)

        let cancel = NSMenuItem(
            title: "Cancel Dictation (Esc)",
            action: #selector(cancelFromMenu),
            keyEquivalent: ""
        )
        cancel.target = self
        cancel.isHidden = true
        cancelMenuItem = cancel
        menu.addItem(cancel)

        menu.addItem(.separator())
        let history = NSMenuItem(
            title: "Dictation History",
            action: nil,
            keyEquivalent: ""
        )
        history.submenu = historyMenu
        historyMenuItem = history
        menu.addItem(history)
        refreshHistoryMenu()

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

    @objc private func cancelFromMenu() {
        cancelDictation()
    }

    private func toggleDictation() {
        guard connected else {
            updateStatus("Daemon unavailable")
            return
        }
        switch phase {
        case .recording:
            liveTranscriptPanel?.showFinishing()
            client.send(.stop)
        case .finalizing, .polishing:
            updateStatus("Finishing current dictation…")
        default:
            lastDeliveryWarning = nil
            cancellationWarning = nil
            cancelRequested = false
            liveTranscript.reset()
            deliverySession = TextDeliverySession()
            let panel = LiveTranscriptPanel()
            liveTranscriptPanel = panel
            panel.showListening()
            hotKey?.setEscapeEnabled(true)
            client.send(.start)
            updateMenuActions()
        }
    }

    private func handle(_ event: DictateEvent) {
        guard event.sequence > lastSequence else { return }
        lastSequence = event.sequence
        if cancelRequested {
            handleCancellationEvent(event)
            updateIcon()
            return
        }
        phase = event.phase
        switch event.type {
        case .transcript:
            if let text = event.text, !text.isEmpty {
                deliverySession?.deliver(event: event)
                if let visibleSnapshot = liveTranscript.update(
                    snapshot: text,
                    finalizedText: event.finalizedText,
                    draftText: event.draftText
                ) {
                    liveTranscriptPanel?.update(snapshot: visibleSnapshot)
                }
            }
            updateStatus(statusText(for: event))

        case .final:
            deliverySession?.deliver(event: event)
            var historyWarning: String?
            if let text = event.text, !text.isEmpty {
                do {
                    try historyStore.append(text)
                    refreshHistoryMenu()
                } catch {
                    historyWarning = "Dictation complete; history not saved"
                    appLogger.error(
                        "History append failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            if let message = event.message {
                lastDeliveryWarning = message
                updateStatus(message)
            } else if let warning = deliverySession?.warning {
                lastDeliveryWarning = warning
                updateStatus(warning)
            } else if let historyWarning {
                updateStatus(historyWarning)
            } else {
                updateStatus("Dictation complete")
            }
            deliverySession = nil
            hotKey?.setEscapeEnabled(false)
            liveTranscript.reset()
            liveTranscriptPanel?.hide()
            liveTranscriptPanel = nil

        case .error:
            updateStatus(event.message ?? "Dictation error")
            deliverySession = nil
            hotKey?.setEscapeEnabled(false)
            liveTranscript.reset()
            liveTranscriptPanel?.hide()
            liveTranscriptPanel = nil

        case .ack, .status:
            if event.phase == .finalizing || event.phase == .polishing {
                liveTranscriptPanel?.showFinishing()
            } else if event.phase == .idle, deliverySession != nil {
                hotKey?.setEscapeEnabled(false)
                liveTranscript.reset()
                liveTranscriptPanel?.hide()
                liveTranscriptPanel = nil
            }
            if event.phase == .idle, let lastDeliveryWarning {
                updateStatus(lastDeliveryWarning)
            } else {
                updateStatus(statusText(for: event))
            }
        }
        updateIcon()
    }

    private func cancelDictation() {
        guard deliverySession != nil
                || phase == .recording
                || phase == .finalizing
                || phase == .polishing
        else {
            return
        }

        cancellationWarning = deliverySession?.cancel()
        cancelRequested = true
        phase = .finalizing
        deliverySession = nil
        hotKey?.setEscapeEnabled(false)
        liveTranscript.reset()
        liveTranscriptPanel?.hide()
        liveTranscriptPanel = nil
        updateStatus(cancellationWarning ?? "Cancelling dictation…")
        updateIcon()
        client.send(.cancel)
    }

    private func handleCancellationEvent(_ event: DictateEvent) {
        if event.type == .error {
            cancelRequested = false
            phase = .error
            hotKey?.setEscapeEnabled(false)
            updateStatus(event.message ?? "Could not cancel dictation")
            cancellationWarning = nil
            return
        }

        guard event.phase == .idle else {
            phase = .finalizing
            return
        }
        cancelRequested = false
        phase = .idle
        hotKey?.setEscapeEnabled(false)
        updateStatus(cancellationWarning ?? "Dictation cancelled")
        cancellationWarning = nil
    }

    private func statusText(for event: DictateEvent) -> String {
        switch event.phase {
        case .warming:
            return "Warming model…"
        case .idle:
            return hotKeyWarning ?? "Ready — ⌥Space or Microphone key"
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
        updateMenuActions()
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

    private func updateMenuActions() {
        let canCancel = deliverySession != nil && !cancelRequested
        cancelMenuItem?.isHidden = !canCancel
        switch phase {
        case .recording:
            toggleMenuItem?.title =
                "Finish Dictation (⌥Space or Microphone key)"
        case .finalizing, .polishing:
            toggleMenuItem?.title = "Finishing Dictation…"
        default:
            toggleMenuItem?.title =
                "Start Dictation (⌥Space or Microphone key)"
        }
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

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let id = UUID(uuidString: identifier),
              let entry = historyStore.history.entries.first(
                  where: { $0.id == id })
        else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        updateStatus("Copied dictation from history")
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear dictation history?"
        alert.informativeText =
            "This permanently removes saved transcripts from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try historyStore.removeAll()
            refreshHistoryMenu()
            updateStatus("Dictation history cleared")
        } catch {
            updateStatus("Could not clear dictation history")
            appLogger.error(
                "History clear failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func refreshHistoryMenu() {
        historyMenu.removeAllItems()
        let entries = historyStore.history.entries

        if entries.isEmpty {
            let empty = NSMenuItem(
                title: historyStore.loadError == nil
                    ? "No completed dictations yet"
                    : "History could not be loaded",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            for entry in entries {
                let item = NSMenuItem(
                    title: Self.historyTitle(entry.text),
                    action: #selector(copyHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id.uuidString
                item.toolTip = entry.text
                historyMenu.addItem(item)
            }
        }

        historyMenu.addItem(.separator())
        let clear = NSMenuItem(
            title: entries.isEmpty && historyStore.loadError != nil
                ? "Reset Dictation History…"
                : "Clear Dictation History…",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clear.target = self
        clear.isEnabled = !entries.isEmpty || historyStore.loadError != nil
        historyMenu.addItem(clear)
        historyMenuItem?.isEnabled = true
    }

    private static func historyTitle(_ text: String) -> String {
        let compact = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let limit = 76
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit - 1)) + "…"
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
            let installedHotKey = try GlobalHotKey(
                action: { [weak self] in
                    self?.toggleDictation()
                },
                cancelAction: { [weak self] in
                    self?.cancelDictation()
                }
            )
            hotKey = installedHotKey
            installedHotKey.setEscapeEnabled(deliverySession != nil)
            hotKeyWarning = installedHotKey.warning
            updateStatus(
                connected
                    ? installedHotKey.warning
                        ?? "Ready — ⌥Space or Microphone key"
                    : "Connecting…"
            )
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
