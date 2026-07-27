import AppKit
import ParloqMenuCore
import QuartzCore

enum ParloqVisuals {
    static let navy = NSColor(
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
    static let text = NSColor(
        srgbRed: 0.92,
        green: 0.94,
        blue: 0.98,
        alpha: 1
    )
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

private enum PanelMetrics {
    static let width: CGFloat = 574
    static let minimumHeight: CGFloat = 104
    static let maximumHeight: CGFloat = 174
    static let horizontalInset: CGFloat = 18
    static let verticalChrome: CGFloat = 78
}

@MainActor
final class LiveTranscriptPanel {
    private let panel: NSPanel
    private let accentRail: NSView
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
    private var contextOverride: String?
    private var latestSnapshot: LiveTranscriptSnapshot?

    init(
        metadata: DictationHUDMetadata,
        targetApplicationIcon: NSImage? = nil,
        presentsWindow: Bool = true
    ) {
        self.metadata = metadata
        self.presentsWindow = presentsWindow
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
        panel.hasShadow = true
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

        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = NSColor.white
            .withAlphaComponent(0.16)
            .cgColor
        panel.contentView = material

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = ParloqVisuals.navy
            .withAlphaComponent(
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                    ? 0.98
                    : 0.84
            )
            .cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false

        accentRail = NSView()
        accentRail.wantsLayer = true
        accentRail.layer?.backgroundColor = ParloqVisuals.listening.cgColor
        accentRail.translatesAutoresizingMaskIntoConstraints = false

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

        material.addSubview(tint)
        material.addSubview(accentRail)
        material.addSubview(iconView)
        material.addSubview(stateLabel)
        material.addSubview(hintLabel)
        material.addSubview(transcriptLabel)
        material.addSubview(targetApplicationIconView)
        material.addSubview(contextLabel)
        material.addSubview(inputSpectrumView)
        material.addSubview(elapsedLabel)

        let contextLeadingConstraint: NSLayoutConstraint
        if targetApplicationIcon == nil {
            contextLeadingConstraint = contextLabel.leadingAnchor.constraint(
                equalTo: material.leadingAnchor,
                constant: PanelMetrics.horizontalInset
            )
        } else {
            contextLeadingConstraint = contextLabel.leadingAnchor.constraint(
                equalTo: targetApplicationIconView.trailingAnchor,
                constant: 6
            )
        }
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            tint.topAnchor.constraint(equalTo: material.topAnchor),
            tint.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            accentRail.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            accentRail.topAnchor.constraint(equalTo: material.topAnchor),
            accentRail.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            accentRail.widthAnchor.constraint(equalToConstant: 3),
            iconView.leadingAnchor.constraint(
                equalTo: material.leadingAnchor,
                constant: PanelMetrics.horizontalInset
            ),
            iconView.centerYAnchor.constraint(
                equalTo: stateLabel.centerYAnchor
            ),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            stateLabel.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor,
                constant: 10
            ),
            stateLabel.topAnchor.constraint(
                equalTo: material.topAnchor,
                constant: 15
            ),
            hintLabel.trailingAnchor.constraint(
                equalTo: material.trailingAnchor,
                constant: -PanelMetrics.horizontalInset
            ),
            hintLabel.firstBaselineAnchor.constraint(
                equalTo: stateLabel.firstBaselineAnchor
            ),
            stateLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: hintLabel.leadingAnchor,
                constant: -12
            ),
            transcriptLabel.leadingAnchor.constraint(
                equalTo: material.leadingAnchor,
                constant: PanelMetrics.horizontalInset
            ),
            transcriptLabel.trailingAnchor.constraint(
                equalTo: material.trailingAnchor,
                constant: -PanelMetrics.horizontalInset
            ),
            transcriptLabel.topAnchor.constraint(
                equalTo: stateLabel.bottomAnchor,
                constant: 12
            ),
            transcriptLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contextLabel.topAnchor,
                constant: -8
            ),
            targetApplicationIconView.leadingAnchor.constraint(
                equalTo: material.leadingAnchor,
                constant: PanelMetrics.horizontalInset
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
                equalTo: material.bottomAnchor,
                constant: -12
            ),
            inputSpectrumView.widthAnchor.constraint(equalToConstant: 40),
            inputSpectrumView.heightAnchor.constraint(equalToConstant: 12),
            inputSpectrumView.centerXAnchor.constraint(
                equalTo: material.centerXAnchor
            ),
            inputSpectrumView.centerYAnchor.constraint(
                equalTo: contextLabel.centerYAnchor
            ),
            elapsedLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: inputSpectrumView.trailingAnchor,
                constant: 16
            ),
            elapsedLabel.trailingAnchor.constraint(
                equalTo: material.trailingAnchor,
                constant: -PanelMetrics.horizontalInset
            ),
            elapsedLabel.firstBaselineAnchor.constraint(
                equalTo: contextLabel.firstBaselineAnchor
            ),
        ])
        renderMetadata()
    }

    func showListening() {
        latestSnapshot = nil
        contextOverride = nil
        inputSpectrumView.isHidden = false
        accentRail.layer?.backgroundColor = ParloqVisuals.listening.cgColor
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.listening
        setMode(
            title: "LISTENING",
            hint: "ESC CANCEL · ⌥SPACE FINISH",
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
        metadata.updateElapsed(elapsedSeconds)
        accentRail.layer?.backgroundColor = ParloqVisuals.listening.cgColor
        iconView.contentTintColor = ParloqVisuals.listening
        iconView.image = StatusIcon.listening
        setMode(
            title: "LISTENING",
            hint: "ESC CANCEL · ⌥SPACE FINISH",
            color: ParloqVisuals.listening
        )
        renderMetadata()
        render(snapshot: snapshot, showCursor: true)
        presentIfNeeded()
    }

    func updateElapsed(_ elapsedSeconds: Double?) {
        metadata.updateElapsed(elapsedSeconds)
        renderMetadata()
    }

    func updateDeliveryMode(_ mode: DictationDeliveryMode) {
        metadata.updateDeliveryMode(mode)
        renderMetadata()
    }

    func updateInput(
        spectrum: InputSpectrum,
        level: InputLevelMeter
    ) {
        inputSpectrumView.update(spectrum, fallback: level)
        iconView.image = StatusIcon.listening(
            level: level,
            spectrum: spectrum
        )
    }

    func showFinishing() {
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        accentRail.layer?.backgroundColor = ParloqVisuals.cyan.cgColor
        iconView.contentTintColor = ParloqVisuals.cyan
        iconView.image = StatusIcon.finishing
        setMode(
            title: "FINALIZING",
            hint: "ESC CANCEL",
            color: ParloqVisuals.cyan
        )
        if let latestSnapshot {
            render(snapshot: latestSnapshot, showCursor: false)
        } else {
            renderPlaceholder("Preparing final text")
        }
    }

    func showRecovery(
        snapshot: LiveTranscriptSnapshot,
        message: String
    ) {
        inputSpectrumView.update(InputSpectrum(dbFS: nil), fallback: nil)
        inputSpectrumView.isHidden = true
        contextOverride = "COPIED TO CLIPBOARD"
        latestSnapshot = snapshot
        accentRail.layer?.backgroundColor = ParloqVisuals.coral.cgColor
        iconView.contentTintColor = ParloqVisuals.coral
        iconView.image = StatusIcon.error
        setMode(
            title: "RECOVERED",
            hint: "TRANSCRIPT COPIED · ESC DISMISS",
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
                        ofSize: 14.5,
                        weight: .regular
                    ),
                    .foregroundColor:
                        ParloqVisuals.text.withAlphaComponent(0.50),
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
                        ofSize: 15.5,
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
                        ofSize: 16.5,
                        weight: .semibold
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
                .font: NSFont.systemFont(ofSize: 15.5, weight: .regular),
                .foregroundColor:
                    ParloqVisuals.text.withAlphaComponent(0.52),
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
                ? ParloqVisuals.coral.withAlphaComponent(0.82)
                : ParloqVisuals.text.withAlphaComponent(0.38)
        )
        contextLabel.attributedStringValue = NSAttributedString(
            string: context,
            attributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: 8.5,
                    weight: .medium
                ),
                .foregroundColor: contextColor,
                .kern: 0.55,
            ]
        )
        contextLabel.setAccessibilityLabel("Dictation destination")
        contextLabel.setAccessibilityValue(context)

        elapsedLabel.attributedStringValue = NSAttributedString(
            string: metadata.elapsedLabel,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 9,
                    weight: .medium
                ),
                .foregroundColor:
                    ParloqVisuals.text.withAlphaComponent(0.48),
                .kern: 0.35,
            ]
        )
        elapsedLabel.setAccessibilityLabel("Elapsed dictation time")
        elapsedLabel.setAccessibilityValue(metadata.elapsedLabel)
    }

    private func growToFitTranscript() {
        let textWidth = PanelMetrics.width
            - 2 * PanelMetrics.horizontalInset
        let bounds = transcriptLabel.attributedStringValue.boundingRect(
            with: NSSize(
                width: textWidth,
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
                .font: NSFont.monospacedSystemFont(
                    ofSize: 10.5,
                    weight: .semibold
                ),
                .foregroundColor: color,
                .kern: 1.0,
            ]
        )
        stateLabel.toolTip = toolTip
        stateLabel.setAccessibilityValue(toolTip ?? title)
        hintLabel.attributedStringValue = NSAttributedString(
            string: hint,
            attributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: 9.5,
                    weight: .medium
                ),
                .foregroundColor: ParloqVisuals.text.withAlphaComponent(0.42),
                .kern: 0.7,
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
