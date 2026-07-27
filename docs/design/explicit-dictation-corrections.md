# Design: explicit dictation corrections

## Problem

Parloq now preserves raw ASR beside delivered text, but it has no safe path from
“that name was wrong” to a reusable correction. Requiring the user to locate
and edit the vocabulary file makes the highest-value personalization loop too
obscure, while silent learning from later edits would require monitoring other
applications and could learn unrelated changes.

## Chosen approach

Add **Teach Parloq From Last Dictation…** to Dictation History. This is an
explicit, user-initiated interactive action; ordinary dictation and the passive
HUD remain nonactivating. The correction sheet shows the last known raw ASR and
delivered final as read-only context, then asks for two short editable fields:
**Heard** and **Use instead**. It never treats the full utterance as an approved
rule by default. A narrowly safe, single contiguous changed span may be
suggested later, but both fields remain editable and Save requires confirmation.

The native app sends a typed correction intent to the Python daemon. The daemon
remains the sole vocabulary mutation authority: it normalizes and validates
both phrases, rejects multiline or ambiguous rules, detects an existing
conflict, atomically appends to the configured vocabulary file, reloads the
effective ordered rules, and returns confirmed status. Learning is allowed only
while idle so it cannot change the finalization of an active recording. The
sheet reports whether the correction was added, already existed, or conflicted,
then returns focus to the application that was active before the user opened it.

The initial implementation teaches deterministic whole-word replacements only.
History retains the evidence; no acoustic model is fine-tuned.

## Non-goals

- No passive observation of edits in target applications; those edits may be
  unrelated and screen/Accessibility monitoring expands the privacy boundary.
- No automatic rules from raw-versus-final differences; polish, punctuation,
  and capitalization are not proof of user intent.
- No whole-utterance replacement proposed as a shortcut; it would be overly
  specific and easy to approve accidentally.
- No fuzzy, semantic, or LLM-authored replacement rules.
- No personal acoustic fine-tuning until explicit corrections outperform the
  existing vocabulary layer on a held-out sample.

## Decision gates

- Save remains disabled until both phrases are non-empty, single-line, and
  different after normalization.
- A conflicting existing rule is never overwritten without a separate,
  explicit replace design.
- If users repeatedly need corrections from older entries, design a searchable
  history/correction palette instead of adding more menu modifiers.
- If deterministic rules cannot reduce recurring entity errors without
  collateral replacements, evaluate decoder contextual biasing before adding
  fuzzy post-processing.
- If the correction panel cannot reliably return focus after a user-initiated
  interaction, keep Edit Vocabulary… as the only mutation surface.

## Why not the rejected options?

Monitoring text after insertion cannot distinguish correction from ordinary
editing and would require a broader Accessibility privacy contract. Opening a
full history window adds search, selection, and lifecycle complexity before the
last-dictation loop has been tested. Letting Swift append the vocabulary file
would create a second mutation authority beside the daemon and make conflicts
and live reload behavior harder to reason about.

---
Decided: 2026-07-27 | Session: Codex
