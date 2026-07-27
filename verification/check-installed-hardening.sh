#!/usr/bin/env bash
set -u -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runtime-paths.sh"
plugin="$OPENCLAW_LOBSTER_INSTALLED"
workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=()
if [[ ! -f "$plugin" ]]; then
  service_exec="$(systemctl show openclaw-gateway.service -p ExecStart --value 2>/dev/null || true)"
  [[ -n "$service_exec" ]] || service_exec="$(systemctl --user show openclaw-gateway.service -p ExecStart --value 2>/dev/null || true)"
  service_root="$(sed -n 's#.*\(/[^ ]*/dist/index\.js\).*#\1#p' <<<"$service_exec" | sed 's#/dist/index\.js$##')"
  for candidate in \
    "$service_root/dist/extensions/lobster/index.js" \
    "${OPENCLAW_SOURCE_FORK:-}/dist/extensions/lobster/index.js" \
    "/opt/openclaw-runtime/openclaw/dist/extensions/lobster/index.js"; do
    if [[ -f "$candidate" ]]; then plugin="$candidate"; break; fi
  done
fi
[[ -f "$plugin" ]] || failures+=(plugin-missing)
for marker in BLOCKED_PLUGIN_APPROVAL plugin.approval.request plugin.approval.waitDecision issueApprovalCapability OPENCLAW_BROKER_SOCKET; do
  [[ -f "$plugin" ]] && rg -q --fixed-strings "$marker" "$plugin" || failures+=("plugin:$marker")
done
for file in verification/approval-broker.sh verification/target-hash.sh verification/mutation-gate.sh; do
  [[ -f "$workspace/$file" ]] || failures+=("workspace:$file")
done
if (( ${#failures[@]} )); then
  printf '%s\n' 'HARDENING_DRIFT'
  printf ' - %s\n' "${failures[@]}"
  exit 2
fi
printf '%s\n' 'HARDENING_INTACT'
