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
import stat
import tempfile
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

    for command in (
        "status", "devices", "start", "stop", "cancel", "subscribe",
    ):
        request = rec.DictateRequest.parse(json.dumps({
            "version": 1,
            "command": command,
        }))
        assert request.command.value == command

    configure = rec.DictateRequest.parse(json.dumps({
        "version": 1,
        "command": "configure",
        "settings": {
            "device": {
                "id": ":2",
                "name": "Studio Display Microphone",
            },
        },
    }))
    assert configure.command == rec.DictateCommand.CONFIGURE
    assert configure.device.identifier == ":2"
    assert configure.device.name == "Studio Display Microphone"

    save_configure = rec.DictateRequest.parse(json.dumps({
        "version": 1,
        "command": "configure",
        "settings": {"save_recordings": True},
    }))
    assert save_configure.command == rec.DictateCommand.CONFIGURE
    assert save_configure.device is None
    assert save_configure.save_recordings is True

    expect_protocol_error(rec, "[]", "JSON object")
    expect_protocol_error(
        rec, '{"version":2,"command":"status"}', "protocol version")
    expect_protocol_error(
        rec, '{"version":1,"command":"toggle"}', "unsupported command")
    expect_protocol_error(rec, "{", "invalid JSON")
    expect_protocol_error(
        rec,
        '{"version":1,"command":"status","settings":{}}',
        "cannot contain settings",
    )
    expect_protocol_error(
        rec,
        '{"version":1,"command":"configure","settings":{}}',
        "exactly one setting",
    )
    expect_protocol_error(
        rec,
        json.dumps({
            "version": 1,
            "command": "configure",
            "settings": {"device": {"id": "2", "name": "Mic"}},
        }),
        "AVFoundation audio index",
    )
    expect_protocol_error(
        rec,
        json.dumps({
            "version": 1,
            "command": "configure",
            "settings": {"device": {"id": ":2", "name": ""}},
        }),
        "non-empty",
    )
    expect_protocol_error(
        rec,
        json.dumps({
            "version": 1,
            "command": "configure",
            "settings": {"save_recordings": "yes"},
        }),
        "true or false",
    )

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
        recordings_path="/tmp/recordings",
        vocab_count=3,
        vocab_path="/tmp/example-vocab.txt",
        vocab_warning="example vocab warning",
        stream_interval_seconds=0.5,
        device_name="Studio Display Microphone",
        device_available=True,
        available_devices=[
            rec.DictationDevice(":0", "MacBook Pro Microphone"),
            rec.DictationDevice(":2", "Studio Display Microphone"),
        ],
        configuration_warning="example warning",
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
        "recordings_path": "/tmp/recordings",
        "vocab_count": 3,
        "vocab_path": "/tmp/example-vocab.txt",
        "vocab_warning": "example vocab warning",
        "stream_interval_seconds": 0.5,
        "device_name": "Studio Display Microphone",
        "device_available": True,
        "available_devices": [
            {"id": ":0", "name": "MacBook Pro Microphone"},
            {"id": ":2", "name": "Studio Display Microphone"},
        ],
        "configuration_warning": "example warning",
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

    original_devices = rec.avfoundation_devices
    rec.avfoundation_devices = lambda: [
        ("0", "Studio Display Microphone"),
    ]
    try:
        assert rec.device_name(":0") == "Studio Display Microphone"
        assert rec.device_name(":7") == ":7"
        assert rec.device_name("Custom Input") == "Custom Input"
    finally:
        rec.avfoundation_devices = original_devices

    saved = rec.DictationDevice(":7", "Studio Display Microphone")
    resolved, warning = rec._resolve_saved_dictation_device(
        saved,
        [
            rec.DictationDevice(":0", "MacBook Pro Microphone"),
            rec.DictationDevice(":2", "Studio Display Microphone"),
        ],
    )
    assert warning is None
    assert resolved.identifier == ":2"
    assert resolved.name == saved.name

    resolved, warning = rec._resolve_saved_dictation_device(
        saved,
        [rec.DictationDevice(":0", "MacBook Pro Microphone")],
    )
    assert resolved is None
    assert "not connected" in warning

    resolved, warning = rec._resolve_saved_dictation_device(
        saved,
        [
            rec.DictationDevice(":1", saved.name),
            rec.DictationDevice(":2", saved.name),
        ],
    )
    assert resolved is None
    assert "Multiple microphones" in warning

    with tempfile.TemporaryDirectory() as temporary_directory:
        config_path = Path(temporary_directory) / "Parloq" / "config.json"
        config = rec.DictationRuntimeConfig(
            device=saved,
            save_recordings=True,
        )
        rec._write_dictate_runtime_config(config_path, config)
        loaded, warning = rec._load_dictate_runtime_config(config_path)
        assert warning is None
        assert loaded.device.identifier == saved.identifier
        assert loaded.device.name == saved.name
        assert loaded.save_recordings is True
        assert stat.S_IMODE(config_path.stat().st_mode) == 0o600

        config_path.write_text('{"version":2}\n', encoding="utf-8")
        loaded, warning = rec._load_dictate_runtime_config(config_path)
        assert loaded.device is None
        assert loaded.save_recordings is None
        assert "unsupported format" in warning

    print("PASS: dictate JSONL protocol and bounded subscriber fan-out")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
