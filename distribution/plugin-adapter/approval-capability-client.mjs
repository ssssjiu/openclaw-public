import net from "node:net";

const SAFE_OPERATIONS = new Set([
  "git-commit",
  "git-push",
  "pull-request",
  "l3-demo",
  "repository-file-change",
  "taskflow-resume",
]);

function requireCapabilityBasename(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9._-]+\.json$/.test(value)) {
    throw new Error("capabilityFile must be a safe JSON basename");
  }
  return value;
}

function request(socketPath, payload, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let buffer = "";
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error("approval broker request timed out"));
    }, timeoutMs);
    socket.setEncoding("utf8");
    socket.on("connect", () => socket.end(`${JSON.stringify(payload)}\n`));
    socket.on("data", (chunk) => {
      buffer += chunk;
      const lineEnd = buffer.indexOf("\n");
      if (lineEnd < 0) return;
      clearTimeout(timer);
      socket.destroy();
      const response = JSON.parse(buffer.slice(0, lineEnd));
      if (!response.ok) reject(new Error(response.error || "approval broker rejected request"));
      else resolve(response);
    });
    socket.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

export async function issueApprovalCapability({ socketPath, capabilityFile, operation, runDir, request: approvalRequest }) {
  if (!SAFE_OPERATIONS.has(operation)) throw new Error("unsupported approval operation");
  if (!socketPath || !capabilityFile || !runDir || !approvalRequest) throw new Error("approval capability request is incomplete");
  capabilityFile = requireCapabilityBasename(capabilityFile);
  if (approvalRequest.operation !== operation || approvalRequest.runDir !== runDir) throw new Error("approval capability binding mismatch");
  return request(socketPath, { action: "issue", capabilityFile, operation, runDir, request: approvalRequest });
}

export async function consumeApprovalCapability({ socketPath, capabilityFile, operation, runDir }) {
  if (!SAFE_OPERATIONS.has(operation)) throw new Error("unsupported approval operation");
  return request(socketPath, { action: "consume", capabilityFile: requireCapabilityBasename(capabilityFile), operation, runDir });
}
