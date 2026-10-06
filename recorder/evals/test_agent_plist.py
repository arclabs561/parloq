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
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace

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
    source = RECORDER.read_text(encoding="utf-8")
    assert '"numpy>=2.2.5,<2.5"' in source, (
        "fresh uv script environments can resolve NumPy 2.5 with an "
        "incompatible legacy Numba/llvmlite pair"
    )
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

    # With a resolved uv, the agent syncs and execs the script interpreter on
    # each start, so no resident `uv run` parent holds the uv cache lock and a
    # pruned cache environment is rebuilt rather than left dangling.
    d3 = plistlib.loads(rec._render_agent_plist(
        "/r", ["--prosody"], "/l", "/opt/uv").encode("utf-8"))
    args = d3["ProgramArguments"]
    assert args[:2] == ["/bin/sh", "-c"], args
    assert args[3:] == ["parloq-dictate", "/opt/uv", "/r", "dictate",
                        "--daemon", "--prosody"], args

    # Execute the real launcher string with a fake uv: it must sync, then exec
    # the found interpreter with the script and every daemon argument intact.
    with tempfile.TemporaryDirectory() as tmp:
        fake_uv = pathlib.Path(tmp) / "uv"
        log = pathlib.Path(tmp) / "uv.log"
        fake_uv.write_text(
            "#!/bin/sh\n"
            f'printf "%s\\n" "$*" >> "{log}"\n'
            'if [ "$1" = python ]; then echo /bin/echo; fi\n')
        fake_uv.chmod(0o755)
        out = subprocess.run(
            [*args[:3], args[3], str(fake_uv), "/r", "dictate", "two words"],
            check=True, capture_output=True, text=True).stdout
        assert out == "/r dictate two words\n", repr(out)
        assert log.read_text().splitlines() == [
            "sync --quiet --script /r", "python find --script /r"], \
            log.read_text()

    calls = []

    def fake_runner(command, **_kwargs):
        calls.append(command[1:3])
        if command[1:3] == ["python", "find"]:
            return subprocess.CompletedProcess(command, 0, stdout=sys.executable)
        return subprocess.CompletedProcess(command, 0)

    assert rec._resolve_script_uv(
        pathlib.Path("/r"), runner=fake_runner) is not None
    assert calls == [["sync", "--quiet"], ["python", "find"]], calls

    def failing_runner(command, **_kwargs):
        raise subprocess.CalledProcessError(1, command)

    assert rec._resolve_script_uv(
        pathlib.Path("/r"), runner=failing_runner) is None

    # The installed engine must not execute from ~/Documents. macOS denies
    # launchd access to that protected tree even when an interactive shell can
    # read the same repo file.
    installed = rec._dictate_installed_recorder_path()
    assert installed == (
        pathlib.Path.home() / "Library" / "Application Support"
        / "Parloq" / "recorder"
    ), installed
    assert not os.path.commonpath([
        str(installed), str(pathlib.Path.home() / "Documents")
    ]) == str(pathlib.Path.home() / "Documents")

    attempts = []
    sleeps = []

    def race_then_success(command, **_kwargs):
        attempts.append(command)
        if len(attempts) == 1:
            return SimpleNamespace(
                returncode=5, stderr="Bootstrap failed: 5: Input/output error")
        return SimpleNamespace(returncode=0, stderr="")

    result = rec._bootstrap_launch_agent(
        "gui/501",
        pathlib.Path("/tmp/parloq.plist"),
        runner=race_then_success,
        sleeper=sleeps.append,
    )
    assert result.returncode == 0
    assert len(attempts) == 2, attempts
    assert sleeps == [0.5], sleeps

    print("PASS: agent plist is well-formed with daemon args and Homebrew PATH")


if __name__ == "__main__":
    main()
