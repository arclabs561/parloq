#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Regression tests for recorder eval report formatting."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
import tempfile
from pathlib import Path


RUN_EVAL = Path(__file__).resolve().parent / "run_eval.py"


def load_run_eval():
    loader = importlib.machinery.SourceFileLoader("run_eval_test_report", str(RUN_EVAL))
    spec = importlib.util.spec_from_loader("run_eval_test_report", loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    loader.exec_module(mod)
    return mod


def main() -> int:
    run_eval = load_run_eval()
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
        )
        text = output.read_text(encoding="utf-8")

    assert text.endswith("- none\n"), repr(text[-40:])
    assert not text.endswith("\n\n"), repr(text[-40:])
    print("PASS: eval report formatting is explicit and diff-check clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
