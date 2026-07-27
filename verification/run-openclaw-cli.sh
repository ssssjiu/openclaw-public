#!/usr/bin/env bash
set -u -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/verification/openclaw-cli.sh"
openclaw_cli "$@"
