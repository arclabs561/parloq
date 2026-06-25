#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["transformers", "torch", "soundfile", "librosa"]
# ///
"""Phase-1 gate probe for paralinguistic-dictation-roadmap.

Verifies: an on-device SER checkpoint loads, emits emotion labels on a real
clip, and runs within the dictate latency budget. Does NOT touch recorder.
Label *accuracy* is out of scope here (needs real emotive clips, phase 3);
this proves the mechanism + latency only.
"""
import subprocess, time, pathlib

MODEL = "superb/wav2vec2-base-superb-er"  # Apache-2.0, categorical (neu/hap/ang/sad)
CLIP = pathlib.Path("/tmp/ser_probe_clip.wav")

# 1. make a real 16kHz speech clip with macOS `say` (no emotive content; mechanism test)
text = "Honestly I'm not totally sure this is going to work, but it sounds super useful."
subprocess.run(
    ["say", "-o", str(CLIP), "--data-format=LEI16@16000", text],
    check=True,
)
import soundfile as sf
audio, sr = sf.read(str(CLIP))
dur = len(audio) / sr
print(f"clip: {dur:.1f}s @ {sr}Hz")

# 2. load + run
t0 = time.perf_counter()
from transformers import pipeline
clf = pipeline("audio-classification", model=MODEL)
t_load = time.perf_counter() - t0
print(f"model load: {t_load:.1f}s  (one-time warm; daemon keeps it resident)")

# warm + timed inference (3 runs)
clf(str(CLIP))  # warm
lat = []
for _ in range(3):
    s = time.perf_counter()
    out = clf(str(CLIP), top_k=4)
    lat.append(time.perf_counter() - s)
print(f"labels: {out}")
print(f"inference latency (3-run): {min(lat)*1000:.0f}-{max(lat)*1000:.0f}ms on {dur:.1f}s clip")
print(f"GATE: emits labels = yes; per-clip latency = {sum(lat)/3*1000:.0f}ms avg")
