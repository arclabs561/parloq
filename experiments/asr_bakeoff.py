#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "parakeet-mlx>=0.5",
#     "mlx-audio",
#     "jiwer",
#     "whisper-normalizer",
#     "numpy",
#     "soundfile",
# ]
# ///
"""Offline ASR bake-off on a LibriSpeech dev-clean sample, clean and noisy.

Question: does any candidate beat the recorder's default final-pass model
(parakeet-tdt-0.6b-v3) by more than resampling noise? Reports WER per model and
condition, a paired-bootstrap 95% interval on the WER difference against the
baseline, and real-time factor. dev-clean is read, clean speech that every
candidate has likely seen in training, so it bounds the gap from below; the
noisy condition (pink noise at 10 dB SNR) is the part that can separate models.

  uv run experiments/asr_bakeoff.py --n 100 --out results/asr_bakeoff.json
"""
from __future__ import annotations

import argparse
import json
import random
import tarfile
import time
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "data" / "corpora" / "recorder"
TARBALL = CORPUS / "_downloads" / "dev-clean.tar.gz"
WORK = CORPUS / "bakeoff"

BASELINE = "parakeet-v3"
MODELS = {
    "parakeet-v3": ("parakeet", "mlx-community/parakeet-tdt-0.6b-v3"),
    "parakeet-v2": ("parakeet", "mlx-community/parakeet-tdt-0.6b-v2"),
    "qwen3-asr-1.7b": ("mlx-audio", "mlx-community/Qwen3-ASR-1.7B-8bit"),
    "whisper-turbo": ("mlx-audio", "mlx-community/whisper-large-v3-turbo-asr-fp16"),
}
SNR_DB = 10.0
SR = 16000


def _read(tar: tarfile.TarFile, member: tarfile.TarInfo) -> bytes:
    stream = tar.extractfile(member)
    assert stream is not None, member.name
    return stream.read()


def build_sample(n: int, seed: int) -> list[dict]:
    """Extract n dev-clean utterances (3-20 s) with references into WORK."""
    WORK.mkdir(parents=True, exist_ok=True)
    index = WORK / f"sample_{n}_{seed}.json"
    if index.exists():
        return json.loads(index.read_text())
    refs: dict[str, str] = {}
    with tarfile.open(TARBALL) as tar:
        members = {m.name: m for m in tar.getmembers()}
        for name, member in members.items():
            if name.endswith(".trans.txt"):
                for line in _read(tar, member).decode().splitlines():
                    uid, _, text = line.partition(" ")
                    refs[uid] = text
        flacs = sorted(k for k in members if k.endswith(".flac"))
        random.Random(seed).shuffle(flacs)
        sample = []
        for name in flacs:
            if len(sample) == n:
                break
            uid = Path(name).stem
            path = WORK / f"{uid}.flac"
            if not path.exists():
                path.write_bytes(_read(tar, members[name]))
            info = sf.info(path)
            if 3.0 <= info.duration <= 20.0:
                sample.append({"id": uid, "path": str(path),
                               "seconds": info.duration, "ref": refs[uid]})
    index.write_text(json.dumps(sample))
    return sample


def make_noisy(clip: dict, seed: int) -> str:
    path = Path(clip["path"]).with_suffix(f".snr{int(SNR_DB)}.flac")
    if path.exists():
        return str(path)
    audio, sr = sf.read(clip["path"], dtype="float32")
    assert sr == SR and audio.ndim == 1
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.standard_normal(len(audio)))
    spectrum /= np.sqrt(np.maximum(np.arange(len(spectrum)), 1))  # pink: 1/f power
    noise = np.fft.irfft(spectrum, n=len(audio)).astype(np.float32)
    gain = np.sqrt(np.mean(audio**2) / (np.mean(noise**2) * 10 ** (SNR_DB / 10)))
    mixed = audio + gain * noise
    sf.write(path, mixed / max(1.0, float(np.abs(mixed).max())), SR)
    return str(path)


def load_transcriber(kind: str, repo: str):
    if kind == "parakeet":
        from parakeet_mlx import from_pretrained
        model = from_pretrained(repo)
        return lambda p: model.transcribe(p).text
    from mlx_audio.stt.utils import load_model
    model = load_model(repo)
    return lambda p: model.generate(p).text


def score(rows: list[dict]) -> dict:
    """Per-utterance (errors, ref_words) so results can be bootstrapped."""
    import jiwer
    from whisper_normalizer.english import EnglishTextNormalizer
    norm = EnglishTextNormalizer()
    out = []
    for r in rows:
        ref, hyp = norm(r["ref"]), norm(r["hyp"])
        o = jiwer.process_words(ref, hyp if hyp else "<empty>")
        out.append((o.substitutions + o.deletions + o.insertions, len(ref.split())))
    return {"errors": [e for e, _ in out], "words": [w for _, w in out]}


def wer(errors: list[int], words: list[int]) -> float:
    return sum(errors) / sum(words)


def paired_bootstrap(base: dict, cand: dict, iters: int = 2000, seed: int = 0):
    """95% interval on WER(cand) - WER(base), resampling utterances in pairs."""
    rng = np.random.default_rng(seed)
    be, ce, w = map(np.array, (base["errors"], cand["errors"], base["words"]))
    n = len(w)
    deltas = []
    for _ in range(iters):
        idx = rng.integers(0, n, n)
        deltas.append((ce[idx].sum() - be[idx].sum()) / w[idx].sum())
    return float(np.percentile(deltas, 2.5)), float(np.percentile(deltas, 97.5))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--models", default=",".join(MODELS))
    ap.add_argument("--out", type=Path, default=ROOT / "results" / "asr_bakeoff.json")
    args = ap.parse_args()

    sample = build_sample(args.n, args.seed)
    conditions = {
        "clean": [c["path"] for c in sample],
        "noisy-10dB": [make_noisy(c, args.seed) for c in sample],
    }
    audio_seconds = sum(c["seconds"] for c in sample)
    print(f"{len(sample)} utterances, {audio_seconds / 60:.1f} min of audio")

    results: dict = {"n": len(sample), "seed": args.seed, "audio_seconds": audio_seconds,
                     "models": {}}
    raw: dict = {}
    for name in args.models.split(","):
        kind, repo = MODELS[name]
        print(f"== {name} ({repo})", flush=True)
        transcribe = load_transcriber(kind, repo)
        transcribe(sample[0]["path"])  # warm-up, excluded from timing
        results["models"][name] = {"repo": repo}
        for cond, paths in conditions.items():
            t0 = time.time()
            rows = [{"id": c["id"], "ref": c["ref"], "hyp": transcribe(p)}
                    for c, p in zip(sample, paths, strict=True)]
            wall = time.time() - t0
            raw[(name, cond)] = score(rows)
            results["models"][name][cond] = {
                "wer": wer(**raw[(name, cond)]),
                "rtfx": audio_seconds / wall,
                "hyps": {r["id"]: r["hyp"] for r in rows[:5]},
            }
            print(f"   {cond:<11} WER {results['models'][name][cond]['wer'] * 100:5.2f}%"
                  f"  {results['models'][name][cond]['rtfx']:6.0f}x real time", flush=True)
        del transcribe

    if BASELINE in args.models.split(","):
        for name in args.models.split(","):
            if name == BASELINE:
                continue
            for cond in conditions:
                lo, hi = paired_bootstrap(raw[(BASELINE, cond)], raw[(name, cond)])
                results["models"][name][cond]["delta_vs_baseline_ci95"] = [lo, hi]
                verdict = ("better" if hi < 0 else "worse" if lo > 0 else "within noise")
                print(f"{name:<16} {cond:<11} dWER {100 * (lo + hi) / 2:+.2f}pp "
                      f"[{lo * 100:+.2f}, {hi * 100:+.2f}] {verdict}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(results, indent=2))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
