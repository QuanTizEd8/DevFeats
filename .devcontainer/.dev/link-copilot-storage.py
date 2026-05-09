#!/usr/bin/env python3
"""Sync Copilot workspaceStorage entries to .ai/copilot/ in the workspace.

VS Code keys workspaceStorage by an MD5 hash of the workspace URI. The URI
differs between the container (vscode-remote://dev-container+...) and the host
(file://...), so the hashes differ. This script:

  1. Copies chatSessions/ and chatEditingSessions/ bidirectionally between the
     canonical .ai/copilot/ store and both hash directories — VS Code on macOS
     refuses to read session .jsonl files through cross-volume symlinks.
  2. Symlinks GitHub.copilot-chat/ (auxiliary data; symlink is acceptable).
  3. Merges the chat session index from host state.vscdb into the container
     state.vscdb so the container sidebar lists host sessions.

Canonical store: <workspace>/.ai/copilot/{entry}/
Host hash dir:   (bind-mounted host workspaceStorage)/<hash>/
Container hash:  ~/.vscode-server/data/User/workspaceStorage/<hash>/

Usage: link-copilot-storage.py <host_workspace> <container_workspace>
                       <config_file>
"""

import hashlib
import json
import logging
import os
import shutil
import signal
import sqlite3
import sys
import time
from pathlib import Path

_logger = logging.getLogger(__name__)

VSCODE_SERVER_STORAGE = Path.home() / ".vscode-server/data/User/workspaceStorage"

# Synced by copy: VS Code won't follow cross-volume symlinks for session files
COPY_SYNC_ENTRIES = ["chatSessions", "chatEditingSessions"]
# Synced by symlink: auxiliary data, symlink is acceptable
SYMLINK_ENTRIES = ["GitHub.copilot-chat"]

MANAGED_ENTRIES = COPY_SYNC_ENTRIES + SYMLINK_ENTRIES

# state.vscdb keys that enumerate and describe chat sessions.
# agentSessions.model.cache  – sidebar list (titles, providers, icons).
# agentSessions.state.cache  – per-session read timestamps.
# chat.ChatSessionStore.index – full session metadata; VS Code uses this to
#   resolve session content when a session is opened (entries is a dict keyed
#   by sessionId, unlike the list-based agentSessions keys).
CHAT_INDEX_KEYS = [
    "agentSessions.model.cache",
    "agentSessions.state.cache",
    "chat.ChatSessionStore.index",
]

# Items that lived directly in .ai/copilot/ before the chatSessions restructure.
# If found there, they are migrated into .ai/copilot/GitHub.copilot-chat/.
_LEGACY_FLAT_ITEMS = ["debug-logs", "transcripts", "workspace-chunks.db"]

# Both candidates are always mounted; whichever has workspace.json files is the
# active one.
HOST_STORAGE_CANDIDATES = [
    Path("/host-vscode-workspacestorage"),       # macOS: ~/Library/Application Support/Code
    Path("/host-vscode-workspacestorage-linux"),  # Linux: ~/.config/Code
]

# Tried in order; first whose computed hash matches an existing
# workspaceStorage dir wins.
DOCKER_CONTEXT_CANDIDATES: list[str | None] = [
    os.environ.get("DOCKER_CONTEXT"),  # user override via containerEnv, may be None
    "desktop-linux",                   # Docker Desktop (macOS and Linux)
    "default",                         # native Docker
]


def detect_local_docker(container_workspace: str) -> bool:
    """Detect if running on native Linux Docker (no VM) vs Docker Desktop."""
    try:
        with Path("/proc/1/mountinfo").open() as f:
            for line in f:
                parts = line.split()
                if len(parts) > 4 and parts[4] == container_workspace:
                    sep = parts.index("-") if "-" in parts else -1
                    if sep >= 0 and sep + 1 < len(parts):
                        return parts[sep + 1] not in ("fakeowner", "virtiofs")
    except OSError:
        pass
    return False


def compute_hash(
    host_path: str,
    container_path: str,
    config_file: str,
    *,
    local_docker: bool,
    context: str | None,
) -> str:
    """Compute VS Code workspace storage directory hash for a devcontainer."""
    obj: dict = {"hostPath": host_path, "localDocker": local_docker}
    if context is not None:
        obj["settings"] = {"context": context}
    obj["configFile"] = {
        "$mid": 1,
        "fsPath": config_file,
        "path": config_file,
        "scheme": "file",
    }
    json_str = json.dumps(obj, separators=(",", ":"))
    uri = (
        f"vscode-remote://dev-container%2B{json_str.encode().hex()}"
        f"{container_path}"
    )
    # nosec: MD5 is used here for VS Code compatibility, not security
    return hashlib.md5(uri.encode()).hexdigest()  # noqa: S324


def _find_container_hash_by_scan(container_path: str) -> str | None:
    """Find the container workspaceStorage hash by scanning workspace.json files.

    This is more reliable than computing the hash because the URI format used
    by VS Code may differ from what we compute (different Docker context,
    devcontainer config path encoding, etc.).
    """
    if not VSCODE_SERVER_STORAGE.is_dir():
        return None
    for workspace_json in VSCODE_SERVER_STORAGE.glob("*/workspace.json"):
        data = _load_workspace_json(workspace_json)
        if data:
            folder = data.get("folder", "")
            # Container workspace URI: vscode-remote://dev-container+{hex}/{path}
            if "dev-container" in folder and folder.endswith(container_path):
                return workspace_json.parent.name
    return None


def find_container_hash(
    host_path: str, container_path: str, config_file: str, *, local_docker: bool,
) -> str:
    """Find VS Code workspace storage hash for this devcontainer.

    Tries scan-based detection first (most reliable), then falls back to
    computing the hash from the known URI formula.
    """
    # Primary: scan existing workspace.json files — no URI formula needed.
    scanned = _find_container_hash_by_scan(container_path)
    if scanned:
        print(f"  Found container hash by scan: {scanned}")
        return scanned

    # Fallback: compute the hash from the URI formula.
    if local_docker:
        contexts: list[str | None] = [None, "default"]
    else:
        contexts = [c for c in DOCKER_CONTEXT_CANDIDATES if c is not None]

    for context in contexts:
        h = compute_hash(
            host_path, container_path, config_file,
            local_docker=local_docker, context=context,
        )
        if (VSCODE_SERVER_STORAGE / h).exists():
            print(f"  Found container hash by compute (context={context}): {h}")
            return h

    # No existing dir yet (first run); fall back to first candidate.
    h = compute_hash(
        host_path, container_path, config_file,
        local_docker=local_docker, context=contexts[0],
    )
    print(f"  Container hash not found on disk; using computed: {h} (context={contexts[0]})")
    return h


def find_host_storage() -> Path | None:
    """Find the host VS Code workspaceStorage directory."""
    for candidate in HOST_STORAGE_CANDIDATES:
        if candidate.exists() and any(candidate.glob("*/workspace.json")):
            return candidate
    return None


def _load_workspace_json(workspace_json: Path) -> dict | None:
    try:
        return json.loads(workspace_json.read_text())
    except (json.JSONDecodeError, OSError) as e:
        _logger.debug("Failed to read %s: %s", workspace_json, e)
        return None


def find_host_hash(host_storage: Path, host_workspace: str) -> str | None:
    """Find the host VS Code workspace storage hash for the workspace."""
    folder_uri = f"file://{host_workspace}"
    for workspace_json in host_storage.glob("*/workspace.json"):
        data = _load_workspace_json(workspace_json)
        if data and data.get("folder") == folder_uri:
            return workspace_json.parent.name
    return None


def _migrate_dir_contents(src: Path, dst: Path) -> None:
    """Move items from src into dst (no-clobber), then remove src."""
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        dest = dst / item.name
        if not dest.exists():
            shutil.move(str(item), str(dest))
    shutil.rmtree(src)


def _ensure_real_dir(path: Path) -> None:
    """Replace a symlink (broken or live) with a real directory."""
    if path.is_symlink():
        print(f"  Replacing symlink with real directory: {path}")
        path.unlink()
    path.mkdir(parents=True, exist_ok=True)


def _copy_new_files(src: Path, dst: Path) -> int:
    """Copy files from src to dst; also replace dst file if src is larger.

    Returns number of files written.
    """
    if not src.is_dir():
        return 0
    dst.mkdir(parents=True, exist_ok=True)
    count = 0
    for item in src.iterdir():
        if item.is_file():
            dest = dst / item.name
            if not dest.exists() or item.stat().st_size > dest.stat().st_size:
                shutil.copy2(str(item), str(dest))
                count += 1
    return count


def sync_copy_entry(
    entry_name: str,
    host_hash_dir: Path,
    container_hash_dir: Path,
    canonical_dir: Path,
) -> None:
    """Bidirectional copy-sync for a workspaceStorage entry.

    .ai/copilot/{entry}/ is the canonical persistent store. On each container
    start we pull new/larger files from both hash dirs into canonical, then push
    all canonical files back to both hash dirs so both sides are in sync.
    """
    # Convert any stale symlinks to real directories first.
    _ensure_real_dir(host_hash_dir / entry_name)
    _ensure_real_dir(container_hash_dir / entry_name)
    canonical_dir.mkdir(parents=True, exist_ok=True)

    # Pull: consolidate from both hash dirs into canonical.
    n_from_host = _copy_new_files(host_hash_dir / entry_name, canonical_dir)
    n_from_container = _copy_new_files(container_hash_dir / entry_name, canonical_dir)

    # Push: distribute from canonical to both hash dirs.
    n_to_host = _copy_new_files(canonical_dir, host_hash_dir / entry_name)
    n_to_container = _copy_new_files(canonical_dir, container_hash_dir / entry_name)

    print(
        f"Synced {entry_name}: "
        f"pulled {n_from_host} from host, {n_from_container} from container; "
        f"pushed {n_to_host} to host, {n_to_container} to container"
    )


def link_symlink_entry(
    entry_name: str,
    host_hash_dir: Path,
    container_hash_dir: Path,
    project_dir_container: Path,
    project_dir_host: Path,
) -> None:
    """Migrate and symlink one workspaceStorage entry (for auxiliary data)."""
    project_dir_container.mkdir(parents=True, exist_ok=True)

    host_entry = host_hash_dir / entry_name
    container_entry = container_hash_dir / entry_name

    if host_entry.is_dir() and not host_entry.is_symlink():
        _migrate_dir_contents(host_entry, project_dir_container)
    elif host_entry.is_symlink():
        host_entry.unlink()

    host_entry.parent.mkdir(parents=True, exist_ok=True)
    host_entry.symlink_to(project_dir_host)

    if container_entry.is_dir() and not container_entry.is_symlink():
        _migrate_dir_contents(container_entry, project_dir_container)
    elif container_entry.is_symlink():
        container_entry.unlink()

    container_entry.parent.mkdir(parents=True, exist_ok=True)
    container_entry.symlink_to(project_dir_container)

    print(f"Linked {entry_name}: container → {project_dir_container}, host → {project_dir_host}")


# ── state.vscdb session index sync ──────────────────────────────────────────


def _read_vscdb(vscdb: Path, key: str) -> object:
    """Read a JSON value from a state.vscdb ItemTable."""
    try:
        con = sqlite3.connect(str(vscdb), timeout=5)
        row = con.execute(
            "SELECT value FROM ItemTable WHERE key = ?", (key,),
        ).fetchone()
        con.close()
        return json.loads(row[0]) if row else None
    except Exception as e:
        _logger.debug("_read_vscdb(%s, %s): %s", vscdb, key, e)
        return None


def _write_vscdb(vscdb: Path, key: str, value: object) -> bool:
    """Upsert a JSON value into a state.vscdb ItemTable. Returns True on success."""
    try:
        vscdb.parent.mkdir(parents=True, exist_ok=True)
        con = sqlite3.connect(str(vscdb), timeout=5)
        con.execute(
            "CREATE TABLE IF NOT EXISTS ItemTable "
            "(key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)"
        )
        con.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            (key, json.dumps(value, separators=(",", ":"))),
        )
        con.commit()
        con.close()
        return True
    except Exception as e:
        _logger.debug("_write_vscdb(%s, %s): %s", vscdb, key, e)
        return False


def _extract_sessions(index: object) -> list[dict]:
    """Extract the session list from whatever structure VS Code uses.

    Handles three formats:
      - flat list  (agentSessions.model.cache, agentSessions.state.cache)
      - dict with list-valued "sessions"/"entries" field
      - dict with dict-valued "entries" field  (chat.ChatSessionStore.index)
    """
    if isinstance(index, list):
        return [s for s in index if isinstance(s, dict)]
    if isinstance(index, dict):
        for field in ("sessions", "entries"):
            if field in index:
                val = index[field]
                if isinstance(val, list):
                    return [s for s in val if isinstance(s, dict)]
                if isinstance(val, dict):
                    return [s for s in val.values() if isinstance(s, dict)]
    return []


def _session_id(session: dict) -> str | None:
    return session.get("resource") or session.get("sessionId") or session.get("id")


def _is_local_provider(session: dict) -> bool:
    """Return True for sessions managed by Copilot's built-in local provider.

    These sessions are discovered in the container by Copilot scanning the
    chatSessions/ directory directly; writing them to state.vscdb causes
    the local agent to "claim" them, fail its internal registry check (the
    sessions were created in a foreign environment), and hide them.
    """
    provider = session.get("providerType", "")
    resource = str(session.get("resource") or session.get("sessionId") or "")
    return provider == "local" or resource.startswith("vscode-chat-session://local/")


def _filter_local_sessions(index: object) -> object:
    """Return a copy of index with local-provider sessions removed.

    Used for container state.vscdb writes only — local sessions from the host
    are discovered by Copilot's chatSessions/ scanner and must not be in
    state.vscdb, or the local agent will claim and hide them.
    """
    if isinstance(index, list):
        return [s for s in index if isinstance(s, dict) and not _is_local_provider(s)]
    if isinstance(index, dict):
        for field in ("sessions", "entries"):
            if field in index:
                val = index[field]
                if isinstance(val, list):
                    return {**index, field: [s for s in val if isinstance(s, dict) and not _is_local_provider(s)]}
                if isinstance(val, dict):
                    return {**index, field: {k: v for k, v in val.items() if not _is_local_provider(v)}}
    return index


def _merge_indices(base: object, extra: object) -> object:
    """Merge two session index values; base takes priority for duplicate IDs.

    Returns a value in the same structural format as base.
    """
    merged: dict[str, dict] = {}
    for s in _extract_sessions(extra):
        sid = _session_id(s)
        if sid:
            merged[sid] = s
    for s in _extract_sessions(base):
        sid = _session_id(s)
        if sid:
            merged[sid] = s

    if isinstance(base, dict) and base:
        field = next((k for k in ("sessions", "entries") if k in base), "sessions")
        if isinstance(base.get(field), dict):
            # chat.ChatSessionStore.index: entries is {sessionId: metadata}
            return {**base, field: {_session_id(s): s for s in merged.values()}}
        return {**base, field: list(merged.values())}
    return list(merged.values())


def sync_chat_indices(
    host_vscdb: Path,
    container_vscdb: Path,
    canonical_dir: Path,
) -> None:
    """Merge session indices: host + canonical + container → all three stores.

    Priority: host wins over canonical wins over container_existing, so the
    host's latest saved state is always authoritative.
    """
    for key in CHAT_INDEX_KEYS:
        canonical_file = canonical_dir / f"sessions-index-{key.replace('.', '-')}.json"

        host_index = _read_vscdb(host_vscdb, key) if host_vscdb.exists() else None

        canonical_index: object = None
        if canonical_file.exists():
            try:
                canonical_index = json.loads(canonical_file.read_text())
            except (json.JSONDecodeError, OSError) as e:
                _logger.debug("Failed to read canonical index %s: %s", canonical_file, e)

        # Read what container already has to preserve sessions from previous
        # container runs that have not yet been synced back to the host.
        container_existing = _read_vscdb(container_vscdb, key)

        n_host = len(_extract_sessions(host_index)) if host_index is not None else 0
        n_canonical = len(_extract_sessions(canonical_index)) if canonical_index is not None else 0
        n_container = len(_extract_sessions(container_existing)) if container_existing is not None else 0
        print(
            f"  {key}: host={n_host} canonical={n_canonical} container={n_container}",
        )

        if host_index is None and canonical_index is None and container_existing is None:
            _logger.debug("No session index found for key %s, skipping", key)
            continue

        # Merge: host wins over canonical wins over container_existing.
        base = host_index if host_index is not None else (canonical_index or container_existing)
        merged = _merge_indices(base, canonical_index)
        merged = _merge_indices(merged, container_existing)
        n = len(_extract_sessions(merged))

        # Write to container — but exclude local-provider sessions.
        # Local sessions are discovered via chatSessions/ directory scan; if
        # they are also in state.vscdb the local agent claims them, fails its
        # internal registry check (foreign-environment sessions), and hides them.
        container_safe = _filter_local_sessions(merged)
        n_container = len(_extract_sessions(container_safe))
        n_filtered = n - n_container
        if _write_vscdb(container_vscdb, key, container_safe):
            suffix = f" ({n_filtered} local filtered)" if n_filtered else ""
            print(f"  → wrote {n_container} session(s) to container vscdb{suffix}")
        else:
            print(f"  Warning: could not write {key} to container vscdb")

        # Persist so future container runs include today's container sessions.
        canonical_dir.mkdir(parents=True, exist_ok=True)
        canonical_file.write_text(json.dumps(merged, indent=2))

        # Best-effort write to host so host VS Code sees container sessions on
        # next open. Tolerate failure (VS Code may hold a write lock).
        if host_vscdb.exists():
            if _write_vscdb(host_vscdb, key, merged):
                print(f"  → wrote {n} session(s) to host vscdb")
            else:
                print(f"  Note: could not write to host vscdb (VS Code lock?) — will retry")


def _resolve_hashes(
    host_path: str, container_path: str, config_file: str,
) -> tuple[Path | None, Path | None, Path | None]:
    """Return (host_hash_dir, container_hash_dir, ai_copilot) or None on failure."""
    local_docker = detect_local_docker(container_path)
    container_hash = find_container_hash(
        host_path, container_path, config_file, local_docker=local_docker,
    )

    host_storage = find_host_storage()
    if not host_storage:
        return None, None, None

    host_hash = find_host_hash(host_storage, host_path)
    if not host_hash:
        return None, None, None

    return (
        host_storage / host_hash,
        VSCODE_SERVER_STORAGE / container_hash,
        Path(container_path) / ".ai" / "copilot",
    )


def link_copilot_storage(host_path: str, container_path: str, config_file: str) -> int:
    """Full bidirectional sync on container start."""
    host_hash_dir, container_hash_dir, ai_copilot = _resolve_hashes(
        host_path, container_path, config_file,
    )

    if host_hash_dir is None:
        print(
            "Copilot history sync skipped: host VS Code storage not found "
            "(check workspaceStorage bind mounts or run on host first).",
        )
        return 0

    print(f"Host hash dir:      {host_hash_dir}")
    print(f"Container hash dir: {container_hash_dir}")
    print(f"Canonical store:    {ai_copilot}")

    # Migrate legacy flat layout.
    if any((ai_copilot / item).exists() for item in _LEGACY_FLAT_ITEMS):
        gh_dir = ai_copilot / "GitHub.copilot-chat"
        gh_dir.mkdir(parents=True, exist_ok=True)
        for item_name in _LEGACY_FLAT_ITEMS:
            src = ai_copilot / item_name
            if src.exists() and not (gh_dir / item_name).exists():
                shutil.move(str(src), str(gh_dir / item_name))
        print("Migrated legacy flat items to GitHub.copilot-chat/")

    for entry_name in COPY_SYNC_ENTRIES:
        sync_copy_entry(entry_name, host_hash_dir, container_hash_dir, ai_copilot / entry_name)

    for entry_name in SYMLINK_ENTRIES:
        link_symlink_entry(
            entry_name,
            host_hash_dir,
            container_hash_dir,
            ai_copilot / entry_name,
            Path(host_path) / ".ai" / "copilot" / entry_name,
        )

    print("Syncing session indices (state.vscdb):")
    sync_chat_indices(
        host_hash_dir / "state.vscdb",
        container_hash_dir / "state.vscdb",
        ai_copilot,
    )

    return 0


def _background_sync_once(
    host_hash_dir: Path,
    container_hash_dir: Path,
    ai_copilot: Path,
) -> None:
    """One iteration of container→host sync: copy new files, update host vscdb."""
    for entry_name in COPY_SYNC_ENTRIES:
        canonical_dir = ai_copilot / entry_name
        canonical_dir.mkdir(parents=True, exist_ok=True)
        n_from = _copy_new_files(container_hash_dir / entry_name, canonical_dir)
        n_to = _copy_new_files(canonical_dir, host_hash_dir / entry_name)
        if n_from or n_to:
            print(f"[bg] {entry_name}: +{n_from} from container, +{n_to} to host", flush=True)

    container_vscdb = container_hash_dir / "state.vscdb"
    host_vscdb = host_hash_dir / "state.vscdb"
    for key in CHAT_INDEX_KEYS:
        canonical_file = ai_copilot / f"sessions-index-{key.replace('.', '-')}.json"

        container_index = _read_vscdb(container_vscdb, key)
        if container_index is None:
            continue

        canonical_index: object = None
        if canonical_file.exists():
            try:
                canonical_index = json.loads(canonical_file.read_text())
            except (json.JSONDecodeError, OSError):
                pass

        base = canonical_index if canonical_index is not None else container_index
        merged = _merge_indices(base, container_index)
        n = len(_extract_sessions(merged))

        canonical_file.write_text(json.dumps(merged, indent=2))
        if host_vscdb.exists():
            _write_vscdb(host_vscdb, key, merged)
            print(f"[bg] {key}: {n} sessions → host vscdb", flush=True)


def background_sync(host_path: str, container_path: str, config_file: str) -> int:
    """Continuous background sync loop: container→host every 5 minutes."""
    host_hash_dir, container_hash_dir, ai_copilot = _resolve_hashes(
        host_path, container_path, config_file,
    )
    if host_hash_dir is None:
        print("[bg] could not resolve storage paths; background sync inactive.", flush=True)
        return 0

    print(f"[bg] Background sync started — container: {container_hash_dir.name}", flush=True)

    def _shutdown(signum: int, frame: object) -> None:
        print("[bg] shutdown signal received; running final sync...", flush=True)
        # Give VS Code ~2 s to flush its own state to state.vscdb before we read it.
        time.sleep(2)
        try:
            _background_sync_once(host_hash_dir, container_hash_dir, ai_copilot)
        except Exception as exc:
            print(f"[bg] final sync error: {exc}", flush=True)
        print("[bg] final sync done.", flush=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    while True:
        time.sleep(300)  # 5 minutes
        try:
            _background_sync_once(host_hash_dir, container_hash_dir, ai_copilot)
        except Exception as exc:
            print(f"[bg] sync error: {exc}", flush=True)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Sync Copilot workspaceStorage between host and devcontainer.",
    )
    parser.add_argument("host_workspace")
    parser.add_argument("container_workspace")
    parser.add_argument("config_file")
    parser.add_argument(
        "--background",
        action="store_true",
        help="Run a continuous background sync loop (container→host every 5 min).",
    )
    args = parser.parse_args()

    if args.background:
        sys.exit(background_sync(args.host_workspace, args.container_workspace, args.config_file))
    else:
        sys.exit(link_copilot_storage(args.host_workspace, args.container_workspace, args.config_file))
