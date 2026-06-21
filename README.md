# parloq

## Overview

Local speech recorder and dictation tool, with experiments that improve what
the recorder can capture from speech.

`recorder/` is the daily-driver tool: meeting capture, live transcription,
offline re-pass, diarization, summaries, search, and push-to-talk dictation.
`eval/`, `experiments/`, and `results/` are the evidence bench for deciding
which speech/prosody signals should graduate into recorder.

The current phase plan lives in
[`docs/design/parloq-recorder-roadmap.md`](docs/design/parloq-recorder-roadmap.md).
The older cross-session decision record remains in harness memory:
`~/.claude/projects/-Users-arc-Documents-dev/memory/paralinguistic-dictation-roadmap.md`.

## Layout

- `recorder/` — local meeting recorder and dictation CLI.
- `experiments/` — self-contained PEP 723 uv scripts (`uv run experiments/<x>.py`).
- `eval/` — reusable evaluation scripts for prosody/tagging experiments.
- `results/` — captured outputs (text logs, JSON pairs). Tracked.
- `data/` — datasets (gitignored; scripts download reproducibly to `/tmp` or here).
- `PROGRESS.md` — dated progress log.

## Running

Each script declares its own deps and runs standalone:

```
uv run experiments/ravdess_dim.py
```

Datasets are public and auto-downloaded by the scripts (RAVDESS from Zenodo).
Models pull from Hugging Face into `~/.cache/huggingface`.

Before changing recorder behavior, run:

```sh
just check
```
