#!/usr/bin/env bash
set -u -o pipefail
[[ $# -eq 1 ]] || { printf 'usage: %s <receipt.json>\n' "$0" >&2; exit 2; }
file="$1"
schema="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/contracts/live-approval-receipt.schema.json"
jq -e . "$file" >/dev/null 2>&1 || { printf '%s\n' 'LIVE_APPROVAL_RECEIPT_BLOCKED: invalid JSON' >&2; exit 2; }
jq -e . "$schema" >/dev/null 2>&1 || { printf '%s\n' 'LIVE_APPROVAL_RECEIPT_BLOCKED: schema invalid' >&2; exit 2; }
jq -e '(.schemaVersion==1 and .status=="LIVE_APPROVAL_E2E_PASS" and .approvalRequired==true and .approvalResolved==true and (.runDir|length)>0 and (.target|length)>0 and (.flowId|length)>0 and (.approvalId|length)>0 and (.approver|test("^discord:[0-9]+$")) and .ledgerStatus=="EVIDENCE_LEDGER_PASS" and .rollbackStatus=="ROLLBACK_PASS" and (.ledgerSha256|test("^[a-f0-9]{64}$")) and .mutationCount==1 and .temporaryFixtureRemoved==true and .noApprovalRequired==false)' "$file" >/dev/null 2>&1 || {
  printf '%s\n' 'LIVE_APPROVAL_RECEIPT_BLOCKED: contract invalid' >&2
  exit 2
}
printf '%s\n' 'LIVE_APPROVAL_RECEIPT_PASS'
