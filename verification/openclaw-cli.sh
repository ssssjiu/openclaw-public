#!/usr/bin/env bash

openclaw_cli() {
  if [[ -n "${OPENCLAW_BIN:-}" ]]; then
    "$OPENCLAW_BIN" "$@"
  elif command -v openclaw >/dev/null 2>&1; then
    openclaw "$@"
  elif [[ -x /usr/bin/node && -f /opt/openclaw-runtime/openclaw/dist/index.js ]]; then
    /usr/bin/node /opt/openclaw-runtime/openclaw/dist/index.js "$@"
  else
    return 127
  fi
}

openclaw_cli_available() {
  [[ -n "${OPENCLAW_BIN:-}" ]] || command -v openclaw >/dev/null 2>&1 || {
    [[ -x /usr/bin/node && -f /opt/openclaw-runtime/openclaw/dist/index.js ]]
  }
}
