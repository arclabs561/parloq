#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["librosa", "numpy", "scikit-learn"]
# ///
"""Fork B: can dependency-free acoustic features carry the prosody signal?

No SER model. Extract energy + pitch dynamics + pause structure (librosa only,
derivable from the audio recorder already keeps), and test whether they separate
RAVDESS arousal. Arousal ~ the user's emphasis/intensity axis. If simple
features separate it cleanly, fork B (signal features + timestamps) beats the
fragile classifier path.
"""
import pathlib, collections, time
import numpy as np, librosa
from sklearn.metrics import roc_auc_score

ROOT = pathlib.Path("/tmp/ravdess")
EMO = {"01":"neutral","02":"calm","03":"happy","04":"sad",
       "05":"angry","06":"fearful","07":"disgust","08":"surprised"}
PER_EMO = 40

all_wavs = sorted(ROOT.glob("Actor_*/*.wav"))
by_emo = collections.defaultdict(list)
for w in all_wavs:
    by_emo[w.stem.split("-")[2]].append(w)
wavs = [(EMO[c], w) for c in sorted(by_emo) for w in by_emo[c][:PER_EMO]]
print(f"{len(wavs)} clips ({PER_EMO}/emotion)")

def feats(path):
    y, sr = librosa.load(str(path), sr=16000, mono=True)
    rms = librosa.feature.rms(y=y)[0]
    f0, voiced, _ = librosa.pyin(y, fmin=65, fmax=400, sr=sr)
    f0v = f0[~np.isnan(f0)]
    sil = rms < (0.15 * rms.max() + 1e-9)
    return {
        "rms_mean": float(rms.mean()),
        "rms_std": float(rms.std()),
        "f0_std": float(f0v.std()) if f0v.size > 5 else 0.0,
        "f0_range": float(np.ptp(f0v)) if f0v.size > 5 else 0.0,
        "pause_ratio": float(sil.mean()),
    }

t0 = time.perf_counter()
rows = []
for i, (emo, w) in enumerate(wavs):
    rows.append((emo, feats(w)))
    if i % 80 == 0: print(f"  {i}/{len(wavs)}")
print(f"features in {time.perf_counter()-t0:.0f}s")

KEYS = ["rms_mean", "rms_std", "f0_std", "f0_range", "pause_ratio"]
# per-emotion means
print("\n=== per-emotion feature means ===")
print("emotion    " + "  ".join(f"{k:>10s}" for k in KEYS))
agg = collections.defaultdict(list)
for emo, f in rows: agg[emo].append(f)
for k in ("angry","happy","surprised","fearful","disgust","neutral","calm","sad"):
    m = {key: np.mean([f[key] for f in agg[k]]) for key in KEYS}
    print(f"{k:9s}  " + "  ".join(f"{m[key]:10.4f}" for key in KEYS))

# separability: each feature vs high/low arousal
HI = {"angry","happy","fearful","surprised"}; LO = {"sad","calm","neutral"}
print("\n=== arousal separability (AUC, high vs low arousal) ===")
for key in KEYS:
    y, s = [], []
    for emo, f in rows:
        if emo in HI or emo in LO:
            y.append(1 if emo in HI else 0); s.append(f[key])
    auc = roc_auc_score(y, s)
    auc = max(auc, 1 - auc)  # feature may correlate negatively
    print(f"  {key:12s} AUC={auc:.3f}")
print("\nAUC>=0.8 = this feature alone separates arousal; ~0.5 = no signal")
