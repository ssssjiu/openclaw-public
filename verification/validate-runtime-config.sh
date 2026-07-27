#!/usr/bin/env bash
set -u -o pipefail
if [[ $# -ne 1 ]]; then printf 'usage: %s <runtime-config.json>\n' "$0" >&2; exit 2; fi
file="$1"
[[ -f "$file" ]] || { printf '%s\n' 'RUNTIME_CONFIG_BLOCKED: config missing' >&2; exit 2; }
jq empty "$file" >/dev/null 2>&1 || { printf '%s\n' 'RUNTIME_CONFIG_BLOCKED: invalid JSON' >&2; exit 2; }
jq -e 'type=="object" and (.approver|test("^discord:[0-9]+$")) and (.workspaceRoot|startswith("/")) and (.capabilityRoot|startswith("/")) and (.brokerSocket|startswith("/")) and (.allowedRemoteHosts|type=="array" and length>0)' "$file" >/dev/null 2>&1 || {
  printf '%s\n' 'RUNTIME_CONFIG_BLOCKED: schema or identity invalid' >&2
  exit 2
}
printf '%s\n' 'RUNTIME_CONFIG_PASS'
