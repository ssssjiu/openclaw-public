#!/usr/bin/env bash
set -u -o pipefail
[[ $# -eq 1 ]] || { printf 'usage: %s <delivery-evidence.json>\n' "$0" >&2; exit 2; }
file="$1"
jq -e . "$file" >/dev/null 2>&1 || { printf '%s\n' 'APPROVAL_DELIVERY_EVIDENCE_BLOCKED: invalid JSON' >&2; exit 2; }
jq -e '(.schemaVersion==1 and .status=="PASS" and (.approvalId|type)=="string" and (.approvalId|length)>0 and (.approvalKind|IN("exec","plugin")) and .channel=="discord" and (.target|type)=="string" and (.target|length)>0 and (.accountId|type)=="string" and (.messageIds|type)=="array" and (.messageIds|length)>0 and all(.messageIds[]; type=="string" and length>0) and (.deliveredAt|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")))' "$file" >/dev/null 2>&1 || {
  printf '%s\n' 'APPROVAL_DELIVERY_EVIDENCE_BLOCKED: contract invalid' >&2
  exit 2
}
printf '%s\n' 'APPROVAL_DELIVERY_EVIDENCE_PASS'
