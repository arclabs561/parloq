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
    private var microphoneMenuItem: NSMenuItem?
    private let microphoneMenu = NSMenu()
    private let detailsMenu = NSMenu()
    private var saveRecordingsMenuItem: NSMenuItem?
    private var historyMenuItem: NSMenuItem?
    private var teachCorrectionMenuItem: NSMenuItem?
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
    private var correctionPromptActive = false
    private var correctionChangePending = false
    private var applicationBeforeMenu: NSRunningApplication?
    private var microphoneChangePending = false
    private var saveRecordingsChangePending = false

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
                self.correctionChangePending = false
                self.microphoneChangePending = false
                self.saveRecordingsChangePending = false
                let failure = message ?? "Daemon unavailable"
                if !self.recoverTranscript(message: failure) {
                    self.clearOverlay()
                    self.updateStatus(failure)
                }
            }
            self.refreshMicrophoneMenu()
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
        let microphone = NSMenuItem(
            title: "Microphone",
            action: nil,
            keyEquivalent: ""
        )
        microphone.submenu = microphoneMenu
        microphoneMenuItem = microphone
        menu.addItem(microphone)
        refreshMicrophoneMenu()

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

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard !microphoneChangePending,
              phase == .idle || phase == .error,
              let identifier = sender.representedObject as? String,
              let device = details.availableDevices?.first(where: {
                  $0.id == identifier
              })
        else {
            return
        }
        microphoneChangePending = true
        updateStatus("Changing microphone…")
        refreshMicrophoneMenu()
        updateMenuActions()
        client.send(DictateRequest(device: device))
    }

    @objc private func toggleSaveRecordings() {
        guard !saveRecordingsChangePending,
              phase == .idle || phase == .error,
              let enabled = details.saveEnabled
        else {
            return
        }
        saveRecordingsChangePending = true
        updateStatus(
            enabled
                ? "Turning recording retention off…"
                : "Turning recording retention on…"
        )
        refreshDetailsMenu()
        updateMenuActions()
        client.send(DictateRequest(saveRecordings: !enabled))
    }

    private func toggleDictation() {
        guard !correctionPromptActive else { return }
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
        if microphoneChangePending,
           event.type == .error
            || (
                event.type == .ack
                && event.message?.hasPrefix("Microphone set to ") == true
            )
        {
            microphoneChangePending = false
        }
        if saveRecordingsChangePending,
           event.type == .error
            || (
                event.type == .ack
                && event.message?.hasPrefix(
                    "Save Audio & Transcript turned "
                ) == true
            )
        {
            saveRecordingsChangePending = false
        }
        if correctionChangePending,
           event.type == .error
            || (
                event.type == .ack
                && event.message?.hasPrefix("Correction ") == true
            )
        {
            correctionChangePending = false
            refreshHistoryMenu()
        }
        let previousDetails = details
        details.update(from: event)
        if details != previousDetails {
            refreshMicrophoneMenu()
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
            let hasFinalText = event.text?.isEmpty == false
            let clipboardPublished =
                hasFinalText
                && deliverySession?.publishFinalToPasteboard() == true
            var clipboardWarning: String?
            if hasFinalText, !clipboardPublished {
                clipboardWarning =
                    "Dictation complete; clipboard could not be updated"
            }
            var historyWarning: String?
            if let text = event.text, !text.isEmpty {
                do {
                    try historyStore.append(
                        text,
                        rawText: event.rawText
                    )
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
            } else if let clipboardWarning {
                lastDeliveryWarning = clipboardWarning
                updateStatus(clipboardWarning)
            } else if let warning = deliverySession?.warning {
                lastDeliveryWarning = warning
                updateStatus(warning)
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
                    details: details,
                    clipboardPublished: clipboardPublished
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
            return event.configurationWarning
                ?? event.message
                ?? hotKeyWarning
                ?? "Ready — ⌥Space or Microphone key"
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
            toggleMenuItem?.isEnabled = connected
        case .finalizing, .polishing:
            toggleMenuItem?.title = "Finishing Dictation…"
            toggleMenuItem?.isEnabled = false
        default:
            toggleMenuItem?.title =
                "Start Dictation (⌥Space or Microphone key)"
            toggleMenuItem?.isEnabled =
                connected && details.deviceAvailable != false
        }
        let canChangeMicrophone =
            connected
            && !microphoneChangePending
            && (phase == .idle || phase == .error)
        for item in microphoneMenu.items
        where item.representedObject is String {
            item.isEnabled = canChangeMicrophone
        }
        saveRecordingsMenuItem?.isEnabled =
            connected
            && !saveRecordingsChangePending
            && (phase == .idle || phase == .error)
        teachCorrectionMenuItem?.isEnabled =
            connected
            && !correctionPromptActive
            && !correctionChangePending
            && (phase == .idle || phase == .error)
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
        guard let entry = historyEntry(from: sender) else { return }
        copyHistoryText(
            entry.text,
            successMessage: "Copied dictation from history"
        )
    }

    @objc private func copyRawHistoryItem(_ sender: NSMenuItem) {
        guard let entry = historyEntry(from: sender),
              let rawText = entry.distinctRawText
        else {
            return
        }
        copyHistoryText(
            rawText,
            successMessage: "Copied original ASR from history"
        )
    }

    @objc private func teachFromLatestDictation() {
        guard !correctionPromptActive,
              !correctionChangePending,
              connected,
              phase == .idle || phase == .error,
              let entry = historyStore.history.entries.first
        else {
            return
        }

        correctionPromptActive = true
        updateMenuActions()
        let returnApplication = applicationBeforeMenu
        let prompt = DictationCorrectionPrompt(entry: entry)
        let correction = prompt.run()
        correctionPromptActive = false
        restoreFocus(to: returnApplication)

        guard let correction else {
            updateMenuActions()
            return
        }
        correctionChangePending = true
        updateStatus("Saving correction…")
        refreshHistoryMenu()
        updateMenuActions()
        client.send(DictateRequest(vocabularyCorrection: correction))
    }

    private func restoreFocus(to application: NSRunningApplication?) {
        guard let application,
              !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo
                .processIdentifier
        else {
            return
        }
        DispatchQueue.main.async {
            application.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func copyHistoryText(
        _ text: String,
        successMessage: String
    ) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            updateStatus("Could not copy dictation from history")
            return
        }
        updateStatus(successMessage)
    }

    private func historyEntry(
        from sender: NSMenuItem
    ) -> TranscriptHistoryEntry? {
        guard let identifier = sender.representedObject as? String,
              let id = UUID(uuidString: identifier)
        else {
            return nil
        }
        return historyStore.history.entries.first(where: { $0.id == id })
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

    @objc private func editVocabulary() {
        guard let path = details.vocabPath else {
            updateStatus("Vocabulary file is unavailable")
            return
        }
        do {
            let fileURL = try VocabularyFile.prepare(atPath: path)
            guard NSWorkspace.shared.open(fileURL) else {
                updateStatus("Could not open vocabulary file")
                return
            }
            updateStatus("Vocabulary reloads with the next dictation")
        } catch {
            updateStatus(
                "Vocabulary file: \(error.localizedDescription)"
            )
        }
    }

    @objc private func copyDiagnostics() {
        let shortVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let buildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String
        let appVersion = [shortVersion, buildVersion.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
        let diagnostics = DictationDiagnostics.render(
            appVersion: appVersion,
            systemVersion: ProcessInfo.processInfo
                .operatingSystemVersionString,
            connected: connected,
            phase: phase,
            accessibilityGranted: AXIsProcessTrusted(),
            details: details
        )

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(
            diagnostics,
            forType: .string
        ) else {
            updateStatus("Could not copy diagnostics")
            return
        }
        updateStatus("Diagnostics copied")
    }

    private func refreshHistoryMenu() {
        historyMenu.removeAllItems()
        teachCorrectionMenuItem = nil
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
            if entries.contains(where: { $0.distinctRawText != nil }) {
                let hint = NSMenuItem(
                    title: "Hold ⌥ for original ASR",
                    action: nil,
                    keyEquivalent: ""
                )
                hint.isEnabled = false
                historyMenu.addItem(hint)
                historyMenu.addItem(.separator())
            }
            for entry in entries {
                let item = NSMenuItem(
                    title: Self.historyTitle(entry.text),
                    action: #selector(copyHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id.uuidString
                if let rawText = entry.distinctRawText {
                    item.toolTip =
                        "Final:\n\(entry.text)\n\nOriginal ASR:\n\(rawText)"
                } else {
                    item.toolTip = entry.text
                }
                historyMenu.addItem(item)

                if let rawText = entry.distinctRawText {
                    let rawItem = NSMenuItem(
                        title: Self.historyTitle(rawText),
                        action: #selector(copyRawHistoryItem(_:)),
                        keyEquivalent: ""
                    )
                    rawItem.target = self
                    rawItem.representedObject = entry.id.uuidString
                    rawItem.toolTip = rawText
                    rawItem.isAlternate = true
                    rawItem.keyEquivalentModifierMask = [.option]
                    historyMenu.addItem(rawItem)
                }
            }
        }

        historyMenu.addItem(.separator())
        if !entries.isEmpty {
            let teach = NSMenuItem(
                title: "Teach Parloq From Latest Dictation…",
                action: #selector(teachFromLatestDictation),
                keyEquivalent: ""
            )
            teach.target = self
            teach.toolTip =
                "Add an exact phrase correction without monitoring other apps."
            teach.isEnabled =
                connected
                && !correctionPromptActive
                && !correctionChangePending
                && (phase == .idle || phase == .error)
            teachCorrectionMenuItem = teach
            historyMenu.addItem(teach)
            historyMenu.addItem(.separator())
        }
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

    private func refreshMicrophoneMenu() {
        microphoneMenu.removeAllItems()
        guard connected else {
            addMicrophoneMessage("Waiting for dictation daemon…")
            microphoneMenuItem?.isEnabled = false
            return
        }
        microphoneMenuItem?.isEnabled = true

        if let warning = details.configurationWarning {
            addMicrophoneMessage(warning)
            microphoneMenu.addItem(.separator())
        } else if details.deviceAvailable == false {
            addMicrophoneMessage("Selected microphone is unavailable")
            microphoneMenu.addItem(.separator())
        }

        guard let devices = details.availableDevices else {
            addMicrophoneMessage("Loading microphones…")
            return
        }
        guard !devices.isEmpty else {
            addMicrophoneMessage("No audio inputs found")
            return
        }

        let canChange =
            !microphoneChangePending
            && (phase == .idle || phase == .error)
        let duplicateNames = Dictionary(
            grouping: devices,
            by: \.name
        ).filter { $0.value.count > 1 }.keys
        for device in devices {
            let item = NSMenuItem(
                title: duplicateNames.contains(device.name)
                    ? "\(device.name) (\(device.id))"
                    : device.name,
                action: #selector(selectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.id
            item.toolTip = "AVFoundation input \(device.id)"
            item.state = (
                details.device == device.id
                && details.deviceName == device.name
                && details.deviceAvailable != false
            ) ? .on : .off
            item.isEnabled = canChange
            microphoneMenu.addItem(item)
        }
    }

    private func addMicrophoneMessage(_ title: String) {
        let item = NSMenuItem(
            title: title,
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        microphoneMenu.addItem(item)
    }

    private func refreshDetailsMenu() {
        detailsMenu.removeAllItems()
        saveRecordingsMenuItem = nil
        guard connected else {
            addDetail("Waiting for dictation daemon…")
            addCopyDiagnosticsItem()
            return
        }

        if let device = details.deviceName ?? details.device {
            addDetail("Microphone: \(device)")
        }
        if let warning = details.configurationWarning {
            addDetail("Microphone warning: \(warning)")
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
        if let warning = details.vocabWarning {
            addDetail("Vocabulary warning: \(warning)")
        }
        if let vocabPath = details.vocabPath {
            let editVocabularyItem = NSMenuItem(
                title: "Edit Vocabulary…",
                action: #selector(editVocabulary),
                keyEquivalent: ""
            )
            editVocabularyItem.target = self
            editVocabularyItem.toolTip =
                "\(vocabPath)\nChanges apply to the next dictation."
            detailsMenu.addItem(editVocabularyItem)
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
        addModeDetail(
            "Voice level analysis",
            enabled: details.prosodyEnabled
        )
        if let saveEnabled = details.saveEnabled {
            let saveRecordings = NSMenuItem(
                title: "Save Audio & Transcript",
                action: #selector(toggleSaveRecordings),
                keyEquivalent: ""
            )
            saveRecordings.target = self
            saveRecordings.state = saveEnabled ? .on : .off
            saveRecordings.isEnabled =
                !saveRecordingsChangePending
                && (phase == .idle || phase == .error)
            let recordingsPath = details.recordingsPath.map(
                Self.displayPath
            ) ?? "the daemon recordings folder"
            saveRecordings.toolTip = saveEnabled
                ? "Completed audio and transcripts are saved in \(recordingsPath)."
                : "Off: audio is temporary and removed after transcription."
            saveRecordingsMenuItem = saveRecordings
            detailsMenu.addItem(saveRecordings)
            if saveEnabled, let path = details.recordingsPath {
                addDetail("Saving to: \(Self.displayPath(path))")
            }
        }
        addModeDetail("Chimes", enabled: details.chimeEnabled)

        if details.latestProsodyState != nil {
            var telemetry = DictationHUDTelemetry()
            telemetry.updateDetails(
                details,
                showLatestProsodyResult: true
            )
            if let label = telemetry.prosodyLabel {
                addDetail("Latest: \(label)")
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

        addCopyDiagnosticsItem()
    }

    private func addCopyDiagnosticsItem() {
        detailsMenu.addItem(.separator())
        let copy = NSMenuItem(
            title: "Copy Diagnostics",
            action: #selector(copyDiagnostics),
            keyEquivalent: ""
        )
        copy.target = self
        copy.toolTip =
            "Copies runtime settings and timing without transcript or target-app text"
        detailsMenu.addItem(copy)
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

    private static func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
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
        applicationBeforeMenu = nil
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo
            .processIdentifier
        {
            applicationBeforeMenu = frontmost
        }
        hotKey?.setTargetActivityMonitoringEnabled(false)
        if connected {
            client.send(.devices)
        }
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
