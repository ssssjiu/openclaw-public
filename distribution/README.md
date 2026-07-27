# OpenClaw safety gate distribution

This package contains the generic approval-boundary core. It does not contain
personal workspace paths, Discord identities, credentials, fixtures, or private
workflow definitions. Copy `config/runtime.example.json` to a local runtime
configuration and replace every placeholder before activation.

The package is fail-closed until a separately managed Gateway issues a one-time
capability through the broker boundary. It does not install, restart, push, or
deploy anything by itself.

## Public installation

The package is portable, but it cannot contain a Discord bot token, Gateway
secret, or a user's Discord ID. A recipient needs a complete official OpenClaw
runtime bundle, an OpenClaw source config produced by their own onboarding, and
their own Discord approver ID.

From the generated package directory, an administrator can install the files
without starting services:

```bash
sudo bash deployment/install-public-package.sh \
  /path/to/openclaw-runtime \
  /path/to/the-user-openclaw.json \
  discord:<THEIR_DISCORD_USER_ID> \
  /path/to/their-gateway-secrets.json
```

The installer asks once for the Discord bot token with hidden input, writes it
to `/etc/openclaw/discord.env` with mode `600`, and installs the supplied
Gateway secret JSON with mode `600`. For non-interactive automation, set
`DISCORD_BOT_TOKEN` only in the protected execution environment; do not put it
in the command line or GitHub repository. Services are deliberately not
enabled or started by the installer.

The installer rejects a non-generated package, private repository metadata,
credential-like files, incomplete runtimes, and unsafe ownership/layouts. This
keeps the GitHub artifact reusable without publishing your identity or secrets.
