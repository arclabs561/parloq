---
status: proposal
scope: parloq recorder, dictation, evals, prosody lanes
grounded-in:
  - README.md
  - PROGRESS.md
  - recorder/README.md
  - recorder/evals/README.md
  - recorder/evals/eval-design.md
  - recorder/evals/results-diarization-der.md
  - ~/.claude/projects/-Users-arc-Documents-dev/memory/paralinguistic-dictation-roadmap.md
review-trigger: revisit after one week of recorder replacing SuperWhisper, or after any ASR/diarization model swap
---

# Parloq Recorder Roadmap

## Current Position

`recorder` is the product surface. It must stay useful as a local desktop
dictation and meeting-capture tool while `eval/`, `experiments/`, and
`results/` provide evidence for what graduates into the daily path.

What is already done:

- CLI meeting recorder with live browser UI, offline re-pass, diarization,
  summary, search, crash-safe artifacts, and deterministic UI fixture.
- `recorder dictate` with daemon trigger mode for global-hotkey use.
- `recorder dictate --prosody`, opt-in, with an energy-based `[emphatic]`
  prefix. The evidence supports arousal/emphasis as the first paralinguistic
  lane; richer affect is not yet proven.
- Evals for ASR WER, live-vs-offline gap, diarization DER, polish A/B,
  hallucination checks, search recall, UI screenshots, and prosody A/B.
- Naming and repo boundary are settled: `parloq` is the umbrella, recorder is
  the daily-driver subproject.

Known load-bearing findings:

- Parakeet-MLX is still the practical Apple Silicon ASR lane. Current external
  references are senstella/parakeet-mlx and NVIDIA Parakeet-TDT 0.6B v3:
  https://github.com/senstella/parakeet-mlx and
  https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3.
- Polish can hurt proper nouns and WER, so polish must stay reviewable and
  never be the only text surface.
- Diarization threshold tuning failed on AMI. DER stayed catastrophic while
  cluster count improved, so the next diarization move is a model/product
  decision, not more threshold work.
- Prosody A/B calibration changed the claim from "slam dunk" to "real but
  modest." Future prosody lanes need noise-controlled A/B before defaults
  change.

## Product Invariant

Every phase must preserve the desktop CLI recorder path:

1. `recorder dictate --daemon --prosody` can stay resident.
2. `recorder dictate trigger --paste` toggles capture and pastes into the
   focused app.
3. `recorder` meeting capture keeps writing playable audio and readable text.
4. Evals may fail a candidate, but they must not make the daily tool harder to
   use.

## Workstreams

### 1. Desktop Dictation Replacement

Consumer: the user's Meta-Space dictation flow into Codex and other text fields.

This is first because it is the actual replacement for SuperWhisper. The goal is
not a native app yet. The goal is a reliable daemon, hotkey trigger, paste path,
and observable state.

Gate:

- Existing Meta-Space muscle memory invokes `recorder dictate trigger --paste`.
- Warm p50 and p95 stop-to-paste latency are measured on 20 short dictations.
- Five real Codex prompts are dictated without manual transcript cleanup.
- Failure states are visible: daemon absent, mic permission denied, empty audio,
  model still loading, paste failed.

Reversibility: reversible. The shortcut can point back at SuperWhisper.

### 2. Quality Harness As Product Infrastructure

Consumer: every future model, prompt, UI, and calibration change.

The fixture work is the start. The next step is to make quality checks cheap
enough to run before changing recorder behavior.

Gate:

- `just check` or an equivalent repo command runs py_compile, unit evals, and
  the deterministic UI fixture.
- UI fixture captures desktop and mobile live/find/stopped screenshots.
- A tiny public audio smoke set runs fast enough for local pre-commit use.
- A slower eval command runs WER, polish A/B, hallucination, search recall, and
  diarization DER when explicitly requested.

Reversibility: reversible. This adds gates and fixtures, not product behavior.

### 3. ASR Model and Calibration Lane

Consumer: dictate and meeting transcript quality.

Stay on Parakeet-MLX until a candidate beats it on local evidence. Do not swap
models from ecosystem excitement alone. Compare candidates on the same corpus:
latency, WER, entity preservation, offline/live gap, memory, and failure modes.

Gate:

- Current Parakeet baseline is re-run and recorded.
- Candidate ASR produces JSON compatible with recorder or has an adapter.
- Candidate wins on at least one product metric without regressing the hotkey
  path: lower WER on real dictation, lower stop-to-paste latency, better named
  entities, or materially lower resource use.
- The old model remains selectable for one release window.

Reversibility: partially reversible. Model swaps are easy in code but expensive
in user trust.

### 4. Prosody Lanes

Consumer: downstream LLM responses to dictated text.

Keep lanes separate:

- Emphasis/arousal: live, cheap energy features, already opt-in.
- Hesitation/uncertainty: pause/disfluency features. Separate eval.
- Nonverbal events: laugh, sigh, breath, cough. Separate eval.
- Affect/valence: model lane only. Do not make it live default without proof.

Gate:

- Each lane has a public or personal validation set.
- Each lane has a tagger metric and a downstream A/B metric.
- A/B controls sampling noise with temp-0 responders or same-vs-same
  subtraction.
- Promotion means opt-in first. Default-on requires one week of real-use notes
  showing benefit exceeds annoyance.

Reversibility: reversible while opt-in, partially reversible once default-on.

### 5. Meeting Post-Processing

Consumer: after-meeting review and searchable meeting memory.

Do not spend more time tuning sherpa threshold defaults. The current evidence
says diarization identity assignment is the failure. The fork is whether to
replace the diarizer or demote speaker labels in the product.

Gate:

- Re-run AMI DER on the current baseline.
- Test one credible replacement, with pyannote Community-1 as the first
  candidate to evaluate: https://huggingface.co/pyannote/speaker-diarization-community-1.
- The replacement candidate installs locally, runs offline after setup, and has
  acceptable licensing/auth friction for a personal local recorder.
- If no local/offline candidate gets DER into a useful range, keep diarization
  behind a caveat and put effort into search, summaries, and transcript quality
  instead.

Reversibility: partially reversible. Output formats and user expectations
propagate.

### 6. Native Shell, Later

Consumer: macOS permissions, hotkey reliability, launch-at-login, menu bar
state, and future iPhone capture/control.

Swift is a shell around recorder first, not a transcription rewrite. It can own
the Mac-specific surface while recorder remains the engine.

Gate:

- CLI daemon replacement path works for at least one week.
- The remaining pain is platform integration, not ASR quality.
- A narrow Swift menu bar prototype can start/stop recorder, show state, and
  paste text without changing the backend.

Reversibility: partially reversible. A native wrapper creates packaging and
permission surface area.

## Phase Order

### Phase 0: Stabilize the Replacement Path

Do:

- Repoint Meta-Space to `recorder dictate trigger --paste`.
- Add a daemon status check and clearer trigger errors.
- Measure warm stop-to-paste latency and transcript quality on real short
  dictations.

Gate to Phase 1: the recorder hotkey is usable for normal Codex dictation for
one work session.

### Phase 1: Make Quality Repeatable

Do:

- Add the canonical local check command.
- Keep the UI fixture as a screenshot-producing gate.
- Add a tiny audio smoke corpus and record the baseline.

Gate to Phase 2: a future model/UI/prosody change can be judged with one command.

### Phase 2: Tune the Current Tool Before Swapping Models

Do:

- Calibrate `--prosody` false positives on real dictation.
- Tighten dictation failure states and latency reporting.
- Run Parakeet live/offline baseline on known clips.

Gate to Phase 3: the current tool's baseline is recorded, and any model swap has
a fair comparison target.

### Phase 3: Decide the Two Big Forks

Decision-required:

- ASR lane: stay Parakeet-MLX, add candidate adapters, or move to another local
  ASR stack.
- Diarization lane: replace with pyannote-style pipeline, demote labels, or
  keep current labels explicitly caveated.

Do not start model replacement work until the ASR gate is written. Do not start
more diarization tuning until the diarization fork is decided.

### Phase 4: Extend Prosody Only Where It Pays Rent

Do:

- Add one lane at a time: hesitation first, then nonverbal events, then
  affect/valence only if a model proves useful.
- Use EMOVOME as the first naturalistic affect validation candidate:
  https://arxiv.org/html/2403.02167v3.

Gate: each lane must pass tagger quality and downstream A/B before touching the
daily default.

### Phase 5: Native Shell

Do:

- Build a minimal macOS Swift menu bar wrapper around the existing daemon.
- Consider iPhone capture/control only after the Mac shell proves useful.

Gate: native shell fixes a real platform pain that the CLI/shortcut path cannot
fix cleanly.

## Decision Forks

### Fork A: Hotkey Integration

Options:

- Shortcuts repoint: fastest, keeps existing Meta-Space muscle memory.
- Karabiner/launchd wrapper: better automation, more config surface.
- Swift menu bar app: best platform fit, highest packaging cost.

Recommendation: Shortcuts now, Swift later only after a week of CLI replacement
use.

### Fork B: ASR Candidate Policy

Options:

- Stay on Parakeet-MLX until beaten.
- Add adapters for multiple local ASR candidates.
- Rewrite around a native Apple framework.

Recommendation: stay on Parakeet-MLX and require candidates to beat a recorded
baseline.

### Fork C: Diarization Product Stance

Options:

- Replace diarizer with pyannote-style pipeline.
- Keep diarization default-on but caveated.
- Default diarization off until quality improves.

Recommendation: evaluate one replacement, then either replace or demote. Do not
continue threshold tuning.

### Fork D: Prosody Default

Options:

- Keep `--prosody` opt-in.
- Enable emphasis tags by default for dictation.
- Add more tags before changing default.

Recommendation: keep opt-in until real-use false-positive notes justify default
promotion. Do not bundle more tags into the default decision.

### Fork E: Native App Boundary

Options:

- CLI plus shortcuts remains the product.
- Swift app wraps the daemon.
- Swift app absorbs inference.

Recommendation: Swift wrapper only. Do not absorb inference until the daemon API
is stable and the CLI path has proven insufficient.

## Backlog, Not Yet Phased

- A private ignored corpus of real dictations with manual notes.
- A promotion rule for private audio: recordings stay gitignored unless a short
  redacted clip is deliberately added as a fixture.
- Calibration report template for one-week `--prosody` use.
- Better summary hallucination reports for shared meeting notes.
- Search recall fixtures with known query/time anchors.
- Local dashboard/history for eval results.

## Stop Rules

- Stop prosody expansion if tags do not change downstream response substance
  above the calibrated noise floor.
- Stop diarization work if a replacement cannot beat the current AMI DER enough
  to become useful.
- Stop native-app work if CLI plus Shortcuts is reliable and the only remaining
  issues are ASR/model quality.
- Stop polish work if entity preservation regresses against raw ASR.
