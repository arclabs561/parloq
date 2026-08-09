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
import subprocess
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
    def __init__(self, audio: bytes, *, ignore_sigint: bool = False):
        self.stdout = FakeStdout(audio)
        self.returncode = None
        self._signalled = False
        self.ignore_sigint = ignore_sigint
        self.killed = False

    def poll(self):
        return self.returncode

    def send_signal(self, _signal) -> None:
        if not self._signalled:
            self._signalled = True
            if not self.ignore_sigint:
                self.stdout.finish()

    def wait(self, timeout=None):
        if self.returncode is None and timeout is not None:
            raise subprocess.TimeoutExpired("ffmpeg", timeout)
        self.returncode = 0
        return 0

    def kill(self) -> None:
        self.killed = True
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
    stubborn_process = FakeProcess(audio, ignore_sigint=True)
    processes.put(stubborn_process)
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
    recordings_path = Path(config_directory.name) / "recordings"
    vocab_path = Path(config_directory.name) / "vocab.txt"
    vocab_path.write_text("parlo = Parloq\n", encoding="utf-8")
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
        out_dir=recordings_path,
        broker=broker,
        session_submit=engine.submit,
        config_path=config_path,
        device_provider=lambda: available_devices,
        polish_provider=lambda _model: (True, None),
        vocab_path=vocab_path,
    )
    # Exercise the provenance boundary even though the fixture does not run
    # the optional external polisher.
    controller._polish = lambda _raw_text: "Hello, world."

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

        event, error = controller.configure_save_recordings(True)
        assert error is None
        assert event.event_type == rec.DictateEventType.ACK
        assert event.save_enabled is True

        event, error = controller.configure_polish(True)
        assert error is None
        assert event.event_type == rec.DictateEventType.ACK
        assert event.polish_enabled is True

        candidate_correction = rec.DictationCorrection("par lock", "Parloq")
        session_id, error = controller.start(legacy=False)
        assert error is None
        assert session_id

        event, error = controller.configure_device(
            rec.DictationDevice(":0", "MacBook Pro Microphone"))
        assert event is None
        assert error == "microphone cannot change during dictation"
        event, error = controller.configure_save_recordings(False)
        assert event is None
        assert error == "recording retention cannot change during dictation"
        event, error = controller.configure_polish(False)
        assert event is None
        assert error == "polish cannot change during dictation"
        event, error = controller.configure_vocabulary_correction(
            candidate_correction)
        assert event is None
        assert error == "corrections cannot change during dictation"

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
        assert stubborn_process.killed, "stop did not kill a stuck capture"

        final = next_type(subscriber, "final")
        assert final.session_id == session_id
        assert final.text == "Hello, world."
        assert final.raw_text == "Hello world."
        assert final.finalized_text == "Hello, world."
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
        assert idle.polish_enabled is True
        assert idle.chime_enabled is False
        assert idle.save_enabled is True
        assert idle.recordings_path == str(recordings_path)
        assert idle.vocab_count == 1
        assert idle.vocab_path == str(vocab_path)
        assert idle.vocab_warning is None
        assert idle.stream_interval_seconds == args.stream_interval
        assert controller.phase() == rec.DictatePhase.IDLE
        assert len(list(recordings_path.glob("dict-*.txt"))) == 1
        assert len(list(recordings_path.glob("dict-*.flac"))) == 1

        event, error = controller.configure_save_recordings(False)
        assert error is None
        assert event.save_enabled is False
        saved_config, warning = rec._load_dictate_runtime_config(config_path)
        assert warning is None
        assert saved_config.device.identifier == selected.identifier
        assert saved_config.save_recordings is False
        assert saved_config.polish_enabled is True

        event, error = controller.configure_polish(False)
        assert error is None
        assert event.polish_enabled is False
        saved_config, warning = rec._load_dictate_runtime_config(config_path)
        assert warning is None
        assert saved_config.polish_enabled is False

        controller._polish_provider = lambda _model: (
            False,
            "Ollama model is not installed",
        )
        event, error = controller.configure_polish(True)
        assert event is None
        assert error == "Ollama model is not installed"
        saved_config, warning = rec._load_dictate_runtime_config(config_path)
        assert warning is None
        assert saved_config.polish_enabled is False

        available_devices[:] = [
            rec.DictationDevice(":0", "MacBook Pro Microphone"),
        ]
        disconnected = controller.devices_event()
        assert disconnected.device_available is False
        assert "not connected" in disconnected.configuration_warning
        unavailable_id, error = controller.start(legacy=False)
        assert unavailable_id is None
        assert "not connected" in error

        available_devices.append(
            rec.DictationDevice(":4", "Studio Display Microphone"))
        reconnected = controller.devices_event()
        assert reconnected.device == ":4"
        assert reconnected.device_name == selected.name
        assert reconnected.device_available is True
        assert reconnected.configuration_warning is None

        vocab_path.write_bytes(b"\xff")
        invalid_vocab_id, error = controller.start(legacy=False)
        assert error is None
        assert invalid_vocab_id
        invalid_vocab_transcript = next_type(subscriber, "transcript")
        assert invalid_vocab_transcript.session_id == invalid_vocab_id
        completion, error = controller.cancel()
        assert error is None
        assert completion is not None
        assert completion.event.wait(timeout=2)
        while True:
            event = subscriber.get(timeout=2)
            if (
                event.event_type == rec.DictateEventType.STATUS
                and event.phase == rec.DictatePhase.IDLE
            ):
                break
        invalid_vocab_status = controller.status_event()
        assert invalid_vocab_status.vocab_count == 1
        assert "using prior corrections" in invalid_vocab_status.vocab_warning

        vocab_path.write_text(
            "parlo = Parloq\nsuper whisper = Superwhisper\n",
            encoding="utf-8",
        )
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
        assert controller.status_event().vocab_count == 2

        event, error = controller.configure_vocabulary_correction(
            candidate_correction)
        assert error is None
        assert event.event_type == rec.DictateEventType.ACK
        assert event.message == "Correction saved for the next dictation"
        assert event.vocab_count == 3
        assert ("par lock", "Parloq") in rec._load_vocab(vocab_path)

        event, error = controller.configure_vocabulary_correction(
            candidate_correction)
        assert error is None
        assert event.message == "Correction already exists"
        assert event.vocab_count == 3

        conflict = rec.DictationCorrection("Par Lock", "Parlock")
        event, error = controller.configure_vocabulary_correction(conflict)
        assert event is None
        assert "already maps to" in error
        assert ("par lock", "Parloq") in rec._load_vocab(vocab_path)
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
