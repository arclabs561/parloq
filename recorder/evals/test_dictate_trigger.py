#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for recorder dictate trigger socket behavior.

These tests use RECORDER_DICTATE_SOCK so they never talk to the user's real
dictation daemon or load the ASR model.
"""
from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import socket
import tempfile
import threading
from pathlib import Path


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def call_trigger(rec, args: list[str]) -> tuple[int, str, str]:
    out = io.StringIO()
    err = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = rec._dictate_trigger(args)
    return code, out.getvalue(), err.getvalue()


def serve_once(sock_path: Path, response: str, seen: list[str]) -> threading.Thread:
    ready = threading.Event()

    def run() -> None:
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            srv.bind(str(sock_path))
            srv.listen(1)
            ready.set()
            conn, _ = srv.accept()
            with conn:
                data = b""
                while not data.endswith(b"\n"):
                    chunk = conn.recv(64)
                    if not chunk:
                        break
                    data += chunk
                seen.append(data.decode("utf-8").strip())
                conn.sendall((response + "\n").encode("utf-8"))
        finally:
            srv.close()
            sock_path.unlink(missing_ok=True)

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    assert ready.wait(timeout=2), "socket server did not start"
    return thread


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        sock_path = Path(td) / "dictate.sock"
        os.environ["RECORDER_DICTATE_SOCK"] = str(sock_path)
        rec = load_recorder()

        code, out, err = call_trigger(rec, ["--status"])
        assert code == 1, code
        assert out == "", out
        assert "dictate daemon is not reachable" in err
        assert str(sock_path) in err

        seen: list[str] = []
        thread = serve_once(sock_path, "phase=idle prosody=on", seen)
        code, out, err = call_trigger(rec, ["--status"])
        thread.join(timeout=2)
        assert code == 0, code
        assert out == "phase=idle prosody=on\n", out
        assert err == "", err
        assert seen == ["status"], seen

        for args, want_cmd in [([], "toggle"), (["--paste"], "toggle:paste")]:
            seen = []
            thread = serve_once(sock_path, "ok", seen)
            code, out, err = call_trigger(rec, args)
            thread.join(timeout=2)
            assert code == 0, (args, code)
            assert out == "ok\n", (args, out)
            assert err == "", (args, err)
            assert seen == [want_cmd], (args, seen)

    print("PASS: dictate trigger status uses isolated socket")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
