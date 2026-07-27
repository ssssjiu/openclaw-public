import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { lstatSync, readFileSync, realpathSync } from "node:fs";
import { join } from "node:path";

const GRAPH_MARKER = /(?:agent-graph|agent-orchestrator|orchestrator-graph|graphId\s*[:=])/i;
const WORKSPACE_ROOT = process.env.OPENCLAW_WORKSPACE_ROOT || "/opt/openclaw-workspace";
const REGISTRY_PATH = process.env.OPENCLAW_GRAPH_REGISTRY_PATH || join(WORKSPACE_ROOT, "loops/graph-registry.json");

function registryAllows(sessionKey) {
  try {
    if (lstatSync(REGISTRY_PATH).isSymbolicLink()) return false;
    const real = realpathSync(REGISTRY_PATH);
    if (real !== REGISTRY_PATH) return false;
    const state = JSON.parse(readFileSync(REGISTRY_PATH, "utf8"));
    const now = Math.floor(Date.now() / 1000);
    return Object.values(state.graphs ?? {}).some((record) =>
      record?.status === "ACTIVE" &&
      Number(record.expiresAt) > now &&
      Array.isArray(record.sessionPrefixes) &&
      record.sessionPrefixes.some((prefix) => typeof prefix === "string" && sessionKey.startsWith(prefix)) &&
      typeof record.graphId === "string" &&
      GRAPH_MARKER.test(record.graphId));
  } catch {
    return false;
  }
}

export default definePluginEntry({
  id: "agent-graph-policy",
  name: "Agent Graph Policy",
  description: "Requires graph context for subagent runs.",
  register(api) {
    api.on("before_agent_run", async (_event, ctx) => {
      if (ctx?.trigger !== "subagent") return { outcome: "pass" };
      const sessionKey = typeof ctx.sessionKey === "string" ? ctx.sessionKey : "";
      if (GRAPH_MARKER.test(sessionKey) && registryAllows(sessionKey)) return { outcome: "pass" };
      return {
        outcome: "block",
        reason: "subagent execution requires an orchestrator graph context",
        message: "BLOCKED_GRAPH_REQUIRED: subagent execution requires an active graph registry binding.",
        category: "orchestration"
      };
    }, { priority: 100 });
  }
});
