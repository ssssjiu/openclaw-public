#!/usr/bin/env bash
set -u -o pipefail

usage() {
  printf '%s\n' 'usage: sudo bash deployment/install-public-package.sh <runtime-source> <source-config> <approver-id> <gateway-secrets.json>' >&2
  exit 2
}

[[ $# -eq 4 ]] || usage
[[ "$(id -u)" == 0 ]] || { printf '%s\n' 'PUBLIC_INSTALL_BLOCKED: root is required' >&2; exit 2; }

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_source="$(realpath "$1")"
source_config="$(realpath "$2")"
approver_id="$3"
gateway_secrets_source="$(realpath "$4")"

[[ -f "$package_root/PUBLIC_PACKAGE_MANIFEST.json" ]] || {
  printf '%s\n' 'PUBLIC_INSTALL_BLOCKED: run from a generated public package' >&2
  exit 2
}
[[ -d "$runtime_source" && -f "$source_config" && -n "$approver_id" && -f "$gateway_secrets_source" ]] || {
  printf '%s\n' 'PUBLIC_INSTALL_BLOCKED: runtime, source config, approver ID, and Gateway secret file are required' >&2
  exit 2
}
jq empty "$gateway_secrets_source" >/dev/null || {
  printf '%s\n' 'PUBLIC_INSTALL_BLOCKED: Gateway secret file is not valid JSON' >&2
  exit 2
}

discord_token="${DISCORD_BOT_TOKEN:-}"
if [[ -z "$discord_token" && -t 0 ]]; then
  printf '%s' 'Discord bot token (input hidden): ' >&2
  IFS= read -r -s discord_token
  printf '\n' >&2
fi
[[ -n "$discord_token" ]] || {
  printf '%s\n' 'PUBLIC_INSTALL_BLOCKED: Discord bot token is required (set DISCORD_BOT_TOKEN or use an interactive terminal)' >&2
  exit 2
}

bash "$package_root/deployment/install-privileged-runtime.sh" --apply "$package_root" "$runtime_source"

config_root="${OPENCLAW_CONFIG_ROOT:-/etc/openclaw}"
install -d -o root -g openclaw-gateway -m 750 "$config_root"
cfg_tmp="$(mktemp /tmp/openclaw-public-config.XXXXXX.json)"
runtime_tmp="$(mktemp /tmp/openclaw-public-runtime.XXXXXX.json)"
discord_tmp="$(mktemp /tmp/openclaw-public-discord.XXXXXX.env)"
trap 'rm -f -- "$cfg_tmp" "$runtime_tmp" "$discord_tmp"' EXIT

bash "$package_root/deployment/render-gateway-config.sh" \
  "$source_config" "$cfg_tmp" \
  /opt/openclaw-workspace /opt/openclaw-workspace "$config_root"
install -o root -g openclaw-gateway -m 640 "$cfg_tmp" "$config_root/openclaw.json"

jq --arg approver "$approver_id" '.approver=$approver' \
  "$package_root/config/runtime.example.json" > "$runtime_tmp"
install -o root -g openclaw-gateway -m 640 "$runtime_tmp" "$config_root/runtime.json"

printf '%s=%s\n' DISCORD_BOT_TOKEN "$discord_token" > "$discord_tmp"
install -o openclaw-gateway -g openclaw-gateway -m 600 "$discord_tmp" "$config_root/discord.env"
install -o openclaw-gateway -g openclaw-gateway -m 600 "$gateway_secrets_source" "$config_root/gateway-secrets.json"

systemctl daemon-reload
printf '%s\n' 'PUBLIC_INSTALL_PASS: files installed; services were not enabled or started'
printf '%s\n' "PUBLIC_INSTALL_NEXT: validate $config_root/openclaw.json, then run the host activation checks and start the units"
