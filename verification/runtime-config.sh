#!/usr/bin/env bash
set -u -o pipefail
runtime_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_config="${OPENCLAW_RUNTIME_CONFIG:-$runtime_root/config/runtime.json}"
bash "$runtime_root/verification/validate-runtime-config.sh" "$runtime_config" >/dev/null || exit $?
OPENCLAW_APPROVER_ID="$(jq -r '.approver' "$runtime_config")"
OPENCLAW_WORKSPACE_ROOT="$(jq -r '.workspaceRoot' "$runtime_config")"
OPENCLAW_CAPABILITY_ROOT="$(jq -r '.capabilityRoot' "$runtime_config")"
OPENCLAW_BROKER_SOCKET="$(jq -r '.brokerSocket' "$runtime_config")"
export OPENCLAW_APPROVER_ID OPENCLAW_WORKSPACE_ROOT OPENCLAW_CAPABILITY_ROOT OPENCLAW_BROKER_SOCKET
