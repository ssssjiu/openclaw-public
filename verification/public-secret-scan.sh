#!/usr/bin/env bash
set -u -o pipefail
if [[ $# -ne 1 ]]; then printf 'usage: %s <directory>\n' "$0" >&2; exit 2; fi
dir="$(realpath "$1")"
[[ -d "$dir" ]] || { printf '%s\n' 'PUBLIC_SECRET_SCAN_BLOCKED: directory missing' >&2; exit 2; }
patterns='(BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|discord:[0-9]{15,}|(DISCORD_BOT_TOKEN|OPENAI_API_KEY|GOOGLE_CLIENT_SECRET|GITHUB_TOKEN)=|/home/[^/]+/\.openclaw|github\.com/[^/]+/[^/]+\.git)'
if rg -n --hidden --glob '!.git/**' --glob '!*.pyc' -e "$patterns" "$dir" >/dev/null 2>&1; then
  printf '%s\n' 'PUBLIC_SECRET_SCAN_BLOCKED: sensitive or personal value found' >&2
  exit 2
fi
printf '%s\n' 'PUBLIC_SECRET_SCAN_PASS'
