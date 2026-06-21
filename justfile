set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

check:
    PYTHONPYCACHEPREFIX=/tmp/parloq-pycache python3 -m py_compile recorder/recorder recorder/evals/run_eval.py recorder/evals/test_ui_fixture.py recorder/evals/test_device_resolution.py recorder/evals/test_dictate_trigger.py recorder/evals/test_fragment_join.py recorder/evals/test_polish_edits.py recorder/evals/test_search_cli.py eval/test_emphasis_tag.py
    python3 recorder/evals/test_device_resolution.py
    uv run recorder/evals/test_dictate_trigger.py
    python3 recorder/evals/test_fragment_join.py
    uv run recorder/evals/test_polish_edits.py
    uv run recorder/evals/test_search_cli.py
    uv run eval/test_emphasis_tag.py
    uv run recorder/evals/test_ui_fixture.py
