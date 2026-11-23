#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for recorder markdown transcript rendering."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import MagicMock, patch


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


def check_unattributed_first_turn(rec):
    sentences = [
        {"start": 0, "end": 1, "text": "Hello."},
        {"start": 1, "end": 2, "text": "Anyone there?"},
        {"start": 2, "end": 3, "text": "Yes."},
        {"start": 4, "end": 5, "text": "Thanks."},
    ]
    sherpa = MagicMock()
    result = sherpa.OfflineSpeakerDiarization.return_value.process.return_value
    result.sort_by_start_time.return_value = [SimpleNamespace(start=2, end=3, speaker=0)]
    soundfile = MagicMock()
    soundfile.read.return_value = (rec.np.zeros(16000), 16000)
    with (
        TemporaryDirectory() as tmp,
        patch.dict(sys.modules, {"sherpa_onnx": sherpa, "soundfile": soundfile}),
        patch.object(rec, "_ensure_diarize_models", return_value=("seg", "emb")),
    ):
        root = Path(tmp)
        offline = root / "sample.offline.json"
        offline.write_text(json.dumps({"sentences": sentences}))
        md = rec.run_diarize_pass(root / "sample.flac", offline, "sample")
        assert md is not None
        transcript = md.read_text().split("## Transcript\n\n", 1)[1].strip()
        assert transcript.split("\n\n") == [
            "**Speaker ?:** Hello. Anyone there?",
            "**Speaker 1:** Yes.",
            "**Speaker ?:** Thanks.",
        ], transcript
        sidecar = json.loads((root / "sample.diarized.json").read_text())
        assert sidecar["speakers_detected"] == 1
        assert sidecar["sentences"] == [
            {**s, "speaker": speaker} for s, speaker in zip(sentences, (None, None, 0, None))
        ]
        result.sort_by_start_time.return_value = []
        audio = root / "sample.flac"
        audio.touch()
        assert rec.cmd_diarize_cli([str(audio), "--force"]) == 0
        empty = json.loads((root / "sample.diarized.json").read_text())
        assert empty["speaker_spans"] == []
        assert empty["speakers_detected"] == 0
        assert empty["sentences"] == [{**s, "speaker": None} for s in sentences]
        assert "**Speaker ?:** Hello. Anyone there? Yes. Thanks." in md.read_text()


def main() -> int:
    rec = load_recorder()
    check_unattributed_first_turn(rec)
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
