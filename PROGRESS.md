# Progress log

Decision record + phase plan: `~/.claude/projects/-Users-arc-Documents-dev/memory/paralinguistic-dictation-roadmap.md`

## 2026-06-13

Session origin: question about phonetic/prosodic notation -> can STT capture the
paralinguistic channel and can an LLM use it. Grounded in research (CP-Bench,
NVSpeech, Qwen3-Omni, Parakeet) and recorder/anno/engram code.

Done:
- Roadmap written (harness memory). Validation-first: prove the channel changes
  Claude's responses before editing the `recorder dictate` daily driver.
- Phase-1 latency/mechanism gate PASSED via `experiments/ser_probe.py`:
  `superb/wav2vec2-base-superb-er` runs on-device, 66ms/clip. Latency fine.
- Phase-1 ACCURACY gate FAILED via `experiments/ravdess_run.py` on 1440 RAVDESS
  clips: 41.7% on 4 shared classes, collapses toward "angry" (ang 97%, hap 15%,
  sad 7%). This categorical IEMOCAP model is unfit on real prosody.
  -> `results/ravdess_ab_pairs_v1_noisy.json` (NOT usable; tags are wrong).
- Dataset survey done (see roadmap): RAVDESS/CREMA-D/ESD for A/B (parallel
  content), DisfluencySpeech (hesitation), VocalSound (breath/laugh). Gaps:
  conversational breathiness + emphasis poorly covered publicly.

- Fork A (dimensional audeering model) BLOCKED: `experiments/ravdess_dim.py`
  fails to load under current transformers (`all_tied_weights_keys` refactor;
  the audeering custom-class recipe is stale). Using it would require a pinned
  transformers or the ONNX export. Not pursued — model frame already suspect.
- Fork B VALIDATED: `experiments/prosody_features.py` (librosa only, no model)
  on 320 RAVDESS clips. Energy features separate high/low arousal:
  rms_std AUC=0.893, rms_mean AUC=0.884. Pitch weaker (f0_std 0.62, f0_range
  0.60); pause_ratio no signal (0.57, but RAVDESS acted fixed-sentence speech is
  the wrong test for hesitation). -> `results/prosody_features.txt`.

Verdict: the "emphasis/intensity" axis is recoverable from raw energy with NO
model and no fragile dep — the robust foundation. Caveats: (1) arousal only,
energy can't tell angry from happy (no valence); (2) absolute RMS is mic/level
sensitive, real dictation needs per-utterance normalization.

Open fork (user to steer):
- B is the path for emphasis/intensity tags. Affect-valence would need a model
  (deferred, and the categorical one failed).
### Evals built (reusable, not one-off)

- `eval/separability_bench.py` — tagger x dataset -> per-dimension AUC + latency.
  Pluggable tagger registry. Confirms: energy_std AUC 0.893 (arousal), valence
  0.66 even with logreg over all features. `energy_std` alone beats 5-feature
  logreg (0.845) -> one feature, not a model.
- `eval/ab_tag_response.py` — cross-model A/B via OpenRouter (6-model panel).
  Does an inline prosody tag change the reply? NAIVE (no tag explanation).

### A/B RESULT (the go/no-go): downstream WORKS

100% ADAPTED across all 6 models (gpt-4o-mini, claude-3.5-haiku, llama-3.3-70b,
mistral-small, qwen-2.5-72b, deepseek-v3.1), zero-shot, no tag explanation.
Inspected raw pairs (not just judge): genuine + tone-appropriate. Best case:
qwen on [uncertain] flips from "Agreed, let's plan the update" to "Could you
share what issues you're seeing?" — untagged would send the user down a rewrite
they only tentatively proposed. [frustrated] reliably adds empathy + concision.
-> `results/ab_tag_response_2026-06-13.json`.

Caveat: tests EXPLICIT English tags, so it proves the *consumer* uses correct
tags; it does not prove signal-derived tags are producible. That's the clean
decomposition below.

### Synthesis across all evidence

- Downstream (do LLMs use inline tags): YES, 100%, genuine, all models. Bottleneck
  is NOT the LLM (CP-Bench lexical-shortcut did not bite for inline text tags).
- Tagger / arousal (emphasis): cheap energy works, AUC 0.89, no model.
- Tagger / valence (affect): cheap features fail (0.66); categorical model fails
  (42%). Needs an audio-LLM (fork C) or a better SER model.
- => End-to-end MVP is viable NOW for the EMPHASIS/AROUSAL dimension: energy tag
  is producible AND LLMs use it. Richer affect (frustrated/uncertain) clearly
  helps downstream but isn't cheaply producible yet -> fork C territory.

### Next forks (user to steer)
- (a) Build the emphasis MVP into recorder dictate (energy -> [emphatic]/[flat]).
- (b) Pursue fork C (audio-LLM, e.g. Qwen3-Omni) for the richer affect tags the
  A/B showed pay off but cheap features can't produce.
- (c) Harden the tagger eval: level-normalization + naturalistic data (EMOVOME),
  and add the "informed" A/B condition (system prompt explains tags).

### Refinement arc (harder evals) — METHODOLOGY ARTIFACT found + calibrated result

The "make it harder" pushes uncovered that single-sample A/B judging is dominated
by LLM sampling noise; the headline number swung wildly with measurement setup:

| eval | noise control | result |
|---|---|---|
| soft (`ab_tag_response`) | none, lenient judge | 100% ADAPTED (inflated) |
| hard (`ab_tag_response_hard`) | placebo tag, strict 3-way judge | placebo floor ~28%; coded tags BELOW it |
| refine temp 0.7 (`ab_tag_refine`) | same-vs-same resample | noise floor 50%(!); code -12pts, word -29pts |
| refine temp 0 | same-vs-same, deterministic | noise floor 12%; code +17pts, word +12pts |

Lesson: ANY A/B here must control sampling noise (temp 0 responders OR same-vs-same
subtraction). Without it you can "prove" 100% or "prove" zero from the same setup.

CALIBRATED FINDING (temp 0, the clean causal measurement): arousal tags DO change
response substance, modestly — code +17pts, word +12pts above a 12% floor, on
NEUTRAL task sentences. Most non-substantive cases are COSMETIC tone-matching
(67-75%). So the effect is real but modest for task-oriented dictation; the larger
effects in the soft/hard evals came from affect-laden sentences where an emotion
WORD carried semantic content, not from prosody per se.

VERDICT (revised): the channel has real-but-modest value for task dictation
(~1 in 6 cases substantively change + tone-matching in most others), NOT the
100% slam-dunk. The build-or-not decision now rests on whether modest+cosmetic
is worth the recorder-integration cost — a judgment call for the user, on solid
evidence. Open: re-measure affect tags on neutral sentences at temp 0 to fully
disentangle word-semantics from prosody-dimension; test on naturalistic data.
