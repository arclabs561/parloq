#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["transformers", "torch", "soundfile", "librosa", "numpy"]
# ///
"""Phase-1 accuracy check + phase-3 A/B seed on RAVDESS.

Downloads RAVDESS speech audio, runs the phase-1 SER model, scores accuracy
on the 4 classes the model (superb/wav2vec2-base-superb-er: neu/hap/ang/sad)
and RAVDESS share, and emits tagged-vs-untagged transcript pairs for the A/B.
RAVDESS statements are fixed text, so the 'transcript' is known (no ASR).
"""
import json, time, zipfile, urllib.request, pathlib, collections
import numpy as np, librosa

ZIP_URL = "https://zenodo.org/records/1188976/files/Audio_Speech_Actors_01-24.zip?download=1"
ROOT = pathlib.Path("/tmp/ravdess"); ROOT.mkdir(exist_ok=True)
ZIP = ROOT / "speech.zip"
MODEL = "superb/wav2vec2-base-superb-er"

EMO = {"01":"neutral","02":"calm","03":"happy","04":"sad",
       "05":"angry","06":"fearful","07":"disgust","08":"surprised"}
# RAVDESS emotion -> model label space (model = IEMOCAP 4-class). calm folded to neu.
TO_MODEL = {"neutral":"neu","calm":"neu","happy":"hap","sad":"sad","angry":"ang"}
STMT = {"01":"Kids are talking by the door","02":"Dogs are sitting by the door"}

# 1. download + extract
if not ZIP.exists():
    print("downloading RAVDESS (~208MB)...")
    urllib.request.urlretrieve(ZIP_URL, ZIP)
if not any(ROOT.glob("Actor_*")):
    print("extracting...")
    with zipfile.ZipFile(ZIP) as z: z.extractall(ROOT)
wavs = sorted(ROOT.glob("Actor_*/*.wav"))
print(f"clips: {len(wavs)}")

# 2. parse
items = []
for w in wavs:
    f = w.stem.split("-")
    if len(f) != 7: continue
    emo = EMO[f[2]]
    items.append({"path": w, "emo": emo, "intensity": f[3],
                  "text": STMT[f[4]], "model_true": TO_MODEL.get(emo)})

# 3. load model + batch inference
from transformers import pipeline
t0 = time.perf_counter()
clf = pipeline("audio-classification", model=MODEL)
print(f"model load: {time.perf_counter()-t0:.0f}s")

def load(p):  # RAVDESS is 48kHz; model wants 16k mono float32
    a, _ = librosa.load(str(p), sr=16000, mono=True)
    return a.astype(np.float32)

t0 = time.perf_counter()
preds = []
B = 32
for i in range(0, len(items), B):
    batch = [load(it["path"]) for it in items[i:i+B]]
    outs = clf(batch, top_k=1, batch_size=B)
    for o in outs:
        preds.append(o[0]["label"] if isinstance(o, list) else o["label"])
    if i % 320 == 0: print(f"  {i+len(batch)}/{len(items)}")
dt = time.perf_counter() - t0
print(f"inference: {len(items)} clips in {dt:.0f}s ({dt/len(items)*1000:.0f}ms/clip)")

for it, p in zip(items, preds): it["pred"] = p

# 4. accuracy on the shared 4 classes (calm folded into neutral)
scored = [it for it in items if it["model_true"] is not None]
correct = sum(it["pred"] == it["model_true"] for it in scored)
print(f"\n=== ACCURACY on shared classes (n={len(scored)}, calm->neu folded) ===")
print(f"overall: {correct/len(scored)*100:.1f}%")
perclass = collections.defaultdict(lambda: [0,0])
for it in scored:
    perclass[it["model_true"]][1] += 1
    perclass[it["model_true"]][0] += it["pred"] == it["model_true"]
for k in ("neu","hap","sad","ang"):
    c,n = perclass[k]
    if n: print(f"  {k}: {c/n*100:.0f}% ({c}/{n})")
# confusion
print("confusion (true -> predicted counts):")
conf = collections.defaultdict(lambda: collections.Counter())
for it in scored: conf[it["model_true"]][it["pred"]] += 1
for k in ("neu","hap","sad","ang"):
    print(f"  {k}: {dict(conf[k])}")

# 5. how the model forces out-of-distribution emotions (fearful/disgust/surprised)
ood = collections.Counter(it["pred"] for it in items if it["model_true"] is None)
print(f"\nOOD emotions (fearful/disgust/surprised) forced into: {dict(ood)}")

# 6. A/B pairs (sample 24, balanced) -> JSON for phase 3
import random; random.seed(0)
sample = random.sample(scored, min(24, len(scored)))
pairs = [{"audio": str(it["path"]), "true_emotion": it["emo"],
          "pred_tag": it["pred"], "untagged": it["text"],
          "tagged": f"[{it['pred']}] {it['text']}"} for it in sample]
out = ROOT / "ab_pairs.json"; out.write_text(json.dumps(pairs, indent=2))
print(f"\nA/B pairs -> {out} ({len(pairs)} pairs). Examples:")
for p in pairs[:4]:
    print(f"  true={p['true_emotion']:9s} untagged={p['untagged']!r}  tagged={p['tagged']!r}")
