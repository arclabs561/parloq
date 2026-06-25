#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression test for the launchd agent plist renderer (_render_agent_plist).

Asserts the generated plist is well-formed (round-trips through plistlib) and
carries the fields the daemon depends on under launchd: the program args
(recorder path + `dictate --daemon` + any pass-through flags), RunAtLoad,
KeepAlive, and an explicit PATH that includes Homebrew (launchd's minimal PATH
would otherwise hide ffmpeg). The launchctl bootstrap itself is a system side
effect and is not exercised here.

Run: uv run recorder/evals/test_agent_plist.py
"""
import importlib.machinery
import importlib.util
import pathlib
import plistlib

REPO = pathlib.Path(__file__).resolve().parents[2]
RECORDER = REPO / "recorder" / "recorder"


def load():
    loader = importlib.machinery.SourceFileLoader("rec", str(RECORDER))
    spec = importlib.util.spec_from_loader("rec", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def main():
    rec = load()
    xml = rec._render_agent_plist(
        "/usr/local/bin/recorder", ["--polish", "--vocab", "/x.txt"],
        "/tmp/parloq.log")
    d = plistlib.loads(xml.encode("utf-8"))  # well-formed or this raises

    assert d["Label"] == "parloq.dictate", d["Label"]
    assert d["ProgramArguments"] == [
        "/usr/local/bin/recorder", "dictate", "--daemon",
        "--polish", "--vocab", "/x.txt"], d["ProgramArguments"]
    assert d["RunAtLoad"] is True
    assert d["KeepAlive"] is True
    assert "/opt/homebrew/bin" in d["EnvironmentVariables"]["PATH"], \
        "Homebrew not on the agent PATH; ffmpeg would not resolve under launchd"
    assert d["StandardOutPath"] == "/tmp/parloq.log"

    # no pass-through args still produces a valid daemon invocation
    d2 = plistlib.loads(rec._render_agent_plist(
        "/r", [], "/l").encode("utf-8"))
    assert d2["ProgramArguments"] == ["/r", "dictate", "--daemon"], \
        d2["ProgramArguments"]

    print("PASS: agent plist is well-formed with daemon args and Homebrew PATH")


if __name__ == "__main__":
    main()
