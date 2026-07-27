#!/usr/bin/env python3
"""Minimal newline-delimited JSON Unix-socket front end for approval-broker.sh."""
from __future__ import annotations

import argparse
import json
import os
import secrets
import socket
import subprocess
import tempfile
from pathlib import Path

OPS = {"git-commit", "git-push", "pull-request", "l3-demo", "repository-file-change", "taskflow-resume"}


def reply(conn: socket.socket, value: dict) -> None:
    conn.sendall((json.dumps(value, separators=(",", ":")) + "\n").encode())


def run_broker(script: Path, root: Path, args: list[str], issuer: bool = False) -> str:
    env = os.environ.copy()
    env["OPENCLAW_APPROVAL_CAPABILITY_ROOT"] = str(root)
    if issuer:
        env["OPENCLAW_APPROVAL_BROKER_ISSUER"] = "gateway"
    result = subprocess.run(["/bin/bash", str(script), *args], text=True, capture_output=True, env=env, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "broker rejected request")
    return result.stdout.strip()


def handle(message: dict, script: Path, root: Path) -> dict:
    action = message.get("action")
    operation = message.get("operation")
    if operation not in OPS:
        raise ValueError("unsupported operation")
    capability_name = str(message.get("capabilityFile", ""))
    if Path(capability_name).name != capability_name or not capability_name.endswith(".json"):
        raise ValueError("capabilityFile must be a safe JSON basename")
    capability = root / capability_name
    run_dir = str(message.get("runDir", ""))
    if not run_dir.startswith("/"):
        raise ValueError("runDir must be absolute")
    if action == "issue":
        request = message.get("request")
        if not isinstance(request, dict):
            raise ValueError("issue request must be an object")
        if request.get("operation") != operation or request.get("runDir") != run_dir:
            raise ValueError("request binding mismatch")
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", dir=root, prefix="request.", suffix=".json", delete=True) as fh:
            json.dump(request, fh, separators=(",", ":"))
            fh.flush()
            output = run_broker(script, root, ["issue", str(capability), fh.name], issuer=True)
        return {"ok": True, "capabilityFile": str(capability), "capability": json.loads(output)}
    if action in {"verify", "consume"}:
        output = run_broker(script, root, [action, str(capability), operation, run_dir])
        return {"ok": True, "result": output}
    raise ValueError("unsupported action")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--capability-root", required=True)
    parser.add_argument("--broker-script", required=True)
    args = parser.parse_args()
    sock_path = Path(args.socket)
    sock_path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    try:
        sock_path.unlink()
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(sock_path))
    os.chmod(sock_path, 0o660)
    server.listen(16)
    try:
        while True:
            conn, _ = server.accept()
            with conn, conn.makefile("r", encoding="utf-8") as stream:
                for line in stream:
                    try:
                        message = json.loads(line)
                        value = handle(message, Path(args.broker_script), Path(args.capability_root))
                    except Exception as exc:  # fail closed at the protocol boundary
                        value = {"ok": False, "error": str(exc)}
                    reply(conn, value)
    finally:
        server.close()
        try:
            sock_path.unlink()
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
