#!/usr/bin/env bash
set -u -o pipefail

usage() { printf 'usage: %s --preflight | --apply <workspace> <runtime-source> | --refresh <workspace> <runtime-source>\n' "$0" >&2; exit 2; }
mode="${1:-}"
[[ "$mode" == --preflight || "$mode" == --apply || "$mode" == --refresh ]] || usage
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_identity() {
  local user="$1"
  id "$user" >/dev/null 2>&1 || { printf 'INSTALL_BLOCKED: missing user %s\n' "$user" >&2; exit 2; }
  [[ "$(getent passwd "$user" | cut -d: -f7)" == /usr/sbin/nologin ]] || { printf 'INSTALL_BLOCKED: %s must be nologin\n' "$user" >&2; exit 2; }
}

require_identity openclaw-gateway
require_identity openclaw-broker

if [[ "$mode" == --preflight ]]; then
  [[ -f "$root/deployment/systemd/openclaw-broker.service.example" ]] || exit 2
  [[ -f "$root/deployment/systemd/openclaw-gateway.service.example" ]] || exit 2
  printf '%s\n' 'PRIVILEGED_INSTALL_PREFLIGHT_PASS'
  exit 0
fi

[[ "$(id -u)" == 0 ]] || { printf '%s\n' 'INSTALL_BLOCKED: root is required for privileged runtime installation' >&2; exit 2; }

[[ $# -eq 3 ]] || usage
workspace_source="$(realpath "$2")"
runtime_source="$(realpath "$3")"
[[ -d "$workspace_source" && -d "$runtime_source" ]] || { printf '%s\n' 'INSTALL_BLOCKED: source directory missing' >&2; exit 2; }
if [[ -e "$runtime_source/lobster-plugin" ]]; then
  [[ -f "$runtime_source/lobster-plugin/index.js" && -f "$runtime_source/lobster-plugin/openclaw.plugin.json" ]] || {
    printf '%s\n' 'INSTALL_BLOCKED: standalone Lobster package is incomplete' >&2
    exit 2
  }
fi
[[ "$workspace_source" != /opt/openclaw-workspace ]] || { printf '%s\n' 'INSTALL_BLOCKED: source and destination must differ' >&2; exit 2; }
if [[ "$mode" == --apply ]]; then
  [[ ! -e /opt/openclaw-workspace ]] || { printf '%s\n' 'INSTALL_BLOCKED: destination already exists; use --refresh after review' >&2; exit 2; }
else
  [[ -f /opt/openclaw-workspace/PUBLIC_PACKAGE_MANIFEST.json ]] || { printf '%s\n' 'INSTALL_BLOCKED: existing destination is not a managed public package' >&2; exit 2; }
fi
[[ -f "$workspace_source/PUBLIC_PACKAGE_MANIFEST.json" ]] || { printf '%s\n' 'INSTALL_BLOCKED: workspace source is not a sanitized public package' >&2; exit 2; }
[[ ! -e "$workspace_source/.git" && ! -e "$workspace_source/config/runtime.json" ]] || { printf '%s\n' 'INSTALL_BLOCKED: private repository state/config in workspace source' >&2; exit 2; }
if find "$workspace_source" -type f \( -name '*.env' -o -name '*.pem' -o -name '*credential*' -o -name '*secret*' \) -print -quit | grep -q .; then
  printf '%s\n' 'INSTALL_BLOCKED: credential-like file in workspace source' >&2
  exit 2
fi
bash "$root/verification/public-secret-scan.sh" "$workspace_source" >/dev/null || exit $?

# Accept either a bundle containing an `openclaw/` directory or an OpenClaw
# package root itself. Normalize both into the immutable
# /opt/openclaw-runtime/openclaw layout expected by the system unit.
runtime_payload="$runtime_source"
if [[ -f "$runtime_source/openclaw/package.json" && -f "$runtime_source/openclaw/dist/index.js" ]]; then
  runtime_payload="$runtime_source/openclaw"
elif [[ -f "$runtime_source/package.json" && -f "$runtime_source/dist/index.js" ]]; then
  runtime_payload="$runtime_source"
else
  printf '%s\n' 'INSTALL_BLOCKED: runtime source must contain package.json and dist/index.js' >&2
  exit 2
fi
bash "$root/verification/check-runtime-integrity.sh" "$runtime_payload" >/dev/null || {
  printf '%s\n' 'INSTALL_BLOCKED: runtime integrity check failed' >&2
  exit 2
}

install -d -o root -g root -m 755 /etc/openclaw
install -d -o openclaw-broker -g openclaw-gateway -m 750 /var/lib/openclaw-broker /var/lib/openclaw-broker/capabilities
install -d -o openclaw-gateway -g openclaw-gateway -m 750 /var/lib/openclaw-gateway/approval-evidence

# Refresh must replace the complete immutable trees. Copying over an existing
# tree leaves hashed JS chunks from older builds behind and can create a
# runtime that starts successfully but crosses incompatible approval modules.
stage_root="$(mktemp -d /opt/.openclaw-refresh.XXXXXX)"
cleanup_stage() { rm -rf -- "$stage_root"; }
trap cleanup_stage EXIT
install -d -o root -g root -m 755 "$stage_root/workspace" "$stage_root/runtime/openclaw"
cp -a -- "$workspace_source/." "$stage_root/workspace/"
cp -a -- "$runtime_payload/." "$stage_root/runtime/openclaw/"
chown -R root:root "$stage_root/workspace" "$stage_root/runtime"
chmod 755 "$stage_root/runtime"

if [[ -e /opt/openclaw-workspace ]]; then
  mv -- /opt/openclaw-workspace "/opt/openclaw-workspace.previous.$(date +%s)"
fi
if [[ -e /opt/openclaw-runtime ]]; then
  mv -- /opt/openclaw-runtime "/opt/openclaw-runtime.previous.$(date +%s)"
fi
mv -- "$stage_root/workspace" /opt/openclaw-workspace
mv -- "$stage_root/runtime" /opt/openclaw-runtime
# Agent workspaces are derived from the rendered deployment root.  Create the
# directories explicitly because sanitized packages do not need to carry empty
# directories, and the service runs with the deployment tree read-only.
for agent_id in social evaluator research approval-runner; do
  install -d -o root -g root -m 755 "/opt/openclaw-workspace/agents/$agent_id"
done
# The runtime loader rejects user-owned plugin trees as an unsafe supply-chain
# source. Public package and runtime files are immutable service inputs and
# must be root-owned after installation.
chown -R root:root /opt/openclaw-workspace /opt/openclaw-runtime
# `runtime_source` is commonly a mktemp directory (0700).  Do not let that
# staging-directory mode become the service's working-directory mode when
# cp -a copies `.` into the destination.
chown root:root /opt/openclaw-runtime
chmod 755 /opt/openclaw-runtime
install -o root -g root -m 644 "$root/deployment/systemd/openclaw-broker.service.example" /etc/systemd/system/openclaw-broker.service
install -o root -g root -m 644 "$root/deployment/systemd/openclaw-gateway.service.example" /etc/systemd/system/openclaw-gateway.service
if [[ "$mode" == --refresh ]]; then
  printf '%s\n' 'PRIVILEGED_REFRESH_PASS: files and units refreshed but not enabled, started, or restarted'
else
  printf '%s\n' 'PRIVILEGED_INSTALL_PASS: units installed but not enabled, started, or restarted'
fi
