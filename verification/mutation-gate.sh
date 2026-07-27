#!/usr/bin/env bash
set -u -o pipefail

if [[ $# -ne 3 ]]; then
  printf '%s\n' 'usage: mutation-gate.sh <run-dir> <criteria-file> <adapter>' >&2
  exit 2
fi

run_dir="$(realpath "$1")"
criteria="$(realpath "$2")"
adapter="$3"
export OPENCLAW_RUNTIME_CONFIG="${OPENCLAW_RUNTIME_CONFIG:-/etc/openclaw/runtime.json}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runtime-config.sh"
case "$run_dir" in
  "$OPENCLAW_WORKSPACE_ROOT"/*) ;;
  *) [[ "${OPENCLAW_TEST_MODE:-0}" == 1 ]] || { printf '%s\n' 'BLOCKED_MUTATION_GATE: run directory escapes configured workspace' >&2; exit 2; } ;;
esac
identity="$run_dir/identity.json"
preflight="$run_dir/preflight.json"

[[ -d "$run_dir" && -f "$identity" && -f "$preflight" && -f "$criteria" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: approval packet is incomplete' >&2
  exit 2
}
[[ "${OPENCLAW_APPROVAL_GATE:-}" == GATEWAY_VERIFIED ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: gateway approval capability is missing' >&2
  exit 2
}
capability="${OPENCLAW_APPROVAL_CAPABILITY_FILE:-}"
[[ -n "$capability" ]] || { printf '%s\n' 'BLOCKED_MUTATION_GATE: one-time capability file is missing' >&2; exit 2; }
broker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/approval-broker.sh"
flow_id="$(jq -r '.flowId // empty' "$identity")"
[[ -n "$flow_id" && "${OPENCLAW_APPROVAL_FLOW_ID:-}" == "$flow_id" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: approval flow binding is missing' >&2
  exit 2
}
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/contracts/validate-approval-identity.sh" "$identity" "$criteria" "$flow_id" >/dev/null || exit $?
jq -e --arg runDir "$run_dir" --arg flowId "$flow_id" '.flowId==$flowId and .runDir==$runDir' "$capability" >/dev/null 2>&1 || { printf '%s\n' 'BLOCKED_MUTATION_GATE: capability binding mismatch' >&2; exit 2; }
capability_revision="$(jq -r '.revision // -1' "$capability")"
preflight_revision="$(jq -r '.revision // 0' "$preflight")"
[[ "$capability_revision" =~ ^[0-9]+$ && "$preflight_revision" =~ ^[0-9]+$ && "$capability_revision" == "$preflight_revision" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: capability revision does not match approved preflight' >&2
  exit 2
}
capability_criteria_hash="$(jq -r '.criteriaHash // empty' "$capability")"
preflight_criteria_hash="$(jq -r '.criteriaSha256 // empty' "$preflight")"
[[ "$preflight_criteria_hash" =~ ^[a-f0-9]{64}$ ]] || preflight_criteria_hash="$(sha256sum "$criteria" | awk '{print $1}')"
[[ "$capability_criteria_hash" == "$preflight_criteria_hash" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: capability criteria hash does not match approved preflight' >&2
  exit 2
}
capability_workflow_hash="$(jq -r '.workflowHash // empty' "$capability")"
preflight_workflow_hash="$(jq -r '.workflowSha256 // empty' "$preflight")"
if [[ -n "${OPENCLAW_APPROVAL_WORKFLOW_FILE:-}" && -f "$OPENCLAW_APPROVAL_WORKFLOW_FILE" ]]; then
  preflight_workflow_hash="$(sha256sum "$OPENCLAW_APPROVAL_WORKFLOW_FILE" | awk '{print $1}')"
fi
[[ "$preflight_workflow_hash" =~ ^[a-f0-9]{64}$ && "$capability_workflow_hash" == "$preflight_workflow_hash" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: capability workflow hash does not match approved preflight' >&2
  exit 2
}
capability_evidence_hash="$(jq -r '.evidenceHash // empty' "$capability")"
[[ "$capability_evidence_hash" =~ ^[a-f0-9]{64}$ ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: capability evidence hash is missing' >&2
  exit 2
}
capability_approval_id="$(jq -r '.approvalId // empty' "$capability")"
identity_approval_id="$(jq -r '.approvalId // empty' "$identity")"
[[ -n "$capability_approval_id" && "$identity_approval_id" == "$capability_approval_id" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: approval identity does not match capability' >&2
  exit 2
}
capability_target_hash="$(jq -r '.targetHash // empty' "$capability")"
preflight_target_hash="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/target-hash.sh" "$preflight")"
[[ "$capability_target_hash" == "$preflight_target_hash" ]] || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: capability target does not match approved preflight'
  exit 2
}
bash "$broker" verify "$capability" "$adapter" "$run_dir" >/dev/null || exit $?
jq -e --arg adapter "$adapter" '(.status|IN("PREFLIGHT_PASS","PREFLIGHT_READY")) and (.adapter == $adapter)' "$preflight" >/dev/null 2>&1 || {
  printf '%s\n' 'BLOCKED_MUTATION_GATE: preflight adapter binding is invalid' >&2
  exit 2
}
printf 'MUTATION_GATE_PASS adapter=%s flow=%s\n' "$adapter" "$flow_id"
