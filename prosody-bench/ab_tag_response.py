#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["requests"]
# ///
"""A/B eval: does an inline prosody tag change an LLM's response? (the go/no-go)

Tests the downstream half of the paralinguistic-dictation idea, independent of
any tagger: feed dictation-like messages to a panel of models, comparing the
reply to the raw inline-tagged input vs untagged. NAIVE condition: no system
prompt explains the tag, so this measures zero-shot interpretation ("does it
just work"). A judge model classifies each pair ADAPTED / IGNORED /
DIFFERENT_UNRELATED. All raw responses are saved for inspection.

Across many models = does the effect generalize, and which models take the
"lexical shortcut" (CP-Bench) of ignoring the tone channel.

Env: EVAL_OPENROUTER_API_KEY (or OPENROUTER_API_KEY).
Run: uv run prosody-bench/ab_tag_response.py
"""
import os, json, time, pathlib, datetime, collections
from concurrent.futures import ThreadPoolExecutor
import requests

KEY = os.environ.get("EVAL_OPENROUTER_API_KEY") or os.environ["OPENROUTER_API_KEY"]
URL = "https://openrouter.ai/api/v1/chat/completions"
HDR = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

PANEL = [
    "openai/gpt-4o-mini",
    "anthropic/claude-3.5-haiku",
    "meta-llama/llama-3.3-70b-instruct",
    "mistralai/mistral-small-3.2-24b-instruct",
    "qwen/qwen-2.5-72b-instruct",
    "deepseek/deepseek-chat-v3.1",
    "google/gemini-2.0-flash-001",   # auto-dropped if not live
    "x-ai/grok-2-1212",              # auto-dropped if not live
]
JUDGE = "openai/gpt-4o-mini"

# dictation-like messages where tone should shift an assistant's reply
CASES = [
    {"text": "I think we should rewrite the auth module", "tag": "[uncertain]"},
    {"text": "the deploy finished",                        "tag": "[anxious]"},
    {"text": "let's go with your suggestion",              "tag": "[reluctant]"},
    {"text": "can you walk me through the diff",           "tag": "[exhausted]"},
    {"text": "we need to ship this today",                 "tag": "[stressed]"},
    {"text": "this is the third time it crashed",          "tag": "[frustrated]"},
]
RESP_SYS = "You are a helpful assistant replying to a short message from the user. Reply concisely, 2-4 sentences."

def call(model, system, user, max_tokens=180, retries=2):
    body = {"model": model, "max_tokens": max_tokens,
            "messages": [{"role":"system","content":system},{"role":"user","content":user}]}
    for a in range(retries+1):
        try:
            r = requests.post(URL, headers=HDR, json=body, timeout=60)
            if r.status_code == 200:
                return r.json()["choices"][0]["message"]["content"].strip()
            err = f"HTTP {r.status_code}: {r.text[:120]}"
        except Exception as e:
            err = str(e)[:120]
        time.sleep(1.5*(a+1))
    return f"<ERROR {err}>"

def live_panel():
    f = pathlib.Path("/tmp/or_models.txt")
    if not f.exists(): return PANEL
    live = set(f.read_text().split())
    keep = [m for m in PANEL if m in live]
    dropped = [m for m in PANEL if m not in live]
    if dropped: print(f"dropped (not live): {dropped}")
    return keep

def main():
    panel = live_panel()
    print(f"panel ({len(panel)}): {panel}\ncases: {len(CASES)}\n")

    # 1. responses: untagged + tagged, per (model, case), concurrent
    jobs = []
    for m in panel:
        for ci, c in enumerate(CASES):
            jobs.append((m, ci, "untagged", c["text"]))
            jobs.append((m, ci, "tagged", f'{c["tag"]} {c["text"]}'))
    def run(job):
        m, ci, kind, user = job
        return (m, ci, kind, call(m, RESP_SYS, user))
    t0 = time.perf_counter()
    out = {}
    with ThreadPoolExecutor(max_workers=12) as ex:
        for m, ci, kind, resp in ex.map(run, jobs):
            out[(m, ci, kind)] = resp
    print(f"{len(jobs)} response calls in {time.perf_counter()-t0:.0f}s")

    # 2. judge each (model, case) tagged-vs-untagged pair
    def judge(job):
        m, ci = job
        c = CASES[ci]
        jp = (f'A user dictated: "{c["text"]}". The tone tag was {c["tag"]}.\n'
              f'Reply WITHOUT tone info:\n"{out[(m,ci,"untagged")]}"\n\n'
              f'Reply WITH the tag {c["tag"]} prefixed to the input:\n"{out[(m,ci,"tagged")]}"\n\n'
              f'Did the tag meaningfully change the second reply in a way that reflects the {c["tag"]} tone? '
              f'First token MUST be one of: ADAPTED / IGNORED / DIFFERENT_UNRELATED. Then one short reason.')
        v = call(JUDGE, "You are a precise evaluator.", jp, max_tokens=80)
        label = v.split()[0].upper().strip(".:") if v and not v.startswith("<ERROR") else "ERROR"
        if label not in ("ADAPTED","IGNORED","DIFFERENT_UNRELATED"): label = "UNPARSED"
        return (m, ci, label, v)
    t0 = time.perf_counter()
    verdicts = {}
    with ThreadPoolExecutor(max_workers=12) as ex:
        for m, ci, label, v in ex.map(judge, [(m,ci) for m in panel for ci in range(len(CASES))]):
            verdicts[(m, ci)] = (label, v)
    print(f"{len(verdicts)} judge calls in {time.perf_counter()-t0:.0f}s\n")

    # 3. per-model adapted rate
    print(f"{'model':42s}  adapted/total   rate")
    rows = {}
    for m in panel:
        labs = [verdicts[(m,ci)][0] for ci in range(len(CASES))]
        ad = labs.count("ADAPTED")
        rows[m] = {"adapted": ad, "total": len(CASES),
                   "counts": dict(collections.Counter(labs))}
        print(f"{m:42s}  {ad:2d}/{len(CASES):<10d}  {ad/len(CASES)*100:.0f}%")
    overall = sum(r["adapted"] for r in rows.values())/(len(panel)*len(CASES))
    print(f"\noverall ADAPTED rate: {overall*100:.0f}%  (high = inline tags work zero-shot)")

    # 4. save everything for inspection
    blob = {"condition":"naive (no tag explanation)", "panel":panel,
            "cases":CASES, "judge":JUDGE, "overall_adapted_rate":round(overall,3),
            "per_model":rows,
            "raw":[{"model":m,"case":ci,"tag":CASES[ci]["tag"],
                    "untagged":out[(m,ci,"untagged")],"tagged":out[(m,ci,"tagged")],
                    "verdict":verdicts[(m,ci)][0],"judge_note":verdicts[(m,ci)][1]}
                   for m in panel for ci in range(len(CASES))]}
    out_dir = pathlib.Path(__file__).resolve().parent.parent/"results"
    p = out_dir/f"ab_tag_response_{datetime.date.today().isoformat()}.json"
    p.write_text(json.dumps(blob, indent=2))
    print(f"saved -> results/{p.name}")

if __name__ == "__main__":
    main()
