#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${MAGPIE_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/magpie-local-derived}"
IDENTITY="${MAGPIE_CODE_SIGN_IDENTITY:--}"
xcodebuild -project "$ROOT/Magpie.xcodeproj" -scheme Magpie \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
printf 'Local app: %s/Build/Products/Release/Magpie.app\n' "$DERIVED_DATA"
printf 'For an explicit local install: python3 Scripts/install-app.py "%s/Build/Products/Release/Magpie.app" --local-build\n' "$DERIVED_DATA"
