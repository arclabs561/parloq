import AppKit

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
    static let text = NSColor(
        srgbRed: 0.92,
        green: 0.94,
        blue: 0.98,
        alpha: 1
    )
}

@MainActor
final class LiveTranscriptPanel {
    private let panel: NSPanel
    private let iconView: NSImageView
    private let stateLabel: NSTextField
    private let hintLabel: NSTextField
    private let transcriptLabel: NSTextField
    private var latestText = ""

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 574, height: 92),
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

        let accentRail = NSView()
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
        transcriptLabel.maximumNumberOfLines = 2
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
                constant: 18
            ),
            iconView.centerYAnchor.constraint(
                equalTo: material.centerYAnchor
            ),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            stateLabel.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor,
                constant: 14
            ),
            stateLabel.topAnchor.constraint(
                equalTo: material.topAnchor,
                constant: 14
            ),
            hintLabel.trailingAnchor.constraint(
                equalTo: material.trailingAnchor,
                constant: -18
            ),
            hintLabel.firstBaselineAnchor.constraint(
                equalTo: stateLabel.firstBaselineAnchor
            ),
            stateLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: hintLabel.leadingAnchor,
                constant: -12
            ),
            transcriptLabel.leadingAnchor.constraint(
                equalTo: stateLabel.leadingAnchor
            ),
            transcriptLabel.trailingAnchor.constraint(
                equalTo: material.trailingAnchor,
                constant: -18
            ),
            transcriptLabel.topAnchor.constraint(
                equalTo: stateLabel.bottomAnchor,
                constant: 6
            ),
            transcriptLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: material.bottomAnchor,
                constant: -13
            ),
        ])
    }

    func showListening() {
        latestText = ""
        iconView.image = StatusIcon.listening
        setMode(title: "LISTENING", hint: "⌥SPACE TO FINISH")
        render(text: "Start speaking", placeholder: true)
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func update(text: String) {
        guard !text.isEmpty else { return }
        latestText = text
        iconView.image = StatusIcon.listening
        setMode(title: "LISTENING", hint: "⌥SPACE TO FINISH")
        render(text: text, placeholder: false)
        if !panel.isVisible {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
    }

    func showFinishing() {
        iconView.image = StatusIcon.finishing
        setMode(title: "FINALIZING", hint: "WORKING")
        if latestText.isEmpty {
            render(text: "Preparing final text", placeholder: true)
        }
    }

    func hide() {
        latestText = ""
        panel.orderOut(nil)
    }

    private func render(text: String, placeholder: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        paragraph.lineSpacing = 1

        let value = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15.5, weight: .regular),
                .foregroundColor: placeholder
                    ? ParloqVisuals.text.withAlphaComponent(0.52)
                    : ParloqVisuals.text,
                .paragraphStyle: paragraph,
            ]
        )
        if !placeholder {
            value.append(NSAttributedString(
                string: "  │",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16.5, weight: .semibold),
                    .foregroundColor: ParloqVisuals.cyan,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        transcriptLabel.attributedStringValue = value
        transcriptLabel.setAccessibilityValue(text)
    }

    private func setMode(title: String, hint: String) {
        stateLabel.attributedStringValue = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: 10.5,
                    weight: .semibold
                ),
                .foregroundColor: ParloqVisuals.mint,
                .kern: 1.0,
            ]
        )
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
