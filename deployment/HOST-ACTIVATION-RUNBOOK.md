# Host activation runbook

This is the final host-side sequence. It must be performed by an administrator
after reviewing the rendered config. It does not copy Discord credentials into
the repository.

1. Record the existing user Gateway health, but do not run it concurrently with
   the production system Gateway on the same port. It must be stopped only
   during the final switch, after the isolated system-service test passes.
2. Build the sanitized workspace package with
   `distribution/build-public-package.sh` and install that package under `/opt`
   using the privileged installer. Never pass the Git checkout as the workspace
   source.
   The runtime source must contain the complete official OpenClaw `dist` tree,
   including every file imported by `dist/extensions/lobster/index.js`, plus
   the official `@clawdbot/lobster` package in the runtime's node_modules. The
   rendered config enables Lobster as a bundled plugin; do not replace it with
   a copied standalone plugin, because Gateway API requests require bundled or
   trusted-official provenance.
3. Copy the existing OpenClaw config to `/etc/openclaw/openclaw.json` through
   `render-gateway-config.sh`, changing only workspace and plugin load paths.
   The plugin root must be `/opt/openclaw-workspace` because packaged plugins
   are installed below that immutable workspace tree; `/opt/openclaw-runtime`
   is reserved for the complete OpenClaw executable runtime.
   The privileged gateway is intentionally not granted access to
   `/var/run/docker.sock` or the `docker` group. The rendered config disables
   Docker-backed agent sandboxing; isolation is provided by the dedicated
   service account, systemd restrictions, read-only package tree, and approval
   broker. Do not fix this by adding `openclaw-gateway` to `docker`.
   Non-main agent workspaces are rendered below
   `/var/lib/openclaw-gateway/workspaces`, separate from the immutable public
   package, so the approval runner has writable state without making the
   package writable.
   The rendered isolated-service config must set `gateway.mode=local`.
4. Copy the existing Discord env file to `/etc/openclaw/discord.env` with mode
   `600`, owner `openclaw-gateway:openclaw-gateway`. Install the rendered JSON
   config as `root:openclaw-gateway` with mode `640` so the service can read it.
   Copy the configured Gateway secret file to
   `/etc/openclaw/gateway-secrets.json` with mode `600`, owner
   `openclaw-gateway:openclaw-gateway`; never copy it into the public package.
5. Install the broker and Gateway system units. Do not enable or start them yet.
6. Run `systemd-analyze verify` on both units and validate the rendered config.
7. Start the broker, then start the isolated Gateway test instance. Confirm the
   Gateway unit runs as `openclaw-gateway`, contains
   `OPENCLAW_BROKER_SOCKET=/run/openclaw-broker/broker.sock`, and can access the
   broker socket through the `openclaw-gateway` group. A user-level Gateway is
   not an acceptable substitute for this check.
8. Run private Discord approval E2E and a single temporary-file mutation.
9. Only after all checks pass, stop the old user Gateway and switch the new
   service to the production port. Keep the old unit available for rollback.
   Never leave both Gateways active on the same port.

Rollback is the reverse order: stop the new system service, restore the old user
service, and leave all capability files expired or consumed.
