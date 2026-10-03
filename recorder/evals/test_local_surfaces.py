#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for the recorder's local attack surface.

Covers the live-view HTTP server (a browser tab can reach 127.0.0.1) and the
dictation daemon's socket-claim probe. Uses RECORDER_DICTATE_SOCK-style temp
paths so it never touches the user's real dictation daemon.
"""
from __future__ import annotations

import http.client
import importlib.machinery
import importlib.util
import socket
import tempfile
import threading
from pathlib import Path


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def request(port: int, method: str, path: str, headers: dict | None = None) -> int:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        # skip_host: tests choose the Host header themselves.
        conn.putrequest(method, path, skip_host=True)
        for key, value in (headers or {}).items():
            conn.putheader(key, value)
        conn.putheader("Content-Length", "0")
        conn.endheaders()
        return conn.getresponse().status
    finally:
        conn.close()


def test_http_rejects_foreign_host_and_origin(rec) -> None:
    state = rec.TranscriptState({"name": "t", "paths": {}})
    server, port, _ = rec.start_server(state, 0)
    own = f"127.0.0.1:{port}"
    try:
        # DNS rebinding: the attacker's hostname resolves to 127.0.0.1.
        assert request(port, "GET", "/snapshot.json", {"Host": f"evil.example:{port}"}) == 403
        # Cross-origin POST from a web page: needs no CORS preflight.
        hostile = {"Host": own, "Origin": "http://evil.example"}
        assert request(port, "POST", "/control/stop", hostile) == 403
        assert request(port, "POST", "/control/mark", hostile) == 403
        assert not state.stop_requested and not state.mark_requested

        # The page's own same-origin requests still work.
        assert request(port, "GET", "/snapshot.json", {"Host": own}) == 200
        assert request(port, "GET", "/snapshot.json", {"Host": f"localhost:{port}"}) == 200
        assert request(port, "POST", "/control/stop", {"Host": own, "Origin": f"http://{own}"}) == 200
        assert state.stop_requested
    finally:
        server.shutdown()
        server.server_close()


def test_socket_probe_distinguishes_live_from_stale(rec) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        sock_path = Path(tmp) / "d.sock"

        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(str(sock_path))
        stale.close()  # node remains on disk, nobody listening
        assert sock_path.exists()
        assert rec._dictate_socket_answers(sock_path) is False
        sock_path.unlink()

        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(str(sock_path))
        srv.listen(1)

        def serve() -> None:
            conn, _ = srv.accept()
            with conn:
                conn.recv(64)
                conn.sendall(b"idle\n")

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        try:
            assert rec._dictate_socket_answers(sock_path) is True
        finally:
            thread.join(timeout=5)
            srv.close()


def main() -> int:
    rec = load_recorder()
    test_http_rejects_foreign_host_and_origin(rec)
    test_socket_probe_distinguishes_live_from_stale(rec)
    print("test_local_surfaces: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
