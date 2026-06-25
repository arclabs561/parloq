#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["requests"]
# ///
"""Disentangle: is the value in the PROSODY DIMENSION (arousal, energy can make)
or in EMOTION-WORD SEMANTICS (needs a model)? And does sentence affect-content
drive it more than the tag?

Cross tag-condition x sentence-type at temp 0 (clean causal), with same-vs-same
noise floor per type. Conditions: arousal_code [arousal:high], arousal_word
[emphatic], affect_word [frustrated]. Sentence types: neutral task vs negative-
affect. If arousal_* ~ affect_word, the producible arousal tag is competitive
(MVP justified). If affect_word >> arousal_*, the value is emotion-word
semantics the cheap tagger can't make.

Env: EVAL_OPENROUTER_API_KEY (or OPENROUTER_API_KEY). Run: uv run prosody-bench/ab_disentangle.py
"""
import os, json, time, pathlib, datetime, collections
from concurrent.futures import ThreadPoolExecutor
import requests

KEY = os.environ.get("EVAL_OPENROUTER_API_KEY") or os.environ["OPENROUTER_API_KEY"]
URL = "https://openrouter.ai/api/v1/chat/completions"
HDR = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
PANEL = ["openai/gpt-4o-mini","anthropic/claude-3.5-haiku","meta-llama/llama-3.3-70b-instruct",
         "mistralai/mistral-small-3.2-24b-instruct","qwen/qwen-2.5-72b-instruct","deepseek/deepseek-chat-v3.1"]
JUDGE = "openai/gpt-4o-mini"
RESP_SYS = "You are a helpful assistant replying to a short message from the user. Reply concisely, 2-4 sentences."
SENTENCES = [
    ("neutral","let's go with the second option"),
    ("neutral","can you review this function"),
    ("neutral","we should refactor the auth module"),
    ("neutral","ship the release"),
    ("affect","this is the third time it crashed"),
    ("affect","we're way behind on this"),
    ("affect","I've been stuck on this for hours"),
    ("affect","the build keeps failing"),
]
TAGS = {"arousal_code":"[arousal:high]","arousal_word":"[emphatic]","affect_word":"[frustrated]"}

def call(model, system, user, temperature=0, max_tokens=180, retries=2):
    body={"model":model,"max_tokens":max_tokens,"temperature":temperature,
          "messages":[{"role":"system","content":system},{"role":"user","content":user}]}
    for a in range(retries+1):
        try:
            r=requests.post(URL,headers=HDR,json=body,timeout=60)
            if r.status_code==200: return r.json()["choices"][0]["message"]["content"].strip()
            err=f"HTTP {r.status_code}: {r.text[:100]}"
        except Exception as e: err=str(e)[:100]
        time.sleep(1.5*(a+1))
    return f"<ERROR {err}>"

JUDGE_SYS="You are a strict evaluator. Be conservative: default to the lower category when unsure."
def jp(text, A, B):
    return (f'A user said: "{text}".\nReply A:\n"{A}"\n\nReply B:\n"{B}"\n\n'
            f'First token EXACTLY one of: SUBSTANTIVE (B changes its actual content: a different '
            f'recommendation/action/question/decision) / COSMETIC (only tone/wording differs, same '
            f'substance) / IGNORED (no meaningful difference). Then one short reason.')

def main():
    f=pathlib.Path("/tmp/or_models.txt")
    panel=[m for m in PANEL if (not f.exists() or m in set(f.read_text().split()))]
    print(f"panel ({len(panel)}), sentences {len(SENTENCES)}, tags {list(TAGS)}\n")

    def build(model, si):
        _,t=SENTENCES[si]
        d={"A":call(model,RESP_SYS,t),"A2":call(model,RESP_SYS,t)}
        for name,tag in TAGS.items(): d[name]=call(model,RESP_SYS,f"{tag} {t}")
        return d
    t0=time.perf_counter(); R={}
    keys=[(m,si) for m in panel for si in range(len(SENTENCES))]
    with ThreadPoolExecutor(max_workers=12) as ex:
        for k,resp in zip(keys, ex.map(lambda mt: build(*mt), keys)): R[k]=resp
    print(f"responses done in {time.perf_counter()-t0:.0f}s")

    # judge: noise (A vs A2) + each tag (A vs tag)
    pairs=[]
    for m in panel:
        for si in range(len(SENTENCES)):
            pairs.append((m,si,"noise",R[(m,si)]["A"],R[(m,si)]["A2"]))
            for name in TAGS: pairs.append((m,si,name,R[(m,si)]["A"],R[(m,si)][name]))
    def judge(p):
        m,si,cond,A,B=p
        v=call(JUDGE,JUDGE_SYS,jp(SENTENCES[si][1],A,B),temperature=0,max_tokens=70)
        lab=v.split()[0].upper().strip(".:") if v and not v.startswith("<ERROR") else "ERR"
        if lab not in ("SUBSTANTIVE","COSMETIC","IGNORED"): lab="UNPARSED"
        return (m,si,cond,lab)
    t0=time.perf_counter(); cell=collections.defaultdict(list)
    with ThreadPoolExecutor(max_workers=12) as ex:
        for m,si,cond,lab in ex.map(judge,pairs):
            cell[(SENTENCES[si][0],cond)].append(lab)
    print(f"judged in {time.perf_counter()-t0:.0f}s\n")

    def sub(stype,cond):
        labs=cell[(stype,cond)]; return labs.count("SUBSTANTIVE")/len(labs) if labs else 0
    print(f"{'condition':14s}  {'neutral':>16s}  {'affect':>16s}")
    print(f"{'(noise floor)':14s}  {sub('neutral','noise')*100:6.0f}% (raw)    {sub('affect','noise')*100:6.0f}% (raw)")
    res={"neutral":{},"affect":{}}
    for cond in TAGS:
        nn=sub('neutral',cond)-sub('neutral','noise'); aa=sub('affect',cond)-sub('affect','noise')
        res['neutral'][cond]=round(nn,3); res['affect'][cond]=round(aa,3)
        print(f"{cond:14s}  {sub('neutral',cond)*100:5.0f}% ({nn*100:+4.0f} net)  {sub('affect',cond)*100:5.0f}% ({aa*100:+4.0f} net)")
    print("\nnet = above per-type noise floor. arousal_* ~ affect_word => arousal tag competitive (MVP ok).")
    print("affect_word >> arousal_* => value is emotion-word semantics the energy tagger can't make.")

    p=pathlib.Path(__file__).resolve().parent.parent/"results"/f"ab_disentangle_{datetime.date.today().isoformat()}.json"
    p.write_text(json.dumps({"panel":panel,"sentences":SENTENCES,"net_above_floor":res,
        "floor":{"neutral":sub('neutral','noise'),"affect":sub('affect','noise')}},indent=2))
    print(f"saved -> results/{p.name}")

if __name__=="__main__": main()
