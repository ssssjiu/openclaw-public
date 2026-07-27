#!/usr/bin/env bash
set -u -o pipefail
if [[ $# -ne 3 ]]; then printf 'usage: %s <identity.json> <criteria.json> <flow-id>\n' "$0" >&2; exit 2; fi
identity="$1"; criteria="$2"; flow_id="$3"
for file in "$identity" "$criteria"; do
  [[ -f "$file" ]] || { printf 'BLOCKED_IDENTITY: missing %s\n' "$file" >&2; exit 2; }
done
jq -e '(.schemaVersion == 1) and (.status == "IDENTITY_PASS") and (.source == "gateway_verified") and (.subject|type == "string") and (.approvalId|type == "string") and (.flowId|type == "string") and (.assertionPayload|type == "string") and (.assertionSha256|test("^[a-f0-9]{64}$"))' "$identity" >/dev/null 2>&1 || { printf '%s\n' 'BLOCKED_IDENTITY: evidence does not satisfy gateway_verified schema' >&2; exit 2; }
required="$(jq -r '.requiredApprover // empty' "$criteria")"
subject="$(jq -r '.subject' "$identity")"
evidence_flow="$(jq -r '.flowId' "$identity")"
[[ -n "$required" && "$subject" == "$required" ]] || { printf '%s\n' 'BLOCKED_IDENTITY: evidence subject does not match requiredApprover' >&2; exit 2; }
[[ "$evidence_flow" == "$flow_id" ]] || { printf '%s\n' 'BLOCKED_IDENTITY: evidence flowId does not match managed flow' >&2; exit 2; }
actual_sha="$(jq -r '.assertionPayload' "$identity" | tr -d '\n' | sha256sum | awk '{print $1}')"
expected_sha="$(jq -r '.assertionSha256' "$identity")"
[[ "$actual_sha" == "$expected_sha" ]] || { printf '%s\n' 'BLOCKED_IDENTITY: assertion payload hash mismatch' >&2; exit 2; }
jq -e --arg subject "$subject" --arg flowId "$flow_id" --arg approvalId "$(jq -r '.approvalId' "$identity")" 'type == "object" and .source == "gateway_verified" and .subject == $subject and .flowId == $flowId and .approvalId == $approvalId' <<<"$(jq -r '.assertionPayload' "$identity")" >/dev/null 2>&1 || { printf '%s\n' 'BLOCKED_IDENTITY: assertion payload fields do not match identity envelope' >&2; exit 2; }
jq -n --arg subject "$subject" --arg flowId "$flow_id" '{status:"IDENTITY_EVIDENCE_PASS",source:"gateway_verified",subject:$subject,flowId:$flowId,checks:["schema","requiredApprover","flow binding","assertion hash"]}'
