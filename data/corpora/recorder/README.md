# Recorder Corpora

`recorder/evals/run_eval.py` defaults to this directory.

Tracked files:

- `corpus.toml`: default public ASR smoke corpus.
- `meeting-corpus.example.toml`: synthetic template for a local eval manifest.
- `private-import.example.toml`: synthetic template mapping local source files to
  neutral destination names under `private/`.
- `ami-corpus.toml`: public AMI diarization DER corpus.
- `extended-corpus.toml`: generated stress clips plus explicit manual entries.
- `scripts/sync.sh`: download, generate, and import corpus payloads.

Ignored files:

- audio under `librispeech/`, `ami/`, `extended/`, `meeting-trimmed/`, and
  similar payload directories.
- downloaded archives under `_downloads/`.
- local manifests, including `meeting-corpus.toml`, `multi-corpus.toml`,
  `multi-slice-corpus.toml`, and `private-import.toml`. Existing local manifests
  can still be passed to `run_eval.py`; keep their metadata off Git.
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

# prepare private import and eval configuration (edit these copies locally)
cp -n data/corpora/recorder/private-import.example.toml data/corpora/recorder/private-import.toml
cp -n data/corpora/recorder/meeting-corpus.example.toml data/corpora/recorder/meeting-corpus.toml

# import only the files explicitly listed in the local mapping (Python 3.11+)
PARLOQ_PRIVATE_RECORDINGS_DIR=/path/to/source \
PARLOQ_PRIVATE_IMPORT_MANIFEST=data/corpora/recorder/private-import.toml \
  data/corpora/recorder/scripts/sync.sh private-meetings
```

Then run evals from the repo root:

```sh
uv run recorder/evals/run_eval.py --skip-live
uv run recorder/evals/run_eval.py --corpus data/corpora/recorder/meeting-corpus.toml --skip-live
uv run recorder/evals/run_eval.py --mode diarize-der --corpus data/corpora/recorder/ami-corpus.toml
```
