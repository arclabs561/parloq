import AppKit
import CoreGraphics
import ParloqMenuCore
import QuartzCore

@MainActor
enum UIFixtureRenderer {
    static func captureNative(to url: URL) throws {
        guard #available(macOS 26.0, *) else {
            throw fixtureError("native glass capture requires macOS 26")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw fixtureError(
                "screen capture access is unavailable; no permission was requested"
            )
        }

        let frontmostBefore =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        let panel = makePanel(elapsedSeconds: 12, presentsWindow: true)
        panel.showListening()
        panel.update(
            snapshot: LiveTranscriptSnapshot(
                text:
                    "Native glass should bend the desktop through this live transcript.",
                settledText: "",
                activeText:
                    "Native glass should bend the desktop through this live transcript."
            ),
            elapsedSeconds: 12
        )
        panel.updateInput(
            spectrum: InputSpectrum(dbFS: [
                -62, -47, -29, -16, -22, -34, -45, -58, -70,
            ]),
            level: InputLevelMeter(dbFS: -16)
        )
        defer { panel.hide() }

        let windowNumber = panel.nativeFixtureWindowNumber
        guard windowNumber > 0 else {
            throw fixtureError("native fixture did not receive a window number")
        }
        let captureFrame = panel.nativeFixtureWindowFrame.insetBy(
            dx: -24,
            dy: -24
        )
        guard let screenFrame = panel.nativeFixtureScreenFrame else {
            throw fixtureError("native fixture is not assigned to a screen")
        }
        let backdrop = makeNativeBackdrop(frame: captureFrame)
        backdrop.order(.below, relativeTo: windowNumber)
        defer { backdrop.orderOut(nil) }

        // Give WindowServer two display turns to resolve glass, merge the
        // nearby islands, and sample the controlled backdrop behind the panel.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.18))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.18))

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-x",
            "-t",
            "png",
            "-R\(Int(floor(captureFrame.minX))),"
                + "\(Int(floor(screenFrame.maxY - captureFrame.maxY))),"
                + "\(Int(ceil(captureFrame.width))),"
                + "\(Int(ceil(captureFrame.height)))",
            url.path,
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw fixtureError(
                "native fixture capture failed"
                    + (message.map { ": \($0)" } ?? "")
            )
        }

        panel.hide()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let frontmostAfter =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontmostBefore == frontmostAfter else {
            throw fixtureError(
                "native fixture changed the frontmost application"
            )
        }

        let data = try Data(contentsOf: url)
        guard let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide >= 200,
              bitmap.pixelsHigh >= 100,
              data.count >= 1_000
        else {
            throw fixtureError("native fixture image is empty or implausibly small")
        }
    }

    private static func makeNativeBackdrop(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]

        let view = NSView(
            frame: NSRect(origin: .zero, size: frame.size)
        )
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.startPoint = CGPoint(x: 0.04, y: 0.90)
        gradient.endPoint = CGPoint(x: 0.96, y: 0.10)
        gradient.colors = [
            NSColor(
                srgbRed: 0.94,
                green: 0.95,
                blue: 0.97,
                alpha: 1
            ).cgColor,
            NSColor(
                srgbRed: 0.66,
                green: 0.70,
                blue: 0.78,
                alpha: 1
            ).cgColor,
            NSColor(
                srgbRed: 0.16,
                green: 0.20,
                blue: 0.27,
                alpha: 1
            ).cgColor,
        ]
        gradient.locations = [0, 0.52, 1]
        view.layer?.addSublayer(gradient)

        let grid = CAShapeLayer()
        let path = CGMutablePath()
        let spacing: CGFloat = 56
        var x: CGFloat = spacing
        while x < view.bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: view.bounds.height))
            x += spacing
        }
        var y: CGFloat = spacing
        while y < view.bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: view.bounds.width, y: y))
            y += spacing
        }
        grid.path = path
        grid.fillColor = nil
        grid.strokeColor = NSColor.black.withAlphaComponent(0.20).cgColor
        grid.lineWidth = 0.75
        view.layer?.addSublayer(grid)

        panel.contentView = view
        return panel
    }

    static func render(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let application = NSApplication.shared
        let previousAppearance = application.appearance
        defer { application.appearance = previousAppearance }

        application.appearance = NSAppearance(named: .darkAqua)
        let dark = try renderStates(to: directory)

        let lightDirectory = directory.appendingPathComponent(
            "light",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: lightDirectory,
            withIntermediateDirectories: true
        )
        application.appearance = NSAppearance(named: .aqua)
        let light = try renderStates(to: lightDirectory)

        application.appearance = NSAppearance(named: .darkAqua)
        let board = try renderReviewBoard(
            dark: dark,
            light: light,
            to: directory
        )
        let manifest = try writeManifest(
            dark: dark,
            light: light,
            board: board,
            to: directory
        )
        return dark + light + [board, manifest]
    }

    private static func renderStates(to directory: URL) throws -> [URL] {
        var rendered: [URL] = []
        rendered.append(try renderListeningShort(to: directory))
        rendered.append(try renderListeningLong(to: directory))
        rendered.append(try renderTargetChanged(to: directory))
        rendered.append(try renderFinalizing(to: directory))
        rendered.append(try renderCompleted(to: directory))
        rendered.append(try renderCopyFailed(to: directory))
        rendered.append(try renderRecovery(to: directory))
        rendered.append(try renderStatusIcons(to: directory))
        rendered.append(try renderCorrectionPrompt(to: directory))
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
        let panel = makePanel(
            elapsedSeconds: 38,
            details: fixtureDetails(saveEnabled: true)
        )
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

    private static func renderCompleted(
        to directory: URL
    ) throws -> URL {
        let details = fixtureDetails(
            latestProsodyState: .elevated,
            latestProsodyEnergyZ: 1.36,
            prosodyBaselineCount: 7,
            lastAudioSeconds: 24,
            lastASRSeconds: 2.4
        )
        let panel = makePanel(elapsedSeconds: 24, details: details)
        let snapshot = LiveTranscriptSnapshot(
            text: "The final pass corrected the live draft and preserved my wording.",
            settledText:
                "The final pass corrected the live draft and preserved my wording.",
            activeText: ""
        )
        panel.showListening()
        panel.update(snapshot: snapshot, elapsedSeconds: 24)
        panel.showCompleted(
            snapshot: snapshot,
            details: details,
            clipboardPublished: true
        )
        return try write(
            panel,
            name: "hud-completed.png",
            to: directory
        )
    }

    private static func renderCopyFailed(
        to directory: URL
    ) throws -> URL {
        let details = fixtureDetails(
            lastAudioSeconds: 9,
            lastASRSeconds: 1.1
        )
        let panel = makePanel(elapsedSeconds: 9, details: details)
        let snapshot = LiveTranscriptSnapshot(
            text:
                "The text was inserted, but clipboard history could not be updated.",
            settledText:
                "The text was inserted, but clipboard history could not be updated.",
            activeText: ""
        )
        panel.showListening()
        panel.update(snapshot: snapshot, elapsedSeconds: 9)
        panel.showCompleted(
            snapshot: snapshot,
            details: details,
            clipboardPublished: false
        )
        return try write(
            panel,
            name: "hud-copy-failed.png",
            to: directory
        )
    }

    private static func renderStatusIcons(
        to directory: URL
    ) throws -> URL {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 92))
        view.appearance = NSApplication.shared.appearance
        view.wantsLayer = true

        func resolved(_ color: NSColor) -> NSColor {
            var cgColor = color.cgColor
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                cgColor = color.cgColor
            }
            return NSColor(cgColor: cgColor) ?? color
        }

        view.layer?.backgroundColor = resolved(
            NSColor.windowBackgroundColor
        ).cgColor
        view.layer?.cornerRadius = 16

        let items: [(String, NSImage, NSColor)] = [
            ("Ready", StatusIcon.ready, ParloqVisuals.text),
            (
                "Listening",
                StatusIcon.listening(
                    level: InputLevelMeter(dbFS: -16),
                    spectrum: InputSpectrum(dbFS: [
                        -62, -45, -25, -14, -22, -31, -49, -60, -72,
                    ])
                ),
                ParloqVisuals.listening
            ),
            ("Finalizing", StatusIcon.finishing, ParloqVisuals.cyan),
            ("Offline", StatusIcon.offline, ParloqVisuals.text),
            ("Error", StatusIcon.error, ParloqVisuals.coral),
        ]

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        for (title, image, color) in items {
            let color = resolved(color)
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
            label.font = NSFont.systemFont(
                ofSize: 9,
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

    private static func renderCorrectionPrompt(
        to directory: URL
    ) throws -> URL {
        let prompt = DictationCorrectionPrompt(entry: TranscriptHistoryEntry(
            text: "Parloq should remember that name for the next dictation.",
            rawText: "Par lock should remember that name for the next dictation."
        ))
        let view = prompt.fixtureView(
            heard: "par lock",
            replacement: "Parloq"
        )
        let url = directory.appendingPathComponent(
            "teach-parloq-prompt.png"
        )
        try write(view, to: url)
        return url
    }

    private struct Artifact: Codable {
        let appearance: String
        let file: String
        let state: String
        let pixelWidth: Int
        let pixelHeight: Int
        let bytes: Int
    }

    private struct ReviewManifest: Codable {
        let artifacts: [Artifact]
        let reviewBoard: String
        let limitations: [String]
    }

    private static func renderReviewBoard(
        dark: [URL],
        light: [URL],
        to directory: URL
    ) throws -> URL {
        guard dark.count == light.count else {
            throw fixtureError("appearance fixture counts do not match")
        }

        let pairs = try zip(dark, light).map { darkURL, lightURL in
            guard darkURL.lastPathComponent == lightURL.lastPathComponent,
                  let darkImage = NSImage(contentsOf: darkURL),
                  let lightImage = NSImage(contentsOf: lightURL)
            else {
                throw fixtureError(
                    "could not pair \(darkURL.lastPathComponent)"
                )
            }
            return (
                state: darkURL.deletingPathExtension().lastPathComponent,
                dark: darkImage,
                light: lightImage
            )
        }

        let margin: CGFloat = 20
        let columnGap: CGFloat = 18
        let columnWidth: CGFloat = 660
        let headerHeight: CGFloat = 84
        let rowGap: CGFloat = 14
        let rows = pairs.map {
            max($0.dark.size.height, $0.light.size.height) + 48
        }
        let boardSize = NSSize(
            width: 2 * margin + 2 * columnWidth + columnGap,
            height: headerHeight
                + rows.reduce(0, +)
                + CGFloat(max(0, rows.count - 1)) * rowGap
                + margin
        )
        let board = NSView(frame: NSRect(origin: .zero, size: boardSize))
        board.wantsLayer = true
        board.layer?.backgroundColor = NSColor(
            srgbRed: 0.055,
            green: 0.06,
            blue: 0.075,
            alpha: 1
        ).cgColor

        let title = reviewLabel(
            "PARLOQ HUD · FOCUS-SAFE REVIEW",
            size: 15,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.92)
        )
        title.frame = NSRect(
            x: margin,
            y: boardSize.height - 36,
            width: 420,
            height: 20
        )
        board.addSubview(title)

        let note = reviewLabel(
            "Compatibility material render · native glass refraction requires "
                + "the installed compositor",
            size: 10.5,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.54)
        )
        note.frame = NSRect(
            x: margin,
            y: boardSize.height - 57,
            width: 620,
            height: 16
        )
        board.addSubview(note)

        for (title, x) in [
            ("DARK APPEARANCE", margin),
            ("LIGHT APPEARANCE", margin + columnWidth + columnGap),
        ] {
            let label = reviewLabel(
                title,
                size: 10,
                weight: .semibold,
                color: NSColor.white.withAlphaComponent(0.60)
            )
            label.frame = NSRect(
                x: x + 14,
                y: boardSize.height - 78,
                width: columnWidth - 28,
                height: 16
            )
            board.addSubview(label)
        }

        var rowTop = boardSize.height - headerHeight
        for (index, pair) in pairs.enumerated() {
            let rowHeight = rows[index]
            let rowBottom = rowTop - rowHeight
            let stateLabel = reviewLabel(
                pair.state.replacingOccurrences(of: "hud-", with: "")
                    .replacingOccurrences(of: "-", with: " ")
                    .uppercased(),
                size: 9.5,
                weight: .medium,
                color: NSColor.white.withAlphaComponent(0.46)
            )
            stateLabel.frame = NSRect(
                x: margin,
                y: rowTop - 22,
                width: 320,
                height: 14
            )
            board.addSubview(stateLabel)

            addReviewCell(
                image: pair.dark,
                frame: NSRect(
                    x: margin,
                    y: rowBottom,
                    width: columnWidth,
                    height: rowHeight - 28
                ),
                light: false,
                to: board
            )
            addReviewCell(
                image: pair.light,
                frame: NSRect(
                    x: margin + columnWidth + columnGap,
                    y: rowBottom,
                    width: columnWidth,
                    height: rowHeight - 28
                ),
                light: true,
                to: board
            )
            rowTop = rowBottom - rowGap
        }

        let url = directory.appendingPathComponent("ui-review-board.png")
        board.layoutSubtreeIfNeeded()
        try write(board, to: url)
        return url
    }

    private static func addReviewCell(
        image: NSImage,
        frame: NSRect,
        light: Bool,
        to board: NSView
    ) {
        let cell = NSView(frame: frame)
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 18
        cell.layer?.cornerCurve = .continuous
        cell.layer?.masksToBounds = true

        let gradient = CAGradientLayer()
        gradient.frame = cell.bounds
        gradient.cornerRadius = 18
        gradient.startPoint = CGPoint(x: 0.05, y: 0.95)
        gradient.endPoint = CGPoint(x: 0.95, y: 0.05)
        if light {
            gradient.colors = [
                NSColor(
                    srgbRed: 0.91,
                    green: 0.93,
                    blue: 0.97,
                    alpha: 1
                ).cgColor,
                NSColor(
                    srgbRed: 0.66,
                    green: 0.70,
                    blue: 0.78,
                    alpha: 1
                ).cgColor,
            ]
        } else {
            gradient.colors = [
                NSColor(
                    srgbRed: 0.12,
                    green: 0.14,
                    blue: 0.19,
                    alpha: 1
                ).cgColor,
                NSColor(
                    srgbRed: 0.035,
                    green: 0.045,
                    blue: 0.07,
                    alpha: 1
                ).cgColor,
            ]
        }
        cell.layer?.addSublayer(gradient)

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = cell.bounds.insetBy(dx: 10, dy: 8)
        imageView.autoresizingMask = [.width, .height]
        cell.addSubview(imageView)
        board.addSubview(cell)
    }

    private static func reviewLabel(
        _ value: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func writeManifest(
        dark: [URL],
        light: [URL],
        board: URL,
        to directory: URL
    ) throws -> URL {
        let artifacts = try [
            ("dark", dark),
            ("light", light),
        ].flatMap { appearance, urls in
            try urls.map { url in
                let data = try Data(contentsOf: url)
                guard let bitmap = NSBitmapImageRep(data: data),
                      bitmap.pixelsWide >= 200,
                      bitmap.pixelsHigh >= 100,
                      data.count >= 1_000
                else {
                    throw fixtureError(
                        "empty or implausibly small fixture "
                            + url.lastPathComponent
                    )
                }
                return Artifact(
                    appearance: appearance,
                    file: url.path.replacingOccurrences(
                        of: directory.path + "/",
                        with: ""
                    ),
                    state: url.deletingPathExtension().lastPathComponent,
                    pixelWidth: bitmap.pixelsWide,
                    pixelHeight: bitmap.pixelsHigh,
                    bytes: data.count
                )
            }
        }

        for index in dark.indices {
            let darkArtifact = artifacts[index]
            let lightArtifact = artifacts[index + dark.count]
            guard darkArtifact.state == lightArtifact.state,
                  darkArtifact.pixelWidth == lightArtifact.pixelWidth,
                  darkArtifact.pixelHeight == lightArtifact.pixelHeight
            else {
                throw fixtureError(
                    "light and dark geometry differ for "
                        + darkArtifact.state
                )
            }
        }

        let manifest = ReviewManifest(
            artifacts: artifacts,
            reviewBoard: board.lastPathComponent,
            limitations: [
                "The review board verifies content, hierarchy, geometry, "
                    + "appearance, and state coverage without showing a window.",
                "NSGlassEffectView refraction and optical merging are rendered "
                    + "only by the installed WindowServer compositor.",
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent("manifest.json")
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fixtureError(_ description: String) -> Error {
        NSError(
            domain: "Parloq.UIFixtureRenderer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    private static func makePanel(
        elapsedSeconds: Double = 0,
        details: DictationDetails = fixtureDetails(),
        presentsWindow: Bool = false
    ) -> LiveTranscriptPanel {
        LiveTranscriptPanel(
            metadata: DictationHUDMetadata(
                targetApplication: "Ghostty",
                deliveryMode: .keyboardFallback,
                elapsedSeconds: elapsedSeconds
            ),
            details: details,
            targetApplicationIcon: fixtureTargetApplicationIcon(),
            presentsWindow: presentsWindow
        )
    }

    private static func fixtureDetails(
        latestProsodyState: DictationProsodyState? = nil,
        latestProsodyEnergyZ: Double? = nil,
        prosodyBaselineCount: Int? = 2,
        saveEnabled: Bool = false,
        lastAudioSeconds: Double? = nil,
        lastASRSeconds: Double? = nil
    ) -> DictationDetails {
        DictationDetails(
            device: ":0",
            deviceName: "Studio Display Microphone",
            model: "mlx-community/parakeet-tdt-0.6b-v3",
            prosodyEnabled: true,
            latestProsodyState: latestProsodyState,
            latestProsodyEnergyZ: latestProsodyEnergyZ,
            prosodyBaselineCount: prosodyBaselineCount,
            polishEnabled: false,
            chimeEnabled: false,
            saveEnabled: saveEnabled,
            vocabCount: 0,
            streamIntervalSeconds: 0.5,
            lastAudioSeconds: lastAudioSeconds,
            lastASRSeconds: lastASRSeconds
        )
    }

    private static func fixtureTargetApplicationIcon() -> NSImage {
        let image = NSImage(
            size: NSSize(width: 32, height: 32),
            flipped: false
        ) { rect in
            NSColor(
                srgbRed: 0.12,
                green: 0.33,
                blue: 0.76,
                alpha: 1
            ).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: 7,
                yRadius: 7
            ).fill()

            NSColor.white.withAlphaComponent(0.94).setStroke()
            let prompt = NSBezierPath()
            prompt.lineWidth = 2.6
            prompt.lineCapStyle = .round
            prompt.lineJoinStyle = .round
            prompt.move(to: NSPoint(x: 8, y: 11))
            prompt.line(to: NSPoint(x: 13, y: 16))
            prompt.line(to: NSPoint(x: 8, y: 21))
            prompt.move(to: NSPoint(x: 16, y: 21))
            prompt.line(to: NSPoint(x: 24, y: 21))
            prompt.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Fixture target application"
        return image
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
