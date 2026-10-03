#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Rule-following and latency bake-off for transcript polish models (Ollama).

Two paths, because the recorder has two polish implementations:
  edits    dictation: STREAMING_POLISH_PROMPT emits SUB/INS_AFTER/CAP lines that
           parse_edits + apply_edits apply (what `recorder dictate --polish` runs)
  rewrite  transcripts: POLISH_SYSTEM_PROMPT returns the whole cleaned text
           (what `recorder polish` runs)

Cases are generated from the rules shared by both prompts, so a
pass or fail is decided by the prompt's own contract rather than by comparing
against another model's output. Reports per-category pass rate, a paired-
bootstrap 95% interval on the pass-rate difference against the baseline, the
baseline's own run-to-run flip rate, and median latency.

  uv run experiments/polish_bakeoff.py --models gemma4:e2b,gemma4:12b
"""
from __future__ import annotations

import argparse
import importlib.machinery
import importlib.util
import json
import random
import re
import statistics
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
RECORDER = ROOT / "recorder" / "recorder"
SAMPLE = ROOT / "data" / "corpora" / "recorder" / "bakeoff" / "sample_200_0.json"
BASELINE = "gemma4:e2b"
FILLERS = ("um", "uh", "like")
PREAMBLE = re.compile(r"^(here is|here's|sure|certainly|corrected|the corrected)", re.I)

# Tokens that must survive verbatim; the prompt forbids reformatting them.
NUMBER_PHRASES = [
    "1150 eastern", "two p m", "route 66", "call 555 0134", "room 4 12",
    "at 0930 sharp", "flight 207", "version 3 1 4", "gate b 14", "ten a m",
]


def load_recorder():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def words(text: str) -> list[str]:
    return re.sub(r"[^\w\s']", " ", text.lower()).split()


def word_error_rate(ref: list[str], hyp: list[str]) -> float:
    d = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        prev, d[0] = d[0], i
        for j, h in enumerate(hyp, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (r != h))
    return d[len(hyp)] / max(1, len(ref))


def build_cases(n_per: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    refs = [c["ref"].lower() for c in json.loads(SAMPLE.read_text())]
    rng.shuffle(refs)
    cases = []
    for i in range(n_per):
        t = refs[i].split()
        cases.append({"cat": "initial_filler", "input": f"{rng.choice(FILLERS)} " + refs[i]})
        k = rng.randint(3, max(3, len(t) - 3))
        cases.append({"cat": "mid_filler", "input": " ".join(t[:k] + ["like"] + t[k:])})
        phrase = NUMBER_PHRASES[i % len(NUMBER_PHRASES)]
        k = rng.randint(2, max(2, len(t) - 2))
        cases.append({"cat": "numbers", "input": " ".join(t[:k] + [phrase] + t[k:]),
                      "phrase": phrase})
        cases.append({"cat": "fidelity", "input": refs[2 * n_per + i]})
        cases.append({"cat": "punct_cap", "input": refs[3 * n_per + i]})
    return cases


def check(case: dict, out: str) -> bool:
    low = out.strip().lower()
    if not low or PREAMBLE.match(low) or low.startswith(("```", '"')) or low.endswith(('"', "```")):
        return False
    cat = case["cat"]
    if cat == "initial_filler":
        original = words(case["input"])[1:]
        got = words(out)
        return not (got and got[0] in FILLERS) and word_error_rate(original, got) <= 0.03
    if cat == "mid_filler":
        return words(out).count("like") >= words(case["input"]).count("like") \
            and word_error_rate(words(case["input"]), words(out)) <= 0.03
    if cat == "numbers":
        return case["phrase"] in re.sub(r"[.,;:!?]", "", low)
    if cat == "punct_cap":
        stripped = out.strip()
        return (stripped[:1].isupper() and stripped[-1:] in ".?!"
                and word_error_rate(words(case["input"]), words(out)) <= 0.03)
    return word_error_rate(words(case["input"]), words(out)) <= 0.03


def polish(rec, path: str, model: str, text: str) -> str:
    """One polish call, mirroring the production code path."""
    if path == "rewrite":
        return rec.ollama_chat(model, [
            {"role": "system", "content": rec.POLISH_SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ]).strip()
    raw = rec.ollama_chat(model, [
        {"role": "system", "content": rec.STREAMING_POLISH_PROMPT},
        {"role": "user", "content": text},
    ], stream=False, timeout=60, num_predict=300)
    parsed = rec.parse_edits(raw)
    if parsed:
        polished, applied = rec.apply_edits(text, parsed)
        if applied > 0:
            return polished
    return text


def run_model(rec, path: str, model: str,
              cases: list[dict]) -> tuple[list[bool], list[float], list[str]]:
    passed, lat, outs = [], [], []
    for c in cases:
        t0 = time.time()
        try:
            out = polish(rec, path, model, c["input"])
        except Exception as e:  # a failed call is a failed case, not a skipped one
            out = f"<error: {e}>"
        lat.append(time.time() - t0)
        outs.append(out)
        passed.append(check(c, out))
    return passed, lat, outs


def bootstrap_diff(base: list[bool], cand: list[bool], iters: int = 5000, seed: int = 0):
    b, c = np.array(base, float), np.array(cand, float)
    rng = np.random.default_rng(seed)
    diffs = [(c[i] - b[i]).mean() for i in (rng.integers(0, len(b), len(b)) for _ in range(iters))]
    return float(np.percentile(diffs, 2.5)), float(np.percentile(diffs, 97.5))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default=BASELINE)
    ap.add_argument("--n-per", type=int, default=25)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--path", choices=["edits", "rewrite"], default="edits")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    out_path = args.out or ROOT / "results" / f"polish_bakeoff_{args.path}.json"
    rec = load_recorder()
    cases = build_cases(args.n_per, args.seed)
    cats = sorted({c["cat"] for c in cases})
    print(f"{len(cases)} cases, categories: {cats}", flush=True)

    results: dict = {"n": len(cases), "seed": args.seed, "path": args.path, "models": {}}
    runs: dict[str, list[bool]] = {}
    models = args.models.split(",")
    for model in models + ([BASELINE + "#2"] if BASELINE in models else []):
        name = model.removesuffix("#2")
        print(f"== {model}", flush=True)
        passed, lat, outs = run_model(rec, args.path, name, cases)
        runs[model] = passed
        by_cat = {cat: float(np.mean([p for p, c in zip(passed, cases, strict=True) if c["cat"] == cat]))
                  for cat in cats}
        results["models"][model] = {
            "pass_rate": float(np.mean(passed)), "by_category": by_cat,
            "median_latency_s": statistics.median(lat),
            "failures": [{"cat": c["cat"], "input": c["input"], "output": o}
                         for p, c, o in zip(passed, cases, outs, strict=True) if not p][:8],
        }
        print(f"   pass {np.mean(passed) * 100:5.1f}%  median {statistics.median(lat):5.2f}s  "
              + "  ".join(f"{k}={v * 100:.0f}%" for k, v in by_cat.items()), flush=True)

    if BASELINE in runs:
        flips = float(np.mean([a != b for a, b in zip(runs[BASELINE], runs[BASELINE + "#2"], strict=True)]))
        results["baseline_flip_rate"] = flips
        print(f"baseline run-to-run flip rate: {flips * 100:.1f}% of cases")
        base_lat = results["models"][BASELINE]["median_latency_s"]
        for model in models:
            if model == BASELINE:
                continue
            lo, hi = bootstrap_diff(runs[BASELINE], runs[model])
            results["models"][model]["diff_vs_baseline_ci95"] = [lo, hi]
            ratio = results["models"][model]["median_latency_s"] / base_lat
            results["models"][model]["latency_ratio"] = ratio
            verdict = "better" if lo > 0 else "worse" if hi < 0 else "within noise"
            print(f"{model:<20} d(pass) [{lo * 100:+.1f}, {hi * 100:+.1f}]pp {verdict}; "
                  f"latency {ratio:.1f}x baseline")

    out_path.write_text(json.dumps(results, indent=2))
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
