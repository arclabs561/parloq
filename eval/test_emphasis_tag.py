#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression test for recorder's --prosody _emphasis_tag (the A/MVP).

Loads the real function from the recorder daily-driver and asserts the
energy-baseline behavior: quiet utterances seed the baseline (no tag), an
utterance well above baseline gets [emphatic], quiet returns clean, and a
sub-0.5s clip is skipped without polluting the baseline.

Run: uv run eval/test_emphasis_tag.py
"""
import importlib.machinery, importlib.util, pathlib
import numpy as np

RECORDER = pathlib.Path.home()/"Documents"/"dev"/"parloq"/"recorder"/"recorder"

def load():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)
    return mod

def main():
    rec = load(); et, SR = rec._emphasis_tag, rec.SAMPLE_RATE
    np.random.seed(0); hist = []
    for i in range(3):
        assert et((np.random.randn(SR)*0.01).astype(np.float32), hist) == "", f"quiet{i} tagged"
    assert et((np.random.randn(SR)*0.20).astype(np.float32), hist) == "[emphatic] ", "loud not tagged"
    assert et((np.random.randn(SR)*0.01).astype(np.float32), hist) == "", "quiet tagged after loud"
    n_before = len(hist)
    assert et((np.random.randn(SR//4)*0.20).astype(np.float32), hist) == "", "short clip tagged"
    assert len(hist) == n_before, "short clip polluted baseline"
    print("PASS: emphasis tag fires on elevated energy, silent otherwise")

if __name__ == "__main__":
    main()
