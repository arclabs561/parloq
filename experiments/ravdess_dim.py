#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["transformers", "torch", "soundfile", "librosa", "numpy", "scikit-learn"]
# ///
"""Fork A: does the dimensional A/V/D model separate RAVDESS emotions?

audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim outputs arousal,
dominance, valence in [0,1] via a custom regression head (not a pipeline).
Test: per-emotion mean A/V, plus AUC for arousal->high/low-arousal grouping
and valence->pos/neg grouping. Arousal ~ the user's emphasis/intensity axis.
"""
import time, pathlib, collections
import numpy as np, librosa, torch, torch.nn as nn
from transformers import Wav2Vec2Processor
from transformers.models.wav2vec2.modeling_wav2vec2 import Wav2Vec2Model, Wav2Vec2PreTrainedModel
from sklearn.metrics import roc_auc_score

MODEL = "audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim"
ROOT = pathlib.Path("/tmp/ravdess")
EMO = {"01":"neutral","02":"calm","03":"happy","04":"sad",
       "05":"angry","06":"fearful","07":"disgust","08":"surprised"}

class RegressionHead(nn.Module):
    def __init__(self, config):
        super().__init__()
        self.dense = nn.Linear(config.hidden_size, config.hidden_size)
        self.dropout = nn.Dropout(config.final_dropout)
        self.out_proj = nn.Linear(config.hidden_size, config.num_labels)
    def forward(self, x):
        x = self.dropout(x); x = self.dense(x); x = torch.tanh(x)
        x = self.dropout(x); return self.out_proj(x)

class EmotionModel(Wav2Vec2PreTrainedModel):
    def __init__(self, config):
        super().__init__(config)
        self.wav2vec2 = Wav2Vec2Model(config)
        self.classifier = RegressionHead(config)
        self.init_weights()
    def forward(self, input_values):
        h = self.wav2vec2(input_values)[0]
        h = torch.mean(h, dim=1)
        return self.classifier(h)  # [arousal, dominance, valence]

print("loading model (~1.2GB first time)...")
t0 = time.perf_counter()
proc = Wav2Vec2Processor.from_pretrained(MODEL)
model = EmotionModel.from_pretrained(MODEL).eval()
print(f"load: {time.perf_counter()-t0:.0f}s")

all_wavs = sorted(ROOT.glob("Actor_*/*.wav"))
# subsample up to N per emotion: large model is unbatched, bound runtime
PER_EMO = 40
by_emo = collections.defaultdict(list)
for w in all_wavs:
    by_emo[w.stem.split("-")[2]].append(w)
wavs = [w for code in sorted(by_emo) for w in by_emo[code][:PER_EMO]]
print(f"subsampled {len(wavs)} clips ({PER_EMO}/emotion) of {len(all_wavs)}")
rows = []
t0 = time.perf_counter()
with torch.no_grad():
    for i, w in enumerate(wavs):
        a, _ = librosa.load(str(w), sr=16000, mono=True)
        x = proc(a, sampling_rate=16000, return_tensors="pt").input_values
        ar, do, va = model(x)[0].tolist()
        rows.append((EMO[w.stem.split("-")[2]], ar, va))
        if i % 240 == 0: print(f"  {i}/{len(wavs)}")
print(f"inference: {len(wavs)} clips in {time.perf_counter()-t0:.0f}s")

# per-emotion means
agg = collections.defaultdict(lambda: [[],[]])
for emo, ar, va in rows:
    agg[emo][0].append(ar); agg[emo][1].append(va)
print("\n=== per-emotion mean [arousal, valence] (0..1) ===")
for k in ("angry","happy","surprised","fearful","disgust","neutral","calm","sad"):
    A = np.mean(agg[k][0]); V = np.mean(agg[k][1])
    print(f"  {k:9s} arousal={A:.3f}  valence={V:.3f}  (n={len(agg[k][0])})")

# separability AUCs
HI = {"angry","happy","fearful","surprised"}; LO = {"sad","calm","neutral"}
POS = {"happy","calm"}; NEG = {"angry","sad","fearful","disgust"}
ar_y, ar_s, va_y, va_s = [], [], [], []
for emo, ar, va in rows:
    if emo in HI or emo in LO: ar_y.append(1 if emo in HI else 0); ar_s.append(ar)
    if emo in POS or emo in NEG: va_y.append(1 if emo in POS else 0); va_s.append(va)
print(f"\narousal AUC (high vs low arousal emotions): {roc_auc_score(ar_y, ar_s):.3f}  (n={len(ar_y)})")
print(f"valence AUC (positive vs negative emotions): {roc_auc_score(va_y, va_s):.3f}  (n={len(va_y)})")
print("\nverdict: AUC>=0.8 = dimension cleanly separates; ~0.5 = no signal")
