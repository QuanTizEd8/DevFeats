#!/usr/bin/env python3
"""Symlink Copilot workspaceStorage entries to .ai/copilot/ in the workspace.

VS Code keys workspaceStorage by an MD5 hash of the workspace URI. The URI differs between
the container (vscode-remote://dev-container+...) and the host (file://...), so the hashes
differ. This script computes both hashes, then symlinks all Copilot-related workspaceStorage
entries to <workspace>/.ai/copilot/ so that chat history lives in the project directory and
travels with it on backup or move.

Managed entries (each becomes a subdirectory under .ai/copilot/):
  chatSessions/          full message history for each Copilot chat
  chatEditingSessions/   inline edit session history
  GitHub.copilot-chat/   extension-private folder (workspace index, transcripts, debug logs)

Usage: link-copilot-storage.py <host_workspace> <container_workspace> <config_file>
"""

import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

VSCODE_SERVER_STORAGE = Path.home() / ".vscode-server/data/User/workspaceStorage"

MANAGED_ENTRIES = ["chatSessions", "chatEditingSessions", "GitHub.copilot-chat"]

# Items that lived directly in .ai/copilot/ before the chatSessions restructure.
# If found there, they are migrated into .ai/copilot/GitHub.copilot-chat/.
_LEGACY_FLAT_ITEMS = ["debug-logs", "transcripts", "workspace-chunks.db"]

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
    return None


def _migrate_dir_contents(src: Path, dst: Path) -> None:
    """Move items from src into dst (no-clobber), then remove src."""
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        dest = dst / item.name
        if not dest.exists():
            shutil.move(str(item), str(dest))
    shutil.rmtree(src)


def link_entry(entry_name: str,
               host_hash_dir: Path, container_hash_dir: Path,
               project_dir_container: Path, project_dir_host: Path) -> None:
    """Migrate and symlink one workspaceStorage entry for both host and container."""
    project_dir_container.mkdir(parents=True, exist_ok=True)

    host_entry = host_hash_dir / entry_name
    container_entry = container_hash_dir / entry_name

    # Migrate existing host-side real directory into project dir.
    if host_entry.is_dir() and not host_entry.is_symlink():
        _migrate_dir_contents(host_entry, project_dir_container)
    elif host_entry.is_symlink():
        host_entry.unlink()

    host_entry.parent.mkdir(parents=True, exist_ok=True)
    host_entry.symlink_to(project_dir_host)

    # Migrate existing container-side real directory into project dir.
    if container_entry.is_dir() and not container_entry.is_symlink():
        _migrate_dir_contents(container_entry, project_dir_container)
    elif container_entry.is_symlink():
        container_entry.unlink()

    container_entry.parent.mkdir(parents=True, exist_ok=True)
    container_entry.symlink_to(project_dir_container)

    print(f"Linked {container_entry} -> {project_dir_container}")
    print(f"Linked {host_entry} -> {project_dir_host}")


def link_copilot_storage(host_path: str, container_path: str, config_file: str) -> int:
    local_docker = detect_local_docker(container_path)
    container_hash = find_container_hash(host_path, container_path, config_file, local_docker)

    host_storage = find_host_storage()
    if not host_storage:
        print("Copilot history sync skipped: host VS Code storage not found at any expected "
              "mount point (are the workspaceStorage bind mounts active?)")
        return 0

    host_hash = find_host_hash(host_storage, host_path)
    if not host_hash:
        print(f"Copilot history sync skipped: no workspace.json found for {host_path} "
              "(open the project in VS Code on the host first)")
        return 0

    ai_copilot = Path(container_path) / ".ai" / "copilot"
    host_hash_dir = host_storage / host_hash
    container_hash_dir = VSCODE_SERVER_STORAGE / container_hash

    # Migrate legacy flat layout: contents that used to live directly in .ai/copilot/
    # now belong in .ai/copilot/GitHub.copilot-chat/.
    if any((ai_copilot / item).exists() for item in _LEGACY_FLAT_ITEMS):
        gh_dir = ai_copilot / "GitHub.copilot-chat"
        gh_dir.mkdir(parents=True, exist_ok=True)
        for item_name in _LEGACY_FLAT_ITEMS:
            src = ai_copilot / item_name
            if src.exists() and not (gh_dir / item_name).exists():
                shutil.move(str(src), str(gh_dir / item_name))

    for entry_name in MANAGED_ENTRIES:
        link_entry(
            entry_name,
            host_hash_dir,
            container_hash_dir,
            ai_copilot / entry_name,
            Path(host_path) / ".ai" / "copilot" / entry_name,
        )

    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <host_workspace> <container_workspace> <config_file>",
              file=sys.stderr)
        sys.exit(1)
    sys.exit(link_copilot_storage(sys.argv[1], sys.argv[2], sys.argv[3]))
