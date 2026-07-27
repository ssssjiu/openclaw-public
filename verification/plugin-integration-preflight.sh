#!/usr/bin/env bash
set -u -o pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/verification/runtime-paths.sh"
plugin_root="$OPENCLAW_LOBSTER_ROOT"
plugin="$OPENCLAW_LOBSTER_INSTALLED"
[[ -f "$plugin" ]] || plugin="$(find "$plugin_root" -path '*/node_modules/@openclaw/lobster/dist/index.js' -type f -print -quit 2>/dev/null || true)"
[[ -n "$plugin" ]] || { printf '%s\n' 'PLUGIN_INTEGRATION_DEFERRED: Lobster installation not found'; exit 2; }
rg -q 'plugin\.approval\.waitDecision|plugin_approval_waitDecision' "$plugin" || { printf '%s\n' 'PLUGIN_INTEGRATION_BLOCKED: approval bridge missing' >&2; exit 2; }
if rg -q 'issueApprovalCapability|OPENCLAW_BROKER_SOCKET|BLOCKED_PLUGIN_APPROVAL' "$plugin"; then
  printf '%s\n' 'PLUGIN_INTEGRATION_PASS'
else
  printf '%s\n' 'PLUGIN_INTEGRATION_DEFERRED: installed plugin does not issue broker capability'
  exit 2
fi
