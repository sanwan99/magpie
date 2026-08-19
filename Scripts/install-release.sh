#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${MAGPIE_DERIVED_DATA_PATH:-/private/tmp/magpie-derived}"
APP_PATH="/Applications/Magpie.app"
RELEASE_APP="$DERIVED_DATA/Build/Products/Release/Magpie.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# shellcheck source=Scripts/xcode-env.sh
source "$ROOT/Scripts/xcode-env.sh"
ensure_magpie_package_cache "$ROOT"

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
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$MAGPIE_PACKAGE_CACHE" \
  build

if [[ ! -d "$RELEASE_APP" ]]; then
  printf 'Release app not found: %s\n' "$RELEASE_APP" >&2
  exit 1
fi

killall Magpie >/dev/null 2>&1 || true
rm -rf "$APP_PATH"
/usr/bin/ditto "$RELEASE_APP" "$APP_PATH"

"$LSREGISTER" -f -R -trusted "$APP_PATH" >/dev/null 2>&1 || true
open "$APP_PATH"

printf 'Installed and launched %s\n' "$APP_PATH"
