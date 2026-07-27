#!/usr/bin/env bash
set -u -o pipefail

runtime_root="${OPENCLAW_RUNTIME_ROOT:-/opt/openclaw-runtime/openclaw}"
unit="${OPENCLAW_GATEWAY_UNIT:-openclaw-gateway.service}"
evidence_dir="${OPENCLAW_APPROVAL_EVIDENCE_DIR:-/var/lib/openclaw-gateway/approval-evidence}"
failures=()

[[ -f "$runtime_root/package.json" ]] || failures+=(runtime-package-missing)
[[ -f "$runtime_root/dist/index.js" ]] || failures+=(runtime-entry-missing)
if [[ -d "$runtime_root/dist" ]]; then
  rg -q 'persistApprovalDeliveryEvidence|OPENCLAW_APPROVAL_EVIDENCE_DIR' "$runtime_root/dist" || failures+=(delivery-evidence-runtime-missing)
else
  failures+=(runtime-dist-missing)
fi

environment="$(systemctl show "$unit" -p Environment --value 2>/dev/null || true)"
grep -Fq 'OPENCLAW_APPROVAL_EVIDENCE_DIR=' <<<"$environment" || failures+=(systemd-evidence-dir-missing)
[[ -d "$evidence_dir" ]] || failures+=(evidence-directory-missing)
systemctl is-active --quiet "$unit" 2>/dev/null || failures+=(gateway-inactive)
systemctl is-active --quiet openclaw-broker.service 2>/dev/null || failures+=(broker-inactive)

if ((${#failures[@]})); then
  printf '%s\n' 'INSTALLED_APPROVAL_EVIDENCE_BLOCKED'
  printf ' - %s\n' "${failures[@]}"
  exit 2
fi
printf '%s\n' 'INSTALLED_APPROVAL_EVIDENCE_PASS'
printf ' - runtime:%s\n' "$runtime_root"
printf ' - evidence:%s\n' "$evidence_dir"
