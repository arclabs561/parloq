#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Regression tests for recorder eval corpus path resolution."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
import tempfile
from pathlib import Path


RUN_EVAL = Path(__file__).resolve().parent / "run_eval.py"


def load_run_eval():
    loader = importlib.machinery.SourceFileLoader("run_eval_test", str(RUN_EVAL))
    spec = importlib.util.spec_from_loader("run_eval_test", loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    loader.exec_module(mod)
    return mod


def main() -> int:
    run_eval = load_run_eval()
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        corpus = root / "corpus.toml"
        corpus.write_text(
            "\n".join([
                "[[clips]]",
                'id = "rel"',
                'path = "audio/clip.flac"',
                "duration_s = 1.0",
                "speakers = 1",
                'ref_transcript = "refs/clip.txt"',
                'ref_rttm = ""',
                'notes = "relative path fixture"',
                "",
            ]),
            encoding="utf-8",
        )

        clips = run_eval.load_corpus(corpus_toml=corpus, corpus_dir=root)
        assert len(clips) == 1, clips
        clip = clips[0]
        assert clip.path == (root / "audio" / "clip.flac").resolve(), clip.path
        assert clip.ref_transcript == (root / "refs" / "clip.txt").resolve(), clip.ref_transcript
        assert clip.ref_rttm is None, clip.ref_rttm

    print("PASS: eval corpus paths resolve once against corpus dir")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
