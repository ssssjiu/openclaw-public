#!/usr/bin/env bash
set -u -o pipefail
packet="$(cat)"
run_dir="$(jq -r '.runDir // empty' <<<"$packet")"
target="$(jq -r '.target // empty' <<<"$packet")"
[[ -n "$run_dir" && -d "$run_dir" ]] || { printf '%s\n' 'EVIDENCE_LEDGER_BLOCKED: run directory missing' >&2; exit 2; }
[[ -f "$run_dir/preflight.json" && -f "$run_dir/identity.json" && -f "$run_dir/delivery.json" && -f "$run_dir/apply.json" && -f "$run_dir/verification.json" && -f "$run_dir/evaluator-result.json" ]] || { printf '%s\n' 'EVIDENCE_LEDGER_BLOCKED: required evidence missing' >&2; exit 2; }
flow_id="$(jq -r '.flowId' "$run_dir/preflight.json")"
approval_id="$(jq -r '.approvalId' "$run_dir/identity.json")"
approver="$(jq -r '.subject // .approver' "$run_dir/identity.json")"
[[ "$approver" =~ ^discord:[0-9]+$ && -n "$approval_id" && -n "$flow_id" ]] || { printf '%s\n' 'EVIDENCE_LEDGER_BLOCKED: identity binding missing' >&2; exit 2; }
ledger_path="${OPENCLAW_LIVE_APPROVAL_LEDGER_PATH:-/var/lib/openclaw-gateway/live-approval-ledger.json}"
mkdir -p "$(dirname "$ledger_path")" || { printf '%s\n' 'EVIDENCE_LEDGER_BLOCKED: ledger directory unavailable' >&2; exit 2; }
entries='[]'
for name in preflight identity delivery apply verification evaluator; do
  file="$run_dir/$name.json"
  status="$(jq -r '.status // "UNKNOWN"' "$file")"
  digest="$(sha256sum "$file" | awk '{print $1}')"
  entries="$(jq -c --arg name "$name" --arg status "$status" --arg sha256 "$digest" '. + [{name:$name,status:$status,sha256:$sha256}]' <<<"$entries")"
done
tmp="${ledger_path}.${BASHPID}.tmp"
jq -n --arg runDir "$run_dir" --arg target "$target" --arg flowId "$flow_id" --arg approvalId "$approval_id" --arg approver "$approver" --argjson entries "$entries" '{schemaVersion:1,status:"EVIDENCE_LEDGER_PASS",runDir:$runDir,target:$target,flowId:$flowId,approvalId:$approvalId,approver:$approver,mutationCount:1,entries:$entries,rollbackPending:true,createdAt:(now|todateiso8601)}' > "$tmp" || exit 2
mv -f "$tmp" "$ledger_path"
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-evidence-ledger.sh" "$ledger_path" >/dev/null || exit 2
jq -n --arg runDir "$run_dir" --arg target "$target" --arg ledgerPath "$ledger_path" '{status:"EVIDENCE_LEDGER_PASS",runDir:$runDir,target:$target,ledgerPath:$ledgerPath,mutationCount:1}'
