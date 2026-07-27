import { consumeApprovalCapability, issueApprovalCapability } from "./approval-capability-client.mjs";

const IDENTITY_RE = /^(?:discord:\d+|(?!discord:)[A-Za-z0-9_.:-]{1,128})$/;

function requiredString(value, name) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} is required`);
  return value.trim();
}

function normalizeIdentity(value) {
  const raw = requiredString(value, "approval identity");
  const labeled = raw.match(/^Chat approval \((discord:\d+)\)$/i);
  const identity = labeled ? labeled[1] : raw;
  if (!IDENTITY_RE.test(identity)) throw new Error("approval identity format is invalid");
  return identity;
}

function trustedNumber(value, name) {
  if (!Number.isFinite(value) || !Number.isInteger(value) || value < 0) throw new Error(`${name} is invalid`);
  return value;
}

/**
 * Called only by the plugin after Gateway approval waitDecision returns.
 * No workflow/model supplied identity, issuer, gate, or capability path is accepted.
 */
export async function issuePluginApprovalCapability({
  socketPath,
  capabilityFile,
  operation,
  runDir,
  flowId,
  revision,
  approvalId,
  targetHash,
  criteriaHash,
  workflowHash,
  evidenceHash,
  approver,
  resolvedBy,
  createdAtMs,
  expiresAtMs,
}) {
  const identity = normalizeIdentity(resolvedBy);
  if (approver !== undefined && normalizeIdentity(approver) !== identity) {
    throw new Error("Gateway approval identity mismatch");
  }
  const request = {
    operation: requiredString(operation, "operation"),
    runDir: requiredString(runDir, "runDir"),
    flowId: requiredString(flowId, "flowId"),
    revision: trustedNumber(revision, "revision"),
    approvalId: requiredString(approvalId, "approvalId"),
    approver: identity,
    targetHash: requiredString(targetHash, "targetHash"),
    criteriaHash: requiredString(criteriaHash, "criteriaHash"),
    workflowHash: requiredString(workflowHash, "workflowHash"),
    evidenceHash: requiredString(evidenceHash, "evidenceHash"),
  };
  if (!/^[a-f0-9]{64}$/.test(request.targetHash)) throw new Error("targetHash is invalid");
  for (const [name, value] of [["criteriaHash", request.criteriaHash], ["workflowHash", request.workflowHash], ["evidenceHash", request.evidenceHash]]) {
    if (!/^[a-f0-9]{64}$/.test(value)) throw new Error(`${name} is invalid`);
  }
  if (createdAtMs !== undefined) trustedNumber(createdAtMs, "createdAtMs");
  if (expiresAtMs !== undefined) trustedNumber(expiresAtMs, "expiresAtMs");
  return issueApprovalCapability({ socketPath, capabilityFile, operation: request.operation, runDir: request.runDir, request });
}

export async function consumePluginApprovalCapability({ socketPath, capabilityFile, operation, runDir }) {
  return consumeApprovalCapability({
    socketPath,
    capabilityFile: requiredString(capabilityFile, "capabilityFile"),
    operation: requiredString(operation, "operation"),
    runDir: requiredString(runDir, "runDir"),
  });
}
