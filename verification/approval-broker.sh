#!/usr/bin/env bash
set -u -o pipefail

usage() {
  printf '%s\n' 'usage: approval-broker.sh <issue|verify|consume> <capability-file> [request-json] [operation] [run-dir]' >&2
  exit 2
}
[[ $# -ge 2 ]] || usage
action="$1"
capability="$(realpath -m "$2")"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/verification/runtime-config.sh"
capability_root="${OPENCLAW_APPROVAL_CAPABILITY_ROOT:-$OPENCLAW_CAPABILITY_ROOT}"
approver_id="$OPENCLAW_APPROVER_ID"
capability_root="$(realpath -m "$capability_root")"
case "$capability" in
  "$capability_root"/*) ;;
  *) printf '%s\n' 'BLOCKED_CAPABILITY: capability path escapes configured root' >&2; exit 2 ;;
esac
now_ms="$(date +%s%3N)"

hash_packet() {
  jq -cS 'del(.capabilitySha256)' "$1" | sha256sum | awk '{print $1}'
}

validate() {
  local file="$1" operation="${2:-}" run_dir="${3:-}"
  [[ -f "$file" ]] || { printf '%s\n' 'BLOCKED_CAPABILITY: capability file missing' >&2; return 2; }
  jq empty "$file" >/dev/null 2>&1 || { printf '%s\n' 'BLOCKED_CAPABILITY: capability is invalid JSON' >&2; return 2; }
  jq -e --arg approver "$approver_id" '(.schemaVersion==1 and .status=="APPROVED" and (.operation|type)=="string" and (.runDir|type)=="string" and (.flowId|type)=="string" and (.revision|type)=="number" and (.revision >= 0) and (.approvalId|type)=="string" and .approver==$approver and (.targetHash|test("^[a-f0-9]{64}$")) and (.criteriaHash|test("^[a-f0-9]{64}$")) and (.workflowHash|test("^[a-f0-9]{64}$")) and (.evidenceHash|test("^[a-f0-9]{64}$")) and (.issuedAtMs|type)=="number" and (.expiresAtMs|type)=="number" and (.nonce|test("^[a-f0-9]{64}$")) and (.capabilitySha256|test("^[a-f0-9]{64}$")))' "$file" >/dev/null 2>&1 || { printf '%s\n' 'BLOCKED_CAPABILITY: capability schema invalid' >&2; return 2; }
  [[ "$(jq -r .capabilitySha256 "$file")" == "$(hash_packet "$file")" ]] || { printf '%s\n' 'BLOCKED_CAPABILITY: capability hash mismatch' >&2; return 2; }
  (( $(jq -r .expiresAtMs "$file") > now_ms )) || { printf '%s\n' 'BLOCKED_CAPABILITY: capability expired' >&2; return 2; }
  if [[ -n "$operation" ]]; then [[ "$(jq -r .operation "$file")" == "$operation" ]] || { printf '%s\n' 'BLOCKED_CAPABILITY: operation mismatch' >&2; return 2; }; fi
  if [[ -n "$run_dir" ]]; then [[ "$(jq -r .runDir "$file")" == "$run_dir" ]] || { printf '%s\n' 'BLOCKED_CAPABILITY: run binding mismatch' >&2; return 2; }; fi
}

case "$action" in
  issue)
    [[ $# -eq 3 ]] || usage
    [[ "${OPENCLAW_APPROVAL_BROKER_ISSUER:-}" == "gateway" ]] || { printf '%s\n' 'BLOCKED_CAPABILITY: only Gateway broker issuer may issue capabilities' >&2; exit 2; }
    request="$3"
    jq -e --arg approver "$approver_id" '(.operation|type)=="string" and (.runDir|type)=="string" and (.flowId|type)=="string" and (.revision|type)=="number" and (.revision >= 0) and (.approvalId|type)=="string" and .approver==$approver and (.targetHash|test("^[a-f0-9]{64}$")) and (.criteriaHash|test("^[a-f0-9]{64}$")) and (.workflowHash|test("^[a-f0-9]{64}$")) and (.evidenceHash|test("^[a-f0-9]{64}$"))' "$request" >/dev/null 2>&1 || { printf '%s\n' 'BLOCKED_CAPABILITY: issue request invalid' >&2; exit 2; }
    mkdir -p "$capability_root"; umask 077
    nonce="$(openssl rand -hex 32 2>/dev/null || true)"; [[ "$nonce" =~ ^[a-f0-9]{64}$ ]] || { printf '%s\n' 'BLOCKED_CAPABILITY: secure nonce unavailable' >&2; exit 2; }
    jq --arg nonce "$nonce" --argjson issued "$now_ms" --argjson expires "$((now_ms + 120000))" '{schemaVersion:1,status:"APPROVED",operation,runDir,flowId,revision,approvalId,approver,targetHash,criteriaHash,workflowHash,evidenceHash,issuedAtMs:$issued,expiresAtMs:$expires,nonce:$nonce,capabilitySha256:""}' "$request" > "$capability.tmp"
    sha="$(hash_packet "$capability.tmp")"; jq --arg sha "$sha" '.capabilitySha256=$sha' "$capability.tmp" > "$capability"; rm -f "$capability.tmp"; chmod 660 "$capability"; validate "$capability"; cat "$capability"
    ;;
  verify) [[ $# -eq 4 ]] || usage; validate "$capability" "$3" "$4" || exit $?; printf '%s\n' 'CAPABILITY_VERIFY_PASS' ;;
  consume) [[ $# -eq 4 ]] || usage; validate "$capability" "$3" "$4" || exit $?; mkdir -p "$capability_root/consumed"; mv -f -- "$capability" "$capability_root/consumed/$(basename "$capability").$(date +%s%3N)"; printf '%s\n' 'CAPABILITY_CONSUME_PASS' ;;
  *) usage ;;
esac
