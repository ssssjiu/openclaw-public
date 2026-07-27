#!/usr/bin/env bash
set -u -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli_runner="$root/verification/run-openclaw-cli.sh"
failures=()
run_check() {
  local name="$1"; shift
  if ! "$@" >/dev/null 2>&1; then failures+=("$name"); fi
}

approval_bridge_static_check() {
  local output rc
  output="$(bash "$root/verification/check-approval-bridge.sh" 2>&1)" || rc=$?
  rc="${rc:-0}"
  if [[ "$rc" == 0 ]]; then
    return 0
  fi
  if grep -q '^APPROVAL_BRIDGE_STATIC_DEFERRED$' <<<"$output"; then
    printf '%s\n' 'APPROVAL_BRIDGE_STATIC_DEFERRED_ACCEPTED' >&2
    printf '%s\n' 'reason=runtime-uses-bundled-lobster-and-installed-hardening-is-checked-separately' >&2
    return 0
  fi
  printf '%s\n' "$output" >&2
  return "$rc"
}

# Upgrade/reinstall regression harness. It is intentionally read-only: it
# never installs packages, restarts Gateway, sends Discord messages, or creates
# a TaskFlow. Detailed command output is ephemeral and discarded.
run_check config-valid bash "$cli_runner" config validate
run_check plugins-doctor bash "$cli_runner" plugins doctor
run_check hardening-intact bash "$root/verification/check-installed-hardening.sh"
run_check approval-bridge approval_bridge_static_check
run_check stale-approval bash "$root/verification/test-stale-approval.sh"
run_check supply-chain bash "$root/verification/check-plugin-supply-chain.sh"
run_check security-static bash "$root/verification/run-security-static-regression.sh"

if (( ${#failures[@]} )); then
  printf '%s\n' 'APPROVAL_BRIDGE_REGRESSION_BLOCKED'
  printf ' - %s\n' "${failures[@]}"
  exit 2
fi

printf '%s\n' 'APPROVAL_BRIDGE_REGRESSION_PASS'
printf '%s\n' 'mode=read-only; external_delivery=none; mutation=none; retained_evidence=none'
