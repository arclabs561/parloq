# Parloq menu app

A native macOS status-item client for Parloq's local dictation daemon. It owns
the platform-specific pieces: the global shortcut, focused text control,
incremental in-field updates, Accessibility permission, and launch at login.
The Python daemon remains the speech engine.

## Behavior

- A tap of the Microphone/Dictation key (F5 on supported Apple keyboards)
  starts and stops Parloq instead of macOS Dictation.
- Parloq remaps only that HID key while it is running, preserves unrelated
  mappings, and restores the prior mapping when it quits.
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
just check
```

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
