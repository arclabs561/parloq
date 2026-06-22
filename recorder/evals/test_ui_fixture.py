#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "playwright"]
# ///
"""Browser e2e for recorder's live UI using the deterministic ui-fixture.

Run:
  uv run recorder/evals/test_ui_fixture.py

The pass/fail oracle is DOM behavior. Screenshots are review artifacts for the
live, find, and stopped states.
"""
from __future__ import annotations

import argparse
import re
import runpy
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[2]
RECORDER = ROOT / "recorder" / "recorder"


class Fixture:
    def __init__(self, server, thread, state):
        self.server = server
        self.thread = thread
        self.state = state


def start_fixture() -> tuple[Fixture, str]:
    recorder = runpy.run_path(str(RECORDER), run_name="parloq_recorder_fixture")
    transcript_state = recorder["TranscriptState"]
    start_server = recorder["start_server"]
    hms = recorder["hms"]

    started = recorder["datetime"].now().astimezone()
    state = transcript_state(
        {
            "name": "ui-fixture",
            "started": started.strftime("%Y-%m-%d %H:%M:%S %Z"),
            "model": "fixture",
            "input": "fixture audio",
            "audio_file": "ui-fixture.flac",
            "md_path": "/tmp/parloq-ui-fixture.md",
            "paths": {
                "md": "/tmp/parloq-ui-fixture.md",
                "txt": "/tmp/parloq-ui-fixture.txt",
                "flac": "/tmp/parloq-ui-fixture.flac",
                "log": "/tmp/parloq-ui-fixture.log",
            },
        }
    )
    state.set_polish_status("idle", "fixture-polish")
    server, port, _ = start_server(state, 0)

    def sleep_step(multiplier: float = 1.0) -> None:
        time.sleep(max(0.01, 0.05 * multiplier))

    def maybe_user_mark(t: float) -> None:
        if state.mark_requested:
            state.mark_requested = False
            state.add_marker(t, f"[{hms(t)}] ★", user=True)

    def drive_state() -> None:
        state.set_status("starting")
        state.set_draft("warming fixture state", 0.5, 0.5, peak_db=-48.0)
        sleep_step()

        state.set_status("recording")
        state.set_draft("", 1.0, 1.0, peak_db=-34.0)
        state.append_finalized(
            "We need the recorder UI to show known transcript data clearly.",
            1.2,
        )
        sleep_step()
        maybe_user_mark(1.4)

        state.append_finalized(
            " The quality gate should catch unreadable states before they ship.",
            4.8,
        )
        state.replace_polished_window(
            0,
            2,
            "We need the recorder UI to show known transcript data clearly. "
            "The quality gate should catch unreadable states before they ship.",
            "We need the recorder UI to show known transcript data clearly. "
            "The quality gate should catch unreadable states before they ship.",
        )
        state.set_draft(
            "and screenshots should cover the live tail", 8.5, 8.5, peak_db=-18.0
        )
        sleep_step()
        maybe_user_mark(8.8)

        state.add_marker(10.0, "[00:00:10]")
        state.append_finalized(
            " Markers, search, raw toggle, and the stop dialog all need coverage.",
            12.0,
        )
        state.set_draft("", 14.0, 14.0, peak_db=-55.0)

        while not state.stop_requested:
            maybe_user_mark(state.snapshot()["audio_seconds"] or 14.0)
            state.set_draft("", 14.0, 14.0, peak_db=-90.0)
            time.sleep(0.05)

        state.set_status("stopped")
        state.set_draft("", 14.0, 14.0, peak_db=-120.0)
        sleep_step(0.5)

    thread = threading.Thread(target=drive_state, daemon=True)
    thread.start()
    return Fixture(server, thread, state), f"http://127.0.0.1:{port}/"


def stop_fixture(fixture: Fixture) -> None:
    fixture.state.stop_requested = True
    fixture.thread.join(timeout=2)
    fixture.server.shutdown()
    fixture.server.server_close()


def run(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    proc, url = start_fixture()
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1280, "height": 900})
            page.goto(url)

            expect(page.locator("#name")).to_have_text("ui-fixture")
            expect(page.locator("#status-text")).to_have_text("recording")
            expect(page.locator("#transcript")).to_contain_text(
                "known transcript data"
            )
            expect(page.locator("#transcript")).to_contain_text("quality gate")
            expect(page.locator("#btn-toggle-raw")).to_be_visible()
            expect(page.locator("#btn-toggle-raw")).to_have_attribute(
                "aria-pressed", "false"
            )
            page.screenshot(path=str(out_dir / "01-live.png"), full_page=True)

            page.set_viewport_size({"width": 390, "height": 844})
            expect(page.locator("#transcript")).to_contain_text("quality gate")
            page.screenshot(path=str(out_dir / "01-mobile-live.png"), full_page=True)
            page.set_viewport_size({"width": 1280, "height": 900})

            page.locator("#btn-toggle-raw").click()
            expect(page.locator("#btn-toggle-raw")).to_have_attribute(
                "aria-pressed", "true"
            )
            expect(page.locator("#btn-toggle-raw")).to_contain_text("polished")
            expect(page.locator("#transcript")).to_contain_text("quality gate")
            page.screenshot(path=str(out_dir / "02-raw.png"), full_page=True)
            page.locator("#btn-toggle-raw").click()
            expect(page.locator("#btn-toggle-raw")).to_have_attribute(
                "aria-pressed", "false"
            )

            page.locator("#btn-find").click()
            page.get_by_label("find in transcript").fill("quality")
            expect(page.locator("mark.find-hit.current")).to_have_text("quality")
            page.screenshot(path=str(out_dir / "03-find.png"), full_page=True)

            page.keyboard.press("Escape")
            page.locator("#btn-mark").click()
            expect(page.locator(".marker.user-mark")).to_have_count(1)
            expect(page.locator(".marker.user-mark .label-text")).to_have_text(
                "[00:00:14] ★"
            )

            page.locator("#btn-stop").click()
            expect(page.locator("#modal")).to_have_class(re.compile("visible"))
            page.locator("#modal-confirm").click()
            expect(page.locator("#status-text")).to_have_text("stopped")
            page.wait_for_timeout(1800)
            expect(page.locator("#conn-text")).to_have_text("stopped")
            page.screenshot(path=str(out_dir / "04-stopped.png"), full_page=True)
            browser.close()
    finally:
        stop_fixture(proc)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "test-results" / "ui-fixture",
        help="directory for screenshot artifacts",
    )
    args = parser.parse_args()
    run(args.out)
    print(f"PASS: recorder UI fixture e2e screenshots -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
