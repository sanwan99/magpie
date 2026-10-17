#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWN_DERIVED=0
if [[ -n "${MAGPIE_TEST_DERIVED_DATA_PATH:-}" ]]; then
  DERIVED_DATA="$MAGPIE_TEST_DERIVED_DATA_PATH"
else
  DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/magpie-tests.XXXXXX")"
  OWN_DERIVED=1
fi
cleanup() {
  if [[ "$OWN_DERIVED" == 1 ]]; then rm -rf -- "$DERIVED_DATA"; fi
}
trap cleanup EXIT
RESULT="${MAGPIE_TEST_RESULT_PATH:-$ROOT/.build/Test-$(date +%Y%m%d-%H%M%S).xcresult}"
mkdir -p "$(dirname "$RESULT")"
xcodebuild -project "$ROOT/Magpie.xcodeproj" -scheme Magpie \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT" -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test "$@"
