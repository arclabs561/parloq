#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["requests"]
# ///
"""Refinement: isolate code-vs-word and measure the true noise floor.

The hard eval showed coded [arousal:high] tags (17% SUBSTANTIVE) sit BELOW the
placebo floor (28%), i.e. no real signal, while explicit emotion-words cleared
it. Two questions this resolves:

  - NOISE FLOOR (rigorous): compare untagged-vs-untagged-RESAMPLE. Pure LLM
    sampling variance, no tag involved. This is the honest baseline to subtract;
    a condition only carries signal if its SUBSTANTIVE rate exceeds this.
  - CODE vs WORD on the SAME arousal dimension: does [emphatic] (a word the
    model knows) beat [arousal:high] (an opaque code) for the same intended
    meaning? If yes, the fix for the MVP is "emit words, not codes."

Same texts across conditions so the only variable is the tag form.
Env: EVAL_OPENROUTER_API_KEY (or OPENROUTER_API_KEY). Run: uv run prosody-bench/ab_tag_refine.py
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
TEXTS = ["let's go with the second option","can you review this function",
         "we should refactor the auth module","ship the release"]
# conditions: how to build the "B" input from the text
COND = {"noise": None, "code": "[arousal:high]", "word": "[emphatic]"}

def call(model, system, user, temperature=0.7, max_tokens=180, retries=2):
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
def jp(text, desc, A, B):
    return (f'A user dictated: "{text}".\nReply A:\n"{A}"\n\nReply B {desc}:\n"{B}"\n\n'
            f'First token EXACTLY one of: SUBSTANTIVE (B changes its actual content: a different '
            f'recommendation/action/question/decision) / COSMETIC (only tone or wording differs, '
            f'same substance) / IGNORED (no meaningful difference). Then one short reason.')

def main():
    f=pathlib.Path("/tmp/or_models.txt")
    panel=[m for m in PANEL if (not f.exists() or m in set(f.read_text().split()))]
    print(f"panel ({len(panel)}), texts {len(TEXTS)}, conditions {list(COND)}\n")

    # responses: A (base), A' (resample for noise), code-B, word-B
    # temperature=0: A and A2 should be ~identical (noise floor -> ~0), so any
    # code/word substantive difference is the TAG's causal effect, not sampling.
    def build(model, ti):
        t=TEXTS[ti]
        return {"A":  call(model,RESP_SYS,t,temperature=0),
                "A2": call(model,RESP_SYS,t,temperature=0),
                "code": call(model,RESP_SYS,f"{COND['code']} {t}",temperature=0),
                "word": call(model,RESP_SYS,f"{COND['word']} {t}",temperature=0)}
    t0=time.perf_counter(); R={}
    with ThreadPoolExecutor(max_workers=12) as ex:
        for (m,ti),resp in zip([(m,ti) for m in panel for ti in range(len(TEXTS))],
                               ex.map(lambda mt: build(*mt), [(m,ti) for m in panel for ti in range(len(TEXTS))])):
            R[(m,ti)]=resp
    print(f"responses done in {time.perf_counter()-t0:.0f}s")

    # judge: noise (A vs A2), code (A vs code), word (A vs word)
    pairs=[]
    for m in panel:
        for ti in range(len(TEXTS)):
            pairs.append((m,ti,"noise","(an independent re-sample, no tag)",R[(m,ti)]["A"],R[(m,ti)]["A2"]))
            pairs.append((m,ti,"code", f'(input prefixed {COND["code"]})',     R[(m,ti)]["A"],R[(m,ti)]["code"]))
            pairs.append((m,ti,"word", f'(input prefixed {COND["word"]})',     R[(m,ti)]["A"],R[(m,ti)]["word"]))
    def judge(p):
        m,ti,cond,desc,A,B=p
        v=call(JUDGE,JUDGE_SYS,jp(TEXTS[ti],desc,A,B),temperature=0,max_tokens=70)
        lab=v.split()[0].upper().strip(".:") if v and not v.startswith("<ERROR") else "ERROR"
        if lab not in ("SUBSTANTIVE","COSMETIC","IGNORED"): lab="UNPARSED"
        return (m,ti,cond,lab,v)
    t0=time.perf_counter(); V=collections.defaultdict(list); raw=[]
    with ThreadPoolExecutor(max_workers=12) as ex:
        for m,ti,cond,lab,v in ex.map(judge,pairs):
            V[cond].append(lab); raw.append({"model":m,"text":TEXTS[ti],"cond":cond,"verdict":lab,"note":v})
    print(f"judged in {time.perf_counter()-t0:.0f}s\n")

    print(f"{'condition':8s}  {'SUBSTANTIVE':>11s}  {'COSMETIC':>9s}  {'IGNORED':>8s}  n")
    rates={}
    for cond in ("noise","code","word"):
        labs=V[cond]; n=len(labs); c=collections.Counter(labs)
        rates[cond]=c.get("SUBSTANTIVE",0)/n
        print(f"{cond:8s}  {c.get('SUBSTANTIVE',0)/n*100:10.0f}%  {c.get('COSMETIC',0)/n*100:8.0f}%  {c.get('IGNORED',0)/n*100:7.0f}%  {n}")
    print(f"\nnoise floor (subtract this): {rates['noise']*100:.0f}%")
    print(f"code signal above floor: {(rates['code']-rates['noise'])*100:+.0f} pts")
    print(f"word signal above floor: {(rates['word']-rates['noise'])*100:+.0f} pts")

    p=pathlib.Path(__file__).resolve().parent.parent/"results"/f"ab_refine_temp0_{datetime.date.today().isoformat()}.json"
    p.write_text(json.dumps({"panel":panel,"texts":TEXTS,"rates":rates,"raw":raw},indent=2))
    print(f"saved -> results/{p.name}")

if __name__=="__main__": main()
