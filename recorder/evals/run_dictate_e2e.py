#!/usr/bin/env python3
"""Run the real dictation daemon and ASR model against recorded speech."""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RECORDER = ROOT / "recorder" / "recorder"


def connect(socket_path: Path, timeout: float) -> socket.socket:
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(timeout)
    connection.connect(str(socket_path))
    return connection


def send_request(socket_path: Path, body: dict, timeout: float) -> dict:
    with connect(socket_path, timeout) as connection:
        connection.sendall((json.dumps(body) + "\n").encode())
        line = connection.makefile("rb").readline()
    if not line:
        raise RuntimeError("daemon closed the request without a response")
    return json.loads(line)


def wait_for_socket(
    socket_path: Path,
    process: subprocess.Popen,
    timeout: float,
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("dictation daemon exited during model startup")
        if socket_path.exists():
            return
        time.sleep(0.1)
    raise TimeoutError("dictation daemon did not become ready")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio", type=Path)
    parser.add_argument(
        "--expect",
        help="case-insensitive text required in final ASR",
    )
    parser.add_argument(
        "--model",
        default="mlx-community/parakeet-tdt-0.6b-v3",
    )
    parser.add_argument("--startup-timeout", type=float, default=180)
    parser.add_argument("--transcription-timeout", type=float, default=120)
    args = parser.parse_args()
    audio = args.audio.expanduser().resolve()
    if not audio.is_file():
        parser.error(f"audio fixture does not exist: {audio}")

    with tempfile.TemporaryDirectory(prefix="parloq-e2e-") as temporary:
        temporary_path = Path(temporary)
        socket_path = temporary_path / "dictate.sock"
        environment = os.environ.copy()
        environment.update({
            "RECORDER_DICTATE_SOCK": str(socket_path),
            "RECORDER_DICTATE_CONFIG": str(temporary_path / "config.json"),
            "MEETING_DIR": str(temporary_path / "recordings"),
        })
        process = subprocess.Popen(
            [
                str(RECORDER),
                "dictate",
                "--daemon",
                "--from-file",
                str(audio),
                "--model",
                args.model,
                "--no-chime",
                "--no-clipboard",
            ],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            wait_for_socket(socket_path, process, args.startup_timeout)
            subscriber = connect(socket_path, args.transcription_timeout)
            with subscriber:
                subscriber.sendall(
                    b'{"version":1,"command":"subscribe"}\n')
                events = subscriber.makefile("rb")
                initial = json.loads(events.readline())
                if initial.get("phase") != "idle":
                    raise RuntimeError(f"unexpected initial event: {initial}")
                started = send_request(
                    socket_path,
                    {"version": 1, "command": "start"},
                    args.transcription_timeout,
                )
                if started.get("type") != "ack":
                    raise RuntimeError(f"dictation did not start: {started}")

                deadline = time.monotonic() + args.transcription_timeout
                final = None
                phases = []
                while time.monotonic() < deadline:
                    line = events.readline()
                    if not line:
                        raise RuntimeError("subscription ended before final ASR")
                    event = json.loads(line)
                    phases.append(event.get("phase"))
                    if event.get("type") == "error":
                        raise RuntimeError(
                            f"daemon error: {event.get('message')}")
                    if event.get("type") == "final":
                        final = event
                        break
                if final is None:
                    raise TimeoutError("no final transcript arrived")

            text = (final.get("text") or "").strip()
            raw_text = (final.get("raw_text") or "").strip()
            if not text or not raw_text:
                raise RuntimeError(
                    "final event did not contain text and raw_text")
            if not final.get("asr_seconds", 0) > 0:
                raise RuntimeError(
                    "final event did not report a real ASR pass")
            if args.expect and args.expect.casefold() not in text.casefold():
                raise RuntimeError(
                    f"expected {args.expect!r} in transcript {text!r}")
            print(json.dumps({
                "result": "PASS",
                "audio": str(audio),
                "text": text,
                "raw_text": raw_text,
                "audio_seconds": final.get("elapsed_seconds"),
                "asr_seconds": final.get("asr_seconds"),
                "phases": phases,
            }, ensure_ascii=False))
            return 0
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if process.returncode not in (0, -signal.SIGTERM):
                error_output = process.stderr.read() if process.stderr else ""
                if error_output:
                    print(error_output, end="", file=os.sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
