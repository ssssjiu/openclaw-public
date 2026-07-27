#!/usr/bin/env bash
set -u -o pipefail

runtime_root="${1:-/opt/openclaw-runtime/openclaw}"
dist="$runtime_root/dist"
failures=()

[[ -f "$runtime_root/package.json" ]] || failures+=("runtime-package-missing")
[[ -f "$dist/index.js" ]] || failures+=("runtime-entry-missing")
[[ -f "$dist/extensions/lobster/index.js" ]] || failures+=("bundled-lobster-missing")

for pattern in 'server.impl-*.js' 'server-aux-handlers-*.js' 'provider.runtime-*.js'; do
  count="$(find "$dist" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)"
  [[ "$count" -eq 1 ]] || failures+=("singleton-chunk:$pattern:$count")
done

if [[ -f "$runtime_root/package.json" ]]; then
  version="$(jq -r '.version // empty' "$runtime_root/package.json" 2>/dev/null || true)"
  [[ -n "$version" ]] || failures+=("runtime-version-missing")
else
  version=""
fi

if ((${#failures[@]})); then
  printf '%s\n' 'RUNTIME_INTEGRITY_BLOCKED'
  printf ' - %s\n' "${failures[@]}"
  exit 2
fi

printf '%s\n' 'RUNTIME_INTEGRITY_PASS'
printf ' - version:%s\n' "$version"
printf ' - dist:%s\n' "$dist"
