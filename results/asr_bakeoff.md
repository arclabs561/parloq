# ASR final-pass bake-off

## Hypotheses (written before the full run)

1. Clean read speech: no candidate beats `parakeet-tdt-0.6b-v3` by more than
   the paired-bootstrap interval. dev-clean is saturated for modern ASR.
2. Pink noise at 10 dB SNR: `Qwen3-ASR-1.7B` beats v3. This is the claim that
   can fail; an LLM decoder may hallucinate on noisy input instead.
3. `parakeet-tdt-0.6b-v2` is equivalent to v3 on English.

Adoption rule: change the recorder default only if a candidate's 95% interval
on the WER difference excludes zero in the noisy condition without a clean-
condition regression, and its real-time factor stays practical for a final pass.

## Method

`uv run experiments/asr_bakeoff.py --n 200 --seed 0`. 200 random dev-clean
utterances of 3-20 s from `data/corpora/recorder/_downloads/dev-clean.tar.gz`,
clean and with synthetic pink noise at 10 dB SNR. WER after the Whisper English
normalizer. Real-time factor includes model inference only (one warm-up
utterance excluded), measured while the dictation daemon was also running.

## Results

200 utterances, 24.4 min, 4,153 reference words. WER is on the Whisper English
normalizer; the interval is a paired bootstrap (2,000 resamples of utterances)
on WER(candidate) minus WER(`parakeet-v3`). Data: `results/asr_bakeoff.json`.

| Model | Clean WER | Noisy WER | dWER clean, 95% | dWER noisy, 95% | Real time |
|---|---|---|---|---|---|
| `parakeet-v3` (baseline) | 1.80% | 2.27% | n/a | n/a | 65x |
| `parakeet-v2` | 1.60% | 1.89% | -0.20pp [-0.62, +0.22] | -0.38pp [-0.88, +0.12] | 68x |
| `Qwen3-ASR-1.7B` (8-bit) | 1.51% | 1.84% | -0.30pp [-0.67, +0.07] | -0.42pp [-0.90, +0.05] | 23x |
| `whisper-large-v3-turbo` | 2.11% | 2.71% | +0.34pp [-0.03, +0.70] | +0.45pp [+0.07, +0.82] | 8x |

Real-time figures were measured while the dictation daemon and other jobs were
running, so read them as ratios, not absolutes.

## Conclusion

1. Held: no candidate separates from v3 on clean speech.
2. Not confirmed: Qwen3-ASR is nominally 0.42pp better in noise, but its
   interval includes zero (upper bound +0.05pp). The adoption rule is not met.
3. Held: v2 and v3 are equivalent on English.
4. Whisper turbo is worse in noise (the one interval that excludes zero) and 8x
   slower than real time here.

Power: at 4,153 words and ~2% WER the interval half-width is about 0.4pp. The
Open ASR Leaderboard gap between Qwen3-ASR-1.7B and v3 is about 0.5pp, so this
sample cannot confirm or rule out a real gap of that size. A decision to adopt
Qwen3-ASR needs more data, ideally conversational audio, not more of this
read-speech set. Decision: keep `parakeet-tdt-0.6b-v3` as the default.
