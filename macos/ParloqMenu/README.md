# Parloq menu app

A native macOS status-item client for Parloq's local dictation daemon. It owns
the platform-specific pieces: the global shortcut, focused text control,
incremental in-field updates, Accessibility permission, and launch at login.
The Python daemon remains the speech engine.

## Behavior

- `⌃⌥Space` starts and stops dictation.
- Live transcript snapshots replace only the text range Parloq inserted in the
  control that was focused at start.
- If focus, selection, or the inserted text changes, Parloq stops replacing it
  and copies the accurate final transcript instead of overwriting user input.
- Controls without writable Accessibility ranges receive finalized text only.
  Unstable draft text is never appended where it cannot be revised safely.
- The daemon runs a higher-quality offline pass after stop; that result replaces
  the live snapshot when range ownership is still intact.
- No transcript popup or floating window is created.

## Build and install

From the repository root:

```sh
just macos-app
just install-macos-app
recorder dictate install-agent
open /Applications/Parloq.app
```

The app does not open a permission prompt at launch. When you are ready, use
the menu item **Request Accessibility Permission**, then enable Parloq under
System Settings > Privacy & Security > Accessibility.

Use **Launch at Login** in the menu after the app is installed. The daemon is
managed separately by its existing `parloq.dictate` launchd agent, so either
side can be restarted and diagnosed independently.

The built bundle is
`macos/ParloqMenu/.build/Parloq.app`. It is signed with the local `stela-dev`
identity so macOS can retain Accessibility approval across rebuilds. Override
the identity with `PARLOQ_CODESIGN_IDENTITY`; use `-` for an ad-hoc development
build on a machine without that identity.

## Development

```sh
swift test --package-path macos/ParloqMenu
just check
```

Set `RECORDER_DICTATE_SOCK` for an isolated daemon socket. The production
default is `/tmp/recorder-dictate-$UID.sock`.
