#!/usr/bin/env bash
# Installs an already signed/notarized public .app. No developer certificate setup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -eq 0 ]]; then
  printf 'Usage: Scripts/install-release.sh /path/to/Magpie.app [--team-id TEAMID]\n' >&2
  exit 2
fi
exec python3 "$ROOT/Scripts/install-app.py" "$@"
