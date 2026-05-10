# AI Chat Storage — Architecture, Sync, and Limitations

This document captures everything learned about how VS Code, GitHub Copilot Chat, and the
Claude Code extension store and manage chat sessions, specifically in the context of syncing
session history between a macOS host and a devcontainer. It documents background architecture,
the sync script design, every approach that was tried, why some things are impossible, and the
current state of what works.

---

## Table of Contents

1. [VS Code Workspace Storage Architecture](#1-vs-code-workspace-storage-architecture)
2. [Session Types and URI Schemes](#2-session-types-and-uri-schemes)
3. [state.vscdb — Session Index Keys](#3-statevscdb--session-index-keys)
4. [Session File Formats](#4-session-file-formats)
5. [Copilot Chat Extension Internals](#5-copilot-chat-extension-internals)
6. [Claude Code Extension Internals](#6-claude-code-extension-internals)
7. [The Sync Problem](#7-the-sync-problem)
8. [link-copilot-storage.py — What the Script Does](#8-link-copilot-storagepy--what-the-script-does)
9. [Approaches Tried and Their Outcomes](#9-approaches-tried-and-their-outcomes)
10. [Confirmed Impossibilities](#10-confirmed-impossibilities)
11. [Remaining Bugs (Extension Behavior, Not Script Issues)](#11-remaining-bugs-extension-behavior-not-script-issues)
12. [Current State](#12-current-state)

---

## 1. VS Code Workspace Storage Architecture

VS Code gives each workspace a private key-value store called `workspaceStorage`. It lives at:

- **macOS host**: `~/Library/Application Support/Code/User/workspaceStorage/`
- **devcontainer**: `~/.vscode-server/data/User/workspaceStorage/`

Each workspace gets a subdirectory named by the **MD5 hash of the workspace URI**. The URI
format differs between environments:

| Environment | URI format |
|-------------|-----------|
| macOS host | `file:///Volumes/T7/repo/gh/quantized8/devfeats` |
| devcontainer | `vscode-remote://dev-container%2B{hex-encoded-config-json}/workspaces/devfeats` |

Because the URIs differ, the hashes differ, and each environment has its own completely
separate storage directory. This is the root cause of all sync complexity.

**Known hashes for this project:**

| Environment | Hash | Path |
|-------------|------|------|
| macOS host | `b1fdeea0fb13a1be9baf552541b5b8df` | (under host workspaceStorage bind-mount) |
| devcontainer | `4cd73b1c7dec3346a68aa637b3e363af` | `~/.vscode-server/data/User/workspaceStorage/…` |

### Inside each hash directory

```
<hash>/
  workspace.json          # {"folder": "<workspace-uri>"} — used to identify the hash
  state.vscdb             # SQLite: key-value store for extension state, session indices
  chatSessions/           # Copilot local session content (one .jsonl per session)
  chatEditingSessions/    # Copilot editing session content
  GitHub.copilot-chat/    # Auxiliary Copilot data (transcripts, debug logs, etc.)
```

`state.vscdb` is a SQLite database with a single table:

```sql
CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)
```

Values are JSON-encoded strings. VS Code holds no persistent write lock on this file —
it opens, writes, and closes. Concurrent access with short `timeout=5` is safe.

### Finding the container hash

The devcontainer URI embeds the devcontainer config JSON as hex. Changes to `context`,
`localDocker`, or config file path change the hash. The sync script uses **scan-based
detection** (reading `workspace.json` in every subdirectory) rather than computing the
hash from the formula, because the formula is fragile. The scan finds the correct hash
even if config details are unknown.

---

## 2. Session Types and URI Schemes

The Copilot Chat extension recognises three session URI schemes:

```js
new Set(["vscode-chat-session", "copilotcli", "claude-code"])
```

### `vscode-chat-session://local/{base64(uuid)}`

- **Provider**: Copilot Chat's built-in "local" session provider
- **Sidebar label**: bullet-point icon
- **Content storage**: `chatSessions/{uuid}.jsonl` in the hash directory
- **Index storage**: `agentSessions.model.cache` + `chat.ChatSessionStore.index`
- **Persistence mechanism**: in-memory registry + state.vscdb
- **`isExternal`**: `false`

Sessions are created when a user opens Copilot Chat in "Ask" or "Agent" mode and starts
a new conversation. The UUID is base64-encoded in the URI authority component.

### `claude-code:/{uuid}`

- **Provider**: The Claude Code extension (`anthropic.claude-code`)
- **Sidebar label**: ❋ (Claude icon)
- **Content storage**: `~/.claude/projects/{workspace-slug}/{uuid}.jsonl`
- **Index storage**: `agentSessions.model.cache` + `chat.ChatSessionStore.index`
- **`isExternal`**: `true`
- **URI construction**: `Ul.forSessionId(uuid)` → `{scheme:"claude-code", path:"/"+uuid}`

Sessions are created by the Claude Code CLI (`claude` command) running in the workspace.
The workspace slug is derived from the workspace path by replacing `/` with `-`:
`/workspaces/devfeats` → `-workspaces-devfeats`.

Untitled sessions created through the Copilot Chat UI (before any CLI interaction) use
the URI `claude-code:/untitled-{uuid}`.

### `copilotcli://…`

Used for Copilot CLI integrations. Not encountered in this project.

---

## 3. state.vscdb — Session Index Keys

Three keys govern chat session metadata. The sync script manages all three.

### `agentSessions.model.cache`

**Format**: flat JSON array of session objects.

**Purpose**: drives the Copilot Chat sidebar "Sessions" list — title, icon, timing, and
file-change metadata.

**Example entry** (claude-code session):
```json
{
  "providerType": "claude-code",
  "providerLabel": "Claude",
  "resource": "claude-code:/9cd14896-6220-4b1e-bf6e-4dca7fbe7e3a",
  "icon": "claude",
  "label": "Fix devcontainer chat persistence setup error",
  "badge": {"value": "$(folder) devfeats", "supportThemeIcons": true, ...},
  "tooltip": "Claude Code session: Fix devcontainer chat persistence setup error",
  "status": 1,
  "timing": {"created": 1778253660603, "lastRequestEnded": 1778346639189},
  "changes": [{"uri": {...}, "insertions": 25, "deletions": 11}],
  "metadata": {
    "workingDirectoryPath": "/workspaces/devfeats",
    "repositoryPath": "/workspaces/devfeats",
    "branchName": "main",
    ...
  }
}
```

**Example entry** (local session — from host, never visible in container sidebar):
```json
{
  "providerType": "local",
  "resource": "vscode-chat-session://local/{base64uuid}",
  "label": "Dev container build error",
  "timing": {...}
}
```

**Note on `workingDirectoryPath`**: Sessions created in the container have
`/workspaces/devfeats`; sessions created on the host have `/Volumes/T7/repo/…/devfeats`.
Both can coexist. The path reflects where the Claude Code CLI was running when it created
the session, not necessarily the current environment.

### `agentSessions.state.cache`

**Format**: flat JSON array.

**Purpose**: per-session read timestamps (used to show "unread" badge on sessions).

**Example entry**:
```json
{"resource": "claude-code:/3ce2f2c9-4cd1-43a5-9529-b0b1ba694771", "read": 1778281163552}
```

### `chat.ChatSessionStore.index`

**Format**: `{"entries": {"<sessionId>": {...}, ...}, ...}` — dict keyed by session ID.

**Purpose**: full session metadata for content resolution. Includes input state, model
configuration, timing, and the `isExternal` flag.

**Example entry** (claude-code session):
```json
{
  "sessionId": "claude-code:/3ce2f2c9-4cd1-43a5-9529-b0b1ba694771",
  "title": "User identity inquiry",
  "isExternal": true,
  "inputState": {
    "mode": {"id": "agent", "kind": "agent"},
    "selectedModel": {
      "identifier": "claude-code/claude-opus-4.7",
      "vendor": "claude-code",
      "targetChatSessionType": "claude-code"
    }
  }
}
```

**Example entry** (local session):
```json
{
  "sessionId": "e2597cfb-fdd2-4818-be5f-38de4401311f",
  "title": "Dev container build error",
  "isExternal": false
}
```

**Key difference**: `isExternal: true` means the session content lives outside
Copilot's own `chatSessions/` store. The Copilot Chat panel will not attempt to render
history for these sessions from local storage.

### Other relevant keys (host only, not synced)

| Key | Purpose |
|-----|---------|
| `chat.customModes` | Custom agent/mode definitions (all providers) |
| `chat.customModes.claude-code` | Custom modes for the claude-code session type |
| `chat.customModes.local` | Custom modes for the local session type |
| `chat.terminalSessions` | Terminal integration sessions |
| `chat.untitledInputState` | Draft input state for new sessions |

---

## 4. Session File Formats

### Copilot local session JSONL (`chatSessions/{uuid}.jsonl`)

Append-only log. Each line is a JSON object:

```
{"kind": 0, "v": {...}}   # kind 0: session creation record
{"kind": 1, "v": "..."}   # kind 1: property update (title, etc.) — v is a string here
{"kind": 2, "v": {...}}   # kind 2: request/response pair
```

**kind 0 `v` fields**:
```json
{
  "version": 3,
  "creationDate": 1778332439675,
  "sessionId": "7625f535-c868-492a-9166-577766930f93",
  "initialLocation": "panel",
  "hasPendingEdits": false,
  "requests": [],
  "inputState": {
    "mode": {
      "id": "vscode-userdata:/Users/home/Library/Application%20Support/Code/User/globalStorage/github.copilot-chat/ask-agent/Ask.agent.md",
      "kind": "agent"
    }
  }
}
```

The `mode.id` path always refers to the HOST macOS path (under
`~/Library/Application Support/Code/…`) regardless of whether the session was created in
the container or on the host. This is NOT a reliable indicator of session origin.

**kind 2 `v` fields** contain `requests` — an array of conversation turns with message
content, tool calls, and model responses.

### Claude Code CLI session JSONL (`~/.claude/projects/{slug}/{uuid}.jsonl`)

Very different format — not compatible with Copilot's chatSessions format.

```
{"type": "queue-operation", "operation": "...", "timestamp": ..., "sessionId": "..."}
{"type": "user", "parentUuid": "...", "message": {"role": "user", "content": [...]}, 
  "cwd": "/workspaces/devfeats", "sessionId": "...", "gitBranch": "main", ...}
{"type": "assistant", "message": {"role": "assistant", "content": [...]}, ...}
{"type": "attachment", ...}
{"type": "file-history-snapshot", "messageId": "...", "snapshot": {...}}
```

`content` follows the Anthropic Messages API format: `[{"type": "text", "text": "..."}]`.

This format is entirely owned by the Claude Code CLI — not readable by Copilot Chat's
local session renderer.

---

## 5. Copilot Chat Extension Internals

**Location**: `/vscode/vscode-server/bin/linux-x64/{commit}/extensions/copilot/dist/extension.js`

This is a built-in extension shipped with VS Code Server, not user-installable in the
extensions directory.

### Session URI utilities

```js
var Ul;
Ul.scheme = "claude-code";
Ul.forSessionId = function(id) {
    return URI.from({scheme: "claude-code", path: "/" + id});
};
Ul.getSessionId = function(uri) {
    if (uri.scheme !== "claude-code") throw new Error("Invalid resource scheme");
    return uri.path.slice(1);
};
```

### Recognised session types

```js
var lRi = new Set(["vscode-chat-session", "copilotcli", "claude-code"]);
function JSn(n) { return lRi.has(n); }
```

### Claude model as language model provider

The Copilot extension registers a language model provider for the `"claude-code"` vendor:

```js
this._register(t.registerLanguageModelChatProvider("claude-code", r))
```

This means "Claude Opus 4.7", "Claude Sonnet 4.6" etc. appear in Copilot Chat's model
picker and route requests through the Claude Code backend.

Sessions using the Claude model have `targetChatSessionType: "claude-code"`:
```json
{
  "identifier": "claude-code/claude-opus-4.7",
  "vendor": "claude-code",
  "targetChatSessionType": "claude-code"
}
```

### The `isExternal` flag

When `isExternal: true`, the Copilot Chat panel knows this session's history is not in
its own `chatSessions/` storage. It will not attempt to load previous messages from
local files. The session can be opened to continue the conversation, but no history is
shown — the history lives in Claude Code's `~/.claude/projects/…` JSONL.

### Session sidebar population

The "Sessions" list in the Copilot Chat sidebar is rendered from the **in-memory session
registry**, not directly from `state.vscdb`. The registry is populated at startup from
`agentSessions.model.cache` in `state.vscdb`. As sessions are created during the current
VS Code instance, they are added to the in-memory registry. The registry is persisted
back to `state.vscdb` periodically and on close.

The crucial implication: **writing a session entry to `state.vscdb` does not add it to
the in-memory registry of a running VS Code instance**. The registry is read-once at
startup, then managed in memory.

---

## 6. Claude Code Extension Internals

**Extension ID**: `anthropic.claude-code`  
**Installed location**: `~/.vscode-server/extensions/anthropic.claude-code-{version}-linux-x64/`  
**Type**: Remote extension (runs inside the devcontainer)

### Views contributed

| View ID | Name |
|---------|------|
| `claude-sidebar` | Main Claude Code panel |
| `claude-sidebar-secondary` | Secondary sidebar |
| `claude-sessions-sidebar` | Session history list |

The `claude-sessions-sidebar` shows a list of Claude Code CLI sessions for the current
workspace. It reads from `~/.claude/projects/{slug}/` directly, watching for new or
updated `.jsonl` files.

### Session registration flow

When the Claude Code CLI completes a conversation turn, it writes (or appends to) a
`.jsonl` file at `~/.claude/projects/{slug}/{uuid}.jsonl`. The Claude Code VS Code
extension watches this directory. When a new or updated session file is detected, the
extension:

1. Reads the session metadata from the `.jsonl` (title, timing, changes, etc.)
2. Updates `agentSessions.model.cache` in `state.vscdb` with the session entry
3. Updates `workbench.view.extension.claude-sessions-sidebar.state` with the sidebar state

This means: **only sessions that were created or updated by the Claude Code CLI produce
entries in `agentSessions.model.cache`**. Sessions created through other paths (e.g., an
Anthropic API call through Copilot Chat UI) only land in `chat.ChatSessionStore.index`,
not in `agentSessions.model.cache`.

### Workspace slug convention

The Claude Code CLI converts the workspace path to a slug by replacing `/` with `-` and
prepending `-`:

```
/workspaces/devfeats       →  ~/.claude/projects/-workspaces-devfeats/
/Volumes/T7/repo/devfeats  →  ~/.claude/projects/-Volumes-T7-repo-devfeats/
```

Sessions created inside the container are stored under `-workspaces-devfeats/`. Sessions
created on the macOS host would be stored under the host path slug in the HOST's
`~/.claude/projects/`, which is an entirely separate directory not accessible from the
container.

---

## 7. The Sync Problem

### Why sync is needed

VS Code uses different workspace hashes for host vs container. The host's and container's
`workspaceStorage/<hash>/` directories are entirely independent. Without intervention:

- Session history created in the container disappears if the container is rebuilt
- Session history created on the host is invisible inside the container
- There is no native VS Code mechanism to share workspaceStorage between environments

### What we mount

The devcontainer mounts the host's VS Code workspaceStorage directory at
`/host-vscode-workspacestorage` (macOS `~/Library/Application Support/Code/User/workspaceStorage`).
This gives the container read/write access to the host's state, enabling bidirectional sync.

### What can be synced

| Data | What it is | Can be synced? |
|------|-----------|----------------|
| `chatSessions/*.jsonl` | Copilot session message history | ✅ Full bidirectional sync |
| `chatEditingSessions/*.jsonl` | Editing session history | ✅ Full bidirectional sync |
| `GitHub.copilot-chat/` | Transcripts, debug logs, workspace chunks | ✅ Symlink works |
| `agentSessions.model.cache` | Sidebar session list | ✅ Merges correctly |
| `agentSessions.state.cache` | Read timestamps | ✅ Merges correctly |
| `chat.ChatSessionStore.index` | Full session metadata | ✅ Merges correctly |
| Local session visibility | Sessions appearing in container sidebar | ❌ Impossible (see §10) |

### The canonical store

`.ai/copilot/` inside the workspace root is the persistent canonical store. It survives
container rebuilds. On each container start:

1. New/larger files from both host and container hash dirs are pulled into `.ai/copilot/`
2. All canonical files are pushed back to both hash dirs
3. `state.vscdb` indices are merged from all three sources and written back to all three

---

## 8. link-copilot-storage.py — What the Script Does

### Startup sync (`postStartCommand`)

Executed once when the container starts, before VS Code begins reading state:

```
Host hash dir  ←→  Canonical (.ai/copilot/)  ←→  Container hash dir
```

1. **chatSessions/ and chatEditingSessions/** — bidirectional copy-sync:
   - Pull from host hash dir → canonical (new/larger files only)
   - Pull from container hash dir → canonical (new/larger files only)
   - Push canonical → host hash dir
   - Push canonical → container hash dir

2. **GitHub.copilot-chat/** — symlink from both hash dirs to canonical

3. **state.vscdb indices** — three-way merge:
   - Read `agentSessions.model.cache`, `agentSessions.state.cache`,
     `chat.ChatSessionStore.index` from all three sources
   - Merge (host wins for duplicate session IDs, then canonical, then container)
   - Write merged result to container vscdb, canonical JSON files, and host vscdb

### Background sync (`--background`, every 5 minutes + SIGTERM)

Runs in a background process launched alongside the startup sync:

1. **chatSessions/** — container → canonical → host (one-way, new/larger files only)
2. **state.vscdb indices** — container → canonical → host:
   - Reads container vscdb, merges into canonical, writes to host vscdb
   - Does **not** modify the container vscdb (VS Code manages it directly)

### Hash detection

1. **Primary**: scan `~/.vscode-server/data/User/workspaceStorage/*/workspace.json` and
   find the entry whose `folder` URI contains `dev-container` and ends with the container
   workspace path. Returns the directory name (hash).
2. **Fallback**: compute the hash from the URI formula (requires knowing the Docker context
   and config file path).

---

## 9. Approaches Tried and Their Outcomes

### Approach 1: Copy chatSessions/ files (✅ Works)

Copy session `.jsonl` files between host and container hash directories via the canonical
store. Both sides then have the same session files.

**Result**: Session files are present on both sides. The sync is reliable and repeatable
because `_copy_new_files()` only copies files that are new or larger (append-only logs
grow, never shrink).

### Approach 2: Merge state.vscdb session indices (✅ Partially works)

Write host session metadata into the container's `state.vscdb` so the container sidebar
shows sessions from the host.

**Result**:
- `claude-code` sessions from the host do appear in the container sidebar with correct
  titles (the Claude Code extension reads `agentSessions.model.cache` at startup)
- `local` sessions from the host do NOT appear (see §10)
- Merge logic is correct; sessions from all three sources are preserved

### Approach 3: Filter local sessions from container vscdb write (❌ Wrong hypothesis, reverted)

Added `_is_local_provider()` and `_filter_local_sessions()` to strip `vscode-chat-session`
entries from the container vscdb write. Hypothesis: local sessions in `state.vscdb` cause
Copilot's local agent to "claim" them, fail its internal registry check, and hide them.

**Result**: The hypothesis was false. Local sessions do not appear in the container sidebar
regardless of whether their entries are in `state.vscdb`. The filter was actively harmful
because it also stripped container-created local sessions from the vscdb write, which
prevented the background sync from capturing them. Reverted.

### Approach 4: Direct state.vscdb write during live test (❌ No effect)

During investigation, directly wrote 6 host local sessions (with correct `providerType`,
`resource`, `label`, `timing` fields) into the container's `state.vscdb`, then performed
"Developer: Reload Window".

**Result**: Zero host local sessions appeared in the container sidebar.

### Approach 5: Restart Extension Host (❌ No effect)

After the direct vscdb write, performed "Developer: Restart Extension Host", which
re-initialises all extensions from scratch and would trigger any startup scans.

**Result**: Still zero host local sessions appeared. This is the definitive test: even
a full extension host restart, with correct entries in state.vscdb and correct `.jsonl`
files in `chatSessions/`, cannot make foreign-environment local sessions visible.

### Approach 6: Symlink chatSessions/ directories (❌ Rejected)

Use symlinks instead of copies for `chatSessions/` to avoid duplication.

**Result**: VS Code on macOS refuses to read `.jsonl` files through cross-volume symlinks
(the host's workspaceStorage is on the macOS volume, mounted into the container as a
different filesystem). Copy-sync is required.

---

## 10. Confirmed Impossibilities

### Local Copilot sessions from host cannot appear in container sidebar

**Root cause**: VS Code's local-session provider maintains an **in-memory registry** that
is the sole source of truth for sidebar visibility. A session is added to the registry
only when it is **created by the current VS Code instance**.

The registry is populated from `state.vscdb` at startup, but in a read-then-track manner:
the vscdb provides initial entries for sessions the extension instance already knows about.
For sessions the current instance never created, the local provider's `getSession()` call
returns nothing, and the sidebar ignores the entry.

**What was confirmed NOT to work**:
- Writing local session entries to container `state.vscdb`
- Having the session's `.jsonl` file in `chatSessions/`
- "Reload Window" (re-reads vscdb but same instance)
- "Restart Extension Host" (re-initialises extensions but creates a fresh registry;
  scans chatSessions/ but does not import foreign sessions into the registry)

**Implication**: This is a fundamental VS Code design decision, not a bug or oversight.
The local session provider intentionally does not allow arbitrary sessions to be injected
into its registry from external sources.

**What still works**: The session `.jsonl` files ARE synced, so if the user opens the
original environment (the host), all the sessions they created there are still available
and visible. The history is preserved; it just cannot be cross-rendered.

---

## 11. Remaining Bugs (Extension Behavior, Not Script Issues)

### Bug A: claude-code sessions show title but no chat history when clicked

Clicking a `claude-code://` session in the Copilot Chat sidebar opens a chat panel but
shows no previous messages.

**Root cause**: These sessions have `"isExternal": true` in `chat.ChatSessionStore.index`.
This flag signals to Copilot Chat that session content lives outside its own storage. The
Copilot Chat panel does not attempt to load history from `chatSessions/` for external
sessions. The conversation history lives in `~/.claude/projects/{slug}/{uuid}.jsonl` and
is only viewable through the **Claude Code extension's own Sessions sidebar**
(`claude-sessions-sidebar`).

Clicking a claude-code session in Copilot Chat is intended to **open a new turn**
continuing from where the CLI session left off, not to browse history inline.

**Not fixable from the sync script**: This is the designed behaviour.

### Bug B: New Copilot Chat sessions using Claude model disappear from sidebar

When a user creates a new conversation in Copilot Chat using a Claude model (Opus 4.7,
Sonnet 4.6, etc.), the session appears in the sidebar while the chat window is open. After
closing the window, the session no longer appears in the "Sessions" list.

**Root cause**: Sessions created through Copilot Chat UI with the Claude model get
`claude-code:/untitled-{uuid}` IDs. They are written to `chat.ChatSessionStore.index` but
NOT to `agentSessions.model.cache`. The `agentSessions.model.cache` is what drives the
Sessions list.

`agentSessions.model.cache` is populated by the **Claude Code VS Code extension**, which
monitors `~/.claude/projects/{slug}/` for new `.jsonl` files. Sessions created through
the Copilot Chat UI that are routed through the Claude Code backend SHOULD eventually
produce a `.jsonl` file; but sessions that are abandoned before sending a message, or
sessions where the backend routing fails, never get a CLI-side JSONL file. Without that
file, the Claude Code extension never registers the session in `agentSessions.model.cache`,
so the sidebar does not persist it after the window closes.

**Not fixable from the sync script**: This requires a fix in the Claude Code extension's
session registration logic, or persistence of untitled sessions to `agentSessions.model.cache`
by the Copilot Chat extension itself.

---

## 12. Current State

### What works

| Feature | Status |
|---------|--------|
| chatSessions/ files synced host ↔ container | ✅ |
| chatEditingSessions/ files synced host ↔ container | ✅ |
| GitHub.copilot-chat/ (transcripts, debug logs) shared | ✅ via symlink |
| claude-code sessions appear in container sidebar | ✅ |
| State persists across container rebuilds | ✅ via .ai/copilot/ canonical store |
| Background sync container → host (every 5 min) | ✅ |
| Final sync on container stop | ✅ via SIGTERM handler |
| Host local sessions appear in container sidebar | ❌ impossible |
| Container local sessions appear in host sidebar | ✅ (they sync, visible on host) |

### Directory structure

```
<workspace>/
  .ai/
    copilot/                     ← canonical persistent store
      chatSessions/              ← Copilot session .jsonl files (all environments)
      chatEditingSessions/       ← editing session .jsonl files
      GitHub.copilot-chat/       ← auxiliary data (symlink target)
      sessions-index-agentSessions-model-cache.json      ← cached index
      sessions-index-agentSessions-state-cache.json
      sessions-index-chat-ChatSessionStore-index.json

~/.vscode-server/data/User/workspaceStorage/
  4cd73b1c7dec3346a68aa637b3e363af/   ← container hash dir (current)
    workspace.json
    state.vscdb                        ← session indices (3 keys)
    chatSessions/                      ← same files as canonical
    chatEditingSessions/
    GitHub.copilot-chat -> .ai/copilot/GitHub.copilot-chat   ← symlink

~/.claude/
  projects/
    -workspaces-devfeats/             ← Claude Code CLI sessions (container-created)
      {uuid}.jsonl                    ← one per conversation
```

### Session counts (as of last sync)

| Key | Sessions |
|-----|---------|
| `agentSessions.model.cache` | 14 (8 claude-code + 6 local from host) |
| `agentSessions.state.cache` | 15 |
| `chat.ChatSessionStore.index` | 31 (incl. untitled + all providers) |
| `chatSessions/` (canonical) | 10 .jsonl files |

Only the 8 claude-code sessions from `agentSessions.model.cache` actually appear in the
container sidebar. The 6 local sessions from the host are present in the indices for
completeness but are invisible in the container (§10).
