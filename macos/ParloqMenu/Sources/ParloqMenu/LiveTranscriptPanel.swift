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
    static let caution = NSColor(
        srgbRed: 1.0,
        green: 0.72,
        blue: 0.25,
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
        let width: CGFloat = 1.8
        let gap: CGFloat = 1.2
        let contentWidth = CGFloat(bars.count) * width
            + CGFloat(max(0, bars.count - 1)) * gap
        let leading = max(0, (bounds.width - contentWidth) / 2)
        for (index, bar) in bars.enumerated() {
            let height = max(1.5, bar.frame.height)
            bar.frame = CGRect(
                x: leading + CGFloat(index) * (width + gap),
                y: (bounds.height - height) / 2,
                width: width,
                height: height
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
                y: (bounds.height - height) / 2,
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
private final class SpectralEdgeView: NSView {
    private let cornerRadius: CGFloat
    private let gradient = CAGradientLayer()
    private let strokeMask = CAShapeLayer()

    init(cornerRadius: CGFloat, intensity: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true

        gradient.startPoint = CGPoint(x: 0.02, y: 0.12)
        gradient.endPoint = CGPoint(x: 0.98, y: 0.88)
        gradient.colors = [
            NSColor.clear.cgColor,
            ParloqVisuals.cyan
                .withAlphaComponent(0.24 * intensity)
                .cgColor,
            NSColor.white
                .withAlphaComponent(0.40 * intensity)
                .cgColor,
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.systemPink
                .withAlphaComponent(0.18 * intensity)
                .cgColor,
            NSColor.clear.cgColor,
            ParloqVisuals.listening
                .withAlphaComponent(0.16 * intensity)
                .cgColor,
            NSColor.white
                .withAlphaComponent(0.26 * intensity)
                .cgColor,
            NSColor.clear.cgColor,
        ]
        gradient.locations = [
            0, 0.09, 0.18, 0.31, 0.58, 0.68, 0.76, 0.86, 0.94, 1,
        ]
        gradient.mask = strokeMask
        layer?.addSublayer(gradient)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        gradient.contentsScale = scale
        gradient.frame = bounds
        strokeMask.contentsScale = scale
        strokeMask.frame = gradient.bounds
        strokeMask.fillColor = NSColor.clear.cgColor
        strokeMask.strokeColor = NSColor.white.cgColor
        strokeMask.lineWidth = 1.35
        let inset: CGFloat = 0.8
        strokeMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: max(0, cornerRadius - inset),
            cornerHeight: max(0, cornerRadius - inset),
            transform: nil
        )
    }
}

@MainActor
private struct PanelSurfaceGroup {
    let root: NSView
    let content: NSView
    let usesNativeGlass: Bool
}

@MainActor
private func makePanelSurfaceGroup(
    presentsWindow: Bool
) -> PanelSurfaceGroup {
    // NSGlassEffectView's compositor does not participate in an offscreen
    // cacheDisplay pass. Fixtures preserve the same single-surface geometry
    // with a visual-effect fallback; the installed panel uses native glass.
    if #available(macOS 26.0, *), presentsWindow {
        let root = NSGlassEffectView()
        root.style = .regular
        root.cornerRadius = 28
        root.tintColor = ParloqVisuals.surfaceTint.withAlphaComponent(0.12)
        let content = NSView()
        root.contentView = content
        return PanelSurfaceGroup(
            root: root,
            content: content,
            usesNativeGlass: true
        )
    }

    let root = NSVisualEffectView()
    root.material = .popover
    root.blendingMode = .behindWindow
    root.state = .active
    root.wantsLayer = true
    root.layer?.cornerRadius = 28
    root.layer?.cornerCurve = .continuous
    root.layer?.masksToBounds = true
    root.layer?.borderWidth = 0.5
    root.layer?.borderColor = NSColor.white
        .withAlphaComponent(0.18)
        .cgColor
    return PanelSurfaceGroup(
        root: root,
        content: root,
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

@MainActor
private func makeAccentGlowView(alpha: CGFloat) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    let gradient = CAGradientLayer()
    gradient.type = .radial
    gradient.startPoint = CGPoint(x: 0.12, y: 0.92)
    gradient.endPoint = CGPoint(x: 0.58, y: 0.36)
    gradient.colors = [
        ParloqVisuals.listening.withAlphaComponent(alpha).cgColor,
        ParloqVisuals.cyan.withAlphaComponent(alpha * 0.34).cgColor,
        NSColor.clear.cgColor,
    ]
    gradient.locations = [0, 0.38, 1]
    gradient.frame = view.bounds
    gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    view.layer?.addSublayer(gradient)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setAccessibilityElement(false)
    return view
}

private enum PanelMetrics {
    static let contentWidth: CGFloat = 520
    static let outerPadding: CGFloat = 8
    static let width: CGFloat = contentWidth + 2 * outerPadding
    static let minimumHeight: CGFloat = 120 + 2 * outerPadding
    static let maximumHeight: CGFloat = 204 + 2 * outerPadding
    static let verticalChrome: CGFloat = 92 + 2 * outerPadding
    static let transcriptWidth: CGFloat = contentWidth - 40
}

@MainActor
final class LiveTranscriptPanel {
    private let panel: NSPanel
    private let surfaces: PanelSurfaceGroup
    private let iconView: NSImageView
    private let stateLabel: NSTextField
    private let hintLabel: NSTextField
    private let transcriptLabel: NSTextField
    private let targetApplicationIconView: NSImageView
    private let contextLabel: NSTextField
    private let inputSpectrumView: InputSpectrumView
    private let elapsedLabel: NSTextField
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
        let tintView = makeTintView(
            color: ParloqVisuals.surfaceTint,
            alpha: reduceTransparency
                ? 0.94
                : (surfaces.usesNativeGlass ? 0 : 0.30)
        )
        let edgeView = SpectralEdgeView(
            cornerRadius: 28,
            intensity: surfaces.usesNativeGlass ? 0.45 : 0.30
        )
        edgeView.frame = surfaces.content.bounds
        edgeView.autoresizingMask = [.width, .height]
        edgeView.isHidden = reduceTransparency
        let accentGlowView = makeAccentGlowView(
            alpha: surfaces.usesNativeGlass ? 0.16 : 0.12
        )
        accentGlowView.isHidden = reduceTransparency
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
        if surfaces.content !== surfaces.root {
            surfaces.content.frame = surfaces.root.bounds
            surfaces.content.autoresizingMask = [.width, .height]
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

        elapsedLabel = NSTextField(labelWithString: "")
        elapsedLabel.alignment = .right
        elapsedLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

        surfaces.content.addSubview(tintView)
        surfaces.content.addSubview(accentGlowView)
        surfaces.content.addSubview(edgeView)
        surfaces.content.addSubview(stateLabel)
        surfaces.content.addSubview(inputSpectrumView)
        surfaces.content.addSubview(iconView)
        surfaces.content.addSubview(elapsedLabel)
        surfaces.content.addSubview(transcriptLabel)
        surfaces.content.addSubview(targetApplicationIconView)
        surfaces.content.addSubview(contextLabel)
        surfaces.content.addSubview(hintLabel)

        let contextLeadingConstraint: NSLayoutConstraint
        if targetApplicationIcon == nil {
            contextLeadingConstraint = contextLabel.leadingAnchor.constraint(
                equalTo: surfaces.content.leadingAnchor,
                constant: 20
            )
        } else {
            contextLeadingConstraint = contextLabel.leadingAnchor.constraint(
                equalTo: targetApplicationIconView.trailingAnchor,
                constant: 6
            )
        }

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: surfaces.content.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: surfaces.content.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: surfaces.content.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: surfaces.content.bottomAnchor),
            accentGlowView.leadingAnchor.constraint(equalTo: surfaces.content.leadingAnchor),
            accentGlowView.trailingAnchor.constraint(equalTo: surfaces.content.trailingAnchor),
            accentGlowView.topAnchor.constraint(equalTo: surfaces.content.topAnchor),
            accentGlowView.bottomAnchor.constraint(equalTo: surfaces.content.bottomAnchor),
            stateLabel.leadingAnchor.constraint(
                equalTo: surfaces.content.leadingAnchor,
                constant: 20
            ),
            stateLabel.topAnchor.constraint(
                equalTo: surfaces.content.topAnchor,
                constant: 16
            ),
            inputSpectrumView.leadingAnchor.constraint(
                equalTo: stateLabel.trailingAnchor,
                constant: 10
            ),
            inputSpectrumView.centerYAnchor.constraint(
                equalTo: stateLabel.centerYAnchor
            ),
            inputSpectrumView.widthAnchor.constraint(equalToConstant: 28),
            inputSpectrumView.heightAnchor.constraint(equalToConstant: 18),
            iconView.centerYAnchor.constraint(
                equalTo: inputSpectrumView.centerYAnchor
            ),
            iconView.centerXAnchor.constraint(
                equalTo: inputSpectrumView.centerXAnchor
            ),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            elapsedLabel.trailingAnchor.constraint(
                equalTo: surfaces.content.trailingAnchor,
                constant: -20
            ),
            elapsedLabel.firstBaselineAnchor.constraint(
                equalTo: stateLabel.firstBaselineAnchor
            ),
            inputSpectrumView.trailingAnchor.constraint(
                lessThanOrEqualTo: elapsedLabel.leadingAnchor,
                constant: -16
            ),
            transcriptLabel.leadingAnchor.constraint(
                equalTo: surfaces.content.leadingAnchor,
                constant: 20
            ),
            transcriptLabel.trailingAnchor.constraint(
                equalTo: surfaces.content.trailingAnchor,
                constant: -20
            ),
            transcriptLabel.topAnchor.constraint(
                equalTo: stateLabel.bottomAnchor,
                constant: 13
            ),
            transcriptLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contextLabel.topAnchor,
                constant: -13
            ),
            targetApplicationIconView.leadingAnchor.constraint(
                equalTo: surfaces.content.leadingAnchor,
                constant: 20
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
            contextLabel.bottomAnchor.constraint(
                equalTo: surfaces.content.bottomAnchor,
                constant: -16
            ),
            hintLabel.trailingAnchor.constraint(
                equalTo: surfaces.content.trailingAnchor,
                constant: -20
            ),
            hintLabel.firstBaselineAnchor.constraint(
                equalTo: contextLabel.firstBaselineAnchor
            ),
            contextLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: hintLabel.leadingAnchor,
                constant: -16
            ),
        ])
        renderMetadata()
    }

    func showListening() {
        latestSnapshot = nil
        contextOverride = nil
        inputSpectrumView.isHidden = false
        iconView.isHidden = true
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.listening
        setMode(
            title: "Listening",
            hint: "Esc Cancel  ·  ⌥Space Finish",
            color: ParloqVisuals.listening
        )
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        renderMetadata()
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
        iconView.isHidden = true
        metadata.updateElapsed(elapsedSeconds)
        telemetry.updateTranscript(
            snapshot.text,
            elapsedSeconds: elapsedSeconds
        )
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.listening
        setMode(
            title: "Listening",
            hint: "Esc Cancel  ·  ⌥Space Finish",
            color: ParloqVisuals.listening
        )
        renderMetadata()
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
    }

    func updateDeliveryMode(_ mode: DictationDeliveryMode) {
        metadata.updateDeliveryMode(mode)
        renderMetadata()
    }

    func updateDetails(_ details: DictationDetails) {
        telemetry.updateDetails(details)
    }

    func updateInput(
        spectrum: InputSpectrum,
        level: InputLevelMeter
    ) {
        telemetry.updateInputPeak(level.dbFS)
        inputSpectrumView.update(spectrum, fallback: level)
    }

    func showFinishing() {
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        iconView.isHidden = false
        iconView.contentTintColor = ParloqVisuals.cyan
        iconView.image = StatusIcon.finishing
        setMode(
            title: "Finalizing",
            hint: "Esc Cancel",
            color: ParloqVisuals.cyan
        )
        if let latestSnapshot {
            render(snapshot: latestSnapshot, showCursor: false)
        } else {
            renderPlaceholder("Preparing final text")
        }
    }

    func showCompleted(
        snapshot: LiveTranscriptSnapshot,
        details: DictationDetails,
        clipboardPublished: Bool
    ) {
        latestSnapshot = snapshot
        telemetry.updateTranscript(
            snapshot.text,
            elapsedSeconds: details.lastAudioSeconds
        )
        telemetry.updateDetails(details, showLatestProsodyResult: true)
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        iconView.isHidden = false
        let completionColor = clipboardPublished
            ? ParloqVisuals.listening
            : ParloqVisuals.caution
        iconView.contentTintColor = completionColor
        iconView.image = StatusIcon.ready
        setMode(
            title: clipboardPublished
                ? "Complete · Copied"
                : "Complete · Copy failed",
            hint: "⌥Space Dictate again",
            color: completionColor
        )
        renderMetadata()
        render(snapshot: snapshot, showCursor: false)
        presentIfNeeded()
    }

    func showRecovery(
        snapshot: LiveTranscriptSnapshot,
        message: String
    ) {
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        iconView.isHidden = false
        contextOverride = "Copied"
        latestSnapshot = snapshot
        iconView.contentTintColor = ParloqVisuals.coral
        iconView.image = StatusIcon.error
        setMode(
            title: "Recovered",
            hint: "Esc Dismiss",
            color: ParloqVisuals.coral,
            toolTip: message
        )
        renderMetadata()
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

    var nativeFixtureWindowNumber: Int {
        panel.windowNumber
    }

    var nativeFixtureWindowFrame: NSRect {
        panel.frame
    }

    var nativeFixtureScreenFrame: NSRect? {
        panel.screen?.frame
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
                        ofSize: 16,
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
                        ofSize: 16,
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
                        ofSize: 16,
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
                ? ParloqVisuals.coral.withAlphaComponent(0.90)
                : metadata.deliveryMode == .targetChanged
                ? ParloqVisuals.caution.withAlphaComponent(0.92)
                : ParloqVisuals.secondaryText.withAlphaComponent(0.88)
        )
        contextLabel.attributedStringValue = NSAttributedString(
            string: context,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: contextColor,
            ]
        )
        contextLabel.setAccessibilityLabel("Dictation destination")
        contextLabel.setAccessibilityValue(context)

        elapsedLabel.attributedStringValue = NSAttributedString(
            string: metadata.elapsedLabel,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 11.5,
                    weight: .medium
                ),
                .foregroundColor:
                    ParloqVisuals.secondaryText.withAlphaComponent(0.78),
            ]
        )
        elapsedLabel.setAccessibilityLabel("Elapsed dictation time")
        elapsedLabel.setAccessibilityValue(metadata.elapsedLabel)
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
        stateLabel.attributedStringValue = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: color,
            ]
        )
        stateLabel.toolTip = toolTip
        stateLabel.setAccessibilityValue(toolTip ?? title)
        hintLabel.attributedStringValue = NSAttributedString(
            string: hint,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor:
                    ParloqVisuals.secondaryText.withAlphaComponent(0.76),
            ]
        )
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
