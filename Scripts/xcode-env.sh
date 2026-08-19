#!/usr/bin/env bash
set -euo pipefail

ensure_magpie_package_cache() {
  local root="$1"
  local cache="${MAGPIE_PACKAGE_CACHE_PATH:-/private/tmp/magpie-source-packages}"

  if [[ -z "$cache" || "$cache" == "/" ]]; then
    printf 'Refusing unsafe MAGPIE_PACKAGE_CACHE_PATH: %s\n' "$cache" >&2
    exit 1
  fi

  if [[ ! -d "$cache/checkouts/GRDB.swift" ]]; then
    local candidates=(
      "$root/build/SourcePackages"
      "$root/.codex_tmp/DerivedData/SourcePackages"
      "/private/tmp/magpie-derived/SourcePackages"
    )

    for candidate in "${candidates[@]}"; do
      if [[ -d "$candidate/checkouts/GRDB.swift" ]]; then
        mkdir -p "$cache"
        /usr/bin/ditto "$candidate" "$cache"
        break
      fi
    done
  fi

  export MAGPIE_PACKAGE_CACHE="$cache"
}
