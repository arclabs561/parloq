#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for recorder search indexing and query fallback.

The test uses an isolated MEETING_DIR with tiny markdown transcripts so it never
reads or mutates the user's real recording index.
"""
from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import tempfile
from pathlib import Path


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def call_search(rec, args: list[str]) -> tuple[int, str, str]:
    out = io.StringIO()
    err = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = rec.cmd_search(args)
    return code, out.getvalue(), err.getvalue()


def write_transcript(path: Path, body: str) -> None:
    path.write_text(
        "\n".join([
            "---",
            "started: 2026-06-20 10:00:00",
            "---",
            "_Generated transcript metadata that should not be indexed._",
            "## Transcript",
            "",
            body,
            "",
        ]),
        encoding="utf-8",
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        os.environ["MEETING_DIR"] = str(root)
        rec = load_recorder()

        write_transcript(
            root / "alpha.md",
            "The live draft contains live-only text that offline indexing must skip.",
        )
        write_transcript(
            root / "alpha.offline.md",
            "The offline transcript contains the anchor budget phrase.\n\n"
            "Alice's budget? The punctuation fallback should still find this paragraph.",
        )
        write_transcript(
            root / "alpha.summary.md",
            "A summary-only phrase should not enter the full-text index.",
        )
        write_transcript(
            root / "beta.md",
            "The live fallback transcript mentions a fallback-only phrase.",
        )

        code, out, err = call_search(rec, ["--reindex"])
        assert code == 0, code
        assert out == "", out
        assert "indexed 3 paragraphs across 2 recordings" in err, err

        code, out, err = call_search(rec, ["anchor budget", "--limit", "5"])
        assert code == 0, (code, err)
        assert "alpha" in out, out
        assert "anchor" in out, out

        code, out, err = call_search(rec, ["fallback-only", "--limit", "5"])
        assert code == 0, (code, err)
        assert "beta" in out, out
        assert "fallback" in out, out

        code, out, err = call_search(rec, ["Alice's budget?", "--limit", "5"])
        assert code == 0, (code, out, err)
        assert "alpha" in out, out
        assert "Alice" in out, out

        code, out, err = call_search(rec, ["summary-only", "--limit", "5"])
        assert code == 1, (code, out, err)
        assert out == "", out
        assert "no results" in err, err

        code, out, err = call_search(rec, ["live-only", "--limit", "5"])
        assert code == 1, (code, out, err)
        assert out == "", out
        assert "no results" in err, err

    print("PASS: search indexes isolated live/offline transcripts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
