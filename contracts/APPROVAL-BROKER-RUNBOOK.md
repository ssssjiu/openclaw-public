# Approval broker runtime contract

This is the boundary between authenticated Discord approval and local mutation.
Until the Gateway/plugin implements it, the workflow remains fail-closed.

## Required sequence

1. Request `plugin.approval.request` with bounded flow, revision, target hash,
   criteria hash, and operation.
2. Wait for `plugin.approval.waitDecision`.
3. Accept only `allow-once` whose `resolvedBy` is the configured Discord
   approver. Missing or mismatched identity is a denial.
4. The Gateway bridge (never the model or worker) creates a request packet and
   invokes `approval-broker.sh issue` with `OPENCLAW_APPROVAL_BROKER_ISSUER=gateway`.
5. Only the one authorized child receives `OPENCLAW_APPROVAL_GATE=GATEWAY_VERIFIED`,
   `OPENCLAW_APPROVAL_FLOW_ID`, and `OPENCLAW_APPROVAL_CAPABILITY_FILE`.
6. The mutation entrypoint verifies all bindings and consumes the one-time
   capability before the side effect. Reuse, expiry, target/evidence changes,
   and missing approval fail closed.

## Host boundary

The capability root must be writable only by the Gateway broker identity and
readable only by the one-shot mutation child. A same-user shell can forge an
environment variable or file, so this repository contract is not a cryptographic
privilege boundary. Production activation requires a separate OS user or an
equivalent isolated Gateway service. Until then, no mutation is authorized.

## Upgrade requirement

The installed Lobster plugin currently returns approval identity and resumes the
workflow, but does not issue this repository capability. Do not patch the
installed package directly; upgrades replace it. Implement the durable change in
the plugin source/build or a supported Gateway hook, then run the approval bridge
upgrade regression suite.

## Forbidden shortcuts

- Never set `OPENCLAW_APPROVAL_GATE` manually.
- Never set the broker issuer from a worker or shell.
- Never use `git commit --no-verify`.
- Never resume without a fresh capability bound to the flow and run.
