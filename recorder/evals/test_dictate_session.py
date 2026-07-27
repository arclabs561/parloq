#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "soundfile>=0.12"]
# ///
"""Exercise the streaming dictation session without a mic or ASR model."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import queue
import threading
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import soundfile as sf


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
        self._pending = bytearray()

    def finish(self) -> None:
        self._chunks.put(None)

    def read(self, count: int) -> bytes:
        if not self._pending:
            chunk = self._chunks.get(timeout=2)
            if chunk is None:
                return b""
            self._pending.extend(chunk)
        result = bytes(self._pending[:count])
        del self._pending[:count]
        return result


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


def next_meter(subscriber, timeout=2):
    while True:
        event = subscriber.get(timeout=timeout)
        if event.input_peak_db is not None:
            return event


def main() -> int:
    rec = load_recorder()
    with tempfile.TemporaryDirectory() as temporary_directory:
        flac_path = Path(temporary_directory) / "dictation.flac"
        expected_samples = np.array(
            [0.0, 0.25, -0.25, 0.5],
            dtype=np.float32,
        )
        rec._write_dictate_flac(flac_path, expected_samples.tobytes())
        actual_samples, sample_rate = sf.read(
            flac_path,
            dtype="float32",
        )
        assert sample_rate == rec.SAMPLE_RATE
        np.testing.assert_allclose(
            actual_samples,
            expected_samples,
            atol=4e-5,
        )

    chunk_samples = int(rec.SAMPLE_RATE * 0.5)
    audio = np.full(chunk_samples, 0.05, dtype=np.float32).tobytes()
    processes = queue.Queue()
    processes.put(FakeProcess(audio))
    processes.put(FakeProcess(audio))
    original_popen = rec.subprocess.Popen
    rec.subprocess.Popen = lambda *_args, **_kwargs: processes.get(timeout=2)
    original_write_flac = rec._write_dictate_flac
    written_audio = []

    def write_fake_flac(path, audio):
        written_audio.append(bytes(audio))
        path.write_bytes(b"fake flac")

    rec._write_dictate_flac = write_fake_flac

    args = SimpleNamespace(
        device=":test",
        model="fake-parakeet",
        stream_interval=0.5,
        polish=False,
        polish_model="unused",
        prosody=True,
        no_chime=True,
        no_clipboard=True,
        save=False,
    )
    broker = rec.DictateEventBroker()
    subscriber = broker.subscribe()
    engine = ThreadPoolExecutor(max_workers=1)
    model = engine.submit(FakeModel).result()
    config_directory = tempfile.TemporaryDirectory()
    config_path = Path(config_directory.name) / "dictation-config.json"
    available_devices = [
        rec.DictationDevice(":0", "MacBook Pro Microphone"),
        rec.DictationDevice(":2", "Studio Display Microphone"),
    ]
    controller = rec.DictateSessionController(
        args=args,
        model=model,
        mx=FakeMX(),
        decoding_config=object(),
        vocab=[],
        out_dir=Path("/unused"),
        broker=broker,
        session_submit=engine.submit,
        config_path=config_path,
        device_provider=lambda: available_devices,
    )

    try:
        devices = controller.devices_event()
        assert [device.to_dict() for device in devices.available_devices] == [
            {"id": ":0", "name": "MacBook Pro Microphone"},
            {"id": ":2", "name": "Studio Display Microphone"},
        ]

        event, error = controller.configure_device(
            rec.DictationDevice(":9", "Missing Microphone"))
        assert event is None
        assert "no longer available" in error
        assert not config_path.exists()

        selected = rec.DictationDevice(
            ":2", "Studio Display Microphone")
        event, error = controller.configure_device(selected)
        assert error is None
        assert event.event_type == rec.DictateEventType.ACK
        assert event.device == ":2"
        assert event.device_name == selected.name
        assert event.device_available is True
        assert config_path.exists()

        session_id, error = controller.start(legacy=False)
        assert error is None
        assert session_id

        event, error = controller.configure_device(
            rec.DictationDevice(":0", "MacBook Pro Microphone"))
        assert event is None
        assert error == "microphone cannot change during dictation"

        meter = next_meter(subscriber)
        assert meter.phase == rec.DictatePhase.RECORDING
        assert meter.session_id == session_id
        assert meter.elapsed_seconds == 0.1
        assert -26.1 < meter.input_peak_db < -25.9
        assert len(meter.input_spectrum_db) == 9

        transcript = next_type(subscriber, "transcript")
        assert transcript.phase == rec.DictatePhase.RECORDING
        assert transcript.elapsed_seconds == 0.5
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
        assert final.asr_seconds is not None
        assert final.prosody_state == "calibrating"
        assert final.prosody_energy_z is None
        assert final.prosody_baseline_count == 1
        assert -26.1 < final.prosody_rms_db < -25.9
        assert completion.message.startswith("✓ 2 words"), completion.message
        assert len(written_audio) == 1

        idle = next_type(subscriber, "status")
        while idle.phase != rec.DictatePhase.IDLE:
            idle = next_type(subscriber, "status")
        assert idle.device == selected.identifier
        assert idle.device_name == selected.name
        assert idle.device_available is True
        assert idle.model == args.model
        assert idle.prosody_enabled is True
        assert idle.prosody_baseline_count == 1
        assert idle.polish_enabled is False
        assert idle.chime_enabled is False
        assert idle.save_enabled is False
        assert idle.vocab_count == 0
        assert idle.stream_interval_seconds == args.stream_interval
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
        rec._write_dictate_flac = original_write_flac
        broker.unsubscribe(subscriber)
        engine.shutdown()
        config_directory.cleanup()

    print("PASS: streaming session finalizes or cancels without a final event")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
