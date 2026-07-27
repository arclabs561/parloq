#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for the native dictation JSON Lines protocol."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
from pathlib import Path


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec_protocol", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec_protocol", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def expect_protocol_error(rec, line: str, message: str) -> None:
    try:
        rec.DictateRequest.parse(line)
    except rec.DictateProtocolError as error:
        assert message in str(error), (line, error)
    else:
        raise AssertionError(f"accepted invalid request: {line}")


def main() -> int:
    rec = load_recorder()

    for command in ("status", "start", "stop", "cancel", "subscribe"):
        request = rec.DictateRequest.parse(json.dumps({
            "version": 1,
            "command": command,
        }))
        assert request.command.value == command

    expect_protocol_error(rec, "[]", "JSON object")
    expect_protocol_error(
        rec, '{"version":2,"command":"status"}', "protocol version")
    expect_protocol_error(
        rec, '{"version":1,"command":"toggle"}', "unsupported command")
    expect_protocol_error(rec, "{", "invalid JSON")

    event = rec.DictateEvent(
        rec.DictateEventType.TRANSCRIPT,
        rec.DictatePhase.RECORDING,
        7,
        session_id="session-1",
        text="Hello, café",
        finalized_text="Hello,",
        draft_text=" café",
        elapsed_seconds=1.25,
        input_peak_db=-18.5,
        input_spectrum_db=[
            -52.0, -41.0, -29.0, -18.5, -24.0,
            -35.0, -48.0, -60.0, -72.0,
        ],
        asr_seconds=0.4,
        device=":0",
        model="model/example",
        prosody_enabled=False,
        polish_enabled=True,
        chime_enabled=False,
        save_enabled=False,
        vocab_count=3,
        stream_interval_seconds=0.5,
        device_name="Studio Display Microphone",
        prosody_state="elevated",
        prosody_energy_z=1.4,
        prosody_baseline_count=8,
        prosody_rms_db=-24.5,
    )
    line = event.to_line()
    assert line.endswith(b"\n")
    body = json.loads(line)
    assert body == {
        "version": 1,
        "type": "transcript",
        "phase": "recording",
        "sequence": 7,
        "session_id": "session-1",
        "text": "Hello, café",
        "finalized_text": "Hello,",
        "draft_text": " café",
        "elapsed_seconds": 1.25,
        "input_peak_db": -18.5,
        "input_spectrum_db": [
            -52.0, -41.0, -29.0, -18.5, -24.0,
            -35.0, -48.0, -60.0, -72.0,
        ],
        "asr_seconds": 0.4,
        "device": ":0",
        "model": "model/example",
        "prosody_enabled": False,
        "polish_enabled": True,
        "chime_enabled": False,
        "save_enabled": False,
        "vocab_count": 3,
        "stream_interval_seconds": 0.5,
        "device_name": "Studio Display Microphone",
        "prosody_state": "elevated",
        "prosody_energy_z": 1.4,
        "prosody_baseline_count": 8,
        "prosody_rms_db": -24.5,
    }, body

    broker = rec.DictateEventBroker()
    subscriber = broker.subscribe()
    for sequence in range(70):
        broker.publish(rec.DictateEvent(
            rec.DictateEventType.TRANSCRIPT,
            rec.DictatePhase.RECORDING,
            sequence,
            text=str(sequence),
        ))
    snapshots = []
    while not subscriber.empty():
        snapshots.append(subscriber.get_nowait())
    broker.unsubscribe(subscriber)
    assert len(snapshots) == 64, len(snapshots)
    assert snapshots[-1].text == "69"
    assert snapshots[0].text == "6"

    capture_command = rec.build_dictate_ffmpeg_cmd(":0")
    assert capture_command[-1] == "pipe:1", capture_command
    assert "-c:a" in capture_command
    assert "flac" not in capture_command

    assert -26.1 < rec._peak_dbfs(
        rec.np.full(1_600, 0.05, dtype=rec.np.float32)
    ) < -25.9
    assert rec._peak_dbfs(rec.np.zeros(1_600, dtype=rec.np.float32)) == -120.0

    silence_spectrum = rec._spectrum_dbfs(
        rec.np.zeros(8_000, dtype=rec.np.float32)
    )
    assert silence_spectrum == [-120.0] * 9

    times = rec.np.arange(8_000, dtype=rec.np.float64) / rec.SAMPLE_RATE
    low_tone = (0.1 * rec.np.sin(2 * rec.np.pi * 220 * times)).astype(
        rec.np.float32
    )
    high_tone = (0.1 * rec.np.sin(2 * rec.np.pi * 2_000 * times)).astype(
        rec.np.float32
    )
    low_spectrum = rec._spectrum_dbfs(low_tone)
    high_spectrum = rec._spectrum_dbfs(high_tone)
    assert len(low_spectrum) == 9
    assert low_spectrum.index(max(low_spectrum)) < 4, low_spectrum
    assert high_spectrum.index(max(high_spectrum)) > 4, high_spectrum
    assert -20.2 < max(low_spectrum) < -19.8, low_spectrum
    assert -20.2 < max(high_spectrum) < -19.8, high_spectrum

    print("PASS: dictate JSONL protocol and bounded subscriber fan-out")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
