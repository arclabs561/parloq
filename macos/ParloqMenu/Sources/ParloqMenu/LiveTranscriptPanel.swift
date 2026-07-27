import AppKit
import ParloqMenuCore

private enum ParloqVisuals {
    static let navy = NSColor(
        srgbRed: 0.035,
        green: 0.055,
        blue: 0.14,
        alpha: 1
    )
    static let mint = NSColor(
        srgbRed: 0.39,
        green: 0.94,
        blue: 0.76,
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

private enum PanelMetrics {
    static let width: CGFloat = 574
    static let minimumHeight: CGFloat = 86
    static let maximumHeight: CGFloat = 150
    static let horizontalInset: CGFloat = 18
    static let verticalChrome: CGFloat = 55
}

@MainActor
final class LiveTranscriptPanel {
    private let panel: NSPanel
    private let accentRail: NSView
    private let iconView: NSImageView
    private let stateLabel: NSTextField
    private let hintLabel: NSTextField
    private let transcriptLabel: NSTextField
    private var latestSnapshot: LiveTranscriptSnapshot?

    init() {
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
        accentRail.layer?.backgroundColor = ParloqVisuals.mint.cgColor
        accentRail.translatesAutoresizingMaskIntoConstraints = false

        iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = ParloqVisuals.cyan
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

        material.addSubview(tint)
        material.addSubview(accentRail)
        material.addSubview(iconView)
        material.addSubview(stateLabel)
        material.addSubview(hintLabel)
        material.addSubview(transcriptLabel)
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
                lessThanOrEqualTo: material.bottomAnchor,
                constant: -13
            ),
        ])
    }

    func showListening() {
        latestSnapshot = nil
        accentRail.layer?.backgroundColor = ParloqVisuals.mint.cgColor
        iconView.image = StatusIcon.listening
        setMode(
            title: "LISTENING",
            hint: "ESC CANCEL · ⌥SPACE FINISH",
            color: ParloqVisuals.mint
        )
        renderPlaceholder("Start speaking")
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func update(snapshot: LiveTranscriptSnapshot) {
        guard !snapshot.text.isEmpty else { return }
        latestSnapshot = snapshot
        accentRail.layer?.backgroundColor = ParloqVisuals.mint.cgColor
        iconView.image = StatusIcon.listening
        setMode(
            title: "LISTENING",
            hint: "ESC CANCEL · ⌥SPACE FINISH",
            color: ParloqVisuals.mint
        )
        render(snapshot: snapshot, showCursor: true)
        if !panel.isVisible {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
    }

    func showFinishing() {
        accentRail.layer?.backgroundColor = ParloqVisuals.cyan.cgColor
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
        latestSnapshot = snapshot
        accentRail.layer?.backgroundColor = ParloqVisuals.coral.cgColor
        iconView.image = StatusIcon.error
        setMode(
            title: "RECOVERED",
            hint: "TRANSCRIPT COPIED · ESC DISMISS",
            color: ParloqVisuals.coral,
            toolTip: message
        )
        render(snapshot: snapshot, showCursor: false)
        if !panel.isVisible {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        latestSnapshot = nil
        panel.orderOut(nil)
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

    private func positionOnActiveScreen() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(pointer, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 88
        )
        panel.setFrameOrigin(origin)
    }
}
