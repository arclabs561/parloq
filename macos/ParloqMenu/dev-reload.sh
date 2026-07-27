#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
app_path="${PARLOQ_DEV_APP_PATH:-/Applications/Parloq.app}"
app_binary="$app_path/Contents/MacOS/ParloqMenu"
bundle_identifier="net.attobop.parloq.menu"
idle_wait_seconds="${PARLOQ_DEV_IDLE_WAIT_SECONDS:-600}"

case "$idle_wait_seconds" in
    "" | *[!0-9]*)
        echo "PARLOQ_DEV_IDLE_WAIT_SECONDS must be a non-negative integer" >&2
        exit 2
        ;;
esac

frontmost_bundle_identifier() {
    /usr/bin/osascript -l JavaScript -e \
        'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js'
}

running_app_pids() {
    local pid command
    while read -r pid command; do
        if [[ "$command" == "$app_binary" ]]; then
            printf '%s\n' "$pid"
        fi
    done < <(ps -axo pid=,command=)
}

app_is_running() {
    [[ -n "$(running_app_pids)" ]]
}

dictation_phase() {
    local status field
    if ! status="$("$repo_root/recorder/recorder" dictate trigger --status)"; then
        echo "Could not read Parloq dictation status; leaving the running app untouched." >&2
        return 1
    fi
    for field in $status; do
        case "$field" in
            phase=*)
                printf '%s\n' "${field#phase=}"
                return 0
                ;;
        esac
    done
    echo "Dictation status did not contain a phase; leaving the running app untouched." >&2
    return 1
}

wait_for_dictation_to_be_idle() {
    local deadline phase announced=false
    deadline=$((SECONDS + idle_wait_seconds))
    while true; do
        phase="$(dictation_phase)"
        case "$phase" in
            idle | error)
                if [[ "$announced" == true ]]; then
                    echo "Dictation is idle; continuing reload."
                fi
                return 0
                ;;
            recording | finalizing | polishing)
                if [[ "$announced" == false ]]; then
                    echo "Reload ready; waiting for active dictation to finish ($phase)."
                    announced=true
                fi
                ;;
            *)
                echo "Unknown dictation phase '$phase'; leaving the running app untouched." >&2
                return 1
                ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Timed out waiting for dictation to become idle; the current app is still running." >&2
            return 1
        fi
        sleep 1
    done
}

wait_for_old_processes_to_exit() {
    local deadline pid all_exited
    deadline=$((SECONDS + 10))
    while true; do
        all_exited=true
        for pid in "$@"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_exited=false
                break
            fi
        done
        if [[ "$all_exited" == true ]]; then
            return 0
        fi
        if ((SECONDS >= deadline)); then
            echo "Parloq did not exit cleanly; it was not force-killed." >&2
            return 1
        fi
        sleep 0.1
    done
}

wait_for_new_process() {
    local deadline
    deadline=$((SECONDS + 10))
    while true; do
        if app_is_running; then
            return 0
        fi
        if ((SECONDS >= deadline)); then
            echo "The rebuilt Parloq app did not start." >&2
            return 1
        fi
        sleep 0.1
    done
}

needs_recovery=false
recover_app_on_exit() {
    local status=$?
    trap - EXIT
    if [[ "$needs_recovery" == true ]] && ! app_is_running; then
        /usr/bin/open -g "$app_path" >/dev/null 2>&1 || true
    fi
    exit "$status"
}
trap recover_app_on_exit EXIT

cd "$repo_root"
echo "Building a signed Parloq.app while the current app keeps running..."
just macos-app

wait_for_dictation_to_be_idle
frontmost_before="$(frontmost_bundle_identifier)"
just install-staged-macos-app

old_pids=()
while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then
        old_pids+=("$pid")
    fi
done < <(running_app_pids)

if ((${#old_pids[@]} > 0)); then
    needs_recovery=true
    kill "${old_pids[@]}"
    wait_for_old_processes_to_exit "${old_pids[@]}"
fi

/usr/bin/open -g "$app_path"
needs_recovery=true
wait_for_new_process
needs_recovery=false

frontmost_after="$(frontmost_bundle_identifier)"
if [[ "$frontmost_after" == "$bundle_identifier" ]]; then
    echo "Reload failed focus safety: Parloq became frontmost." >&2
    exit 1
fi
if [[ "$frontmost_before" == "$frontmost_after" ]]; then
    echo "Reloaded Parloq in the background; frontmost app preserved."
else
    echo "Reloaded Parloq in the background; focus changed externally, but not to Parloq."
fi
