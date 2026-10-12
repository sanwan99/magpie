#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${MAGPIE_DERIVED_DATA_PATH:-/private/tmp/magpie-derived}"
RELEASE_APP="$DERIVED_DATA/Build/Products/Release/Magpie.app"

source "$ROOT/Scripts/xcode-env.sh"
ensure_magpie_package_cache "$ROOT"
python3 "$ROOT/Scripts/setup-local-signing.py"

xcodebuild \
  -project "$ROOT/Magpie.xcodeproj" \
  -scheme Magpie \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$MAGPIE_PACKAGE_CACHE" \
  -disableAutomaticPackageResolution \
  build

python3 "$ROOT/Scripts/install-app.py" "$RELEASE_APP" "$@"
