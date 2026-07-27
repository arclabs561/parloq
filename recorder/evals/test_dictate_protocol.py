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
        asr_seconds=0.4,
        device=":0",
        model="model/example",
        prosody_enabled=False,
        polish_enabled=True,
        chime_enabled=False,
        save_enabled=False,
        vocab_count=3,
        stream_interval_seconds=0.5,
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
        "asr_seconds": 0.4,
        "device": ":0",
        "model": "model/example",
        "prosody_enabled": False,
        "polish_enabled": True,
        "chime_enabled": False,
        "save_enabled": False,
        "vocab_count": 3,
        "stream_interval_seconds": 0.5,
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

    print("PASS: dictate JSONL protocol and bounded subscriber fan-out")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
