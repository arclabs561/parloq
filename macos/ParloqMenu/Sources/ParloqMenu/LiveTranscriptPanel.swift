import AppKit
import ParloqMenuCore
import QuartzCore

enum ParloqVisuals {
    static let surfaceTint = NSColor(
        srgbRed: 0.035,
        green: 0.055,
        blue: 0.14,
        alpha: 1
    )
    static let listening = NSColor(
        srgbRed: 0.31,
        green: 0.92,
        blue: 0.58,
        alpha: 1
    )
    static let cyan = NSColor(
        srgbRed: 0.20,
        green: 0.79,
        blue: 0.95,
        alpha: 1
    )
    static let coral = NSColor(
        srgbRed: 1.0,
        green: 0.42,
        blue: 0.45,
        alpha: 1
    )
    static let text = NSColor.labelColor
    static let secondaryText = NSColor.secondaryLabelColor
    static let tertiaryText = NSColor.tertiaryLabelColor
}

@MainActor
private final class InputSpectrumView: NSView {
    private let bars: [CALayer]
    private var displayedBands = Array(
        repeating: 0.0,
        count: InputSpectrum.bandCount
    )

    override init(frame frameRect: NSRect) {
        bars = (0..<InputSpectrum.bandCount).map { _ in CALayer() }
        super.init(frame: frameRect)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
        }
        setAccessibilityLabel("Live microphone frequency spectrum")
        update(InputSpectrum(dbFS: nil), fallback: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let width: CGFloat = 2.4
        let gap: CGFloat = 1.8
        let contentWidth = CGFloat(bars.count) * width
            + CGFloat(max(0, bars.count - 1)) * gap
        let leading = max(0, (bounds.width - contentWidth) / 2)
        for (index, bar) in bars.enumerated() {
            bar.frame = CGRect(
                x: leading + CGFloat(index) * (width + gap),
                y: 0,
                width: width,
                height: max(1.5, bar.frame.height)
            )
        }
    }

    func update(
        _ spectrum: InputSpectrum,
        fallback level: InputLevelMeter?
    ) {
        let normalized = spectrum.hasTelemetry
            ? spectrum.normalizedBands
            : fallbackBands(for: level)
        let hasSignal = spectrum.hasTelemetry || level != nil
        for index in displayedBands.indices {
            guard hasSignal else {
                displayedBands[index] = 0
                continue
            }
            let target = normalized[index]
            let response = target > displayedBands[index] ? 0.58 : 0.24
            displayedBands[index] += (
                target - displayedBands[index]
            ) * response
        }

        CATransaction.begin()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || !hasSignal
        {
            CATransaction.setDisableActions(true)
        } else {
            CATransaction.setAnimationDuration(0.11)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut)
            )
        }
        for (index, bar) in bars.enumerated() {
            let value = displayedBands[index]
            let availableHeight = max(bounds.height, 11)
            let height = 1.5 + CGFloat(value) * (availableHeight - 1.5)
            bar.frame = CGRect(
                x: bar.frame.minX,
                y: 0,
                width: bar.frame.width,
                height: height
            )
            bar.backgroundColor = ParloqVisuals.listening
                .withAlphaComponent(0.22 + 0.78 * value)
                .cgColor
        }
        CATransaction.commit()
        let audibleBands = displayedBands.filter { $0 >= 0.18 }.count
        setAccessibilityValue("\(audibleBands) active frequency bands")
    }

    private func fallbackBands(for level: InputLevelMeter?) -> [Double] {
        guard let level, level.normalizedLevel > 0 else {
            return Array(repeating: 0, count: InputSpectrum.bandCount)
        }
        let contour = [0.25, 0.42, 0.72, 1.0, 0.86, 0.64, 0.44, 0.28, 0.18]
        return contour.map { $0 * level.normalizedLevel }
    }
}

@MainActor
private struct PanelSurfaceGroup {
    let root: NSView
    let rootContent: NSView
    let main: NSView
    let mainContent: NSView
    let shelf: NSView
    let shelfContent: NSView
    let state: NSView
    let stateContent: NSView
    let usesNativeGlass: Bool
}

@MainActor
private func makePanelSurfaceGroup(
    presentsWindow: Bool
) -> PanelSurfaceGroup {
    // NSGlassEffectView's compositor does not participate in an offscreen
    // cacheDisplay pass. Fixtures preserve the exact island geometry with
    // visual-effect fallbacks; the installed panel uses native glass.
    if #available(macOS 26.0, *), presentsWindow {
        let container = NSGlassEffectContainerView()
        container.spacing = 12
        let rootContent = NSView()
        container.contentView = rootContent

        func glass(
            radius: CGFloat,
            style: NSGlassEffectView.Style = .regular,
            tint: NSColor? = nil
        ) -> (NSGlassEffectView, NSView) {
            let surface = NSGlassEffectView()
            surface.style = style
            surface.cornerRadius = radius
            surface.tintColor = tint
            let content = NSView()
            surface.contentView = content
            return (surface, content)
        }

        let (main, mainContent) = glass(radius: 27)
        let (shelf, shelfContent) = glass(radius: 18, style: .clear)
        let (state, stateContent) = glass(
            radius: 28,
            tint: ParloqVisuals.listening.withAlphaComponent(0.22)
        )
        rootContent.addSubview(main)
        rootContent.addSubview(shelf)
        rootContent.addSubview(state)
        return PanelSurfaceGroup(
            root: container,
            rootContent: rootContent,
            main: main,
            mainContent: mainContent,
            shelf: shelf,
            shelfContent: shelfContent,
            state: state,
            stateContent: stateContent,
            usesNativeGlass: true
        )
    }

    let root = NSView()

    func fallback(
        radius: CGFloat
    ) -> NSVisualEffectView {
        let surface = NSVisualEffectView()
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = radius
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 0.5
        surface.layer?.borderColor = NSColor.white
            .withAlphaComponent(0.18)
            .cgColor
        return surface
    }

    let main = fallback(radius: 27)
    let shelf = fallback(radius: 18)
    let state = fallback(radius: 28)
    root.addSubview(main)
    root.addSubview(shelf)
    root.addSubview(state)
    return PanelSurfaceGroup(
        root: root,
        rootContent: root,
        main: main,
        mainContent: main,
        shelf: shelf,
        shelfContent: shelf,
        state: state,
        stateContent: state,
        usesNativeGlass: false
    )
}

@MainActor
private func makeTintView(
    color: NSColor,
    alpha: CGFloat
) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = color
        .withAlphaComponent(alpha)
        .cgColor
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

private enum PanelMetrics {
    static let width: CGFloat = 640
    static let minimumHeight: CGFloat = 154
    static let maximumHeight: CGFloat = 236
    static let verticalChrome: CGFloat = 136
    static let transcriptWidth: CGFloat = width - 88
}

@MainActor
final class LiveTranscriptPanel {
    private let panel: NSPanel
    private let surfaces: PanelSurfaceGroup
    private let stateTintView: NSView
    private let iconView: NSImageView
    private let stateLabel: NSTextField
    private let hintLabel: NSTextField
    private let transcriptLabel: NSTextField
    private let targetApplicationIconView: NSImageView
    private let contextLabel: NSTextField
    private let inputSpectrumView: InputSpectrumView
    private let centerMetricLabel: NSTextField
    private let elapsedLabel: NSTextField
    private let statsLabel: NSTextField
    private let prosodyLabel: NSTextField
    private let presentsWindow: Bool
    private var metadata: DictationHUDMetadata
    private var telemetry: DictationHUDTelemetry
    private var contextOverride: String?
    private var latestSnapshot: LiveTranscriptSnapshot?

    init(
        metadata: DictationHUDMetadata,
        details: DictationDetails = DictationDetails(),
        targetApplicationIcon: NSImage? = nil,
        presentsWindow: Bool = true
    ) {
        self.metadata = metadata
        telemetry = DictationHUDTelemetry(details: details)
        self.presentsWindow = presentsWindow
        surfaces = makePanelSurfaceGroup(presentsWindow: presentsWindow)
        let reduceTransparency =
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let mainTintView = makeTintView(
            color: ParloqVisuals.surfaceTint,
            alpha: reduceTransparency
                ? 0.94
                : (surfaces.usesNativeGlass ? 0 : 0.30)
        )
        let shelfTintView = makeTintView(
            color: ParloqVisuals.surfaceTint,
            alpha: reduceTransparency
                ? 0.90
                : (surfaces.usesNativeGlass ? 0 : 0.24)
        )
        stateTintView = makeTintView(
            color: ParloqVisuals.listening,
            alpha: reduceTransparency
                ? 0.28
                : (surfaces.usesNativeGlass ? 0 : 0.14)
        )
        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.width,
                height: PanelMetrics.minimumHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.contentView = surfaces.root
        if surfaces.rootContent !== surfaces.root {
            surfaces.rootContent.frame = surfaces.root.bounds
            surfaces.rootContent.autoresizingMask = [.width, .height]
        }
        for (surface, content) in [
            (surfaces.main, surfaces.mainContent),
            (surfaces.shelf, surfaces.shelfContent),
            (surfaces.state, surfaces.stateContent),
        ] where content !== surface {
            content.frame = surface.bounds
            content.autoresizingMask = [.width, .height]
        }

        iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = ParloqVisuals.cyan
        iconView.wantsLayer = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        stateLabel = NSTextField(labelWithString: "")
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel = NSTextField(labelWithString: "")
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        transcriptLabel = NSTextField(wrappingLabelWithString: "")
        transcriptLabel.maximumNumberOfLines = 4
        transcriptLabel.lineBreakMode = .byTruncatingHead
        transcriptLabel.isSelectable = false
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false
        transcriptLabel.setAccessibilityLabel("Live transcription")

        targetApplicationIconView = NSImageView()
        targetApplicationIconView.image = targetApplicationIcon
        targetApplicationIconView.imageScaling = .scaleProportionallyUpOrDown
        targetApplicationIconView.isHidden = targetApplicationIcon == nil
        targetApplicationIconView.translatesAutoresizingMaskIntoConstraints =
            false
        targetApplicationIconView.setAccessibilityLabel(
            "Dictation target application"
        )
        targetApplicationIconView.setAccessibilityValue(
            metadata.targetApplication ?? "Unknown"
        )

        contextLabel = NSTextField(labelWithString: "")
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.maximumNumberOfLines = 1
        contextLabel.usesSingleLineMode = true
        contextLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        contextLabel.translatesAutoresizingMaskIntoConstraints = false

        inputSpectrumView = InputSpectrumView()
        inputSpectrumView.translatesAutoresizingMaskIntoConstraints = false

        centerMetricLabel = NSTextField(labelWithString: "")
        centerMetricLabel.alignment = .center
        centerMetricLabel.translatesAutoresizingMaskIntoConstraints = false

        elapsedLabel = NSTextField(labelWithString: "")
        elapsedLabel.alignment = .right
        elapsedLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

        statsLabel = NSTextField(labelWithString: "")
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.maximumNumberOfLines = 1
        statsLabel.usesSingleLineMode = true
        statsLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        prosodyLabel = NSTextField(labelWithString: "")
        prosodyLabel.alignment = .right
        prosodyLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        prosodyLabel.translatesAutoresizingMaskIntoConstraints = false

        surfaces.main.translatesAutoresizingMaskIntoConstraints = false
        surfaces.shelf.translatesAutoresizingMaskIntoConstraints = false
        surfaces.state.translatesAutoresizingMaskIntoConstraints = false

        surfaces.mainContent.addSubview(mainTintView)
        surfaces.mainContent.addSubview(stateLabel)
        surfaces.mainContent.addSubview(hintLabel)
        surfaces.mainContent.addSubview(transcriptLabel)

        surfaces.stateContent.addSubview(stateTintView)
        surfaces.stateContent.addSubview(iconView)

        surfaces.shelfContent.addSubview(shelfTintView)
        surfaces.shelfContent.addSubview(targetApplicationIconView)
        surfaces.shelfContent.addSubview(contextLabel)
        surfaces.shelfContent.addSubview(inputSpectrumView)
        surfaces.shelfContent.addSubview(centerMetricLabel)
        surfaces.shelfContent.addSubview(elapsedLabel)
        surfaces.shelfContent.addSubview(statsLabel)
        surfaces.shelfContent.addSubview(prosodyLabel)

        let contextLeadingConstraint: NSLayoutConstraint
        if targetApplicationIcon == nil {
            contextLeadingConstraint = contextLabel.leadingAnchor.constraint(
                equalTo: surfaces.shelfContent.leadingAnchor,
                constant: 16
            )
        } else {
            contextLeadingConstraint = contextLabel.leadingAnchor.constraint(
                equalTo: targetApplicationIconView.trailingAnchor,
                constant: 6
            )
        }
        NSLayoutConstraint.activate([
            surfaces.main.leadingAnchor.constraint(
                equalTo: surfaces.rootContent.leadingAnchor,
                constant: 18
            ),
            surfaces.main.trailingAnchor.constraint(
                equalTo: surfaces.rootContent.trailingAnchor
            ),
            surfaces.main.topAnchor.constraint(
                equalTo: surfaces.rootContent.topAnchor
            ),
            surfaces.main.bottomAnchor.constraint(
                equalTo: surfaces.shelf.topAnchor,
                constant: -8
            ),
            surfaces.shelf.leadingAnchor.constraint(
                equalTo: surfaces.rootContent.leadingAnchor,
                constant: 30
            ),
            surfaces.shelf.trailingAnchor.constraint(
                equalTo: surfaces.rootContent.trailingAnchor,
                constant: -12
            ),
            surfaces.shelf.bottomAnchor.constraint(
                equalTo: surfaces.rootContent.bottomAnchor
            ),
            surfaces.shelf.heightAnchor.constraint(equalToConstant: 58),
            surfaces.state.leadingAnchor.constraint(
                equalTo: surfaces.rootContent.leadingAnchor
            ),
            surfaces.state.topAnchor.constraint(
                equalTo: surfaces.main.topAnchor,
                constant: 12
            ),
            surfaces.state.widthAnchor.constraint(equalToConstant: 56),
            surfaces.state.heightAnchor.constraint(equalToConstant: 56),

            mainTintView.leadingAnchor.constraint(
                equalTo: surfaces.mainContent.leadingAnchor
            ),
            mainTintView.trailingAnchor.constraint(
                equalTo: surfaces.mainContent.trailingAnchor
            ),
            mainTintView.topAnchor.constraint(
                equalTo: surfaces.mainContent.topAnchor
            ),
            mainTintView.bottomAnchor.constraint(
                equalTo: surfaces.mainContent.bottomAnchor
            ),
            shelfTintView.leadingAnchor.constraint(
                equalTo: surfaces.shelfContent.leadingAnchor
            ),
            shelfTintView.trailingAnchor.constraint(
                equalTo: surfaces.shelfContent.trailingAnchor
            ),
            shelfTintView.topAnchor.constraint(
                equalTo: surfaces.shelfContent.topAnchor
            ),
            shelfTintView.bottomAnchor.constraint(
                equalTo: surfaces.shelfContent.bottomAnchor
            ),
            stateTintView.leadingAnchor.constraint(
                equalTo: surfaces.stateContent.leadingAnchor
            ),
            stateTintView.trailingAnchor.constraint(
                equalTo: surfaces.stateContent.trailingAnchor
            ),
            stateTintView.topAnchor.constraint(
                equalTo: surfaces.stateContent.topAnchor
            ),
            stateTintView.bottomAnchor.constraint(
                equalTo: surfaces.stateContent.bottomAnchor
            ),
            iconView.centerYAnchor.constraint(
                equalTo: surfaces.stateContent.centerYAnchor
            ),
            iconView.centerXAnchor.constraint(
                equalTo: surfaces.stateContent.centerXAnchor
            ),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            stateLabel.leadingAnchor.constraint(
                equalTo: surfaces.mainContent.leadingAnchor,
                constant: 54
            ),
            stateLabel.topAnchor.constraint(
                equalTo: surfaces.mainContent.topAnchor,
                constant: 16
            ),
            hintLabel.trailingAnchor.constraint(
                equalTo: surfaces.mainContent.trailingAnchor,
                constant: -20
            ),
            hintLabel.firstBaselineAnchor.constraint(
                equalTo: stateLabel.firstBaselineAnchor
            ),
            stateLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: hintLabel.leadingAnchor,
                constant: -12
            ),
            transcriptLabel.leadingAnchor.constraint(
                equalTo: surfaces.mainContent.leadingAnchor,
                constant: 48
            ),
            transcriptLabel.trailingAnchor.constraint(
                equalTo: surfaces.mainContent.trailingAnchor,
                constant: -22
            ),
            transcriptLabel.topAnchor.constraint(
                equalTo: stateLabel.bottomAnchor,
                constant: 15
            ),
            transcriptLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: surfaces.mainContent.bottomAnchor,
                constant: -17
            ),
            targetApplicationIconView.leadingAnchor.constraint(
                equalTo: surfaces.shelfContent.leadingAnchor,
                constant: 16
            ),
            targetApplicationIconView.centerYAnchor.constraint(
                equalTo: contextLabel.centerYAnchor
            ),
            targetApplicationIconView.widthAnchor.constraint(
                equalToConstant: 13
            ),
            targetApplicationIconView.heightAnchor.constraint(
                equalToConstant: 13
            ),
            contextLeadingConstraint,
            contextLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: inputSpectrumView.leadingAnchor,
                constant: -16
            ),
            contextLabel.bottomAnchor.constraint(
                equalTo: statsLabel.topAnchor,
                constant: -6
            ),
            inputSpectrumView.widthAnchor.constraint(equalToConstant: 40),
            inputSpectrumView.heightAnchor.constraint(equalToConstant: 12),
            inputSpectrumView.centerXAnchor.constraint(
                equalTo: surfaces.shelfContent.centerXAnchor
            ),
            inputSpectrumView.centerYAnchor.constraint(
                equalTo: contextLabel.centerYAnchor
            ),
            elapsedLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: inputSpectrumView.trailingAnchor,
                constant: 16
            ),
            elapsedLabel.trailingAnchor.constraint(
                equalTo: surfaces.shelfContent.trailingAnchor,
                constant: -16
            ),
            elapsedLabel.firstBaselineAnchor.constraint(
                equalTo: contextLabel.firstBaselineAnchor
            ),
            centerMetricLabel.centerXAnchor.constraint(
                equalTo: inputSpectrumView.centerXAnchor
            ),
            centerMetricLabel.centerYAnchor.constraint(
                equalTo: inputSpectrumView.centerYAnchor
            ),
            centerMetricLabel.widthAnchor.constraint(equalToConstant: 112),
            statsLabel.leadingAnchor.constraint(
                equalTo: surfaces.shelfContent.leadingAnchor,
                constant: 16
            ),
            statsLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: prosodyLabel.leadingAnchor,
                constant: -12
            ),
            statsLabel.bottomAnchor.constraint(
                equalTo: surfaces.shelfContent.bottomAnchor,
                constant: -10
            ),
            prosodyLabel.trailingAnchor.constraint(
                equalTo: surfaces.shelfContent.trailingAnchor,
                constant: -16
            ),
            prosodyLabel.firstBaselineAnchor.constraint(
                equalTo: statsLabel.firstBaselineAnchor
            ),
        ])
        renderMetadata()
    }

    func showListening() {
        latestSnapshot = nil
        contextOverride = nil
        inputSpectrumView.isHidden = false
        centerMetricLabel.isHidden = true
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.listening
        setMode(
            title: "Listening",
            hint: "Esc  Cancel   ·   ⌥ Space  Finish",
            color: ParloqVisuals.listening
        )
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        renderMetadata()
        renderTelemetry()
        renderPlaceholder("Start speaking")
        presentIfNeeded()
    }

    func update(
        snapshot: LiveTranscriptSnapshot,
        elapsedSeconds: Double?
    ) {
        guard !snapshot.text.isEmpty else { return }
        latestSnapshot = snapshot
        inputSpectrumView.isHidden = false
        centerMetricLabel.isHidden = true
        metadata.updateElapsed(elapsedSeconds)
        telemetry.updateTranscript(
            snapshot.text,
            elapsedSeconds: elapsedSeconds
        )
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.listening
        setMode(
            title: "Listening",
            hint: "Esc  Cancel   ·   ⌥ Space  Finish",
            color: ParloqVisuals.listening
        )
        renderMetadata()
        renderTelemetry()
        render(snapshot: snapshot, showCursor: true)
        presentIfNeeded()
    }

    func updateElapsed(_ elapsedSeconds: Double?) {
        metadata.updateElapsed(elapsedSeconds)
        telemetry.updateTranscript(
            latestSnapshot?.text ?? "",
            elapsedSeconds: elapsedSeconds
        )
        renderMetadata()
        renderTelemetry()
    }

    func updateDeliveryMode(_ mode: DictationDeliveryMode) {
        metadata.updateDeliveryMode(mode)
        renderMetadata()
    }

    func updateDetails(_ details: DictationDetails) {
        telemetry.updateDetails(details)
        renderTelemetry()
    }

    func updateInput(
        spectrum: InputSpectrum,
        level: InputLevelMeter
    ) {
        telemetry.updateInputPeak(level.dbFS)
        inputSpectrumView.update(spectrum, fallback: level)
        iconView.image = StatusIcon.listening(
            level: level,
            spectrum: spectrum
        )
        renderTelemetry()
    }

    func showFinishing() {
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        setCenterMetric("Accuracy pass")
        iconView.contentTintColor = ParloqVisuals.cyan
        iconView.image = StatusIcon.finishing
        setMode(
            title: "Finalizing",
            hint: "Esc  Cancel",
            color: ParloqVisuals.cyan
        )
        renderTelemetry()
        if let latestSnapshot {
            render(snapshot: latestSnapshot, showCursor: false)
        } else {
            renderPlaceholder("Preparing final text")
        }
    }

    func showCompleted(
        snapshot: LiveTranscriptSnapshot,
        details: DictationDetails
    ) {
        latestSnapshot = snapshot
        telemetry.updateTranscript(
            snapshot.text,
            elapsedSeconds: details.lastAudioSeconds
        )
        telemetry.updateDetails(details, showLatestProsodyResult: true)
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        setCenterMetric(
            telemetry.completionPerformanceLabel ?? "Processed locally"
        )
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.ready
        let copied = metadata.deliveryMode == .clipboardFallback
            || metadata.deliveryMode == .targetChanged
        setMode(
            title: copied ? "Copied" : "Complete",
            hint: "⌥ Space  Dictate again",
            color: ParloqVisuals.listening
        )
        renderMetadata()
        renderTelemetry()
        render(snapshot: snapshot, showCursor: false)
        presentIfNeeded()
    }

    func showRecovery(
        snapshot: LiveTranscriptSnapshot,
        message: String
    ) {
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        setCenterMetric("Transcript preserved")
        contextOverride = "Copied to clipboard"
        latestSnapshot = snapshot
        iconView.contentTintColor = ParloqVisuals.coral
        iconView.image = StatusIcon.error
        setMode(
            title: "Recovered",
            hint: "Transcript copied   ·   Esc  Dismiss",
            color: ParloqVisuals.coral,
            toolTip: message
        )
        renderMetadata()
        renderTelemetry()
        render(snapshot: snapshot, showCursor: false)
        presentIfNeeded()
    }

    func hide() {
        latestSnapshot = nil
        panel.orderOut(nil)
    }

    func writeFixturePNG(to url: URL) throws {
        guard !presentsWindow, let contentView = panel.contentView else {
            throw CocoaError(.featureUnsupported)
        }
        panel.layoutIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(
            in: contentView.bounds
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        guard let data = bitmap.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    private func render(
        snapshot: LiveTranscriptSnapshot,
        showCursor: Bool
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0

        let value = NSMutableAttributedString(string: "")
        if !snapshot.settledText.isEmpty {
            value.append(NSAttributedString(
                string: snapshot.settledText,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: 15,
                        weight: .regular
                    ),
                    .foregroundColor:
                        ParloqVisuals.secondaryText.withAlphaComponent(0.78),
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        if !snapshot.activeText.isEmpty {
            if !value.string.isEmpty {
                value.append(NSAttributedString(
                    string: "\n",
                    attributes: [.paragraphStyle: paragraph]
                ))
            }
            value.append(NSAttributedString(
                string: snapshot.activeText,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: 16.5,
                        weight: .regular
                    ),
                    .foregroundColor: ParloqVisuals.text,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        if showCursor {
            value.append(NSAttributedString(
                string: "\u{00A0}\u{00A0}│",
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: 17,
                        weight: .medium
                    ),
                    .foregroundColor: ParloqVisuals.cyan,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        transcriptLabel.attributedStringValue = value
        transcriptLabel.setAccessibilityValue(snapshot.text)
        growToFitTranscript()
    }

    private func renderPlaceholder(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        paragraph.lineSpacing = 3
        transcriptLabel.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor:
                    ParloqVisuals.secondaryText.withAlphaComponent(0.78),
                .paragraphStyle: paragraph,
            ]
        )
        transcriptLabel.setAccessibilityValue(text)
        growToFitTranscript()
    }

    private func renderMetadata() {
        let context = contextOverride ?? metadata.contextLabel
        let contextColor = (
            contextOverride != nil
                || metadata.deliveryMode == .targetChanged
                ? ParloqVisuals.coral.withAlphaComponent(0.90)
                : ParloqVisuals.secondaryText.withAlphaComponent(0.88)
        )
        contextLabel.attributedStringValue = NSAttributedString(
            string: context,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: contextColor,
            ]
        )
        contextLabel.setAccessibilityLabel("Dictation destination")
        contextLabel.setAccessibilityValue(context)

        elapsedLabel.attributedStringValue = NSAttributedString(
            string: metadata.elapsedLabel,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 10,
                    weight: .medium
                ),
                .foregroundColor:
                    ParloqVisuals.secondaryText.withAlphaComponent(0.78),
            ]
        )
        elapsedLabel.setAccessibilityLabel("Elapsed dictation time")
        elapsedLabel.setAccessibilityValue(metadata.elapsedLabel)
    }

    private func renderTelemetry() {
        let summary = telemetry.summaryLabel
        statsLabel.attributedStringValue = NSAttributedString(
            string: summary,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                .foregroundColor:
                    ParloqVisuals.tertiaryText.withAlphaComponent(0.90),
            ]
        )
        statsLabel.setAccessibilityLabel("Dictation telemetry")
        statsLabel.setAccessibilityValue(summary)

        let prosody = telemetry.prosodyLabel ?? ""
        prosodyLabel.isHidden = prosody.isEmpty
        prosodyLabel.attributedStringValue = NSAttributedString(
            string: prosody,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: telemetry.hasElevatedEnergy
                    ? ParloqVisuals.listening
                    : ParloqVisuals.secondaryText.withAlphaComponent(0.82),
            ]
        )
        prosodyLabel.setAccessibilityLabel("Prosody")
        prosodyLabel.setAccessibilityValue(prosody)
    }

    private func setCenterMetric(_ text: String) {
        centerMetricLabel.isHidden = false
        centerMetricLabel.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor:
                    ParloqVisuals.secondaryText.withAlphaComponent(0.78),
            ]
        )
        centerMetricLabel.setAccessibilityValue(text)
    }

    private func growToFitTranscript() {
        let bounds = transcriptLabel.attributedStringValue.boundingRect(
            with: NSSize(
                width: PanelMetrics.transcriptWidth,
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let fittedHeight = ceil(bounds.height)
            + PanelMetrics.verticalChrome
        let targetHeight = min(
            PanelMetrics.maximumHeight,
            max(PanelMetrics.minimumHeight, fittedHeight)
        )

        guard targetHeight > panel.frame.height + 0.5 else { return }
        var frame = panel.frame
        frame.size.height = targetHeight
        panel.setFrame(frame, display: true)
    }

    private func setMode(
        title: String,
        hint: String,
        color: NSColor,
        toolTip: String? = nil
    ) {
        updateStateSurface(color: color)
        stateLabel.attributedStringValue = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: color,
            ]
        )
        stateLabel.toolTip = toolTip
        stateLabel.setAccessibilityValue(toolTip ?? title)
        hintLabel.attributedStringValue = NSAttributedString(
            string: hint,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor:
                    ParloqVisuals.secondaryText.withAlphaComponent(0.76),
            ]
        )
    }

    private func updateStateSurface(color: NSColor) {
        if #available(macOS 26.0, *),
           let glass = surfaces.state as? NSGlassEffectView
        {
            glass.tintColor = color.withAlphaComponent(0.22)
        }

        let alpha: CGFloat
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            alpha = 0.28
        } else {
            alpha = surfaces.usesNativeGlass ? 0 : 0.14
        }
        stateTintView.layer?.backgroundColor = color
            .withAlphaComponent(alpha)
            .cgColor
    }

    private func positionNearFocusedTarget() {
        let pointer = NSEvent.mouseLocation
        let screen = FocusedTargetScreen.capture()
            ?? NSScreen.screens.first {
                NSMouseInRect(pointer, $0.frame, false)
            }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 88
        )
        panel.setFrameOrigin(origin)
    }

    private func presentIfNeeded() {
        guard presentsWindow, !panel.isVisible else { return }
        positionNearFocusedTarget()
        panel.orderFrontRegardless()
    }
}
