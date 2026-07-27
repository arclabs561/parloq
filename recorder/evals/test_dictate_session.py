#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Exercise the streaming dictation session without a mic or ASR model."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import queue
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace

import numpy as np


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec_session", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec_session", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class FakeStdout:
    def __init__(self, audio: bytes):
        self._chunks: queue.Queue = queue.Queue()
        self._chunks.put(audio)

    def finish(self) -> None:
        self._chunks.put(None)

    def read(self, _count: int) -> bytes:
        chunk = self._chunks.get(timeout=2)
        return b"" if chunk is None else chunk


class FakeProcess:
    def __init__(self, audio: bytes):
        self.stdout = FakeStdout(audio)
        self.returncode = None
        self._signalled = False

    def poll(self):
        return self.returncode

    def send_signal(self, _signal) -> None:
        if not self._signalled:
            self._signalled = True
            self.stdout.finish()

    def wait(self, timeout=None):
        self.returncode = 0
        return 0

    def kill(self) -> None:
        self.returncode = -9
        self.stdout.finish()


class Token:
    def __init__(self, text: str):
        self.text = text


class FakeTranscription:
    def __init__(self):
        self.finalized_tokens = []
        self.draft_tokens = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def add_audio(self, _samples) -> None:
        self.finalized_tokens = [Token("hello")]
        self.draft_tokens = [Token(" wor")]


class FakeModel:
    def __init__(self):
        self._owner_thread = threading.get_ident()

    def _assert_owner_thread(self):
        assert threading.get_ident() == self._owner_thread, (
            "MLX model used from a different thread than it was initialized on"
        )

    def transcribe_stream(self, **_kwargs):
        self._assert_owner_thread()
        return FakeTranscription()

    def transcribe(self, _path: str):
        self._assert_owner_thread()
        return SimpleNamespace(text="Hello world.")


class FakeMX:
    @staticmethod
    def array(samples):
        return samples


def next_type(subscriber, event_type: str, timeout=2):
    while True:
        event = subscriber.get(timeout=timeout)
        if event.event_type.value == event_type:
            return event


def main() -> int:
    rec = load_recorder()
    chunk_samples = int(rec.SAMPLE_RATE * 0.1)
    audio = np.full(chunk_samples, 0.05, dtype=np.float32).tobytes()
    processes = queue.Queue()
    processes.put(FakeProcess(audio))
    processes.put(FakeProcess(audio))
    original_popen = rec.subprocess.Popen
    rec.subprocess.Popen = lambda *_args, **_kwargs: processes.get(timeout=2)

    args = SimpleNamespace(
        device=":test",
        model="fake-parakeet",
        stream_interval=0.1,
        polish=False,
        polish_model="unused",
        prosody=False,
        no_chime=True,
        no_clipboard=True,
        save=False,
    )
    broker = rec.DictateEventBroker()
    subscriber = broker.subscribe()
    engine = ThreadPoolExecutor(max_workers=1)
    model = engine.submit(FakeModel).result()
    controller = rec.DictateSessionController(
        args=args,
        model=model,
        mx=FakeMX(),
        decoding_config=object(),
        vocab=[],
        out_dir=Path("/unused"),
        broker=broker,
        session_submit=engine.submit,
    )

    try:
        session_id, error = controller.start(legacy=False)
        assert error is None
        assert session_id

        transcript = next_type(subscriber, "transcript")
        assert transcript.phase == rec.DictatePhase.RECORDING
        assert transcript.text == "hello wor", transcript.text
        assert transcript.finalized_text == "hello"
        assert transcript.draft_text == " wor"

        completion, error = controller.stop(paste=False)
        assert error is None
        assert completion is not None
        assert completion.event.wait(timeout=2), "session did not finish"

        final = next_type(subscriber, "final")
        assert final.session_id == session_id
        assert final.text == "Hello world."
        assert final.finalized_text == "Hello world."
        assert completion.message.startswith("✓ 2 words"), completion.message

        idle = next_type(subscriber, "status")
        while idle.phase != rec.DictatePhase.IDLE:
            idle = next_type(subscriber, "status")
        assert controller.phase() == rec.DictatePhase.IDLE

        cancelled_id, error = controller.start(legacy=False)
        assert error is None
        assert cancelled_id
        cancelled_transcript = next_type(subscriber, "transcript")
        assert cancelled_transcript.session_id == cancelled_id

        completion, error = controller.cancel()
        assert error is None
        assert completion is not None
        assert completion.event.wait(timeout=2), "cancelled session did not finish"
        assert completion.message == "○ dictation cancelled", completion.message

        cancelled_events = []
        while True:
            event = subscriber.get(timeout=2)
            if event.session_id == cancelled_id:
                cancelled_events.append(event)
            if (
                event.event_type == rec.DictateEventType.STATUS
                and event.phase == rec.DictatePhase.IDLE
            ):
                break
        assert not any(
            event.event_type == rec.DictateEventType.FINAL
            for event in cancelled_events
        ), cancelled_events
        assert controller.phase() == rec.DictatePhase.IDLE
    finally:
        rec.subprocess.Popen = original_popen
        broker.unsubscribe(subscriber)
        engine.shutdown()

    print("PASS: streaming session finalizes or cancels without a final event")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
