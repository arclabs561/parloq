# Design: dictation history and live HUD

## Problem

Parloq delivers live text well, but its HUD turns longer speech into a
single-line ticker and its menu remembers only the last transcript. Escape also
has no recording-specific meaning, so trying to dismiss the HUD can interrupt
the focused application. The user wants Maccy-like recovery after every
recording without requiring Maccy or changing focus.

## Chosen approach

Keep a small, Parloq-owned history of completed dictations. Append exactly one
non-empty final transcript per recording, persist it as a bounded local JSON
file under Application Support, and expose recent entries in a native
`Dictation History` submenu. Selecting an entry copies it. Drafts, cancelled
recordings, audio, and target-application metadata never enter history.

Also publish each non-empty final exactly once to the system pasteboard at the
native completion boundary, regardless of how text delivery succeeded. This
makes the latest dictation immediately pasteable and lets clipboard managers
retain it without coupling to their private storage. Parloq deliberately does
not rewrite a clipboard manager's database or cycle and restore pasteboard
contents.

Render live speech as one wrapping paragraph with two visual roles. Settled
context is muted; the actively revised tail and cursor remain bright at the
bottom. The label keeps the newest lines and uses a leading ellipsis only when
older context no longer fits. The daemon's existing `finalized_text` and
`draft_text` fields provide the split; no second transcript model or timer is
added.

While a recording exists, Escape becomes an explicit cancel action. The global
event tap consumes both Escape events before the focused app sees them, the
daemon stops without publishing a final result, and Accessibility delivery
restores the text Parloq owned when that remains safe. The HUD advertises
`ESC CANCEL`; outside dictation, Escape is untouched.

## Non-goals

- No searchable history window, clipboard monitoring, or general clipboard
  manager.
- No Maccy database access, URL automation, or required third-party app.
- No history entries for drafts, errors, empty results, or cancellations.
- No unsafe deletion of text after focus or ownership changes.

## Decision gates

- If a native submenu becomes unwieldy in real use, design a searchable
  history palette from observed scale; do not pre-build one.
- If restoring cancelled text cannot prove range ownership, preserve user
  input and report that live text remains.
- If persistence fails, keep dictation delivery working and surface a concise
  menu status instead of losing the transcript silently.
- Keep history bounded and private (`0700` directory, `0600` file).

## Why not the rejected options

Writing a clipboard manager's storage couples Parloq to an undocumented schema
and concurrent writer. Cycling and restoring pasteboard contents creates timing
races and extra entries; publishing the completed final once and leaving it
current has one owner and one observable result. A custom history window adds
focus, search, and keyboard-navigation complexity before the native menu has
failed.

Decided: 2026-07-27 | Session: Codex
