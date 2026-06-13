# prosody

## Overview

Experiments toward paralinguistic-aware dictation: tagging a speech transcript
with how something was said (emphasis, hesitation, affect, breath/laughter), so
a downstream LLM sees the prosodic channel that ASR normally discards. The
motivating use case is dictation into Claude Code, where Superwhisper (closed,
Whisper-family) strips exactly that channel. The modifiable vehicle is the
user's own `recorder dictate` daemon (`~/Documents/dev/toolbox/recorder`); this
repo is the experiment bench that decides whether the channel is worth wiring
in before touching that daily driver.

This is a research bench, not a shipped tool. The cross-session decision record
and phase plan live in harness memory:
`~/.claude/projects/-Users-arc-Documents-dev/memory/paralinguistic-dictation-roadmap.md`.

## Layout

- `experiments/` — self-contained PEP 723 uv scripts (`uv run experiments/<x>.py`).
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
