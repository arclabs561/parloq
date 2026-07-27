# Parloq menu app

A native macOS status-item client for Parloq's local dictation daemon. It owns
the platform-specific pieces: the global shortcut, focused text control,
incremental in-field updates, Accessibility permission, and launch at login.
The Python daemon remains the speech engine.

## Behavior

- **Option-Space** or a tap of the Microphone/Dictation key (F5 on supported
  Apple keyboards) starts and stops Parloq.
- Parloq remaps only that HID key while it is running, preserves unrelated
  mappings, and restores the prior mapping when it quits.
- A compact, non-activating HUD shows revisable transcript snapshots while
  recording. On macOS 26, a native glass container optically joins the tinted
  state lens to the transcript capsule while a detached clear-glass shelf keeps
  diagnostics subordinate. The established visual-effect material remains the
  compatibility and offscreen-test fallback. Settled context is muted above
  the bright, changing tail, and older context truncates from the top. Two
  quiet instrument rows identify the captured application and delivery
  behavior, elapsed time, microphone, model, live speaking rate, peak dBFS,
  and the short voice-level learning phase. The state lens shows the real input
  spectrum without mixing it with an insertion cursor. It cannot receive
  keyboard focus or mouse input. It follows the focused caret or window's
  display, with the pointer display only as a fallback.
- The menu-bar icon uses a different silhouette for ready, listening,
  finalizing, unavailable, and error states. Listening adds a visible status
  dot and green tint; its waveform and the HUD's nine-band **SPECTRUM**
  visualization respond to real FFT telemetry from the daemon. Peak dBFS
  remains available as a compatibility fallback. Spectrum telemetry updates at
  10 Hz independently of the heavier live-transcription cadence. Finalizing is
  cyan and errors are coral. Shape and accessible state text remain
  authoritative when color or motion is reduced.
- **Escape** cancels while a dictation is active. Parloq consumes the key before
  the focused app sees it, stops without creating a final/history item, and
  restores live text when it still owns that text safely.
- Live transcript snapshots replace only the text range Parloq inserted in the
  control that was focused at start when that control exposes a writable
  Accessibility range.
- If focus, selection, or the inserted text changes, Parloq stops replacing it
  and copies the accurate final transcript instead of overwriting user input.
- Controls without writable Accessibility ranges receive the complete final
  transcript only after dictation stops. The HUD still provides live feedback,
  while unstable draft text is never appended where it cannot be revised
  safely. Any ordinary click or keystroke before delivery changes the HUD to
  **Safe copy · final goes to clipboard** and prevents Parloq from guessing at
  a new insertion point. Blind keyboard delivery keeps
  Unicode surrogate pairs intact and refuses line breaks or control characters
  that could act as terminal commands; the full final is copied instead.
- The daemon runs a higher-quality offline pass after stop; that result replaces
  the live snapshot when range ownership is still intact. A brief passive
  completion state reports local ASR realtime factor and, when enabled, the
  latest energy-relative prosody result before dismissing itself.
- The optional voice-level analysis is structured acoustic metadata, never
  transcript markup. It learns typical utterance energy from three completed
  dictations, then reports only whether a completed recording was typical or
  above that baseline. A ready state is not shown because it requires no user
  action. Parloq does not present emotion, valence, intent, or confidence labels
  that its evidence does not support.
- If the daemon fails or disconnects after speech appears, the HUD retains the
  latest transcript, copies it for clipboard-history recovery, and changes to a
  distinct **Recovered** state. Escape dismisses that recovery without sending
  a key to the focused app.
- Each non-empty completed dictation is saved locally in the
  **Dictation History** submenu. Selecting an entry copies it. The bounded
  history lives at
  `~/Library/Application Support/Parloq/History/dictation-history.json`; drafts,
  cancellations, and audio are never stored there.
- Each non-empty final transcript is also published once to the system
  pasteboard, regardless of insertion mode, so clipboard managers such as
  Maccy can retain it and the latest dictation remains ready to paste. The
  completion HUD says **Complete · Copied** only after that write succeeds and
  changes to **Complete · Copy failed** when it does not.
- **Dictation Details** reports effective microphone, model, quality/privacy
  modes, vocabulary count, live-update cadence, and latest capture/ASR timing
  from the running daemon, including the latest ASR-to-audio realtime factor.
  These values are diagnostic and read-only. **Copy Diagnostics** exports the
  same runtime facts plus connection, phase, app, system, and Accessibility
  state without transcript or target-application contents.

## Build and install

From the repository root:

```sh
just macos-app
just install-macos-app
recorder dictate install-agent
open -g /Applications/Parloq.app
```

The app does not open a permission prompt at launch. When you are ready, use
the menu item **Request Accessibility Permission**, then enable Parloq under
System Settings > Privacy & Security > Accessibility. Accessibility lets
Parloq replace the Microphone key and update the focused text field.

Use **Launch at Login** in the menu after the app is installed. The daemon is
managed separately by its existing `parloq.dictate` launchd agent, so either
side can be restarted and diagnosed independently.

The built bundle is `~/Library/Caches/Parloq/Parloq.app`, outside File
Provider-managed project metadata that can invalidate codesigning. It is signed
with the local `stela-dev` identity so macOS can retain Accessibility approval
across rebuilds. Override the identity with `PARLOQ_CODESIGN_IDENTITY`; use `-`
for an ad-hoc development build on a machine without that identity.

## Development

```sh
swift test --package-path macos/ParloqMenu
just ui-fixtures
just ui-native-fixture
just check
```

`just ui-fixtures` renders every representative HUD and status-icon state in
dark and light appearances to `test-results/ui-fixtures/`. It also creates
`ui-review-board.png` for one-pass comparison and `manifest.json`, which checks
that every appearance pair has matching, non-empty geometry. The command uses
the real AppKit hierarchy without showing a window, activating Parloq, arming
shortcuts, or opening the microphone, so visual changes can be inspected
without interrupting another app. The compatibility material stands in for
native glass in these offscreen renders; WindowServer-owned refraction and
optical merging require a native capture.

`just ui-native-fixture` briefly presents a synthetic, nonactivating HUD over a
bounded gradient-and-grid backdrop, captures it to
`test-results/ui-fixtures/native-glass.png`, and verifies that the frontmost
application did not change. It preflights Screen Recording access but never
opens a permission prompt, global shortcut, daemon connection, or microphone.
Use it to inspect the real macOS 26 glass compositor without starting a
dictation or asking for a manual screenshot.

For normal development against the installed app:

```sh
just reload-macos-app
just dev-macos-app
```

`reload-macos-app` builds and signs a staging bundle while the current app
continues running. It waits for any recording, finalization, or polishing pass
to finish, installs the staged bundle, terminates only the exact installed
Parloq process, and relaunches with `open -g`. It never force-kills the app and
checks that Parloq did not become frontmost. `dev-macos-app` wraps the same
operation in Watchexec, watches only the Swift package sources and resources,
debounces save bursts, and queues one follow-up build when files change during
a build. This is rebuild-and-relaunch rather than runtime code injection; the
stable signed bundle preserves macOS permissions.

Set `RECORDER_DICTATE_SOCK` for an isolated daemon socket. The production
default is `/tmp/recorder-dictate-$UID.sock`.

Check the installed app's Accessibility state without opening a window:

```sh
/Applications/Parloq.app/Contents/MacOS/ParloqMenu --check-accessibility
```

Request permission from the installed bundle without opening an app window:

```sh
/Applications/Parloq.app/Contents/MacOS/ParloqMenu --request-accessibility
```

With Parloq quit, verify that macOS can arm its global shortcut event tap:

```sh
/Applications/Parloq.app/Contents/MacOS/ParloqMenu --check-hotkey
```
