set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

check:
    uvx ruff check --select F recorder/recorder prosody-bench/ recorder/evals/ experiments/
    uvx ruff check --select B023 recorder/recorder
    for f in recorder/evals/test_*.py prosody-bench/test_*.py; do grep -Eq "(uv run|python3) $f( |$)" justfile || { echo "test not run by just check: $f" >&2; exit 1; }; done
    PYTHONPYCACHEPREFIX=/tmp/parloq-pycache python3 -m py_compile recorder/recorder recorder/evals/run_eval.py recorder/evals/run_dictate_e2e.py recorder/evals/test_ui_fixture.py recorder/evals/test_device_resolution.py recorder/evals/test_dictate_protocol.py recorder/evals/test_dictate_session.py recorder/evals/test_dictate_trigger.py recorder/evals/test_eval_corpus_paths.py recorder/evals/test_eval_report_format.py recorder/evals/test_fragment_join.py recorder/evals/test_polish_edits.py recorder/evals/test_render_md.py recorder/evals/test_search_cli.py recorder/evals/test_vocab.py recorder/evals/test_agent_plist.py recorder/evals/test_local_surfaces.py prosody-bench/test_emphasis_tag.py
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
    uv run recorder/evals/test_local_surfaces.py
    swift test --package-path macos/ParloqMenu
    swift run --package-path macos/ParloqMenu ParloqMenu --render-ui-fixtures "test-results/ui-fixtures"

recorder-corpus target="librispeech":
    data/corpora/recorder/scripts/sync.sh {{target}}

recorder-eval-smoke output="test-results/recorder-eval-smoke.md":
    mkdir -p test-results
    uv run recorder/evals/run_eval.py --skip-live --clip L1-clean --output {{output}}

ui-fixtures output="test-results/ui-fixtures":
    swift run --package-path macos/ParloqMenu ParloqMenu --render-ui-fixtures "{{output}}"

ui-native-fixture output="test-results/ui-fixtures/native-glass.png":
    swift run --package-path macos/ParloqMenu ParloqMenu --capture-native-ui-fixture "{{output}}"

dictate-e2e audio="data/corpora/recorder/extended/short-dictation/ls_1272_0000_5s.flac" expect="apostle":
    python3 recorder/evals/run_dictate_e2e.py "{{audio}}" --expect "{{expect}}"

delivery-e2e: install-macos-app
    /Applications/Parloq.app/Contents/MacOS/ParloqMenu --e2e-delivery

e2e: dictate-e2e delivery-e2e

macos-app:
    swift build -c release --package-path macos/ParloqMenu
    mkdir -p "$HOME/Library/Caches/Parloq/Parloq.app/Contents/MacOS" "$HOME/Library/Caches/Parloq/Parloq.app/Contents/Resources"
    cp macos/ParloqMenu/.build/release/ParloqMenu "$HOME/Library/Caches/Parloq/Parloq.app/Contents/MacOS/ParloqMenu"
    cp macos/ParloqMenu/Resources/AppIcon.icns "$HOME/Library/Caches/Parloq/Parloq.app/Contents/Resources/AppIcon.icns"
    cp macos/ParloqMenu/Resources/Info.plist "$HOME/Library/Caches/Parloq/Parloq.app/Contents/Info.plist"
    xattr -cr "$HOME/Library/Caches/Parloq/Parloq.app"
    codesign --force --sign "${PARLOQ_CODESIGN_IDENTITY:-stela-dev}" --identifier net.attobop.parloq.menu "$HOME/Library/Caches/Parloq/Parloq.app"
    codesign --verify --deep --strict "$HOME/Library/Caches/Parloq/Parloq.app"

install-staged-macos-app:
    ditto "$HOME/Library/Caches/Parloq/Parloq.app" /Applications/Parloq.app
    codesign --verify --deep --strict /Applications/Parloq.app
    cmp "$HOME/Library/Caches/Parloq/Parloq.app/Contents/MacOS/ParloqMenu" /Applications/Parloq.app/Contents/MacOS/ParloqMenu

install-macos-app: macos-app install-staged-macos-app

reload-macos-app:
    ./macos/ParloqMenu/dev-reload.sh

dev-macos-app:
    watchexec \
        --watch macos/ParloqMenu/Sources \
        --watch macos/ParloqMenu/Resources \
        --watch macos/ParloqMenu/Package.swift \
        --exts swift,plist,png,icns \
        --debounce 300ms \
        --on-busy-update queue \
        -- ./macos/ParloqMenu/dev-reload.sh
