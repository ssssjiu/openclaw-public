#!/usr/bin/env bash

 # Central deployment paths. Developers may override these for a local
 # checkout; executable paths must not contain a machine-specific username.
runtime_paths_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPENCLAW_WORKSPACE_ROOT="${OPENCLAW_WORKSPACE_ROOT:-$runtime_paths_root}"
export OPENCLAW_LOBSTER_ROOT="${OPENCLAW_LOBSTER_ROOT:-${HOME:-/var/lib/openclaw-gateway}/.openclaw/npm/projects}"
export OPENCLAW_LOBSTER_INSTALLED="${OPENCLAW_LOBSTER_INSTALLED:-${HOME:-/var/lib/openclaw-gateway}/.openclaw/extensions/lobster/index.js}"
