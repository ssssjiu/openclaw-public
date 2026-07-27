#!/usr/bin/env bash
set -u -o pipefail
workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$workspace/verification/openclaw-cli.sh"
projects_root="${OPENCLAW_NPM_PROJECTS_ROOT:-$HOME/.openclaw/npm/projects}"

# Read-only supply-chain check. It does not install, update, or rewrite plugins.
registry_state="$(openclaw_cli plugins registry --json 2>/dev/null | jq -r '.state // empty' || true)"
failures=()
[[ "$registry_state" == "fresh" ]] || failures+=("plugin-registry:${registry_state:-unavailable}")

while IFS= read -r lock; do
  root="$(dirname "$lock")"
  while IFS=$'\t' read -r package spec; do
    [[ -n "$package" ]] || continue
    # Only enforce direct dependencies that are exact versions; ranges are
    # intentionally reported for review rather than silently treated as pinned.
    if [[ ! "$spec" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$ ]]; then
      continue
    fi
    key="node_modules/$package"
    version="$(jq -r --arg key "$key" '.packages[$key].version // empty' "$lock")"
    integrity="$(jq -r --arg key "$key" '.packages[$key].integrity // empty' "$lock")"
    resolved="$(jq -r --arg key "$key" '.packages[$key].resolved // empty' "$lock")"
    [[ "$version" == "$spec" ]] || failures+=("$package:version-$spec!=${version:-missing}")
    [[ -n "$integrity" ]] || failures+=("$package:integrity-missing")
    [[ "$resolved" =~ ^https://registry\.npmjs\.org/ ]] || failures+=("$package:resolved-origin-${resolved:-missing}")
  done < <(jq -r '.dependencies // {} | to_entries[] | [.key,.value] | @tsv' "$root/package.json" 2>/dev/null || true)
done < <(find "$projects_root" -maxdepth 2 -name package-lock.json -type f -print 2>/dev/null)

while IFS= read -r project; do
  [[ -n "$project" ]] || continue
  if find "$project" -xdev \( -type f -o -type d \) -perm /022 -print -quit 2>/dev/null | rg -q .; then
    failures+=("permissions:group-or-world-writable-$project")
  fi
done < <(find "$projects_root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
code_lsp="${OPENCLAW_CODE_LSP_PLUGIN_ROOT:-$workspace/plugins/code-lsp}"
if [[ -d "$code_lsp" ]] && find "$code_lsp" -xdev \( -type f -o -type d \) -perm /022 -print -quit 2>/dev/null | rg -q .; then
  failures+=("permissions:group-or-world-writable-code-lsp:$code_lsp")
fi

if (( ${#failures[@]} )); then
  printf '%s\n' 'SUPPLY_CHAIN_REVIEW_REQUIRED'
  printf ' - %s\n' "${failures[@]}"
  exit 2
fi

printf '%s\n' 'SUPPLY_CHAIN_INTACT'
