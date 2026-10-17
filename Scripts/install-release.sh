#!/usr/bin/env bash
# Installs an already signed/notarized public .app. No developer certificate setup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -eq 0 ]]; then
  printf 'Usage: Scripts/install-release.sh /path/to/Magpie.app [--team-id TEAMID]\n' >&2
  exit 2
fi
for argument in "$@"; do
  if [[ "$argument" == "--local-build" ]]; then
    printf 'Public installation requires Developer ID verification. For your own source build use install-app.py --local-build.\n' >&2
    exit 2
  fi
done
exec python3 "$ROOT/Scripts/install-app.py" "$@"
