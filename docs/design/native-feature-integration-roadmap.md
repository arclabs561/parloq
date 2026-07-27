---
status: proposal
scope: Parloq's native dictation surface and the recorder capabilities behind it
grounded-in:
  - docs/design/parloq-recorder-roadmap.md
  - docs/design/live-menu-bar-dictation.md
  - docs/design/live-dictation-forward.md
  - docs/design/dictation-history-and-hud.md
  - docs/design/dictation-tui.md
  - recorder/parloq_recorder/cli.py
  - recorder/parloq_recorder/daemon.py
  - macos/ParloqMenu/Sources/ParloqMenu/AppDelegate.swift
review-trigger: choose a configuration authority before implementing mutable native settings, and choose a product surface before integrating meeting workflows
---

# Native Feature Integration Roadmap

## Current position

Parloq now has a useful native dictation shell: global shortcuts, live
transcription, final-pass correction, safe focused-field delivery, a
non-activating HUD, cancellation, recovery history, daemon status, and login
launching. That shell exposes only a narrow slice of the recorder behind it.

The dictation daemon already understands microphone selection, model selection,
vocabulary corrections, optional polish, optional prosody, recording
retention, chimes, clipboard behavior, and streaming cadence. The broader
recorder also has meeting capture, saved artifacts, offline processing,
summaries, search, glossary support, and experimental diarization. Most of
those capabilities are currently reachable only through CLI arguments or
recorder workflows.

Some earlier non-goals have deliberately changed after real use. A live HUD
became valuable when direct field insertion alone gave too little feedback,
and bounded history became valuable for recovery. The reason to add more
surface area is therefore observed dictation use, not parity with every CLI
flag.

## Product boundary

The menu-bar app should remain the fast, ambient dictation product:

- start, observe, finish, cancel, and recover dictation;
- make the active microphone and quality/privacy modes understandable;
- offer the few settings that materially affect everyday dictation;
- avoid windows, focus changes, and configuration ceremony during capture.

Meeting capture is a different interaction: it has duration, files, speakers,
post-processing, search, and summaries. If it becomes native, it should have a
dedicated window or companion surface rather than expanding the status menu
into a recorder dashboard.

## Phase 0: finish the daily dictation loop

Consumer: dictation into any editable control.

Deliver:

- a compact HUD for short speech that grows upward for multiple lines;
- settled context as a muted paragraph above the bright, revisable tail;
- leading truncation only when older context exceeds the panel;
- Escape cancellation and Option-Space completion without activating Parloq;
- bounded local history containing completed transcripts only.

Gate:

- two- and four-sentence trials wrap vertically rather than scroll as one line;
- the newest revision remains visible at the bottom;
- cancellation cannot submit or disturb the focused application;
- the final text and one history entry agree.

Reversibility: complete. The HUD and local history do not alter daemon
configuration or recorder artifacts.

## Phase 1: expose facts before controls

Consumer: a user diagnosing why dictation sounds or behaves differently.

Add a concise read-only `Dictation Details` section or submenu showing:

- active microphone;
- ASR model;
- whether polish, prosody, recording retention, and chimes are enabled;
- the vocabulary file in use;
- most recent capture duration and stop-to-final latency.

Extend the typed daemon status/event protocol only for facts that are not
already present. Keep the top-level menu calm: state belongs in a details
submenu unless it requires action.

Gate:

- displayed values come from the running daemon, not duplicated app defaults;
- reconnect and daemon restart refresh all values;
- no setting appears mutable until one authority owns persistence and restart
  behavior.

Reversibility: high. Read-only protocol fields can remain backward compatible
and unknown fields are ignored.

## Decision fork A: configuration authority

Mutable native settings need one owner. Choose before Phase 2.

### A. Runtime daemon configuration

Add a typed `configure` command, validate changes in the daemon, persist a
versioned local configuration, and report effective values through `status`.
Settings that require reloading capture or inference do so explicitly.

This gives the cleanest native experience and one source of truth, but expands
the protocol and daemon lifecycle.

### B. App-managed launch configuration

Have the app rewrite the launch-agent invocation and restart the daemon.

This is smaller initially, but makes the UI responsible for process
configuration and risks drift between CLI installation and app-owned state.

### C. CLI-owned configuration

Keep the CLI authoritative. The app exposes current values and offers focused
actions such as `Edit Vocabulary…` or `Copy Configuration Command`.

This preserves the simplest architecture but leaves microphone and privacy
changes less immediate.

Recommendation: use runtime daemon configuration if native microphone and
privacy controls are wanted as first-class features. Otherwise keep CLI
authority and add only the vocabulary affordance. Do not maintain both mutable
paths.

## Phase 2: integrate the settings that earn their place

Consumer: daily dictation quality, privacy, and input reliability.

After choosing configuration authority, expose in this order:

1. `Microphone` selector using the daemon's existing device discovery.
2. `Vocabulary…` to edit or reveal the deterministic correction file.
3. `Save Recordings` privacy toggle with a plain description of the storage
   location and retention behavior.
4. `Polish Final Text` as an explicit opt-in. Preserve raw ASR alongside any
   polished result so entity regressions remain recoverable.
5. `Prosody` only under a Labs/experimental section after a real-use quality
   comparison justifies it.

Do not expose model selection or stream interval as everyday knobs. They are
diagnostic/advanced settings and should remain stable during quality trials.

Gate:

- the running daemon confirms every change;
- invalid devices or values fail without stopping an active dictation;
- app restart and daemon restart preserve the chosen configuration;
- saved-audio and polish modes are visible during capture and in history
  metadata where recovery requires it;
- polish and prosody have repeatable quality comparisons before their defaults
  can change.

Reversibility: medium. The settings are reversible, but the persisted schema
and protocol become compatibility commitments.

## Phase 3: make quality observable

Consumer: the user deciding whether a quality feature is actually better.

Build on existing recorder evaluations rather than adding opaque preference
knobs:

- keep recent latency and fallback outcomes locally;
- provide `Copy Diagnostics` with no transcript or target-app contents by
  default;
- let a deliberately saved recording be reprocessed with alternative
  vocab/polish/model settings;
- compare raw ASR and polished final text when polish is enabled.

Gate:

- diagnostics explain slow or failed delivery without collecting private text;
- every quality change has a fixed sample and a baseline;
- no automatic tuning changes behavior behind the user's back.

Reversibility: high for diagnostics; medium for a persisted comparison format.

## Decision fork B: native dictation or full recorder

Question: should meeting workflows become part of the macOS app?

- Keep them CLI/browser-based: smallest product, strongest dictation focus.
- Add a dedicated native recorder window: appropriate if meeting capture is a
  recurring workflow and saved sessions need browsing.
- Put meetings in the status menu: reject. The interaction and information
  density do not fit an ambient menu utility.

Recommendation: keep the current app dictation-first until at least five real
meeting sessions demonstrate a need for native browsing or controls. If that
gate passes, write a separate meeting-surface design before implementation.

## Explicit deferrals

- Diarization remains hidden until its measured speaker quality is dependable.
- Summary and search remain attached to saved meeting artifacts, not short
  dictation history.
- No cloud account, sync, general clipboard monitoring, or analytics.
- No configurable matrix of hotkeys until Option-Space or the hardware
  Dictation key reproduces a real conflict.
- No inference rewrite in Swift while the warm Python daemon remains reliable.

## Dependency order

```text
HUD/history reliability
        |
read-only effective settings + diagnostics
        |
choose one configuration authority
        |
microphone -> vocabulary -> privacy -> polish -> experimental prosody
        |
measure recurring meeting use
        |
choose whether a dedicated recorder surface exists
```

This order keeps every early step useful on its own and prevents hidden CLI
capabilities from dictating the shape of the native product.
