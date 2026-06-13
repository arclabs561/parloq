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
- Next experiment options: (a) confirm energy survives level-normalization +
  test on naturalistic data (EMOVOME); (b) jump to the actual A/B — wire a
  minimal energy-based `[emphatic]`/`[flat]` tag and test if it changes Claude's
  responses (the real go/no-go); (c) revisit fork C (audio-LLM) for valence.
