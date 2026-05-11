# AI Chat Storage — Architecture, Sync, and Limitations

This document captures everything learned about how VS Code, GitHub Copilot Chat, and the
Claude Code extension store and manage chat sessions, specifically in the context of syncing
session history between a macOS host and a devcontainer. It documents background architecture,
the sync script design, every approach that was tried, why some things are impossible, and the
current state of what works.

> **Note on sourcing**: Sections 1–12 were written based on VS Code source code inspection,
> extension bundle analysis, and indirect observation. Section 13 onwards documents **direct
> experimental observations** from an isolated test devcontainer with no custom scripts or
> mounts — these take precedence where they conflict with earlier inferred conclusions.

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
13. [Experimental Observations — Isolated Test Container](#13-experimental-observations--isolated-test-container)
14. [Online Research — state.vscdb and chatSessions/ Deep Dive](#14-online-research--statevscdb-and-chatsessions-deep-dive)

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

---

## 13. Experimental Observations — Isolated Test Container

To resolve contradictions between inferred behaviour and observed behaviour, a minimal
isolated test devcontainer was created at `.devcontainer/.test/`. It has:

- No custom mounts beyond exposing its `~/.vscode-server/data/User` and `~/.claude` to
  a known path in the workspace (`output/copilot/` and `output/claude/` at workspace root)
- No postStartCommand scripts of any kind
- Only three extensions: `GitHub.copilot`, `GitHub.copilot-chat`, `anthropic.claude-code`

This eliminates all interference from `link-copilot-storage.py` and the devcontainer setup.
Snapshots were taken before each session and diffed after, so every file change is attributed
to a specific action.

Snapshots live at `.local/ai-chat-test/`:

| Snapshot | State |
|----------|-------|
| `output-init/` | Container started, no sessions yet |
| `output-after-A/` | After Copilot Chat agent mode session |
| `output-after-A-ask/` | After Copilot Chat ask mode session |
| `output-after-A-plan/` | After Copilot Chat plan mode session |
| `output-after-B/` | After Claude Code sidebar session |
| `output-after-C/` | After Copilot Chat with Claude model session |
| `output-after-shutdown/` | After VS Code window closed and container stopped |

---

### 13.1 Initial State (container start, no sessions yet)

Files written by VS Code and extensions on startup alone, before any session is created:

```
output/claude/
  backups/.claude.json.backup.{timestamp}
  ide/{pid}.lock                            # claude-vscode process lock
  sessions/{pid}.json                       # process tracking (see below)
  plugins/installed_plugins.json            # {"version":2,"plugins":{}}
  .last-cleanup

output/copilot/
  globalStorage/github.copilot-chat/        # extension global assets
    ask-agent/Ask.agent.md
    plan-agent/Plan.agent.md
    copilotCli/…
    debugCommand/…
  globalStorage/vscode.json-language-features/json-schema-cache/
  workspaceStorage/{hash}/
    vscode.lock                             # only file in hash dir on startup
```

**`sessions/{pid}.json` format** — tracks the running claude-vscode process, not a chat session:
```json
{
  "pid": 786,
  "sessionId": "792ec43f-f755-40f7-acc3-3e7b6acc779b",
  "cwd": "/workspaces/devfeats",
  "startedAt": 1778451083780,
  "version": "2.1.138",
  "kind": "interactive",
  "entrypoint": "claude-vscode"
}
```

The `sessionId` here is pre-assigned and will become the filename of the JSONL conversation
file once a message is sent. **No `state.vscdb` and no `chatSessions/` are created at startup.**

---

### 13.2 Session A — Copilot Chat (agent mode)

**Action**: opened Copilot Chat panel in "agent" mode, sent a message, closed.

**Files created:**
```
workspaceStorage/{hash}/GitHub.copilot-chat/
  transcripts/{sessionId}.jsonl       ← full conversation event log
  debug-logs/{sessionId}/
    main.jsonl
    models.json
    system_prompt_0.json
    title-{uuid}.jsonl
    tools_0.json
globalStorage/github.copilot-chat/
  toolEmbeddingsCache.bin             ← agent tool index (new)
```

**Files NOT created:** `state.vscdb`, `chatSessions/`, `chatEditingSessions/`

**Transcript format** (`transcripts/{sessionId}.jsonl`):
```jsonl
{"type":"session.start","data":{"sessionId":"…","version":1,"producer":"copilot-agent",…}}
{"type":"assistant.message","data":{"messageId":"…","content":"…","toolRequests":[…]},…}
{"type":"assistant.turn_end","data":{"turnId":"0"},…}
{"type":"assistant.turn_start","data":{"turnId":"1"},…}
{"type":"tool.execution_start","data":{"toolCallId":"…","toolName":"…","arguments":{…}},…}
{"type":"tool.execution_complete","data":{"toolCallId":"…","success":true},…}
```

Note `"producer":"copilot-agent"` in the session.start record regardless of mode.

---

### 13.3 Session A-ask — Copilot Chat (ask mode)

**Action**: opened Copilot Chat in "ask" mode, sent a message, closed.

**Result**: Identical storage pattern to agent mode.
- New `transcripts/{sessionId}.jsonl` with `"producer":"copilot-agent"`
- New `debug-logs/{sessionId}/` directory
- Still no `state.vscdb`, no `chatSessions/`

---

### 13.4 Session A-plan — Copilot Chat (plan mode)

**Action**: opened Copilot Chat in "plan" mode, sent a message, closed.

**Result**: Identical storage pattern to agent and ask modes.
- New `transcripts/{sessionId}.jsonl` with `"producer":"copilot-agent"`
- One extra `debug-logs/{uuid}/` entry with no matching transcript (likely an aborted
  internal sub-call for title generation or planning)
- Still no `state.vscdb`, no `chatSessions/`

---

### 13.5 Session B — Claude Code extension sidebar

**Action**: opened Claude Code extension sidebar, started a new chat, sent a message.

**Files created:**
```
output/claude/
  projects/-workspaces-devfeats/{sessionId}.jsonl   ← conversation JSONL
  sessions/{pid}.json                               ← new process tracking entry
  settings.json                                     ← {"model":"haiku"}
  .credentials.json                                 ← auth credentials
  shell-snapshots/snapshot-bash-{timestamp}-{id}.sh
  backups/.claude.json.backup.{timestamp}
```

**Files NOT created in Copilot storage:** `state.vscdb`, `chatSessions/`, `agentSessions.model.cache`

**Observed**: the new session immediately appeared in the **Copilot Chat sidebar** as well,
with no file written to `output/copilot/` — confirmed by diff. Registration is via in-memory
VS Code extension API (see §13.8, Finding 5).

**Project JSONL path**: `~/.claude/projects/-workspaces-devfeats/{sessionId}.jsonl`
- The slug `-workspaces-devfeats` is the container workspace path with `/`→`-`
- The `sessionId` matches the one pre-assigned in `sessions/{pid}.json` at extension startup
- The JSONL file is created when the first message is sent, not when the session opens

**JSONL format** (first lines):
```jsonl
{"type":"queue-operation","operation":"enqueue","timestamp":"…","sessionId":"…"}
{"type":"queue-operation","operation":"dequeue","timestamp":"…","sessionId":"…"}
{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":…},
 "cwd":"/workspaces/devfeats","sessionId":"…","gitBranch":"main","entrypoint":"claude-vscode"}
```

---

### 13.6 Session C — Copilot Chat with Claude model

**Action**: opened Copilot Chat panel, selected Claude model, sent marker message
`test copilot claude mode: say hi`.

**Observed**: the new session immediately appeared in the **Claude Code extension's Session
list** as well — the mirror of Session B. Bidirectional cross-registration confirmed.

**Files created in `output/claude/`:**
```
projects/-workspaces-devfeats/153f531c-8e3e-45b5-a629-f1ebabfa4b65.jsonl
sessions/9091.json     ← entrypoint: sdk-ts (SDK process)
sessions/9428.json     ← entrypoint: claude-vscode (VS Code extension detecting the file)
file-history/{uuid}/   ← file edit history tracking
backups/…
```

**Files created in `output/copilot/`:**
```
workspaceStorage/{hash}/GitHub.copilot-chat/debug-logs/153f531c-…/
  main.jsonl
  models.json
  system_prompt_0.json
```

**No transcript written** — unlike Sessions A/ask/plan, there is no entry in
`GitHub.copilot-chat/transcripts/`. Only a debug-logs entry.

**The session UUID appears in THREE places with the same value:**
1. `claude/projects/-workspaces-devfeats/153f531c-….jsonl` — Claude's conversation JSONL
2. `copilot/…/debug-logs/153f531c-…/` — Copilot's debug log
3. `claude/sessions/9091.json` + `9428.json` — two process tracking entries

**JSONL entrypoint field**: `"entrypoint":"sdk-ts"` — distinguishes Copilot-initiated sessions
from direct Claude Code extension sessions (`"entrypoint":"claude-vscode"`). When Copilot Chat
routes a message through the Claude model, it calls the **Claude Code TypeScript SDK**
directly, which writes a real session JSONL to `~/.claude/projects/`.

**Two process tracking entries for the same session:**
```json
// 9091.json — the SDK process spawned by Copilot Chat
{"pid":9091,"sessionId":"153f531c-…","entrypoint":"sdk-ts"}

// 9428.json — the Claude Code extension detecting the new JSONL file
{"pid":9428,"sessionId":"153f531c-…","entrypoint":"claude-vscode","version":"2.1.138"}
```

---

### 13.7 Shutdown Observations

**Action**: VS Code window closed. Container stopped via `shutdownAction: stopContainer`.

**New files written:** none.

**Files cleaned up on shutdown:**
- `claude/sessions/{pid}.json` — all process tracking entries deleted
- `claude/ide/{pid}.lock` — IDE lock deleted
- `claude/shell-snapshots/` — cleared
- `copilot/workspaceStorage/{hash}/vscode.lock` — deleted

**Files updated on shutdown:**
- `claude/projects/-workspaces-devfeats/*.jsonl` — final content flushed

**`state.vscdb` was never written. `chatSessions/` was never created.**
This holds after a full clean shutdown with all extension deactivation cycles complete.

---

### 13.8 Restart Observations

**Action**: test container reopened, extensions fully reloaded.

**New files:** only `claude/sessions/{pid}.json` (new process entry) and `vscode.lock`.

**All sessions immediately appeared in both sidebars** — with no `state.vscdb` and no
`chatSessions/` anywhere on disk. Sessions are restored purely from directory scanning.

---

### 13.9 Key Findings and Corrections to Earlier Assumptions

#### Finding 1: `chatSessions/` and `state.vscdb` are never written

Earlier sections (1, 5, 7) described `chatSessions/` as the live Copilot session store and
`state.vscdb` as the session index. **Direct observation fully contradicts this.**

After four distinct sessions (agent, ask, plan, Claude Code) and a full shutdown+restart
cycle, neither `chatSessions/` nor `state.vscdb` were ever created. The entire sync script
(`link-copilot-storage.py`) was built around these files. They do not exist in the current
version of Copilot Chat (0.47.0).

#### Finding 2: All three Copilot Chat modes produce identical storage

"Agent", "ask", and "plan" all write `transcripts/{uuid}.jsonl` and `debug-logs/{uuid}/`
with `"producer":"copilot-agent"`. Mode selection only affects which tools are available.

#### Finding 3: `chatSessions/` (kind 0/1/2 format) is from an older Copilot version

Section 4 documents a `kind 0/1/2` JSONL format for `chatSessions/`. This format was never
observed. The current persistence format is `GitHub.copilot-chat/transcripts/{uuid}.jsonl`
with typed event objects (`session.start`, `assistant.message`, `tool.execution_start`, etc.).

#### Finding 4: Claude Code assigns session ID at process start, writes JSONL at first message

`sessions/{pid}.json` is created at extension launch and contains the pre-assigned
`sessionId`. The `projects/{slug}/{sessionId}.jsonl` file is only created when the first
message is actually sent.

#### Finding 5: Sidebar registration is via in-memory VS Code extension API

Both extensions register sessions with each other's sidebar via in-process VS Code extension
API calls — not by writing to any file. This is bidirectional: Claude Code sessions appear
in Copilot's sidebar (Session B) and Copilot+Claude sessions appear in Claude Code's sidebar
(Session C), both immediately upon session creation, with zero disk writes to the other
extension's storage directory.

#### Finding 6: Session persistence is by directory scanning, not state.vscdb

On startup, each extension scans its own directory for session files and rebuilds the
sidebar from those files directly:
- Copilot Chat scans `workspaceStorage/{hash}/GitHub.copilot-chat/transcripts/`
- Claude Code scans `~/.claude/projects/{slug}/`

Cross-registration then happens via extension API as in Finding 5. No `state.vscdb` read
occurs at any point. The earlier model ("registry populated from state.vscdb at startup")
is incorrect for the current version.

---

### 13.10 Implications for the Persistence Feature

The correct persistence targets are radically simpler than previously assumed:

| What to persist | How |
|-----------------|-----|
| Copilot sessions | `workspaceStorage/{hash}/GitHub.copilot-chat/` |
| Claude Code sessions | `~/.claude/projects/{slug}/` |
| `state.vscdb` | **Not needed — never written** |
| `chatSessions/` | **Not needed — does not exist** |

The simplest implementation: symlink `~/.vscode-server/data/User/workspaceStorage` →
`.ai/copilot/` in the workspace root, and symlink `~/.claude/projects/{slug}` →
`.ai/claude/` (already implemented in the devcontainer).

The only remaining complexity is **hash stability**: if the devcontainer config file path,
Docker context, or workspace path changes between rebuilds, VS Code computes a new hash and
Copilot cannot find the old transcripts in the old hash directory. A migration step
(scan for old hash directory, rename to new hash) handles this edge case.

#### On shutdown (VS Code window closed, container stopped)

New files written: **none.**

Files cleaned up:
- `claude/sessions/{pid}.json` — all process tracking entries deleted
- `claude/ide/{pid}.lock` — IDE lock deleted
- `claude/shell-snapshots/` — cleared
- `copilot/workspaceStorage/{hash}/vscode.lock` — deleted

Files updated:
- `claude/projects/-workspaces-devfeats/*.jsonl` — final content flushed

**`state.vscdb` was never written. `chatSessions/` was never created.**

#### On restart (container reopened, extensions reloaded)

New files: only `claude/sessions/{pid}.json` (new process entry) and `vscode.lock`.

**All sessions immediately appeared in both sidebars** — with no `state.vscdb` and no
`chatSessions/` anywhere on disk.

---

## 14. Online Research — state.vscdb and chatSessions/ Deep Dive

> **Sourcing note**: Section 13 established by direct experiment that `state.vscdb` and
> `chatSessions/` were never written in a clean Copilot Chat 0.47.0 environment. This section
> reports what online research (VS Code/Copilot source code, GitHub issues, release notes)
> reveals about those files, reconciles the findings with our experimental data, and pins down
> the version boundary where the storage architecture changed.

---

### 14.1 What `state.vscdb` Is

`state.vscdb` is a SQLite database managed exclusively by **VS Code core** (not by
extensions directly). It is the implementation of the `IStorageService` API and lives at:

```
workspaceStorage/<hash>/state.vscdb         # per-workspace state
globalStorage/state.vscdb                   # global (user-level) state
```

Schema (single table, all versions):
```sql
CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)
```

Extensions read and write it through the VS Code API (`context.workspaceState.update(key,
value)`, `context.globalState.update(key, value)`). The VS Code host process translates
these calls into SQL writes. Extensions never open the SQLite file themselves.

The database stores state for all VS Code features — editor history, panel positions, UI
preferences, debug configurations — as well as chat-session indices when chat extensions
use VS Code's built-in `chatSessionsProvider` proposed API.

**Source**: [VS Code issue #61928](https://github.com/Microsoft/vscode/issues/61928),
[VS Code source `storageService.ts`](https://github.com/microsoft/vscode),
[jeziellegos/vscode-chat-history-fix](https://github.com/jeziellopes/vscode-chat-history-fix)

---

### 14.2 Chat-Related Keys in state.vscdb

The following keys are written to `state.vscdb` when VS Code's **built-in** chat service
is active. They are owned by VS Code core, not by the Copilot extension:

| Key | Written by | Contents |
|-----|-----------|---------|
| `chat.ChatSessionStore.index` | VS Code core chat service | Session metadata dict: title, timing, isEmpty, `isExternal`, `permissionLevel`. **Not the conversation content.** |
| `agentSessions.model.cache` | VS Code core + extension cooperation | Sidebar session list with provider type, resource URI, label, icon, badge, timing, file-change diffs |
| `agentSessions.state.cache` | VS Code core + extension cooperation | Per-session read timestamps (unread badge) |
| `interactive.sessions` | VS Code core (pre-2024) | Legacy: full session content inline — superseded |
| `memento/interactive-session` | VS Code core (pre-2023) | Legacy: full session blob — superseded |

**`chat.ChatSessionStore.index` is a metadata-only index, not a content store.** Actual
conversation content lives in separate JSONL files (see §14.3). A damaged or missing
index entry will make a session invisible in the sidebar even if its JSONL file is intact
on disk — this is the class of bugs fixed by the
[vscode-chat-history-fix](https://github.com/jeziellopes/vscode-chat-history-fix) tool.

**Cross-extension sessions**: `chat.ChatSessionStore.index` can contain entries with
`sessionId: "claude-code:/…"` and `isExternal: true`. These are registered by the Claude
Code extension to make its sessions appear in Copilot's sidebar. Sessions with
`isExternal: true` are known to fail to reload after restart in some VS Code versions
([issue #295745](https://github.com/microsoft/vscode/issues/295745), VS Code 1.109.4).

---

### 14.3 What `chatSessions/` Is

`chatSessions/` is a directory written by **VS Code core's built-in chat service**, not
by the Copilot extension itself:

```
workspaceStorage/<hash>/chatSessions/<uuid>.jsonl    # current format (VS Code ≥ 1.109)
workspaceStorage/<hash>/chatSessions/<uuid>.json     # legacy format (VS Code ≤ 1.108)
```

For sessions opened without a workspace folder:
```
globalStorage/emptyWindowChatSessions/<uuid>.jsonl
```

The Copilot extension participates through the `chatSessionsProvider` **proposed API**:
it supplies content when VS Code asks, but VS Code core's `IChatSessionsService` owns
the directory and writes the files. The extension never writes to `chatSessions/` directly.

**Format history — version transition at VS Code 1.109 (January 2026):**

| Era | VS Code | Format | How written |
|-----|---------|--------|------------|
| ≤ 1.108 | pre-Jan 2026 | `.json` — full session rewritten on every save | Snapshot |
| ≥ 1.109 | Jan 2026+ | `.jsonl` — append-only mutation log | Incremental |

The mutation log entries use `kind` values:
- `kind 0`: Initial session state
- `kind 1`: Property update (title, etc.)
- `kind 2`: Array splice/push (new request/response pair)
- `kind 3`: Delete

When both `.json` and `.jsonl` exist for the same UUID, the `.jsonl` takes priority.
The format change introduced a regression ([issue #291374](https://github.com/microsoft/vscode/issues/291374))
where old JSONL entries from before 2026-01-28 lacked the Iterator protocol required by
the new loader. This was the bug that broke session history in Copilot 0.37.x for
sessions that straddled the format boundary.

**Sources**: [issue #291374](https://github.com/microsoft/vscode/issues/291374),
[issue #291897](https://github.com/microsoft/vscode/issues/291897),
[agentsview gist](https://gist.github.com/cdeil/93ceacbdea17a7e744fb8c6ec95b3d9f)

---

### 14.4 What `GitHub.copilot-chat/transcripts/` Is

`transcripts/` is written by the **Copilot Chat extension itself** using its
`ISessionTranscriptService`. It lives at:

```
workspaceStorage/<hash>/GitHub.copilot-chat/transcripts/<uuid>.jsonl
```

The `GitHub.copilot-chat` subdirectory name comes from the extension's publisher.name,
which VS Code uses as the namespace under `workspaceStorage/<hash>/` for
`context.storageUri`. This is extension-private storage — VS Code core does not read
or write here.

The `ISessionTranscriptService` is called from `toolCallingLoop.ts` in the extension:
- `startSession(sessionId, …)` — creates the file
- `logUserMessage(sessionId, message)` — appends user turns
- `logAssistantTurnStart/End(sessionId, turnId)` — wraps assistant turns

The transcript format is an event log (confirmed by our test, §13.2):
```jsonl
{"type":"session.start","data":{"sessionId":"…","version":1,"producer":"copilot-agent",…}}
{"type":"assistant.message","data":{"messageId":"…","content":"…","toolRequests":[…]},…}
{"type":"tool.execution_start","data":{"toolCallId":"…","toolName":"…","arguments":{…}},…}
{"type":"tool.execution_complete","data":{"toolCallId":"…","success":true},…}
```

The transcript path is also passed as `transcript_path` to Claude Code hooks, enabling
pre/post-compaction processing. A newer experimental feature called "Chronicle" uses
these transcripts to build a local session search index.

**Sources**: [vscode-copilot-chat toolCallingLoop.ts](https://github.com/microsoft/vscode-copilot-chat/blob/main/src/extension/intents/node/toolCallingLoop.ts),
[release v0.37.6 "transcript_path to fsPath"](https://github.com/microsoft/vscode-copilot-chat/releases/tag/v0.37.6),
[issue #310586](https://github.com/microsoft/vscode/issues/310586)

---

### 14.5 Two Parallel Storage Systems — Who Uses Which

The existence of both `chatSessions/` and `transcripts/` creates a picture of two separate
systems that were designed for different purposes and have overlapping lifetimes:

| System | Owner | Used for | Active? |
|--------|-------|---------|---------|
| `chatSessions/` | VS Code core via `chatSessionsProvider` proposed API | Copilot Chat sessions in versions that used the proposed API | Older Copilot versions (≤ ~0.43.x) |
| `GitHub.copilot-chat/transcripts/` | Copilot Chat extension directly | All current Copilot sessions (agent, ask, plan) | Current (≥ ~0.37.6 for transcripts feature; primary from ~0.44+) |

The `chatSessionsProvider` proposed API is the key: when the Copilot extension uses it,
VS Code core manages the `chatSessions/` files. When the extension bypasses this API and
writes directly to its own `context.storageUri`, only `transcripts/` is written.

Research found reports ([issue #310586](https://github.com/microsoft/vscode/issues/310586),
April 2026) of both directories coexisting in VS Code 1.116.0 / Copilot 0.44.0. This
aligns with a transitional period where both the proposed API path and the direct path
were active simultaneously.

---

### 14.6 Version Boundary — When the Architecture Changed

Cross-referencing the research with our test (Copilot 0.47.0), the clearest picture is:

| Version range | Copilot Chat | VS Code | Storage written |
|---------------|-------------|---------|----------------|
| Pre-2024 | ≤ 0.12 | ≤ 1.85 | `state.vscdb` only (inline session blobs: `interactive.sessions`) |
| 2024 – Dec 2025 | 0.13 – 0.36 | 1.86 – 1.108 | `chatSessions/*.json` + `state.vscdb` index (`chat.ChatSessionStore.index`) |
| Jan 2026 | 0.37.x | 1.109 | `chatSessions/*.jsonl` (mutation log) + `state.vscdb` index |
| Apr 2026 | 0.44.0 (built-in in VS Code 1.116) | 1.116 | `chatSessions/*.jsonl` + `transcripts/*.jsonl` (both active, transitional) |
| May 2026+ | 0.47.0 | ≥ 1.117 | `transcripts/*.jsonl` **only** — `chatSessions/` no longer written |

The `0.47.0 → transcripts only` row is **confirmed by direct experiment** (§13). All
prior rows are inferred from research and GitHub issues.

**Why the main devcontainer has both**: the host macOS VS Code is running an older version
of Copilot Chat. The `chatSessions/` files and `state.vscdb` session keys accumulated from
sessions run under that older version. A fresh container running the current marketplace
Copilot (0.47.0) writes only `transcripts/`.

---

### 14.7 Claude Code and state.vscdb

Our test showed that Copilot Chat 0.47.0 + Claude Code 2.1.138 did **not** write
`state.vscdb` at all — not even `agentSessions.model.cache` (§13.5). Yet the main
devcontainer's `state.vscdb` contains `agentSessions.model.cache` entries with Claude Code
sessions at `/workspaces/devfeats`.

The research confirms that `agentSessions.model.cache` is written by a cooperative
mechanism between VS Code core and the extensions. The most likely explanation for the
discrepancy:

1. **The main devcontainer accumulated `state.vscdb` entries from an older Copilot Chat
   version** running on the host. The host's older Copilot Chat used the `chatSessionsProvider`
   API, which triggered VS Code core to create and populate `state.vscdb`.

2. **In the test container**, Copilot 0.47.0 no longer calls the `chatSessionsProvider`
   proposed API. Without that API in use, VS Code core's chat service never activates its
   storage layer, so `state.vscdb` is never created and `agentSessions.model.cache` is
   never written.

3. **`agentSessions.model.cache` entries for Claude Code** come from the Claude Code
   extension registering sessions with Copilot Chat's session registry. In older versions,
   this registration path also triggered a `state.vscdb` write. In the current pairing
   (Copilot 0.47.0 + Claude Code 2.1.138), the registration is entirely in-memory
   (confirmed by §13, Finding 5) — no disk write occurs.

**Known bug**: The Claude Code VS Code extension does NOT write entries to
`~/.claude/history.jsonl` (the CLI session index). This means sessions created through
the VS Code extension are invisible to the `/resume` command in the CLI
([claude-code issue #24579](https://github.com/anthropics/claude-code/issues/24579)).
This is a separate known limitation, unrelated to `state.vscdb`.

---

### 14.8 Hash Stability and Dev Containers

The workspaceStorage hash is an MD5 of the workspace URI. For dev containers, the URI
includes the remote authority string, which encodes the devcontainer configuration. This
means:

- A new container rebuild → new hash → new empty `workspaceStorage/<new-hash>/`
- Sessions under the old hash are unreachable — the UI never scans all hash directories

This is a [documented known issue](https://github.com/microsoft/vscode-remote-release/issues/7669)
without an upstream fix. The workaround is to persist the entire `workspaceStorage/<hash>/`
directory (or specifically `GitHub.copilot-chat/`) under a stable path and recreate the
symlink/directory structure on each container start.

**Note on Windows**: On Windows, the hash also incorporates the folder birthtime as a salt,
making it non-deterministic across rebuilds even for the same path. On Linux (all dev
containers), the hash is deterministic given the same workspace URI. This means a container
whose configuration does not change will always produce the same hash — making persistent
symlinks reliable on Linux.

---

### 14.9 Complete Storage Map (Current: Copilot 0.47.0 + Claude Code 2.1.138)

| Path | Written by | When created | Active? | Required for persistence? |
|------|-----------|-------------|---------|--------------------------|
| `workspaceStorage/<hash>/GitHub.copilot-chat/transcripts/<uuid>.jsonl` | Copilot Chat extension (`ISessionTranscriptService`) | First message sent | **Yes** | **Yes — primary session store** |
| `workspaceStorage/<hash>/GitHub.copilot-chat/debug-logs/<uuid>/` | Copilot Chat extension | Every session | Yes (ephemeral) | No |
| `workspaceStorage/<hash>/state.vscdb` | VS Code core (IStorageService) | When VS Code's `chatSessionsProvider` API is in use | **No** (not written with Copilot 0.47.0) | No |
| `workspaceStorage/<hash>/chatSessions/<uuid>.jsonl` | VS Code core (`IChatSessionsService`) | When `chatSessionsProvider` API is in use | **No** (not written with Copilot 0.47.0) | No |
| `~/.claude/projects/<slug>/<uuid>.jsonl` | Claude Code CLI / SDK | First message sent | **Yes** | **Yes — primary session store** |
| `~/.claude/sessions/<pid>.json` | Claude Code extension | Extension startup | Yes (ephemeral) | No — process tracking only |
| `~/.claude/history.jsonl` | Claude Code CLI only (not the VS Code extension) | CLI sessions | Yes (CLI only) | No — separate CLI feature |
| `globalStorage/github.copilot-chat/` | Copilot Chat extension | Extension startup / on demand | Yes | No |

---

### 14.10 Revised Conclusion on state.vscdb and chatSessions/

**`state.vscdb` — not obsolete globally, but not relevant for us:**
- VS Code core always creates it for non-chat state (editor history, UI preferences, etc.)
- Chat-related keys (`chat.ChatSessionStore.index`, `agentSessions.*`) are written when
  VS Code's built-in `chatSessionsProvider` proposed API is active
- **Current Copilot Chat 0.47.0 does not use this API.** No chat keys are written.
- The main devcontainer's chat keys were written by an older Copilot version on the host.
- **For our persistence design: `state.vscdb` is not a target and not needed.**

**`chatSessions/` — obsolete for our setup:**
- Was the primary Copilot session content store through VS Code ~1.115 / Copilot ~0.43.x
- Superseded by `GitHub.copilot-chat/transcripts/` starting around Copilot 0.44
- Confirmed absent in Copilot 0.47.0 by direct experiment
- **For our persistence design: `chatSessions/` is not a target and not needed.**
- The content described in §4 (kind 0/1/2 mutation log) was accurate for older versions
  but is not the format produced by the current extension.

**`GitHub.copilot-chat/transcripts/` — the actual persistence target:**
- Confirmed by direct experiment as the sole Copilot session store in 0.47.0
- Written by the extension itself, not VS Code core
- Persists across container restarts (sessions appear in sidebar on next startup)
- **For our persistence design: this is the only Copilot target needed.**

Finding 1 in §13.9 remains correct: for our devcontainer environment running current
extension versions, `state.vscdb` session keys and `chatSessions/` are never written.
The earlier analysis in sections 1–12 accurately described an older architecture that
was current at the time it was written but has since been superseded.

