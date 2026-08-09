---
status: accepted
scope: Parloq's native dictation surface and the recorder capabilities behind it
grounded-in:
  - docs/design/parloq-recorder-roadmap.md
  - docs/design/live-menu-bar-dictation.md
  - docs/design/live-dictation-forward.md
  - docs/design/dictation-history-and-hud.md
  - docs/design/dictation-tui.md
  - recorder/recorder
  - macos/ParloqMenu/Sources/ParloqMenu/AppDelegate.swift
review-trigger: choose a product surface before integrating meeting workflows, or revisit configuration ownership if a second runtime client needs to mutate settings
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

The first read-only `Dictation Details` submenu now shows:

- active microphone;
- ASR model;
- whether polish, prosody, recording retention, and chimes are enabled;
- the number of vocabulary corrections loaded;
- streaming cadence;
- most recent capture and offline-ASR duration.

The typed daemon protocol carries those facts as optional fields, so older
clients and daemons remain compatible. Keep extending it only for effective
runtime facts that are not already present. The top-level menu remains calm:
state belongs in the details submenu unless it requires action.

Gate:

- displayed values come from the running daemon, not duplicated app defaults;
- reconnect and daemon restart refresh all values;
- no setting appears mutable until one authority owns persistence and restart
  behavior.

Reversibility: high. Read-only protocol fields can remain backward compatible
and unknown fields are ignored.

## Decision: the daemon owns runtime configuration

Mutable native settings have one authority: the running dictation daemon. The
native app sends typed configuration requests, the daemon validates and
persists them, and status events report the effective values back to every
client.

The versioned configuration lives at
`~/Library/Application Support/Parloq/dictation-config.json`. Writes are atomic
and user-only. Launch-agent and CLI arguments remain bootstrap defaults; a
field appears in the configuration only after the user explicitly saves it,
and that saved field then overrides the corresponding bootstrap default.
Neither the app nor another client rewrites the launch-agent property list.

Configuration changes are accepted only while the daemon is idle. A successful
request persists before mutating runtime state and returns the resulting status.
An invalid or unavailable value leaves both the file and current state
unchanged.

Microphone identity needs more than AVFoundation's session-local numeric index.
The saved microphone is an `(index, name)` pair. At startup the daemon
re-resolves a unique matching name to its current index, which survives ordinary
device reordering. If the saved name is absent or ambiguous, it does not
silently substitute a different input: status reports the unavailable
selection and recording remains blocked until the user chooses an available
microphone. A newly selected pair is validated against fresh device discovery
before it is persisted.

This decision favors one truthful runtime source over the initially smaller
alternatives of app-managed launch configuration or CLI-only configuration.
It also keeps the protocol additive: typed fields can be introduced one at a
time without exposing every recorder flag as a preference.

## Phase 2: integrate the settings that earn their place

Consumer: daily dictation quality, privacy, and input reliability.

After choosing configuration authority, expose in this order:

1. `Microphone` selector using the daemon's existing device discovery.
   Delivered with daemon-owned persistence, restart re-resolution, and
   hot-plug reconciliation.
2. `Vocabulary…` to edit or reveal the deterministic correction file.
   Delivered as an edit action against the daemon-reported path, with a reload
   at the start of each dictation.
3. `Save Recordings` privacy toggle with a plain description of the storage
   location and retention behavior. Delivered as an off-by-default
   `Save Audio & Transcript` control, with the effective output path in the
   menu and an active-retention label in the HUD.
4. `Polish Final Text` as an explicit opt-in. Preserve raw ASR alongside any
   polished result so entity regressions remain recoverable. The additive
   protocol and native history fields are delivered; comparison and revert UI
   remain gated on the interaction design.
5. `Prosody` only under a Labs/experimental section after a real-use quality
   comparison justifies it.

Execution checkpoint:

- microphone selection, vocabulary correction, and recording retention are
  integrated with daemon-owned persistence;
- `Polish Final Text` is integrated as an idle-only opt-in whose enable path
  verifies that Ollama is reachable and the configured model is installed;
- raw ASR remains attached to the final event and native history, and any
  polish request failure falls back to raw ASR;
- the cold-model request budget is deliberately longer than ordinary local
  requests, because a persisted opt-in must not routinely degrade into a
  silent no-op after Ollama has evicted the model.

Before polish can become a recommended default, add per-utterance outcome
telemetry (`applied`, `no edits`, or `fallback`), expose fallback in history or
diagnostics, and reuse the meeting polisher's edit-count, content-preservation,
and length-ratio guards. These are quality gates, not reasons to hide the
current explicit opt-in.

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

Concrete delivery slices:

1. Add typed, transcript-free polish outcome fields to the final event and
   `DictationDetails`; show only failures in the ordinary menu and include all
   outcomes in copied diagnostics.
2. Store raw/final comparison metadata with the existing bounded history entry
   rather than creating another history store.
3. Add `Reprocess Saved Dictation…` only for deliberately retained recordings;
   it must never imply that temporary audio can be recovered.
4. Establish a fixed local speech corpus containing names, numbers, commands,
   and disfluencies; compare raw ASR, vocabulary-only, and polish output before
   changing defaults or prompts.
5. Keep prosody observational: first extend the evaluator with pitch range,
   speaking-rate, pause, and energy features, then decide which results are
   stable enough to display. Do not label emotion, intent, confidence, or
   speaker identity from those signals.

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
