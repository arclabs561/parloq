import AppKit
import ParloqMenuCore

@MainActor
final class DictationCorrectionPrompt: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let heardField = NSTextField()
    private let replacementField = NSTextField()

    init(entry: TranscriptHistoryEntry) {
        super.init()

        alert.messageText = "Teach Parloq"
        alert.informativeText =
            "Add one exact phrase correction for future dictation."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save Correction")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.isEnabled = false
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        heardField.placeholderString = "exact words Parloq heard"
        heardField.delegate = self
        heardField.setAccessibilityLabel("Heard")
        heardField.lineBreakMode = .byTruncatingTail

        replacementField.placeholderString = "words Parloq should use"
        replacementField.delegate = self
        replacementField.setAccessibilityLabel("Use instead")
        replacementField.lineBreakMode = .byTruncatingTail

        heardField.nextKeyView = replacementField
        replacementField.nextKeyView = heardField
        alert.accessoryView = makeAccessoryView(entry: entry)
    }

    func run() -> DictationVocabularyCorrection? {
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = heardField
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return correction
    }

    func fixtureView(
        heard: String,
        replacement: String
    ) -> NSView {
        heardField.stringValue = heard
        replacementField.stringValue = replacement
        alert.buttons.first?.isEnabled = correction != nil
        alert.layout()
        let view = alert.window.contentView ?? NSView()
        view.layoutSubtreeIfNeeded()
        view.removeFromSuperview()

        let container = NSView(frame: view.bounds)
        container.appearance = NSApplication.shared.appearance
        container.wantsLayer = true
        var background = NSColor.windowBackgroundColor.cgColor
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.cgColor
        }
        container.layer?.backgroundColor = background
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        container.layoutSubtreeIfNeeded()
        return container
    }

    func controlTextDidChange(_ notification: Notification) {
        alert.buttons.first?.isEnabled = correction != nil
    }

    private var correction: DictationVocabularyCorrection? {
        DictationVocabularyCorrection(
            heard: heardField.stringValue,
            replacement: replacementField.stringValue
        )
    }

    private func makeAccessoryView(
        entry: TranscriptHistoryEntry
    ) -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(
            top: 4,
            left: 0,
            bottom: 4,
            right: 0
        )

        let rawText = entry.rawText ?? entry.text
        content.addArrangedSubview(contextView(
            title: entry.distinctRawText == nil
                ? "LAST DICTATION"
                : "ORIGINAL ASR",
            text: rawText
        ))
        if entry.distinctRawText != nil {
            content.addArrangedSubview(contextView(
                title: "DELIVERED",
                text: entry.text
            ))
        }

        let fields = NSGridView(views: [
            [fieldLabel("Heard"), heardField],
            [fieldLabel("Use instead"), replacementField],
        ])
        fields.rowSpacing = 8
        fields.columnSpacing = 10
        fields.column(at: 0).xPlacement = .trailing
        fields.column(at: 1).width = 350
        content.addArrangedSubview(fields)

        let note = NSTextField(
            wrappingLabelWithString:
                "Only this exact phrase is learned. Parloq does not monitor edits in other apps."
        )
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
        content.addArrangedSubview(note)

        content.setFrameSize(NSSize(
            width: 450,
            height: content.fittingSize.height
        ))
        return content
    }

    private func contextView(title: String, text: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .semibold
        )
        titleLabel.textColor = .secondaryLabelColor

        let textLabel = NSTextField(wrappingLabelWithString: text)
        textLabel.isSelectable = true
        textLabel.maximumNumberOfLines = 3
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.toolTip = text

        let stack = NSStackView(views: [titleLabel, textLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.widthAnchor.constraint(equalToConstant: 450).isActive = true
        return stack
    }

    private func fieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        return label
    }
}
