#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["requests"]
# ///
"""Harder A/B: the naive eval hit 100% on explicit English emotion-words, which
is the easy case. This attacks that result four ways:

  - STRICTER JUDGE: 3-way SUBSTANTIVE / COSMETIC / IGNORED. COSMETIC = only adds
    empathy wording, same substance (recommendation/action/info). The real
    metric is SUBSTANTIVE rate; 100% should collapse.
  - INCONGRUENT cases: tag contradicts the words (sarcasm/masking). The true
    "does prosody override lexical content" test (CP-Bench).
  - CODED tags: [arousal:high]/[arousal:low] — what the energy tagger actually
    emits, no emotion word to lean on. The MVP-relevant condition.
  - PLACEBO: [neutral]/junk tags on neutral text. Control: SUBSTANTIVE here
    should be ~0; if not, the judge is over-firing and the whole eval is suspect.

Env: EVAL_OPENROUTER_API_KEY (or OPENROUTER_API_KEY). Run: uv run prosody-bench/ab_tag_response_hard.py
(Self-contained per uv-script convention; shares the small call() shape with
ab_tag_response.py by design, not via a lib until a 3rd consumer appears.)
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

CASES = [
  # congruent English (the easy baseline)
  ("congruent", "I think we should rewrite the auth module", "[uncertain]"),
  ("congruent", "this is the third time it crashed",         "[frustrated]"),
  ("congruent", "we need to ship this today",                "[stressed]"),
  # incongruent: tag contradicts the words (does prosody override lexis?)
  ("incongruent", "everything is working perfectly now",     "[frustrated]"),
  ("incongruent", "this whole thing is completely broken",   "[calm]"),
  ("incongruent", "I guess we could try your idea",          "[excited]"),
  # coded arousal: what the energy tagger emits, no emotion word
  ("coded", "let's go with the second option",               "[arousal:high]"),
  ("coded", "let's go with the second option",               "[arousal:low]"),
  ("coded", "can you review this function",                  "[arousal:high]"),
  # placebo control: should be ~0 SUBSTANTIVE
  ("placebo", "the meeting is at three",                     "[neutral]"),
  ("placebo", "the file is in the src folder",               "[xq7]"),
  ("placebo", "here is the config",                          "[neutral]"),
]

def call(model, system, user, max_tokens=180, retries=2):
    body = {"model": model, "max_tokens": max_tokens,
            "messages":[{"role":"system","content":system},{"role":"user","content":user}]}
    for a in range(retries+1):
        try:
            r = requests.post(URL, headers=HDR, json=body, timeout=60)
            if r.status_code == 200: return r.json()["choices"][0]["message"]["content"].strip()
            err = f"HTTP {r.status_code}: {r.text[:100]}"
        except Exception as e: err = str(e)[:100]
        time.sleep(1.5*(a+1))
    return f"<ERROR {err}>"

JUDGE_SYS = "You are a strict evaluator. Be conservative: default to the lower category when unsure."
def judge_prompt(text, tag, untagged, tagged):
    return (f'A user dictated: "{text}" with tone tag {tag}.\n'
            f'Reply A (no tag):\n"{untagged}"\n\nReply B (input prefixed with {tag}):\n"{tagged}"\n\n'
            f'Classify how B differs from A. First token EXACTLY one of:\n'
            f'SUBSTANTIVE = B changes its actual content: a different recommendation, action, '
            f'question, or decision driven by the tag.\n'
            f'COSMETIC = B only adds/changes tone or empathy wording; the substance '
            f'(recommendation/info/action) is the same as A.\n'
            f'IGNORED = no meaningful difference.\n'
            f'Then one short reason.')

def main():
    f = pathlib.Path("/tmp/or_models.txt")
    panel = [m for m in PANEL if (not f.exists() or m in set(f.read_text().split()))]
    print(f"panel ({len(panel)}), cases {len(CASES)} across "
          f"{sorted(set(c[0] for c in CASES))}\n")

    jobs = [(m, ci, kind, (f"{CASES[ci][2]} {CASES[ci][1]}" if kind=="tagged" else CASES[ci][1]))
            for m in panel for ci in range(len(CASES)) for kind in ("untagged","tagged")]
    t0=time.perf_counter(); out={}
    with ThreadPoolExecutor(max_workers=12) as ex:
        for m,ci,kind,resp in ex.map(lambda j:(j[0],j[1],j[2],call(j[0],RESP_SYS,j[3])), jobs):
            out[(m,ci,kind)] = resp
    print(f"{len(jobs)} response calls in {time.perf_counter()-t0:.0f}s")

    def jd(job):
        m,ci=job; cond,text,tag=CASES[ci]
        v=call(JUDGE,JUDGE_SYS,judge_prompt(text,tag,out[(m,ci,"untagged")],out[(m,ci,"tagged")]),max_tokens=80)
        lab=v.split()[0].upper().strip(".:") if v and not v.startswith("<ERROR") else "ERROR"
        if lab not in ("SUBSTANTIVE","COSMETIC","IGNORED"): lab="UNPARSED"
        return (m,ci,lab,v)
    t0=time.perf_counter(); verd={}
    with ThreadPoolExecutor(max_workers=12) as ex:
        for m,ci,lab,v in ex.map(jd,[(m,ci) for m in panel for ci in range(len(CASES))]):
            verd[(m,ci)]=(lab,v)
    print(f"{len(verd)} judge calls in {time.perf_counter()-t0:.0f}s\n")

    # by condition: SUBSTANTIVE / COSMETIC / IGNORED rates
    conds=sorted(set(c[0] for c in CASES))
    print(f"{'condition':12s}  {'SUBSTANTIVE':>12s}  {'COSMETIC':>9s}  {'IGNORED':>8s}  n")
    cond_rows={}
    for cond in conds:
        idxs=[ci for ci,c in enumerate(CASES) if c[0]==cond]
        labs=[verd[(m,ci)][0] for m in panel for ci in idxs]
        n=len(labs); cnt=collections.Counter(labs)
        cond_rows[cond]={k:cnt.get(k,0) for k in ("SUBSTANTIVE","COSMETIC","IGNORED","UNPARSED")}
        print(f"{cond:12s}  {cnt.get('SUBSTANTIVE',0)/n*100:11.0f}%  {cnt.get('COSMETIC',0)/n*100:8.0f}%  {cnt.get('IGNORED',0)/n*100:7.0f}%  {n}")

    allsub=sum(1 for m in panel for ci in range(len(CASES)) if verd[(m,ci)][0]=="SUBSTANTIVE")
    tot=len(panel)*len(CASES)
    print(f"\noverall SUBSTANTIVE: {allsub/tot*100:.0f}% (vs 100% ADAPTED in the soft eval)")
    print("placebo SUBSTANTIVE should be ~0; if high the judge over-fires.")

    blob={"panel":panel,"judge":JUDGE,"by_condition":cond_rows,
          "raw":[{"model":m,"cond":CASES[ci][0],"text":CASES[ci][1],"tag":CASES[ci][2],
                  "untagged":out[(m,ci,"untagged")],"tagged":out[(m,ci,"tagged")],
                  "verdict":verd[(m,ci)][0],"note":verd[(m,ci)][1]}
                 for m in panel for ci in range(len(CASES))]}
    p=pathlib.Path(__file__).resolve().parent.parent/"results"/f"ab_hard_{datetime.date.today().isoformat()}.json"
    p.write_text(json.dumps(blob,indent=2)); print(f"saved -> results/{p.name}")

if __name__=="__main__": main()
