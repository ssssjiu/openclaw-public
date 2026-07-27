#!/usr/bin/env bash
set -u -o pipefail

if [[ $# -ne 3 ]]; then
  printf '%s\n' 'usage: gateway-approval-capability-bridge.sh <decision-json> <request-json> <capability-file>' >&2
  exit 2
fi

decision="$1"
request="$2"
capability="$3"
broker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/approval-broker.sh"
source "$(dirname "${BASH_SOURCE[0]}")/runtime-config.sh"

bash "$(dirname "${BASH_SOURCE[0]}")/validate-plugin-approval-envelope.sh" "$decision" "$request" >/dev/null || exit $?

OPENCLAW_APPROVAL_BROKER_ISSUER=gateway bash "$broker" issue "$capability" "$request"
