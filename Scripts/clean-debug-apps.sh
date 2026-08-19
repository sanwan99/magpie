#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="/Applications/Magpie.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

unregister_app() {
  local app="$1"
  "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
}

is_cleanup_path() {
  local path="$1"
  case "$path" in
    "$ROOT"/*|/private/tmp/*|/tmp/*|"$HOME/Library/Developer/Xcode/DerivedData"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

remove_cleanup_path() {
  local path="$1"
  if [[ -z "$path" || "$path" == "/" || "$path" == "$APP_PATH" ]]; then
    printf 'Refusing unsafe cleanup path: %s\n' "$path" >&2
    exit 1
  fi
  if ! is_cleanup_path "$path"; then
    printf 'Refusing cleanup outside allowed roots: %s\n' "$path" >&2
    exit 1
  fi
  rm -rf "$path"
}

remove_debug_product_dir() {
  local dir="$1"
  if [[ -d "$dir/Magpie.app" ]]; then
    unregister_app "$dir/Magpie.app"
  fi
  if [[ -d "$dir" ]]; then
    remove_cleanup_path "$dir"
  fi
}

known_debug_dirs=(
  "$ROOT/build/Build/Products/Debug"
  "$ROOT/.codex_tmp/DerivedData/Build/Products/Debug"
  "/private/tmp/magpie-derived/Build/Products/Debug"
  "/private/tmp/magpie-tests.noindex/Build/Products/Debug"
  "/private/tmp/magpie-release.noindex/Build/Products/Debug"
)

for dir in "${known_debug_dirs[@]}"; do
  remove_debug_product_dir "$dir"
done

search_roots=(
  "$ROOT"
  "/private/tmp"
  "/tmp"
  "$HOME/Library/Developer/Xcode/DerivedData"
)

existing_roots=()
for root in "${search_roots[@]}"; do
  [[ -d "$root" ]] && existing_roots+=("$root")
done

if (( ${#existing_roots[@]} > 0 )); then
  while IFS= read -r -d '' app; do
    [[ "$app" == "$APP_PATH" ]] && continue
    unregister_app "$app"
    if [[ "$(basename "$(dirname "$app")")" == "Debug" ]]; then
      remove_cleanup_path "$(dirname "$app")"
    else
      remove_cleanup_path "$app"
    fi
  done < <(find "${existing_roots[@]}" -path '*/Magpie.app' -type d -prune -print0 2>/dev/null)
fi

if [[ -d "$APP_PATH" ]]; then
  "$LSREGISTER" -f -R -trusted "$APP_PATH" >/dev/null 2>&1 || true
fi

stray_apps=()
if (( ${#existing_roots[@]} > 0 )); then
  while IFS= read -r -d '' app; do
    [[ "$app" == "$APP_PATH" ]] && continue
    stray_apps+=("$app")
  done < <(find "$APP_PATH" "${existing_roots[@]}" -path '*/Magpie.app' -type d -prune -print0 2>/dev/null)
fi

if (( ${#stray_apps[@]} > 0 )); then
  printf 'Stray Magpie apps remain:\n' >&2
  printf '  %s\n' "${stray_apps[@]}" >&2
  exit 1
fi

printf 'Magpie app entries are clean: %s\n' "$APP_PATH"
