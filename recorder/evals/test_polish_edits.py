#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression tests for recorder polish edit-script parsing and application."""
from __future__ import annotations

import importlib.machinery
import importlib.util
from pathlib import Path


RECORDER = Path(__file__).resolve().parent.parent / "recorder"


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def main() -> int:
    rec = load_recorder()

    parsed = rec.parse_edits(
        '\n'.join([
            'SUB "their" => "there"',
            'INS_AFTER "done" => "."',
            'CAP "tuesday"',
            'SUB "quote: \\"yes\\"" => "quote: \\"no\\""',
            'not an edit',
            'NONE',
        ])
    )
    assert parsed == [
        ("SUB", "their", "there"),
        ("INS_AFTER", "done", "."),
        ("CAP", "tuesday", ""),
        ("SUB", 'quote: "yes"', 'quote: "no"'),
    ], parsed

    text, applied = rec.apply_edits(
        "users can invite users",
        [
            ("INS_AFTER", "users", ","),
            ("INS_AFTER", "users", "."),
        ],
    )
    assert text == "users, can invite users.", text
    assert applied == 2, applied

    text, applied = rec.apply_edits(
        "their plan starts tuesday",
        [
            ("SUB", "their", "there"),
            ("CAP", "tuesday", ""),
        ],
    )
    assert text == "there plan starts Tuesday", text
    assert applied == 2, applied

    text, applied = rec.apply_edits(
        "Their plan starts Tuesday",
        [
            ("SUB", "their", "there"),
            ("CAP", "Tuesday", ""),
            ("INS_AFTER", "missing", "."),
        ],
    )
    assert text == "Their plan starts Tuesday", text
    assert applied == 0, applied

    print("PASS: polish edit parsing and cursor application")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
