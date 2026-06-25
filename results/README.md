# results/

Run-artifacts from the prosody / paralinguistic eval bench. Each `*.json` is a
dated, immutable dump from one experiment run; the matching `*.txt` (no date) is
the human-readable summary printed at run time. These are evidence, not inputs:
no downstream code reads them, so deleting one loses a record of what was tested,
not a dependency.

## What each artifact is

| Artifact | Source | What it tested | Verdict |
|---|---|---|---|
| `separability_bench_*.{json,txt}` | `prosody-bench/separability_bench.py` | Can acoustic features separate RAVDESS arousal vs valence? | Arousal yes (`energy_std` AUC 0.89); valence ~chance (0.66). The one robust finding. |
| `prosody_features.txt` | `experiments/prosody_features.py` | Fork B: dependency-free energy/pitch/pause features. | Energy separates arousal. Basis for the shipped emphasis tag. |
| `ravdess_dim.txt` | `experiments/ravdess_dim.py` | Fork A: dimensional A/V model (audeering wav2vec2). | Per-emotion arousal/valence means; arousal separable. |
| `ravdess_ab_pairs_v1_noisy.json` | `experiments/ravdess_run.py` | SER-classifier path: predict an emotion tag per clip. | Negative. `pred_tag` agrees with the true label only 9/24 times. This is why the classifier path was dropped for acoustic features. The `_noisy` suffix is the point. |
| `ab_tag_response_*.{json,txt}` | `prosody-bench/ab_tag_response.py` | Do inline tags change LLM responses, zero-shot, across 6 models? | 100% "adapted" on the soft judge. Optimistic; the hard evals below deflate it. |
| `ab_hard_*.{json,txt}` | `prosody-bench/ab_tag_response_hard.py` | Same, strict judge + placebo + congruent/incongruent. | Effect falls to 36% substantive; placebo fires 28% (judge over-fires). |
| `ab_refine_*.json` (+ `_temp0`) | refine A/B | Effect net of a same-vs-same noise floor. | Code -12 pts, word -29 pts below the 50% floor. The headline effect is mostly noise. |
| `ab_disentangle_*.{json,txt}` | `prosody-bench/ab_disentangle.py` | Is the value the arousal dimension or the emotion word? | Arousal tag competitive (MVP ok); emotion-word semantics carry more, which an energy tagger can't produce. |

Read top to bottom the story is consistent: the soft eval looked like a 100%
effect and each harder control shrank it. The shipped emphasis tag rests on the
one robust finding (energy separates arousal, AUC ~0.89), not on the
response-change numbers.

## On the labels (read before trusting any of this)

`true_emotion` in the RAVDESS artifacts is decoded from the RAVDESS filename's
third field (`experiments/ravdess_run.py:42`). The decoding is correct. The
labels are still a weak basis for the live claim, and no relabeling fixes it:

- RAVDESS is *acted* emotion: actors portraying an emotion while reading one of
  two fixed sentences. Portrayed affect is a poor proxy for spontaneous
  conversational emphasis, which is the real target.
- The label space is lossy by construction: `calm` is folded into `neutral`, and
  fearful/disgust/surprised are forced into a 4-class model space
  (`experiments/ravdess_run.py:23,89`).

So: trust the decoding, distrust the corpus as evidence for live emphasis.

## Open gate: naturalistic validation (not yet run)

The roadmap names EMOVOME as the first naturalistic affect corpus
(`docs/design/parloq-recorder-roadmap.md:234`). Until the separability bench is
re-run against a spontaneous-speech corpus, the emphasis tag's validity rests
only on acted RAVDESS. That re-run is the next eval gate and has not been done.
