#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for recorder markdown transcript rendering."""
from __future__ import annotations

import importlib.machinery
import importlib.util
from pathlib import Path


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def index_of(text: str, needle: str) -> int:
    idx = text.find(needle)
    assert idx >= 0, (needle, text)
    return idx


def main() -> int:
    rec = load_recorder()
    state = rec.TranscriptState({
        "name": "render-fixture",
        "started": "2026-06-20 10:00:00 EDT",
        "model": "fixture-model",
        "input": "fixture mic",
        "audio_file": "render-fixture.flac",
        "md_path": "/tmp/render-fixture.md",
    })
    state.append_finalized("The b", 1.0)
    state.append_finalized("ank phrase was noisy.", 2.0)
    state.add_marker(2.5, "[00:00:02] ★", user=True)
    state.append_finalized(" The next paragraph survives.", 3.0)
    state.replace_polished_window(
        0, 2,
        "The bank phrase was clean.",
        "The bank phrase was noisy.",
    )
    state.set_draft("still listening", 4.2, 5.8, peak_db=-30.0)

    md = rec.render_md(state)
    assert "name: render-fixture" in md, md
    assert "model: fixture-model" in md, md
    assert "The bank phrase was clean." in md, md
    assert "noisy" not in md, md
    assert "_…still listening_" in md, md

    first = index_of(md, "The bank phrase was clean.")
    mark = index_of(md, "### [00:00:02] ★")
    tail = index_of(md, "The next paragraph survives.")
    assert first < mark < tail, md

    state.set_status("stopped")
    stopped = rec.render_md(state, ended="2026-06-20 10:00:06 EDT")
    assert "_…still listening_" not in stopped, stopped
    assert "_Ended 2026-06-20 10:00:06 EDT" in stopped, stopped
    assert "00:00:05 wall" in stopped, stopped
    assert "00:00:04 audio" in stopped, stopped

    print("PASS: markdown rendering preserves polish, markers, and footer")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
