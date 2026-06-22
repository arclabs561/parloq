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
import select
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[2]
RECORDER = ROOT / "recorder" / "recorder"


def start_fixture() -> tuple[subprocess.Popen[str], str]:
    proc = subprocess.Popen(
        [sys.executable, str(RECORDER), "ui-fixture", "--port", "0", "--step", "0.05"],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert proc.stderr is not None
    logs: list[str] = []
    deadline = time.time() + 10
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stderr], [], [], 0.1)
        if ready:
            line = proc.stderr.readline()
            if line:
                logs.append(line)
                match = re.search(r"live\s+->\s+(http://127\.0\.0\.1:\d+/)", line)
                if match:
                    return proc, match.group(1)
        if proc.poll() is not None:
            break
    proc.kill()
    raise RuntimeError("fixture did not start:\n" + "".join(logs))


def stop_fixture(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()


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
