#!/usr/bin/env bash
set -u -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli_runner="$root/verification/run-openclaw-cli.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
failures=()

run_check() {
  local name="$1"; shift
  if ! timeout -k 3 "${OPERATIONAL_CHECK_TIMEOUT_SECONDS:-90}" "$@" >"$tmp/$name.out" 2>&1; then
    failures+=("$name")
  fi
}

# Read-only operational cycle. It never creates a TaskFlow, sends delivery,
# mutates a workspace fixture, installs packages, or changes Gateway state.
run_check config_validate bash "$cli_runner" config validate
run_check gateway_health bash "$cli_runner" gateway health
run_check hardening bash "$root/verification/check-installed-hardening.sh"
run_check supply_chain bash "$root/verification/check-plugin-supply-chain.sh"
run_check approval_bridge bash "$root/verification/approval-bridge-regression.sh"
run_check hallucination bash "$root/verification/hallucination-negative-regression.sh"
run_check structural bash "$root/verification/run-structural-regression.sh"
run_check security bash "$root/verification/run-security-static-regression.sh"
run_check readiness bash "$root/verification/check-operational-readiness.sh"
run_check shadow-l1 bash -c '
  set +e
  output="$(OPENCLAW_SHADOW_CI=1 bash "$1")"
  rc=$?
  set -e
  jq -e '\'' .mode=="shadow" and .automaticMutation==false and .levels.L1=="PASS" and .levels.L2=="BLOCKED" and .levels.L3=="BLOCKED" '\'' <<<"$output" >/dev/null
' _ "$root/verification/run-shadow-promotion.sh"

waiting_blocked="$(timeout -k 3 "${OPERATIONAL_TASKFLOW_TIMEOUT_SECONDS:-30}" bash "$cli_runner" tasks flow list --json 2>/dev/null | jq '[.flows[] | select(.status=="waiting" or .status=="blocked")] | length' 2>/dev/null || printf 'unavailable')"
if [[ "$waiting_blocked" != 0 ]]; then
  failures+=("taskflow_waiting_or_blocked:${waiting_blocked}")
fi

if (( ${#failures[@]} )); then
  printf 'OPERATIONAL_REGRESSION_BLOCKED\nfailures=%s\n' "$(IFS=,; echo "${failures[*]}")"
  exit 2
fi

printf 'OPERATIONAL_REGRESSION_PASS\nchecks=10\nwaiting_or_blocked=%s\nretained_evidence=none\n' "$waiting_blocked"
