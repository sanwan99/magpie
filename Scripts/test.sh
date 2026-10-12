#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${MAGPIE_TEST_DERIVED_DATA_PATH:-/private/tmp/magpie-derived}"

# shellcheck source=Scripts/xcode-env.sh
source "$ROOT/Scripts/xcode-env.sh"
ensure_magpie_package_cache "$ROOT"
python3 "$ROOT/Scripts/setup-local-signing.py"

cleanup_app_entries() {
  local status=$?
  "$ROOT/Scripts/clean-debug-apps.sh" || {
    local cleanup_status=$?
    if [[ "$status" -eq 0 ]]; then
      status="$cleanup_status"
    fi
  }
  exit "$status"
}

trap cleanup_app_entries EXIT

mkdir -p "$DERIVED_DATA"

xcodebuild \
  -project "$ROOT/Magpie.xcodeproj" \
  -scheme Magpie \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$MAGPIE_PACKAGE_CACHE" \
  test
