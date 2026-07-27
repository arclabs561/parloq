import AppKit
import ParloqMenuCore

@MainActor
enum UIFixtureRenderer {
    static func render(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var rendered: [URL] = []
        rendered.append(try renderListeningShort(to: directory))
        rendered.append(try renderListeningLong(to: directory))
        rendered.append(try renderTargetChanged(to: directory))
        rendered.append(try renderFinalizing(to: directory))
        rendered.append(try renderRecovery(to: directory))
        rendered.append(try renderStatusIcons(to: directory))
        return rendered
    }

    private static func renderListeningShort(
        to directory: URL
    ) throws -> URL {
        let panel = makePanel()
        panel.showListening()
        panel.update(
            snapshot: LiveTranscriptSnapshot(
                text: "Test. Test.",
                settledText: "",
                activeText: "Test. Test."
            ),
            elapsedSeconds: 2
        )
        panel.updateInput(
            spectrum: InputSpectrum(dbFS: [
                -56, -42, -27, -19, -23, -35, -48, -61, -70,
            ]),
            level: InputLevelMeter(dbFS: -17)
        )
        return try write(
            panel,
            name: "hud-listening-short.png",
            to: directory
        )
    }

    private static func renderListeningLong(
        to directory: URL
    ) throws -> URL {
        let panel = makePanel(elapsedSeconds: 38)
        panel.showListening()
        panel.update(
            snapshot: LiveTranscriptSnapshot(
                text: """
                I want the previous text to remain visible as a quiet paragraph \
                while the newest phrase updates below it. The live tail should \
                be obvious without turning the popup into a document editor.
                """,
                settledText: """
                I want the previous text to remain visible as a quiet paragraph \
                while the newest phrase updates below it.
                """,
                activeText: """
                The live tail should be obvious without turning the popup into \
                a document editor.
                """
            ),
            elapsedSeconds: 38
        )
        panel.updateInput(
            spectrum: InputSpectrum(dbFS: [
                -61, -48, -31, -17, -21, -32, -43, -55, -68,
            ]),
            level: InputLevelMeter(dbFS: -15)
        )
        return try write(
            panel,
            name: "hud-listening-long.png",
            to: directory
        )
    }

    private static func renderTargetChanged(
        to directory: URL
    ) throws -> URL {
        let panel = makePanel(elapsedSeconds: 11)
        panel.showListening()
        panel.update(
            snapshot: LiveTranscriptSnapshot(
                text: "Keep recording safely even if the active field changes.",
                settledText: "",
                activeText:
                    "Keep recording safely even if the active field changes."
            ),
            elapsedSeconds: 11
        )
        panel.updateDeliveryMode(.targetChanged)
        panel.updateInput(
            spectrum: InputSpectrum(dbFS: [
                -68, -53, -38, -25, -22, -29, -46, -58, -73,
            ]),
            level: InputLevelMeter(dbFS: -20)
        )
        return try write(
            panel,
            name: "hud-target-changed.png",
            to: directory
        )
    }

    private static func renderFinalizing(
        to directory: URL
    ) throws -> URL {
        let panel = makePanel(elapsedSeconds: 24)
        panel.showListening()
        panel.update(
            snapshot: LiveTranscriptSnapshot(
                text: "The final accuracy pass can correct the live draft.",
                settledText:
                    "The final accuracy pass can correct the live draft.",
                activeText: ""
            ),
            elapsedSeconds: 24
        )
        panel.showFinishing()
        return try write(
            panel,
            name: "hud-finalizing.png",
            to: directory
        )
    }

    private static func renderRecovery(
        to directory: URL
    ) throws -> URL {
        let panel = makePanel(elapsedSeconds: 19)
        panel.showRecovery(
            snapshot: LiveTranscriptSnapshot(
                text:
                    "The transcript was preserved and copied for manual recovery.",
                settledText: "",
                activeText:
                    "The transcript was preserved and copied for manual recovery."
            ),
            message: "Focused text field was no longer available"
        )
        return try write(
            panel,
            name: "hud-recovered.png",
            to: directory
        )
    }

    private static func renderStatusIcons(
        to directory: URL
    ) throws -> URL {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 92))
        view.wantsLayer = true
        view.layer?.backgroundColor = ParloqVisuals.navy.cgColor
        view.layer?.cornerRadius = 12

        let items: [(String, NSImage, NSColor)] = [
            ("READY", StatusIcon.ready, ParloqVisuals.text),
            (
                "LISTENING",
                StatusIcon.listening(
                    level: InputLevelMeter(dbFS: -16),
                    spectrum: InputSpectrum(dbFS: [
                        -62, -45, -25, -14, -22, -31, -49, -60, -72,
                    ])
                ),
                ParloqVisuals.listening
            ),
            ("FINALIZING", StatusIcon.finishing, ParloqVisuals.cyan),
            ("OFFLINE", StatusIcon.offline, ParloqVisuals.text),
            ("ERROR", StatusIcon.error, ParloqVisuals.coral),
        ]

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        for (title, image, color) in items {
            let cell = NSStackView()
            cell.orientation = .vertical
            cell.alignment = .centerX
            cell.spacing = 10

            let imageView = NSImageView()
            imageView.image = image
            imageView.contentTintColor = color
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 26),
                imageView.heightAnchor.constraint(equalToConstant: 24),
            ])

            let label = NSTextField(labelWithString: title)
            label.font = NSFont.monospacedSystemFont(
                ofSize: 8,
                weight: .medium
            )
            label.textColor = color.withAlphaComponent(0.78)
            cell.addArrangedSubview(imageView)
            cell.addArrangedSubview(label)
            stack.addArrangedSubview(cell)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -16
            ),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        view.layoutSubtreeIfNeeded()

        let url = directory.appendingPathComponent("status-icons.png")
        try write(view, to: url)
        return url
    }

    private static func makePanel(
        elapsedSeconds: Double = 0
    ) -> LiveTranscriptPanel {
        LiveTranscriptPanel(
            metadata: DictationHUDMetadata(
                targetApplication: "Ghostty",
                deliveryMode: .keyboardFallback,
                elapsedSeconds: elapsedSeconds
            ),
            presentsWindow: false
        )
    }

    private static func write(
        _ panel: LiveTranscriptPanel,
        name: String,
        to directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try panel.writeFixturePNG(to: url)
        return url
    }

    private static func write(_ view: NSView, to url: URL) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(
            in: view.bounds
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}
