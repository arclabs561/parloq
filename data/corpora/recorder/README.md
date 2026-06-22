# Recorder Corpora

`recorder/evals/run_eval.py` defaults to this directory.

Tracked files:

- `corpus.toml`: default public ASR smoke corpus.
- `multi-corpus.toml`: public ASR clips plus imported meeting clips when present.
- `multi-slice-corpus.toml`: imported private meeting slices.
- `meeting-corpus.toml`: imported private meeting clips.
- `ami-corpus.toml`: public AMI diarization DER corpus.
- `extended-corpus.toml`: generated stress clips plus explicit manual entries.
- `scripts/sync.sh`: download, generate, and import corpus payloads.

Ignored files:

- audio under `librispeech/`, `ami/`, `extended/`, `meeting-trimmed/`, and
  similar payload directories.
- downloaded archives under `_downloads/`.
- generated recorder outputs such as `.offline.*`, `.diarized.*`, and summaries.

Common commands:

```sh
# public ASR smoke corpus, enough for a fast real WER eval
data/corpora/recorder/scripts/sync.sh librispeech

# AMI diarization corpus, enough for DER evals
data/corpora/recorder/scripts/sync.sh ami

# generated stress clips derived from the LibriSpeech smoke clip
data/corpora/recorder/scripts/sync.sh extended-generated

# optional long-form public-domain audiobook clip; Archive.org can return 503
data/corpora/recorder/scripts/sync.sh librivox

# copy private meeting eval files into this repo-local corpus tree
PARLOQ_PRIVATE_RECORDINGS_DIR=/path/to/source \
  data/corpora/recorder/scripts/sync.sh private-meetings
```

Then run evals from the repo root:

```sh
uv run recorder/evals/run_eval.py --skip-live
uv run recorder/evals/run_eval.py --corpus data/corpora/recorder/multi-corpus.toml --skip-live
uv run recorder/evals/run_eval.py --mode diarize-der --corpus data/corpora/recorder/ami-corpus.toml
```
