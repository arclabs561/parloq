#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression test for recorder's structured energy-relative prosody signal.

Loads the real function from the recorder daily-driver and asserts the
energy-baseline behavior: quiet utterances seed the baseline, an utterance well
above baseline reports elevated energy, quiet returns to baseline, and a
sub-0.5s clip is skipped without polluting the baseline. Transcript text is not
an output of this analysis.

Run: uv run prosody-bench/test_emphasis_tag.py
"""
import importlib.machinery, importlib.util, pathlib
import numpy as np

REPO = pathlib.Path(__file__).resolve().parents[1]
RECORDER = REPO / "recorder" / "recorder"

def load():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    mod = importlib.util.module_from_spec(spec); loader.exec_module(mod)
    return mod

def main():
    rec = load(); analyze, SR = rec._analyze_prosody, rec.SAMPLE_RATE
    np.random.seed(0); hist = []
    for i in range(3):
        result = analyze(
            (np.random.randn(SR)*0.01).astype(np.float32), hist)
        assert result.state == "calibrating", (i, result)
        assert result.energy_z is None, result
    elevated = analyze(
        (np.random.randn(SR)*0.20).astype(np.float32), hist)
    assert elevated.state == "elevated", elevated
    assert elevated.energy_z > 0.8, elevated
    baseline = analyze(
        (np.random.randn(SR)*0.01).astype(np.float32), hist)
    assert baseline.state == "baseline", baseline
    n_before = len(hist)
    short = analyze(
        (np.random.randn(SR//4)*0.20).astype(np.float32), hist)
    assert short.state == "insufficient_audio", short
    assert short.energy_z is None, short
    assert len(hist) == n_before, "short clip polluted baseline"
    print("PASS: prosody reports calibrated energy without mutating text")

if __name__ == "__main__":
    main()
