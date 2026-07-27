#!/usr/bin/env bash
set -u -o pipefail
if [[ $# -ne 1 || ! -f "$1" ]]; then
  printf '%s\n' 'usage: target-hash.sh <preflight.json>' >&2
  exit 2
fi
jq -cS 'del(.targetHash, .__openclawCapabilityRequest)' "$1" | sha256sum | awk '{print $1}'
