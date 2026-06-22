#!/usr/bin/env bash
# Compatibility wrapper. Corpus payloads now live under the repo-local
# data/corpora/recorder tree, not under ~/recordings.
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$repo_root/data/corpora/recorder/scripts/sync.sh" ami
