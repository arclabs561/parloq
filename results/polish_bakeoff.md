# Polish model bake-off

## Hypotheses (written before the run)

1. `gemma4:e2b` (current default) already follows the polish prompt's explicit
   rules on most cases, so no candidate shows a gain larger than the
   run-to-run flip rate of the same model.
2. A larger model (`gemma4:12b`) follows "do not reformat numbers" and "leave
   mid-sentence fillers" better than e2b. This can fail: larger models tend to
   improve text they were told to leave alone.
3. `granite4.2:3b` is the fastest candidate and stays within noise of e2b on
   rule-following.

4. (added after the edits-path run, before the next run) `gemma4:e2b`'s
   failures on the edits path are mostly corrupted output such as `nothin,g`,
   `iI`, `butbut`, produced when `apply_edits` matches an anchor inside a
   longer word. Requiring word-boundary matches in `_find_after` raises e2b's
   edits-path pass rate by at least 5pp with no category regressing. This can
   fail if the corruption comes from the model's own edit text instead.

5. (added after the word-boundary run, before the next run) Word-boundary
   matching raised e2b's edits-path pass rate from 70.4% to 74.4%, short of the
   +5pp predicted in 4. The remaining corruption comes from the model's own SUB
   edits (`butbut`, `evidentlyevidently`, a phrase repeated, a word dropped),
   which `apply_edits` applies although the prompt forbids them. Rejecting a
   SUB that changes more than leading fillers or one near-homophone word raises
   e2b's pass rate by at least 5pp over 74.4% without lowering the
   initial_filler or numbers categories.

Adoption rule: change the default only if the candidate's paired-bootstrap 95%
interval on the pass-rate difference excludes zero in its favour AND its median
latency is at most 1.5x the baseline's. Dictation is latency-sensitive.

## Correction made before the final runs

The first full run measured only the whole-text rewrite path
(`POLISH_SYSTEM_PROMPT`, used by `recorder polish`). Dictation does not use it:
the daemon's `_polish` sends `STREAMING_POLISH_PROMPT`, which returns
SUB/INS_AFTER/CAP edit lines applied by `apply_edits`. The script now has
`--path edits|rewrite` and a fifth category, `punct_cap` (a sentence start is
capitalized and the text ends with `.`, `?` or `!`), which the prompts promise.
The hypotheses and the adoption rule are unchanged and apply per path. The
aborted first run (rewrite path, five models, no `punct_cap`) is not reported.
`lfm2.5:8b` was dropped after it made no progress for over ten minutes on
the rewrite path (cause not investigated).

## What this measures, and what it does not

The cases are generated from the prompt's own rules (`POLISH_SYSTEM_PROMPT` in
`recorder/recorder`), not from model output: sentence-initial filler removal,
mid-sentence filler retention, exact preservation of number and time tokens,
word-level fidelity on unpunctuated input, and output format (no preamble,
quotes, or fences). It measures rule-following and speed. It does not measure
whether the added punctuation and capitalization are good; there is no cased,
punctuated gold text in the repo's corpora to score that against.

## Method

`uv run experiments/polish_bakeoff.py --path edits` and `--path rewrite`. 125
cases (25 per category) built from LibriSpeech dev-clean reference text (seed
0), one call each at temperature 0 through the recorder's own `ollama_chat`,
plus a second baseline run to estimate the model's own flip rate.

## Results

125 cases per run (25 per category), temperature 0. Baseline `gemma4:e2b` run
twice per file: the flip rate was 0.0% every time, so the intervals below are
case-sampling noise only (paired bootstrap, 5,000 resamples). Latency is the
median per call on this machine while other jobs ran; read it as a ratio.

### Dictation path (`--path edits`), before the `apply_edits` guards

File: `polish_bakeoff_edits.json`.

| Model | Pass | vs e2b (95%) | Latency |
|---|---|---|---|
| `gemma4:e2b` (default) | 70.4% | n/a | 1.0x (0.80 s) |
| `granite4.2:3b` | 72.0% | [-8.8, +12.0] within noise | 1.0x |
| `gemma4:12b` | 60.0% | [-20.8, +0.8] within noise | 4.0x |
| `gemma4:latest` | 46.4% | [-34.4, -13.6] worse | 1.3x |
| `granite4.2:8b` | 43.2% | [-36.8, -17.6] worse | 1.5x |

No candidate beat the default. Hypothesis 1 held.

### After the guards (hypotheses 4 and 5)

Files: `polish_bakeoff_edits_wordboundary.json`,
`polish_bakeoff_edits_subguard.json`, `polish_bakeoff_edits_subguard_all.json`.

| Model | Pass, no guard | + word boundaries | + SUB guard | vs e2b after guards (95%) | Latency |
|---|---|---|---|---|---|
| `gemma4:e2b` | 70.4% | 74.4% | 87.2% | n/a | 1.0x |
| `gemma4:12b` | 60.0% | not run | 89.6% | [-4.8, +9.6] within noise | 3.6x |
| `gemma4:latest` | 46.4% | not run | 70.4% | [-24.8, -8.8] worse | 1.3x |
| `granite4.2:3b` | 72.0% | 72.0% | 76.8% | [-18.4, -1.6] worse | 1.0x |

Hypothesis 4 (word boundaries alone, at least +5pp) did not hold: +4.0pp.
Hypothesis 5 (SUB guard, at least +5pp over 74.4% with no category lost) held:
+12.8pp; initial_filler 80 to 100, numbers 88 to 100, mid_filler 60 to 84;
punct_cap moved 64 to 60 (one case in 25). The guards also closed the gap to
`gemma4:12b`: before them the ranking read "e2b clearly ahead of 12b", after
them the two are within noise at 3.6x the latency. Most of the earlier spread
between models was bad edits that `apply_edits` accepted, not model quality.

Circularity: the checker and the guard both enforce the prompt's rules. The
result shows the guard enforces them. It does not show the polished text reads
better. The cases contain no multi-word homophone fixes, so the rate at which
the SUB guard rejects legitimate edits is unmeasured.

### Transcript path (`--path rewrite`, `recorder polish`)

File: `polish_bakeoff_rewrite.json`. The repo has no guard on this path; the
model's whole output is used.

| Model | Pass | vs e2b (95%) | Latency |
|---|---|---|---|
| `gemma4:e2b` | 64.8% | n/a | 1.0x (0.49 s) |
| `gemma4:12b` | 92.8% | [+20.0, +36.0] better | 4.7x |
| `gemma4:latest` (current `recorder polish` default) | 78.4% | [+5.6, +21.6] better | 1.8x |
| `granite4.2:8b` | 72.8% | [-0.8, +16.8] within noise | 1.6x |
| `granite4.2:3b` | 60.0% | [-16.0, +5.6] within noise | 0.7x |

The intervals are against e2b, which is not this command's default, so
`gemma4:12b` against `gemma4:latest` has no paired interval; the unpaired gap is
14.4pp. The pre-registered adoption rule (latency at most 1.5x the baseline)
was written for dictation and is not met by 12b here (4.7x). `recorder polish`
is an offline command where that latency matters little, so whether to move its
default from `gemma4:latest` to `gemma4:12b` is left as a decision rather than
applied.

## Conclusions

1. Keep `gemma4:e2b` as the dictation polish model. No candidate beats it,
   before or after the guards.
2. The bigger finding is a code defect, not a model choice: `apply_edits`
   accepted edits the prompt forbids. Fixed in `recorder` (word-boundary
   anchors and a SUB content-preservation guard), with tests.
3. `lfm2.5:8b` made no progress on the rewrite path for over ten minutes and
   was dropped without investigation; it is untested, not rejected.
4. Not measured: polish quality as a reader would judge it, any multi-word
   homophone correction, and meeting-length inputs (the cases are single
   utterances of 3 to 20 seconds).
