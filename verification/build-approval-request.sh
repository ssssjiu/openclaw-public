#!/usr/bin/env bash
set -u -o pipefail
if [[ $# -ne 2 ]]; then printf '%s\n' 'usage: build-approval-request.sh <operation> <approver>' >&2; exit 2; fi
operation="$1"; approver="$2"; packet="$(cat)"
run_dir="$(jq -r '.runDir // empty' <<<"$packet")"
flow_id="$(jq -r '.flowId // empty' <<<"$packet")"
revision="$(jq -r '.revision // .flowRevision // 0' <<<"$packet")"
target_hash="$(jq -r '.targetHash // empty' <<<"$packet")"
[[ "$revision" =~ ^[0-9]+$ ]] || { printf '%s\n' 'BLOCKED_APPROVAL_REQUEST: revision is invalid' >&2; exit 2; }
if [[ -z "$flow_id" && -n "$run_dir" ]]; then flow_id="${operation}-$(basename "$run_dir")"; fi
if [[ -z "$target_hash" ]]; then target_hash="$(printf '%s' "$packet" | jq -cS 'del(.targetHash, .__openclawCapabilityRequest)' | sha256sum | awk '{print $1}')"; fi
hash_file_or_empty() { local path="$1"; if [[ -n "$path" && -f "$path" ]]; then sha256sum "$path" | awk '{print $1}'; else printf '%s' '' | sha256sum | awk '{print $1}'; fi; }
criteria_file="$(jq -r '.criteria // empty' <<<"$packet")"; workflow_file="$(jq -r '.workflow // .workflowFile // empty' <<<"$packet")"
if [[ -z "$criteria_file" ]]; then criteria_file="$PWD/loops/$operation/criteria.json"; [[ -f "$criteria_file" ]] || criteria_file="$PWD/loops/$operation/l3-criteria.json"; fi
if [[ -z "$workflow_file" ]]; then workflow_file="$PWD/loops/$operation/$operation.lobster"; fi
criteria_hash="$(jq -r '.criteriaHash // .criteriaSha256 // empty' <<<"$packet")"; [[ "$criteria_hash" =~ ^[a-f0-9]{64}$ ]] || criteria_hash="$(hash_file_or_empty "$criteria_file")"
workflow_hash="$(jq -r '.workflowHash // .workflowSha256 // empty' <<<"$packet")"; [[ "$workflow_hash" =~ ^[a-f0-9]{64}$ ]] || workflow_hash="$(hash_file_or_empty "$workflow_file")"
evidence_hash="$(jq -r '.evidenceHash // empty' <<<"$packet")"; [[ "$evidence_hash" =~ ^[a-f0-9]{64}$ ]] || evidence_hash="$(printf '%s' "$packet" | jq -cS 'del(.__openclawCapabilityRequest)' | sha256sum | awk '{print $1}')"
[[ -n "$run_dir" && -n "$flow_id" && "$target_hash" =~ ^[a-f0-9]{64}$ && "$criteria_hash" =~ ^[a-f0-9]{64}$ && "$workflow_hash" =~ ^[a-f0-9]{64}$ && "$evidence_hash" =~ ^[a-f0-9]{64}$ ]] || { printf '%s\n' 'BLOCKED_APPROVAL_REQUEST: preflight binding is incomplete' >&2; exit 2; }
jq -n --arg operation "$operation" --arg runDir "$run_dir" --arg flowId "$flow_id" --arg approver "$approver" --arg targetHash "$target_hash" --argjson revision "$revision" --arg criteriaHash "$criteria_hash" --arg workflowHash "$workflow_hash" --arg evidenceHash "$evidence_hash" '{approvalReady:true,flowId:$flowId,revision:$revision,targetHash:$targetHash,criteriaHash:$criteriaHash,workflowHash:$workflowHash,evidenceHash:$evidenceHash,__openclawCapabilityRequest:{operation:$operation,runDir:$runDir,flowId:$flowId,revision:$revision,approvalId:"",approver:$approver,targetHash:$targetHash,criteriaHash:$criteriaHash,workflowHash:$workflowHash,evidenceHash:$evidenceHash}}'
