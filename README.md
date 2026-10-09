# parloq

Local speech recorder and dictation tool.

Platform: macOS on Apple Silicon only (ASR runs on MLX through parakeet-mlx).

```sh
brew install ffmpeg uv
recorder/recorder dictate     # push-to-talk; transcript goes to the clipboard
recorder/recorder team-sync   # record a meeting with a live transcript page
```

`recorder/recorder` is a uv script that installs its own Python dependencies on
first run. See [recorder/README.md](recorder/README.md) for system-audio
capture, diarization, summaries, and the menu-bar client.

`recorder/` is the daily-driver tool: meeting capture, live transcription,
offline re-pass, diarization, summaries, search, and push-to-talk dictation.
`prosody-bench/`, `experiments/`, and `results/` are the evidence bench for deciding
which speech/prosody signals should graduate into recorder.

## Layout

- `recorder/`: local meeting recorder and dictation CLI.
- `macos/ParloqMenu/`: native menu-bar client for live in-field dictation.
- `examples/`: sample files for the dictation features (a starter vocab file).
- `experiments/`: self-contained PEP 723 uv scripts (`uv run experiments/<x>.py`).
- `prosody-bench/`: reusable evaluation scripts for prosody/tagging experiments.
- `results/`: captured outputs (text logs, JSON pairs). Tracked.
- `data/`: repo-local corpus roots. Large payloads are gitignored; manifests
  and sync scripts are tracked.
- `PROGRESS.md`: dated progress log.

## Running

Each script declares its own deps and runs standalone:

```
uv run experiments/ravdess_dim.py
```

Prosody experiment scripts fetch their public datasets as needed. Recorder eval
corpora are synced into `data/corpora/recorder/`; run
`data/corpora/recorder/scripts/sync.sh --help` for the available downloads and
private imports. Models pull from Hugging Face into `~/.cache/huggingface`.

Before changing recorder behavior, run:

```sh
just check
```
