set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

check:
    uvx ruff check --select F recorder/recorder prosody-bench/ recorder/evals/ experiments/
    PYTHONPYCACHEPREFIX=/tmp/parloq-pycache python3 -m py_compile recorder/recorder recorder/evals/run_eval.py recorder/evals/test_ui_fixture.py recorder/evals/test_device_resolution.py recorder/evals/test_dictate_protocol.py recorder/evals/test_dictate_session.py recorder/evals/test_dictate_trigger.py recorder/evals/test_eval_corpus_paths.py recorder/evals/test_eval_report_format.py recorder/evals/test_fragment_join.py recorder/evals/test_polish_edits.py recorder/evals/test_render_md.py recorder/evals/test_search_cli.py recorder/evals/test_vocab.py recorder/evals/test_agent_plist.py prosody-bench/test_emphasis_tag.py
    python3 recorder/evals/test_device_resolution.py
    uv run recorder/evals/test_dictate_protocol.py
    uv run recorder/evals/test_dictate_session.py
    uv run recorder/evals/test_dictate_trigger.py
    uv run recorder/evals/test_eval_corpus_paths.py
    uv run recorder/evals/test_eval_report_format.py
    python3 recorder/evals/test_fragment_join.py
    uv run recorder/evals/test_polish_edits.py
    uv run recorder/evals/test_render_md.py
    uv run recorder/evals/test_search_cli.py
    uv run prosody-bench/test_emphasis_tag.py
    uv run recorder/evals/test_vocab.py
    uv run recorder/evals/test_agent_plist.py
    uv run recorder/evals/test_ui_fixture.py
    swift test --package-path macos/ParloqMenu

recorder-corpus target="librispeech":
    data/corpora/recorder/scripts/sync.sh {{target}}

recorder-eval-smoke output="test-results/recorder-eval-smoke.md":
    mkdir -p test-results
    uv run recorder/evals/run_eval.py --skip-live --clip L1-clean --output {{output}}

macos-app:
    swift build -c release --package-path macos/ParloqMenu
    mkdir -p macos/ParloqMenu/.build/Parloq.app/Contents/MacOS macos/ParloqMenu/.build/Parloq.app/Contents/Resources
    cp macos/ParloqMenu/.build/release/ParloqMenu macos/ParloqMenu/.build/Parloq.app/Contents/MacOS/ParloqMenu
    cp macos/ParloqMenu/Resources/AppIcon.icns macos/ParloqMenu/.build/Parloq.app/Contents/Resources/AppIcon.icns
    cp macos/ParloqMenu/Resources/Info.plist macos/ParloqMenu/.build/Parloq.app/Contents/Info.plist
    xattr -d com.apple.FinderInfo macos/ParloqMenu/.build/Parloq.app 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' macos/ParloqMenu/.build/Parloq.app 2>/dev/null || true
    codesign --force --sign "${PARLOQ_CODESIGN_IDENTITY:-stela-dev}" --identifier net.attobop.parloq.menu macos/ParloqMenu/.build/Parloq.app
    codesign --verify --deep --strict macos/ParloqMenu/.build/Parloq.app

install-macos-app: macos-app
    ditto macos/ParloqMenu/.build/Parloq.app /Applications/Parloq.app
    codesign --verify --deep --strict /Applications/Parloq.app
