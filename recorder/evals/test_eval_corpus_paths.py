#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Regression tests for recorder eval corpus path resolution."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import tomllib

RUN_EVAL = Path(__file__).resolve().parent / "run_eval.py"


def load_run_eval():
    loader = importlib.machinery.SourceFileLoader("run_eval_test", str(RUN_EVAL))
    spec = importlib.util.spec_from_loader("run_eval_test", loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    loader.exec_module(mod)
    return mod


def check_private_import() -> None:
    repo = RUN_EVAL.parents[2]
    script = repo / "data/corpora/recorder/scripts/sync.sh"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source = root / "input with spaces"
        source.mkdir()
        (source / "unrelated name.flac").write_bytes(b"synthetic audio fixture")
        (source / "reference.txt").write_text("synthetic reference")
        manifest = root / "mapping.toml"
        manifest.write_text(
            '[[files]]\nsource = "unrelated name.flac"\ndestination = "sample.flac"\n'
            '[[files]]\nsource = "reference.txt"\ndestination = "sample.txt"\n'
        )
        corpus = root / "corpus"
        env = {**os.environ, "PARLOQ_RECORDER_CORPUS_DIR": str(corpus)}
        command = ["bash", str(script), "private-meetings", str(source), str(manifest)]
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=False
        )
        assert result.returncode == 0, result.stderr
        assert (
            corpus / "private/sample.flac"
        ).read_bytes() == b"synthetic audio fixture"
        assert (corpus / "private/sample.txt").read_text() == "synthetic reference"
        assert (corpus / "private/sample.txt").stat().st_mode & 0o777 == 0o600
        template = repo / "data/corpora/recorder/meeting-corpus.example.toml"
        clips = load_run_eval().load_corpus(corpus_toml=template, corpus_dir=corpus)
        assert clips[0].path == (corpus / "private/sample.flac").resolve()
        assert clips[0].ref_transcript == (corpus / "private/sample.txt").resolve()

        manifest.write_text(
            '[[files]]\nsource = "absent.flac"\ndestination = "missing.flac"\n'
        )
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=False
        )
        assert result.returncode != 0 and "missing" in result.stderr, result.stderr
        manifest.write_text(
            '[[files]]\nsource = "reference.txt"\ndestination = "../../escape.txt"\n'
        )
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=False
        )
        assert result.returncode != 0 and "within" in result.stderr, result.stderr
        assert not (root / "escape.txt").exists()

    corpus_root = repo / "data/corpora/recorder"
    for name in ("corpus.toml", "ami-corpus.toml", "extended-corpus.toml"):
        with (corpus_root / name).open("rb") as stream:
            assert tomllib.load(stream)["clips"], name
    # Local mappings and arbitrary new TOML manifests stay ignored; public
    # fixtures remain addable. --no-index also works before tracked migration.
    for name in (
        "meeting-corpus.toml",
        "multi-corpus.toml",
        "multi-slice-corpus.toml",
        "private-import.toml",
        "new-personal-corpus.toml",
    ):
        result = subprocess.run(
            ["git", "check-ignore", "--no-index", "-q", str(corpus_root / name)],
            cwd=repo,
            check=False,
        )
        assert result.returncode == 0, name
    for name in (
        "corpus.toml",
        "ami-corpus.toml",
        "extended-corpus.toml",
        "meeting-corpus.example.toml",
        "private-import.example.toml",
    ):
        result = subprocess.run(
            ["git", "check-ignore", "--no-index", "-q", str(corpus_root / name)],
            cwd=repo,
            check=False,
        )
        assert result.returncode == 1, name
    print("PASS: caller-defined private import and public corpus boundary")


def main() -> int:
    check_private_import()
    run_eval = load_run_eval()
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        corpus = root / "corpus.toml"
        corpus.write_text(
            "\n".join(
                [
                    "[[clips]]",
                    'id = "rel"',
                    'path = "audio/clip.flac"',
                    "duration_s = 1.0",
                    "speakers = 1",
                    'ref_transcript = "refs/clip.txt"',
                    'ref_rttm = ""',
                    'notes = "relative path fixture"',
                    "",
                ]
            ),
            encoding="utf-8",
        )

        clips = run_eval.load_corpus(corpus_toml=corpus, corpus_dir=root)
        assert len(clips) == 1, clips
        clip = clips[0]
        assert clip.path == (root / "audio" / "clip.flac").resolve(), clip.path
        assert clip.ref_transcript == (root / "refs" / "clip.txt").resolve(), (
            clip.ref_transcript
        )
        assert clip.ref_rttm is None, clip.ref_rttm

    print("PASS: eval corpus paths resolve once against corpus dir")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
