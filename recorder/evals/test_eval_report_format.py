#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Regression tests for recorder eval report formatting."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import json
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


RUN_EVAL = Path(__file__).resolve().parent / "run_eval.py"


def load_run_eval():
    loader = importlib.machinery.SourceFileLoader("run_eval_test_report", str(RUN_EVAL))
    spec = importlib.util.spec_from_loader("run_eval_test_report", loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    loader.exec_module(mod)
    return mod


def check_diarizer_speaker_count(run_eval):
    # Only speaker 0 had the largest overlap with an ASR sentence. The acoustic
    # timeline also contains speaker 3; both speakers contribute to the DER.
    sidecar = {
        "speakers_detected": 1,
        "speaker_spans": [
            {"start": 0, "end": 3, "speaker": 0},
            {"start": 3, "end": 4, "speaker": 3},
            {"start": 4, "end": 5, "speaker": 0},
        ],
    }
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        audio = root / "test.flac"
        audio.touch()
        (root / "test.offline.json").write_text("{}")
        (root / "test.diarized.json").write_text(json.dumps(sidecar))
        corpus = root / "corpus.toml"
        corpus.write_text(
            f'[[clips]]\nid = "meeting"\nspeakers = 2\npath = "{audio}"\n'
            f'ref_rttm = "{root / "test.rttm"}"\n'
        )
        output = io.StringIO()
        with (
            patch.object(run_eval.subprocess, "run") as recorder,
            patch.object(run_eval, "compute_der", return_value=0.0),
            redirect_stdout(output),
        ):
            recorder.return_value.returncode = 0
            assert run_eval.cmd_diarize_der(corpus) == 0
            assert run_eval.cmd_diarize_stability(audio, runs=1) == 0
        (root / "test.diarized.json").write_text(json.dumps({"speaker_spans": []}))
        output_empty = io.StringIO()
        with (
            patch.object(run_eval.subprocess, "run") as recorder,
            patch.object(run_eval, "compute_der", return_value=1.0) as score,
            redirect_stdout(output_empty),
        ):
            recorder.return_value.returncode = 0
            assert run_eval.cmd_diarize_der(corpus) == 0
            score.assert_called_once_with([], root / "test.rttm")
            assert "mean DER: 100.0%  (n=1" in output_empty.getvalue()
            (root / "test.diarized.json").write_text("{}")
            score.reset_mock()
            assert run_eval.cmd_diarize_der(corpus) == 1
            score.assert_not_called()

        rows = [line.split() for line in output.getvalue().splitlines()]
        assert ["meeting", "2", "2", "0.0%"] in rows, rows
        assert any(row[:4] == ["run", "1:", "2", "speakers,"] for row in rows), rows


def main() -> int:
    run_eval = load_run_eval()
    check_diarizer_speaker_count(run_eval)
    with tempfile.TemporaryDirectory() as td:
        output = Path(td) / "results.md"
        run_eval.write_report(
            [
                run_eval.EvalResult(
                    clip_id="clean",
                    duration_s=1.0,
                    offline_wer=0.0,
                )
            ],
            output,
            corpus_toml=Path("data/corpora/recorder/corpus.toml"),
            clip_filter="clean",
            skip_live=True,
        )
        text = output.read_text(encoding="utf-8")

    assert "- corpus: `data/corpora/recorder/corpus.toml`" in text
    assert "- clips: `clean`" in text
    assert "- live pass: skipped" in text
    assert text.endswith("- none\n"), repr(text[-40:])
    assert not text.endswith("\n\n"), repr(text[-40:])
    print("PASS: eval report formatting is explicit and diff-check clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
