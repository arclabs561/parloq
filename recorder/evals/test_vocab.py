#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Regression test for the dictation vocab path (_load_vocab / _apply_vocab).

Loads the real functions from the recorder daily-driver and asserts the
deterministic correction behavior: whole-word case-insensitive replacement,
sentence-initial capital preserved, substrings left alone, multi-word phrases
matched, empty/missing vocab is a no-op, and the file parser skips comments and
blank lines. These are the invariants the daemon relies on when it rewrites a
transcript before clipboard/paste.

Run: uv run recorder/evals/test_vocab.py
"""
import importlib.machinery
import importlib.util
import pathlib
import tempfile

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
    av, lv = rec._apply_vocab, rec._load_vocab

    pairs = [("kubernetes", "Kubernetes"), ("nextjs", "Next.js"),
             ("clod code", "Claude Code")]

    # whole-word, case-insensitive replacement
    assert av("i use kubernetes daily", pairs) == "i use Kubernetes daily"
    # sentence-initial capital is preserved when replacement is lowercase
    assert av("React beats this", [("react", "preact")]) == "Preact beats this"
    # a lowercase match stays lowercase
    assert av("i like react", [("react", "preact")]) == "i like preact"
    # substring must NOT match (whole-word boundary)
    assert av("kubernetesy thing", pairs) == "kubernetesy thing"
    # multi-word phrase matches as a phrase
    assert av("run clod code now", pairs) == "run Claude Code now"
    # punctuation-adjacent token still matches
    assert av("deploy to kubernetes.", pairs) == "deploy to Kubernetes."
    # punctuation is allowed inside or at the edge of a standalone technical term
    assert av("write see plus plus", [("see plus plus", "C++")]) == "write C++"
    assert av("use C++ here", [("C++", "C plus plus")]) == "use C plus plus here"
    # empty vocab and empty text are no-ops
    assert av("anything", []) == "anything"
    assert av("", pairs) == ""

    # file parser: skips comments and blanks, splits on first '='
    with tempfile.NamedTemporaryFile("w", suffix=".vocab.txt",
                                     delete=False) as f:
        f.write("# a comment\n\n"
                "nextjs = Next.js\n"
                "  spaced =  Spaced Out  \n"
                "noequals line\n")
        path = f.name
    loaded = lv(path)
    assert ("nextjs", "Next.js") in loaded, loaded
    assert ("spaced", "Spaced Out") in loaded, loaded
    assert len(loaded) == 2, f"comment/blank/no-equals not skipped: {loaded}"
    # missing file is a no-op, not an error
    assert lv("/nonexistent/path/.vocab.txt") == []

    with tempfile.TemporaryDirectory() as directory:
        managed = pathlib.Path(directory) / "nested" / ".vocab.txt"
        correction = rec.DictationCorrection("par lock", "Parloq")
        updated, error = rec._append_vocab_correction(managed, correction)
        assert error is None
        assert updated == [("par lock", "Parloq")]
        assert managed.read_text(encoding="utf-8") == "par lock = Parloq\n"
        assert managed.stat().st_mode & 0o777 == 0o600

        updated, outcome = rec._append_vocab_correction(managed, correction)
        assert outcome == "correction already exists"
        assert updated == [("par lock", "Parloq")]
        assert managed.read_text(encoding="utf-8") == "par lock = Parloq\n"

        conflicting = rec.DictationCorrection("Par Lock", "Parlock")
        updated, error = rec._append_vocab_correction(
            managed,
            conflicting,
        )
        assert updated is None
        assert "already maps to" in error
        assert managed.read_text(encoding="utf-8") == "par lock = Parloq\n"

    print("PASS: vocab corrections are whole-word, case-aware, file-parsed")


if __name__ == "__main__":
    main()
