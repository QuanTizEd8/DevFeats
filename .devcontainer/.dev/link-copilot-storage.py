#!/usr/bin/env python3
"""Symlink both the container's and host's Copilot chat storage to .ai/copilot/ in the workspace.

VS Code keys workspaceStorage by an MD5 hash of the workspace URI. The URI differs between
the container (vscode-remote://dev-container+...) and the host (file://...), so the hashes
differ. This script detects the runtime environment, computes both hashes, then symlinks both
workspaceStorage/GitHub.copilot-chat entries to <workspace>/.ai/copilot/ so that chat history
lives in the project directory and travels with it on backup or move.

Usage: link-copilot-storage.py <host_workspace> <container_workspace> <config_file>
"""

import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

VSCODE_SERVER_STORAGE = Path.home() / ".vscode-server/data/User/workspaceStorage"

# Both candidates are always mounted; whichever has workspace.json files is the active one.
HOST_STORAGE_CANDIDATES = [
    Path("/host-vscode-workspacestorage"),        # macOS: ~/Library/Application Support/Code
    Path("/host-vscode-workspacestorage-linux"),   # Linux: ~/.config/Code
]

# Tried in order; first whose computed hash matches an existing workspaceStorage dir wins.
DOCKER_CONTEXT_CANDIDATES: list[str | None] = [
    os.environ.get("DOCKER_CONTEXT"),  # user override via containerEnv, may be None
    "desktop-linux",                    # Docker Desktop (macOS and Linux)
    "default",                          # native Docker
]


def detect_local_docker(container_workspace: str) -> bool:
    """Returns True when running on native Linux Docker (no VM), False for Docker Desktop.

    Docker Desktop mounts the workspace via virtiofs/fakeowner (a VM passthrough layer).
    Native Linux Docker uses a host filesystem type like ext4 or overlay.
    """
    try:
        with open("/proc/1/mountinfo") as f:
            for line in f:
                parts = line.split()
                if len(parts) > 4 and parts[4] == container_workspace:
                    sep = parts.index("-") if "-" in parts else -1
                    if sep >= 0 and sep + 1 < len(parts):
                        return parts[sep + 1] not in ("fakeowner", "virtiofs")
    except OSError:
        pass
    return False


def compute_hash(host_path: str, container_path: str, config_file: str,
                 local_docker: bool, context: str | None) -> str:
    obj: dict = {"hostPath": host_path, "localDocker": local_docker}
    if context is not None:
        obj["settings"] = {"context": context}
    obj["configFile"] = {"$mid": 1, "fsPath": config_file, "path": config_file, "scheme": "file"}
    json_str = json.dumps(obj, separators=(",", ":"))
    uri = f"vscode-remote://dev-container%2B{json_str.encode().hex()}{container_path}"
    return hashlib.md5(uri.encode()).hexdigest()


def find_container_hash(host_path: str, container_path: str, config_file: str,
                        local_docker: bool) -> str:
    """Try common Docker contexts and return whichever hash has an existing workspaceStorage dir."""
    if local_docker:
        # Native Docker has no Docker Desktop context; settings field is absent from the URI.
        contexts: list[str | None] = [None, "default"]
    else:
        contexts = [c for c in DOCKER_CONTEXT_CANDIDATES if c is not None]

    for context in contexts:
        h = compute_hash(host_path, container_path, config_file, local_docker, context)
        if (VSCODE_SERVER_STORAGE / h).exists():
            return h

    # No existing dir found yet (first run); fall back to first candidate.
    return compute_hash(host_path, container_path, config_file, local_docker, contexts[0])


def find_host_storage() -> Path | None:
    for candidate in HOST_STORAGE_CANDIDATES:
        if candidate.exists() and any(candidate.glob("*/workspace.json")):
            return candidate
    return None


def find_host_hash(host_storage: Path, host_workspace: str) -> str | None:
    folder_uri = f"file://{host_workspace}"
    for workspace_json in host_storage.glob("*/workspace.json"):
        try:
            data = json.loads(workspace_json.read_text())
            if data.get("folder") == folder_uri:
                return workspace_json.parent.name
        except Exception:
            continue
    print(f"No workspace.json found matching {folder_uri}", file=sys.stderr)
    return None


def link_copilot_storage(host_path: str, container_path: str, config_file: str) -> int:
    local_docker = detect_local_docker(container_path)
    container_hash = find_container_hash(host_path, container_path, config_file, local_docker)

    host_storage = find_host_storage()
    if not host_storage:
        print("Host VS Code storage not found at any expected mount point", file=sys.stderr)
        return 1

    host_hash = find_host_hash(host_storage, host_path)
    if not host_hash:
        return 1

    # Project-local storage: both symlinks point here using their respective absolute paths.
    # The two paths resolve to the same physical directory via the workspace bind mount.
    project_chat_container = Path(container_path) / ".ai" / "copilot"
    project_chat_host = Path(host_path) / ".ai" / "copilot"
    project_chat_container.mkdir(parents=True, exist_ok=True)

    container_chat = VSCODE_SERVER_STORAGE / container_hash / "GitHub.copilot-chat"
    host_chat = host_storage / host_hash / "GitHub.copilot-chat"

    # Migrate existing host-side data into the project dir before symlinking.
    if host_chat.is_dir() and not host_chat.is_symlink():
        for item in host_chat.iterdir():
            dest = project_chat_container / item.name
            if not dest.exists():
                shutil.move(str(item), str(dest))
        shutil.rmtree(host_chat)
    elif host_chat.is_symlink():
        host_chat.unlink()

    # Symlink host-side workspaceStorage → project dir (host-valid absolute path).
    host_chat.parent.mkdir(parents=True, exist_ok=True)
    host_chat.symlink_to(project_chat_host)

    # Symlink container-side workspaceStorage → project dir.
    container_chat.parent.mkdir(parents=True, exist_ok=True)
    if container_chat.is_symlink():
        container_chat.unlink()
    elif container_chat.is_dir() and any(container_chat.iterdir()):
        for item in container_chat.iterdir():
            dest = project_chat_container / item.name
            if not dest.exists():
                shutil.move(str(item), str(dest))
        shutil.rmtree(container_chat)
    elif container_chat.is_dir():
        container_chat.rmdir()

    container_chat.symlink_to(project_chat_container)
    print(f"Linked {container_chat} -> {project_chat_container}")
    print(f"Linked {host_chat} -> {project_chat_host}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <host_workspace> <container_workspace> <config_file>",
              file=sys.stderr)
        sys.exit(1)
    sys.exit(link_copilot_storage(sys.argv[1], sys.argv[2], sys.argv[3]))
