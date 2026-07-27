import AppKit

@MainActor
final class LiveTranscriptPanel {
    private let panel: NSPanel
    private let iconView: NSImageView
    private let transcriptLabel: NSTextField
    private var latestText = ""

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 72),
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
        material.layer?.cornerRadius = 13
        material.layer?.cornerCurve = .continuous
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(0.45)
            .cgColor
        panel.contentView = material

        iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        transcriptLabel = NSTextField(wrappingLabelWithString: "")
        transcriptLabel.maximumNumberOfLines = 2
        transcriptLabel.lineBreakMode = .byTruncatingHead
        transcriptLabel.isSelectable = false
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false
        transcriptLabel.setAccessibilityLabel("Live transcription")

        material.addSubview(iconView)
        material.addSubview(transcriptLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(
                equalTo: material.leadingAnchor,
                constant: 16
            ),
            iconView.centerYAnchor.constraint(
                equalTo: material.centerYAnchor
            ),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            transcriptLabel.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor,
                constant: 12
            ),
            transcriptLabel.trailingAnchor.constraint(
                equalTo: material.trailingAnchor,
                constant: -18
            ),
            transcriptLabel.topAnchor.constraint(
                greaterThanOrEqualTo: material.topAnchor,
                constant: 10
            ),
            transcriptLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: material.bottomAnchor,
                constant: -10
            ),
            transcriptLabel.centerYAnchor.constraint(
                equalTo: material.centerYAnchor
            ),
        ])
    }

    func showListening() {
        latestText = ""
        iconView.image = StatusIcon.listening
        render(text: "Listening…", placeholder: true)
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func update(text: String) {
        guard !text.isEmpty else { return }
        latestText = text
        iconView.image = StatusIcon.listening
        render(text: text, placeholder: false)
        if !panel.isVisible {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
    }

    func showFinishing() {
        iconView.image = StatusIcon.finishing
        if latestText.isEmpty {
            render(text: "Finishing…", placeholder: true)
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
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: placeholder
                    ? NSColor.secondaryLabelColor
                    : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        if !placeholder {
            value.append(NSAttributedString(
                string: "  │",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: NSColor.controlAccentColor,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        transcriptLabel.attributedStringValue = value
        transcriptLabel.setAccessibilityValue(text)
    }

    private func positionOnActiveScreen() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(pointer, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 30
        )
        panel.setFrameOrigin(origin)
    }
}
