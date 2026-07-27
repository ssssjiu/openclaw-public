# OpenClaw Public Safety Gate

Portable, fail-closed approval and mutation-gate components for an OpenClaw
deployment.

This repository contains deployment helpers and safety contracts. It does not
contain Discord tokens, Gateway secrets, personal IDs, private workspace data,
or a complete OpenClaw runtime.

## What it provides

- Discord-backed one-time approval integration through the Gateway
- Capability-bound mutation checks
- A broker boundary for approved actions
- Runtime and package integrity checks
- A sanitized public-package builder and installer
- Delivery evidence and an independent evidence-ledger verifier
- Systemd examples for the Gateway and approval broker

The installer never enables or starts services automatically.

## Requirements

- Linux with `systemd`, `bash`, `jq`, `git`, and Python 3
- A complete official OpenClaw runtime bundle containing `package.json` and
  `dist/index.js`
- An OpenClaw configuration generated for the installing user
- A Discord bot token
- The Discord user ID that is allowed to approve actions
- A Gateway secret JSON file managed outside Git
- Service accounts named `openclaw-gateway` and `openclaw-broker`

The official OpenClaw project is available at
<https://github.com/openclaw/openclaw>.

## Install

Clone this repository and run the installer as root:

```bash
git clone https://github.com/ssssjiu/openclaw-public
cd openclaw-public

sudo bash deployment/install-public-package.sh \
  /path/to/openclaw-runtime \
  /path/to/openclaw.json \
  discord:<YOUR_DISCORD_USER_ID> \
  /path/to/gateway-secrets.json
```

The installer asks for the Discord bot token with hidden input. For protected
non-interactive automation, `DISCORD_BOT_TOKEN` may be supplied through the
process environment; do not place it in the command line or repository.

The installer writes secrets only to:

- `/etc/openclaw/discord.env` with mode `600`
- `/etc/openclaw/gateway-secrets.json` with mode `600`

The package also records one-time Discord delivery evidence and requires an
independent evidence ledger before a scoped mutation can be reported as
complete. Missing, stale, contradictory, or unverifiable evidence fails
closed.

It installs the sanitized workspace under `/opt/openclaw-workspace` and the
runtime under `/opt/openclaw-runtime`.

## Validate before starting

```bash
sudo jq empty /etc/openclaw/openclaw.json
sudo jq empty /etc/openclaw/runtime.json
sudo systemd-analyze verify \
  /etc/systemd/system/openclaw-broker.service \
  /etc/systemd/system/openclaw-gateway.service
```

Follow the complete host checklist in
[`deployment/HOST-ACTIVATION-RUNBOOK.md`](deployment/HOST-ACTIVATION-RUNBOOK.md).
The final service start is intentionally an administrator decision.

## Security boundary

The public package is not a general-purpose unattended executor. Host
execution is pinned to the Gateway, requires approval, and fails closed when
the approval broker, runtime configuration, capability, or evidence is absent.
Only temporary, explicitly scoped mutations should be used in demonstrations.

Never commit:

- Discord tokens
- Gateway secrets
- Personal Discord IDs in deployment defaults
- `.env` files or private runtime configurations
- Private approval fixtures or live evidence

## Development checks

From a checkout, run:

```bash
bash verification/test-public-package-clean-room.sh
bash verification/public-release-preflight.sh
bash verification/check-installed-hardening.sh
```

To build a sanitized package outside the checkout:

```bash
bash distribution/build-public-package.sh /tmp/openclaw-public-package
```
