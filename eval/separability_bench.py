#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["librosa", "numpy", "scikit-learn"]
# ///
"""Separability benchmark: how well does a tagger separate a prosodic dimension?

The reusable form of the 4 one-off experiments (ser_probe, ravdess_run,
ravdess_dim, prosody_features). A tagger emits per-dimension scores; the bench
reports symmetrized ROC-AUC per (tagger, dimension) plus extraction latency,
over a labeled dataset. Add a tagger to TAGGERS to benchmark it.

AUC >= 0.8 = separates; ~0.5 = no signal. The expected theme: cheap signal
features separate AROUSAL but not VALENCE (valence needs a learned model).

Run: uv run eval/separability_bench.py
"""
import json, time, pathlib, collections, datetime, urllib.request, zipfile
import numpy as np, librosa
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import cross_val_predict

# ---- dataset (RAVDESS; circumplex labels for arousal/valence) ----------------
RAVDESS_ZIP = "https://zenodo.org/records/1188976/files/Audio_Speech_Actors_01-24.zip?download=1"
EMO = {"01":"neutral","02":"calm","03":"happy","04":"sad",
       "05":"angry","06":"fearful","07":"disgust","08":"surprised"}
AROUSAL_HI = {"angry","happy","fearful","surprised"}; AROUSAL_LO = {"sad","calm","neutral"}
VALENCE_POS = {"happy","calm"};                       VALENCE_NEG = {"angry","sad","fearful","disgust"}

def ravdess_root():
    for c in (pathlib.Path("/tmp/ravdess"), pathlib.Path(__file__).resolve().parent.parent/"data"/"ravdess"):
        if any(c.glob("Actor_*")): return c
    dst = pathlib.Path(__file__).resolve().parent.parent/"data"/"ravdess"; dst.mkdir(parents=True, exist_ok=True)
    z = dst/"speech.zip"; print("downloading RAVDESS (~208MB)..."); urllib.request.urlretrieve(RAVDESS_ZIP, z)
    with zipfile.ZipFile(z) as zf: zf.extractall(dst)
    return dst

def load_ravdess(per_emo=40):
    by = collections.defaultdict(list)
    for w in sorted(ravdess_root().glob("Actor_*/*.wav")): by[w.stem.split("-")[2]].append(w)
    clips = []
    for code in sorted(by):
        emo = EMO[code]
        for w in by[code][:per_emo]:
            clips.append({"path": w, "emotion": emo,
                          "arousal": 1 if emo in AROUSAL_HI else 0 if emo in AROUSAL_LO else None,
                          "valence": 1 if emo in VALENCE_POS else 0 if emo in VALENCE_NEG else None})
    return clips

# ---- features (cheap, model-free, derivable from recorder audio) -------------
def extract(path):
    y, sr = librosa.load(str(path), sr=16000, mono=True)
    rms = librosa.feature.rms(y=y)[0]
    f0, _, _ = librosa.pyin(y, fmin=65, fmax=400, sr=sr)
    f0v = f0[~np.isnan(f0)]
    return {"rms_mean": float(rms.mean()), "rms_std": float(rms.std()),
            "f0_std": float(f0v.std()) if f0v.size > 5 else 0.0,
            "f0_range": float(np.ptp(f0v)) if f0v.size > 5 else 0.0,
            "pause_ratio": float((rms < 0.15*rms.max()+1e-9).mean())}

# ---- taggers: feature-bundle -> {dimension: score}. Add entries here. --------
SINGLE = {
    "energy_std":   lambda f: {"arousal": f["rms_std"]},
    "energy_mean":  lambda f: {"arousal": f["rms_mean"]},
    "pitch_std":    lambda f: {"arousal": f["f0_std"]},
    "pitch_range":  lambda f: {"arousal": f["f0_range"]},
    "pause_ratio":  lambda f: {"arousal": f["pause_ratio"]},
}
FEAT_KEYS = ["rms_mean","rms_std","f0_std","f0_range","pause_ratio"]

def sym_auc(y, s):
    a = roc_auc_score(y, s); return max(a, 1-a)

def main():
    clips = load_ravdess()
    print(f"{len(clips)} clips")
    t0 = time.perf_counter()
    F = [extract(c["path"]) for c in clips]
    lat_ms = (time.perf_counter()-t0)/len(clips)*1000
    print(f"feature extraction: {lat_ms:.0f}ms/clip\n")

    results = {"dataset":"ravdess", "n":len(clips), "latency_ms_per_clip":round(lat_ms,1),
               "taggers":{}}
    X = np.array([[f[k] for k in FEAT_KEYS] for f in F])

    for dim in ("arousal","valence"):
        idx = [i for i,c in enumerate(clips) if c[dim] is not None]
        y = np.array([clips[i][dim] for i in idx])
        # single-feature taggers
        for name, tag in SINGLE.items():
            s = np.array([tag(F[i])[dim] for i in idx if dim in tag(F[i])])
            if s.size == len(y):
                auc = sym_auc(y, s)
                results["taggers"].setdefault(name, {})[dim] = round(auc,3)
        # learned ceiling: logreg over all cheap features (cross-validated)
        clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000))
        proba = cross_val_predict(clf, X[idx], y, cv=5, method="predict_proba")[:,1]
        results["taggers"].setdefault("logreg_allfeats", {})[dim] = round(roc_auc_score(y, proba),3)

    # table
    names = list(results["taggers"])
    print(f"{'tagger':16s}  {'arousal':>8s}  {'valence':>8s}")
    for n in names:
        a = results["taggers"][n].get("arousal","-"); v = results["taggers"][n].get("valence","-")
        print(f"{n:16s}  {str(a):>8s}  {str(v):>8s}")
    print("\nAUC>=0.8 separates; ~0.5 no signal. Theme check: arousal high, valence ~chance.")

    out = pathlib.Path(__file__).resolve().parent.parent/"results"
    stamp = datetime.date.today().isoformat()
    (out/f"separability_bench_{stamp}.json").write_text(json.dumps(results, indent=2))
    print(f"\nsaved -> results/separability_bench_{stamp}.json")

if __name__ == "__main__":
    main()
