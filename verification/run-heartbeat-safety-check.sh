#!/usr/bin/env bash
set -u -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/verification/openclaw-cli.sh"
checks=()
run_check() {
  local id="$1"; shift
  if timeout -k 2 "${HEARTBEAT_CHECK_TIMEOUT_SECONDS:-45}" "$@" >/dev/null 2>&1; then
    checks+=("$(jq -cn --arg id "$id" '{id:$id,status:"PASS"}')")
  else
    checks+=("$(jq -cn --arg id "$id" '{id:$id,status:"BLOCKED"}')")
  fi
}

run_check recovery bash "$root/verification/scan-loop-state-recovery.sh" "$root/loops"
run_check readiness bash "$root/verification/check-operational-readiness.sh"
if openclaw_cli_available; then
  run_check taskflow-inventory bash -c 'source "$1"; openclaw_cli tasks flow list --json' _ "$root/verification/openclaw-cli.sh"
else
  checks+=("$(jq -cn '{id:"taskflow-inventory",status:"NOT_RUN",reason:"openclaw CLI unavailable"}')")
fi

jq -n --argjson checks "[$(IFS=,; printf '%s' "${checks[*]}")]" \
  '{mode:"read-only-heartbeat",automaticResume:false,mutationCount:0,checks:$checks,status:(if any($checks[]; .status=="BLOCKED") then "BLOCKED" else "PASS" end),summary:(if any($checks[]; .status=="BLOCKED") then "Read-only heartbeat detected a condition requiring operator review." else "Read-only heartbeat checks passed; no resume or mutation was attempted." end)}'
if [[ "$(jq -r 'if any(.[]; .status=="BLOCKED") then "BLOCKED" else "PASS" end' <<<"[$(IFS=,; printf '%s' "${checks[*]}")]")" == BLOCKED ]]; then
  exit 1
fi
