#!/usr/bin/env bash
set -u -o pipefail
[[ $# -eq 1 ]] || { printf 'usage: %s <ledger.json>\n' "$0" >&2; exit 2; }
file="$1"
jq -e . "$file" >/dev/null 2>&1 || { printf '%s\n' 'EVIDENCE_LEDGER_BLOCKED: invalid JSON' >&2; exit 2; }
jq -e '(.schemaVersion==1 and .status=="EVIDENCE_LEDGER_PASS" and (.runDir|type)=="string" and (.flowId|length)>0 and (.approvalId|length)>0 and (.approver|test("^discord:[0-9]+$")) and .mutationCount==1 and (.entries|type)=="array" and (.entries|length)>=6 and all(.entries[]; (.name|type)=="string" and (.status|type)=="string" and (.sha256|test("^[a-f0-9]{64}$"))) and ([.entries[] | select(.name=="preflight")][0].status=="PREFLIGHT_PASS") and ([.entries[] | select(.name=="identity")][0].status=="IDENTITY_PASS") and ([.entries[] | select(.name=="delivery")][0].status=="PASS") and ([.entries[] | select(.name=="apply")][0].status=="APPLY_PASS") and ([.entries[] | select(.name=="verification")][0].status=="VERIFY_PASS") and ([.entries[] | select(.name=="evaluator-result")][0].status=="PASS"))' "$file" >/dev/null 2>&1 || {
  printf '%s\n' 'EVIDENCE_LEDGER_BLOCKED: contract invalid' >&2
  exit 2
}
printf '%s\n' 'EVIDENCE_LEDGER_PASS'
