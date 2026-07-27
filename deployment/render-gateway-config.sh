#!/usr/bin/env bash
set -u -o pipefail
if [[ $# -lt 4 || $# -gt 5 ]]; then printf 'usage: %s <source-config> <output-config> <workspace-root> <plugin-root> [config-root]\n' "$0" >&2; exit 2; fi
source_config="$(realpath "$1")"; output_config="$(realpath -m "$2")"; workspace_root="$(realpath "$3")"; plugin_root="$(realpath "$4")"; config_root="$(realpath -m "${5:-${OPENCLAW_CONFIG_ROOT:-/etc/openclaw}}")"; state_root="$(realpath -m "${OPENCLAW_STATE_DIR:-/var/lib/openclaw-gateway}")"
runtime_root="$(realpath -m "${OPENCLAW_RUNTIME_ROOT:-/opt/openclaw-runtime/openclaw/dist}")"
# Lobster must remain inside the complete official OpenClaw dist tree.  The
# Gateway API rejects copied third-party/config-selected plugin roots even when
# their files are otherwise identical, because they lack trusted bundled
# provenance.  The runtime installer therefore must ship the full dist tree.
lobster_path="$runtime_root/extensions/lobster"
[[ -f "$source_config" && "$output_config" != "$source_config" ]] || { printf '%s\n' 'CONFIG_RENDER_BLOCKED: invalid source/output' >&2; exit 2; }
mkdir -p "$(dirname "$output_config")"
jq --arg workspace "$workspace_root" --arg pluginRoot "$plugin_root" --arg configRoot "$config_root" --arg stateRoot "$state_root" '
  # Accept the safety-layer names used by the private configuration, but
  # always render the canonical OpenClaw keys consumed by the Gateway.
  if (.approvals.plugin // null) == null and ((.pluginApprovals // .approvalsPlugin) // null) != null
    then .approvals.plugin=(.pluginApprovals // .approvalsPlugin)
    else . end
  | if (.channels.discord.execApprovals // null) == null and ((.discordApprovals // .discordExecApprovals) // null) != null
    then .channels.discord.execApprovals=(.discordApprovals // .discordExecApprovals)
    else . end
  | if (.channels.discord.accounts // null) == null and (.discordAccounts // null) != null
    then .channels.discord.accounts=.discordAccounts
    else . end
  | del(.pluginApprovals, .approvalsPlugin, .discordApprovals, .discordExecApprovals, .discordAccounts)
  | .agents.defaults.workspace=$workspace
  | .agents.defaults.skipBootstrap=true
  | .agents.defaults.contextTokens=16384
  | (.agents.defaults.compaction //= {})
  | .agents.defaults.compaction.reserveTokensFloor=1024
  # The privileged service deliberately has no Docker socket access.  Keep the
  # hard systemd/broker boundary instead of granting the gateway docker-group
  # membership (which would be equivalent to host root).
  | .agents.defaults.sandbox.mode="off"
  # Every host exec must enter the approval path.  The OpenClaw default is
  # ask=off, which would allow a model-generated exec call to bypass Discord
  # approval entirely.  The privileged runtime has no sandbox, so pin the
  # execution target to the gateway and fail closed if approval is unavailable.
  | (.tools.exec //= {})
  | .tools.exec.host="gateway"
  | .tools.exec.ask="always"
  | .tools.exec.security="full"
  | (.agents.list //= [])
  | (.agents.list |= map(.sandbox.mode="off"))
  | (.agents.list |= map(
      .workspace=(if (.id == "main" or .id == "orchestrator")
                  then $workspace
                  else ($stateRoot + "/workspaces/" + (.id // "unnamed"))
                  end)
      | if .agentDir then .agentDir=($stateRoot + "/agents/" + (.id // "unnamed") + "/agent") else . end
      | if .id == "approval-runner" then
          (.tools //= {})
          | (.tools.deny //= [])
          | .tools.deny=((.tools.deny + ["tool_search", "tool_describe", "tool_call"]) | unique)
        else . end
    ))
  | (.skills //= {})
  | (.skills.limits //= {})
  | .skills.limits.maxSkillsInPrompt=4
  | .skills.limits.maxSkillsPromptChars=2500
  | (.channels.discord.execApprovals //= {})
  | (.channels.discord.execApprovals.agentFilter //= [])
  | .channels.discord.execApprovals.agentFilter=((.channels.discord.execApprovals.agentFilter + ["approval-runner"]) | unique)
  | (.approvals.plugin.targets //= [])
  | (.approvals.plugin.targets |= map(
      if (.channel == "discord" and (.accountId // "") == "")
      then .accountId="default"
      else .
      end
    ))
  | (.models.providers.ollama.models //= [])
  | (.models.providers.ollama.models |= map(
      if .id == "qwen3.5:9b" then .maxTokens=2048 else . end
    ))
  | .gateway.mode=(.gateway.mode // "local")
  | if .secrets.providers.gateway_secrets.path then .secrets.providers.gateway_secrets.path=($configRoot + "/gateway-secrets.json") else . end
  | .plugins.load.paths=(.plugins.load.paths // [] | map(if test("/plugins/") then ($pluginRoot + "/plugins/" + (split("/plugins/")[1])) else . end))
' "$source_config" > "$output_config.tmp"
jq empty "$output_config.tmp" >/dev/null || { printf '%s\n' 'CONFIG_RENDER_BLOCKED: output invalid' >&2; exit 2; }
# Lobster is bundled with the pinned official runtime. Register it explicitly
# so approval-runner can resolve the real tool instead of stopping after
# tool_search/tool_describe.
if [[ -d "$lobster_path" && -f "$lobster_path/index.js" ]]; then
  jq --arg path "$lobster_path" '
    (.plugins.entries //= {})
    | .plugins.entries.lobster={enabled:true}
    | (.plugins.allow //= [])
    | .plugins.allow=((.plugins.allow + ["lobster"]) | unique)
  ' "$output_config.tmp" > "$output_config.with-lobster"
  mv -- "$output_config.with-lobster" "$output_config.tmp"
fi
# Never ship a configuration that points at a plugin absent from the sanitized
# runtime. This removes private-only plugins while retaining packaged ones.
existing_paths='[]'
while IFS= read -r plugin_path; do
  [[ -n "$plugin_path" && -e "$plugin_path" ]] || continue
  existing_paths="$(jq -c --arg path "$plugin_path" '. + [$path]' <<<"$existing_paths")"
done < <(jq -r '.plugins.load.paths[]?' "$output_config.tmp")
loaded_plugin_ids='[]'
while IFS= read -r plugin_path; do
  [[ -n "$plugin_path" ]] || continue
  plugin_id=''
  if [[ -f "$plugin_path/openclaw.plugin.json" ]]; then
    plugin_id="$(jq -r '.id // .name // empty' "$plugin_path/openclaw.plugin.json" 2>/dev/null || true)"
  fi
  [[ -n "$plugin_id" ]] || plugin_id="$(basename "$plugin_path")"
  loaded_plugin_ids="$(jq -c --arg id "$plugin_id" '. + [$id] | unique' <<<"$loaded_plugin_ids")"
done < <(jq -r '.[]' <<<"$existing_paths")
# Keep built-in/explicitly packaged plugins, but remove entries and allow-list
# names whose private plugin directories were removed from the public package.
# Otherwise the Gateway starts with misleading stale-plugin warnings and may
# silently run a different capability surface than the rendered config implies.
jq --argjson paths "$existing_paths" --argjson loaded "$loaded_plugin_ids" '
  .plugins.load.paths=$paths
  | (.plugins.entries //= {})
  | (.plugins.entries |= with_entries(. as $entry | select(([
      "browser", "discord", "duckduckgo", "document-extract", "llm-task", "lobster",
      "ollama", "policy", "web-readability", "workboard"
    ] + $loaded) | index($entry.key) != null)))
  | (.plugins.allow //= [])
  | (.plugins.allow |= (map(. as $id | select(([
      "browser", "discord", "duckduckgo", "document-extract", "llm-task", "lobster",
      "ollama", "policy", "web-readability", "workboard"
    ] + $loaded) | index($id) != null)) | unique))
  | if (.tools.web.search.provider? == "searxng" and ($loaded | index("searxng") == null))
    then .tools.web.search.provider="duckduckgo"
    else .
    end
' "$output_config.tmp" > "$output_config.filtered"
mv -- "$output_config.filtered" "$output_config.tmp"
jq empty "$output_config.tmp" >/dev/null || { printf '%s\n' 'CONFIG_RENDER_BLOCKED: output invalid' >&2; exit 2; }
mv -- "$output_config.tmp" "$output_config"
printf '%s\n' 'GATEWAY_CONFIG_RENDER_PASS'
