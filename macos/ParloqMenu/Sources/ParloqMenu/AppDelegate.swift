import AppKit
import ParloqMenuCore
import ServiceManagement
import os

private let appLogger = Logger(
    subsystem: "net.attobop.parloq.menu",
    category: "app"
)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum IconState: Equatable {
        case idle
        case offline
        case listening
        case finishing
        case error
    }

    private let client = UnixSocketClient()
    private var liveTranscriptPanel: LiveTranscriptPanel?
    private var completionDismissWorkItem: DispatchWorkItem?
    private var hotKey: GlobalHotKey?
    private var hotKeyRetry: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var cancelMenuItem: NSMenuItem?
    private let detailsMenu = NSMenu()
    private var historyMenuItem: NSMenuItem?
    private let historyMenu = NSMenu()
    private let historyStore = TranscriptHistoryStore()
    private var launchAtLoginMenuItem: NSMenuItem?
    private var phase: DictatePhase?
    private var connected = false
    private var deliverySession: TextDeliverySession?
    private var overlay = DictationOverlayModel()
    private var lastSequence = 0
    private var lastDeliveryWarning: String?
    private var cancellationWarning: String?
    private var cancelRequested = false
    private var hotKeyWarning: String?
    private var iconState: IconState?
    private var details = DictationDetails()
    private var statusMenuIsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        configureClient()
        installHotKey()
        client.startSubscription()
        requestAccessibilityPermission(prompt: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        completionDismissWorkItem?.cancel()
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
                self.updateStatus(
                    self.recoveryMessage
                        ?? self.hotKeyWarning
                        ?? "Connected"
                )
            } else {
                self.phase = nil
                self.lastSequence = 0
                self.deliverySession = nil
                self.cancelRequested = false
                self.cancellationWarning = nil
                self.details = DictationDetails()
                let failure = message ?? "Daemon unavailable"
                if !self.recoverTranscript(message: failure) {
                    self.clearOverlay()
                    self.updateStatus(failure)
                }
            }
            self.refreshDetailsMenu()
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
        menu.delegate = self
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
        let details = NSMenuItem(
            title: "Dictation Details",
            action: nil,
            keyEquivalent: ""
        )
        details.submenu = detailsMenu
        menu.addItem(details)
        refreshDetailsMenu()

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
        cancelOrDismiss()
    }

    private func toggleDictation() {
        guard connected else {
            updateStatus("Daemon unavailable")
            return
        }
        switch phase {
        case .recording:
            overlay.markFinishing()
            liveTranscriptPanel?.showFinishing()
            client.send(.stop)
        case .finalizing, .polishing:
            updateStatus("Finishing current dictation…")
        default:
            clearOverlay()
            lastDeliveryWarning = nil
            cancellationWarning = nil
            cancelRequested = false
            overlay.begin()
            let session = TextDeliverySession()
            deliverySession = session
            let metadata = DictationHUDMetadata(
                targetApplication: session.hudTargetApplication,
                deliveryMode: session.hudDeliveryMode
            )
            let panel = LiveTranscriptPanel(
                metadata: metadata,
                details: details,
                targetApplicationIcon: session.hudTargetApplicationIcon
            )
            liveTranscriptPanel = panel
            panel.showListening()
            hotKey?.setEscapeEnabled(true)
            hotKey?.setTargetActivityMonitoringEnabled(
                session.needsTargetActivityMonitoring
            )
            client.send(.start)
            updateMenuActions()
        }
    }

    private func handle(_ event: DictateEvent) {
        guard event.sequence > lastSequence else { return }
        lastSequence = event.sequence
        let previousDetails = details
        details.update(from: event)
        if details != previousDetails {
            refreshDetailsMenu()
            liveTranscriptPanel?.updateDetails(details)
        }
        liveTranscriptPanel?.updateElapsed(event.elapsedSeconds)
        updateInputLevel(from: event)
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
                if let visibleSnapshot = overlay.update(
                    snapshot: text,
                    finalizedText: event.finalizedText,
                    draftText: event.draftText
                ) {
                    liveTranscriptPanel?.update(
                        snapshot: visibleSnapshot,
                        elapsedSeconds: event.elapsedSeconds
                    )
                }
            }
            updateStatus(statusText(for: event))

        case .final:
            deliverySession?.deliver(event: event)
            var clipboardWarning: String?
            if let text = event.text, !text.isEmpty,
               deliverySession?.publishFinalToPasteboard() != true
            {
                clipboardWarning =
                    "Dictation complete; clipboard could not be updated"
            }
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
            } else if let clipboardWarning {
                lastDeliveryWarning = clipboardWarning
                updateStatus(clipboardWarning)
            } else if let historyWarning {
                updateStatus(historyWarning)
            } else {
                updateStatus("Dictation complete")
            }
            deliverySession = nil
            if let text = event.text, !text.isEmpty {
                overlay.complete()
                hotKey?.setEscapeEnabled(false)
                hotKey?.setTargetActivityMonitoringEnabled(false)
                liveTranscriptPanel?.showCompleted(
                    snapshot: LiveTranscriptSnapshot(
                        text: text,
                        settledText: text,
                        activeText: ""
                    ),
                    details: details
                )
                scheduleCompletionDismissal()
                updateMenuActions()
            } else {
                clearOverlay()
            }

        case .error:
            deliverySession = nil
            let failure = event.message ?? "Dictation error"
            if !recoverTranscript(message: failure) {
                clearOverlay()
                updateStatus(failure)
            }

        case .ack, .status:
            if event.phase == .finalizing || event.phase == .polishing {
                overlay.markFinishing()
                liveTranscriptPanel?.showFinishing()
            } else if event.phase == .idle, deliverySession != nil {
                clearOverlay()
            }
            if let recoveryMessage {
                updateStatus(recoveryMessage)
            } else if event.phase == .idle, let lastDeliveryWarning {
                updateStatus(lastDeliveryWarning)
            } else {
                updateStatus(statusText(for: event))
            }
        }
        updateIcon()
    }

    private func cancelOrDismiss() {
        if recoveryMessage != nil {
            clearOverlay()
            if !connected {
                updateStatus("Daemon unavailable")
            } else if phase == .error {
                updateStatus(lastDeliveryWarning ?? "Dictation error")
            } else {
                updateStatus(
                    hotKeyWarning ?? "Ready — ⌥Space or Microphone key")
            }
            updateIcon()
            return
        }
        cancelDictation()
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
        clearOverlay()
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

    private func updateInputLevel(from event: DictateEvent) {
        guard event.phase == .recording,
              let inputPeakDB = event.inputPeakDB
        else {
            return
        }
        let level = InputLevelMeter(dbFS: inputPeakDB)
        let spectrum = InputSpectrum(dbFS: event.inputSpectrumDB)
        liveTranscriptPanel?.updateInput(
            spectrum: spectrum,
            level: level
        )
        if iconState == .listening {
            statusItem?.button?.image = StatusIcon.listening(
                level: level,
                spectrum: spectrum
            )
        }
    }

    private func updateIcon() {
        let state: IconState
        if !connected {
            state = .offline
        } else if recoveryMessage != nil {
            state = .error
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
        button.contentTintColor = statusTint(for: state)
        button.title = ""
        button.setAccessibilityLabel("Parloq")
        button.setAccessibilityValue(accessibilityValue(for: state))
    }

    private func updateMenuActions() {
        if recoveryMessage != nil {
            cancelMenuItem?.title = "Dismiss Recovered Transcript (Esc)"
            cancelMenuItem?.isHidden = false
        } else {
            cancelMenuItem?.title = "Cancel Dictation (Esc)"
            let canCancel = deliverySession != nil && !cancelRequested
            cancelMenuItem?.isHidden = !canCancel
        }
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

    private var recoveryMessage: String? {
        guard case let .recovering(message) = overlay.phase else {
            return nil
        }
        return message
    }

    @discardableResult
    private func recoverTranscript(message: String) -> Bool {
        let status = "\(message) — transcript copied"
        guard let snapshot = overlay.fail(message: status) else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.text, forType: .string)
        lastDeliveryWarning = status
        hotKey?.setEscapeEnabled(true)
        liveTranscriptPanel?.showRecovery(
            snapshot: snapshot,
            message: status
        )
        updateStatus(status)
        updateMenuActions()
        return true
    }

    private func clearOverlay() {
        completionDismissWorkItem?.cancel()
        completionDismissWorkItem = nil
        overlay.complete()
        hotKey?.setEscapeEnabled(false)
        hotKey?.setTargetActivityMonitoringEnabled(false)
        liveTranscriptPanel?.hide()
        liveTranscriptPanel = nil
        updateMenuActions()
    }

    private func scheduleCompletionDismissal() {
        completionDismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.completionDismissWorkItem = nil
            self?.clearOverlay()
        }
        completionDismissWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.25,
            execute: item
        )
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

    private func statusTint(for state: IconState) -> NSColor? {
        switch state {
        case .idle, .offline:
            return nil
        case .listening:
            return ParloqVisuals.listening
        case .finishing:
            return ParloqVisuals.cyan
        case .error:
            return ParloqVisuals.coral
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

    private func refreshDetailsMenu() {
        detailsMenu.removeAllItems()
        guard connected else {
            addDetail("Waiting for dictation daemon…")
            return
        }

        if let device = details.deviceName ?? details.device {
            addDetail("Microphone: \(device)")
        }
        if let model = details.model {
            addDetail(
                "Model: \(Self.shortModelName(model))",
                toolTip: model
            )
        }
        if let vocabCount = details.vocabCount {
            addDetail(
                vocabCount == 1
                    ? "Vocabulary: 1 correction"
                    : "Vocabulary: \(vocabCount) corrections"
            )
        }
        if let interval = details.streamIntervalSeconds {
            addDetail(
                "Live updates: every \(Self.seconds(interval)) s"
            )
        }

        if details.polishEnabled != nil
            || details.prosodyEnabled != nil
            || details.saveEnabled != nil
            || details.chimeEnabled != nil
        {
            if !detailsMenu.items.isEmpty {
                detailsMenu.addItem(.separator())
            }
        }
        addModeDetail("Polish final text", enabled: details.polishEnabled)
        addModeDetail("Voice energy analysis", enabled: details.prosodyEnabled)
        addModeDetail("Save recordings", enabled: details.saveEnabled)
        addModeDetail("Chimes", enabled: details.chimeEnabled)

        if details.latestProsodyState != nil {
            var telemetry = DictationHUDTelemetry()
            telemetry.updateDetails(
                details,
                showLatestProsodyResult: true
            )
            if let label = telemetry.prosodyLabel {
                addDetail("Latest voice energy: \(label)")
            }
        }

        if let audio = details.lastAudioSeconds {
            if !detailsMenu.items.isEmpty {
                detailsMenu.addItem(.separator())
            }
            let asr = details.lastASRSeconds.map {
                " · \(Self.seconds($0)) s ASR"
            } ?? ""
            let realtime = details.latestRealtimeFactor.map {
                " · \(Self.multiplier($0))× realtime"
            } ?? ""
            addDetail(
                "Latest: \(Self.seconds(audio)) s audio\(asr)\(realtime)"
            )
        }
        if detailsMenu.items.isEmpty {
            addDetail("Waiting for daemon details…")
        }
    }

    private func addDetail(
        _ title: String,
        toolTip: String? = nil
    ) {
        let item = NSMenuItem(
            title: title,
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        item.toolTip = toolTip
        detailsMenu.addItem(item)
    }

    private func addModeDetail(
        _ title: String,
        enabled: Bool?
    ) {
        guard let enabled else { return }
        let item = NSMenuItem(
            title: title,
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        item.state = enabled ? .on : .off
        detailsMenu.addItem(item)
    }

    private static func shortModelName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func multiplier(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
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
                    self?.cancelOrDismiss()
                },
                targetActivityAction: { [weak self] in
                    self?.invalidateFinalOnlyTarget()
                }
            )
            hotKey = installedHotKey
            installedHotKey.setEscapeEnabled(deliverySession != nil)
            installedHotKey.setTargetActivityMonitoringEnabled(
                deliverySession?.needsTargetActivityMonitoring == true
            )
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

    private func invalidateFinalOnlyTarget() {
        guard !statusMenuIsOpen else { return }
        guard deliverySession?.invalidateFinalOnlyTarget() == true else {
            return
        }
        hotKey?.setTargetActivityMonitoringEnabled(false)
        liveTranscriptPanel?.updateDeliveryMode(.targetChanged)
        updateStatus("Safe copy mode; final transcript will be copied")
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuIsOpen = true
        hotKey?.setTargetActivityMonitoringEnabled(false)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusMenuIsOpen = false
        hotKey?.setTargetActivityMonitoringEnabled(
            deliverySession?.needsTargetActivityMonitoring == true
        )
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
