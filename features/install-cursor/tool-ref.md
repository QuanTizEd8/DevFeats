# Feature Reference

Cursor CLI (invoked primarily as `agent`) is Cursor's terminal-native interface for agentic coding workflows, including interactive sessions, non-interactive scripting/CI runs, shell command execution with approval controls, and integration with MCP/ACP-based tooling. It is positioned as the same agent workflow available in the editor, adapted for terminal-first usage.[^cli-homepage][^cli-overview][^cli-using][^cli-params]

From an implementation perspective, Cursor CLI is distributed as prebuilt binaries downloaded by official installer scripts rather than by a documented public source repository or package-manager-first flow. The official installers are lightweight bootstrap scripts (Bash for macOS/Linux/WSL and PowerShell for native Windows) that install user-local binaries, set PATH guidance (or PATH entries on Windows), and rely on runtime configuration in `~/.cursor` and project-local `.cursor` files.[^cli-installation][^install-script-unix][^install-script-win][^cli-config]

- **Homepage**: https://cursor.com/cli[^cli-homepage]
- **Source Code**: Proprietary distribution (no official public Cursor CLI source repository is linked from CLI docs); public installer script sources are available at https://cursor.com/install and https://cursor.com/install?win32=true.[^cli-overview][^cli-installation][^install-script-unix][^install-script-win]
- **Documentation**: https://cursor.com/docs/cli/overview[^cli-overview]
- **Latest Release**: `2026.05.16-0338208` (installer package build identifier embedded in both official installers, as of 2026-05-17).[^install-script-unix][^install-script-win]

## Tool Architecture

Cursor CLI is a prebuilt command-line client that runs as a local executable and communicates with Cursor services for model-backed agent behavior. Its default command experience is interactive (`agent`), with optional non-interactive print mode (`-p/--print`) for automation and CI usage.[^cli-overview][^cli-using][^cli-params][^cli-headless]

The CLI supports multiple operating modes (`agent`, `plan`, `ask`) and can also run in ACP server mode (`agent acp`) over stdio/JSON-RPC for custom client integrations. This means the runtime can operate either as an end-user terminal client or as a protocol endpoint for other tools.[^cli-overview][^cli-using][^cli-params][^cli-acp]

At runtime, behavior is controlled by configuration files and environment variables:

- Global CLI config: `~/.cursor/cli-config.json` (macOS/Linux) or `%USERPROFILE%\.cursor\cli-config.json` (Windows).
- Project-level permissions config: `<project>/.cursor/cli.json`.
- MCP server configs: project-level `.cursor/mcp.json` and global `~/.cursor/mcp.json`.

The CLI also supports plugin and MCP extensibility, including marketplace plugins, local plugin directories, and MCP server registrations.[^cli-config][^cli-permissions][^mcp-docs][^plugins-docs][^cli-params]

## Installation Methods

The official installation surface is installer-script-based, with one documented script path for Unix-like systems (including WSL) and one for native Windows PowerShell. Both scripts download architecture-specific prebuilt packages from `downloads.cursor.com` and install user-local executables.[^cli-installation][^install-script-unix][^install-script-win]

### Official Curl/Bash Installer (macOS, Linux, WSL)

#### Supported Platforms

- Documented: macOS, Linux, and Windows Subsystem for Linux (WSL).[^cli-installation]
- Installer source implementation support: only `Darwin` and `Linux` kernels; unsupported OS values exit with error.[^install-script-unix]
- Architecture support in installer source: `x64` (`x86_64`/`amd64`) and `arm64` (`arm64`/`aarch64`); other architectures exit with error.[^install-script-unix]

#### Dependencies

##### Common Dependencies

- `bash` (script shebang and Bash conditionals/functions).[^install-script-unix]
- `curl` and `tar` for package download and extraction (`curl ... | tar ...`).[^install-script-unix]
- Standard Unix userland tools used directly by script (`uname`, `mkdir`, `mv`, `ln`, `rm`, `basename`, `date`).[^install-script-unix]
- Writable user home for installation targets under `~/.local/share/cursor-agent` and `~/.local/bin`.[^install-script-unix]

##### Platform-Specific Dependencies

- Linux/macOS/WSL: none beyond the shell tooling above is called out by official docs for this path.[^cli-installation][^install-script-unix]

#### Installation Steps

1. Run the official installer:

   ```bash
   curl https://cursor.com/install -fsS | bash
   ```

2. Installer flow (from source):
   - Detects OS/arch.
   - Creates temp extraction dir under `~/.local/share/cursor-agent/versions/.tmp-...`.
   - Downloads `agent-cli-package.tar.gz` from `downloads.cursor.com/lab/<version>/<os>/<arch>/`.
   - Extracts package to temp dir and atomically moves it to `~/.local/share/cursor-agent/versions/<version>`.
   - Ensures `~/.local/bin` exists.
   - Creates `agent` and `cursor-agent` symlinks to the installed `cursor-agent` binary.

3. If `~/.local/bin` is not already on PATH, follow installer-emitted shell-specific instructions (Bash/Zsh/Fish), or manually add it.[^cli-installation][^install-script-unix]

#### Installation Verification

- Run:

  ```bash
  agent --version
  ```

  This is the official verification command in CLI installation docs.[^cli-installation]

- Optional structural verification from installer behavior:

  ```bash
  command -v agent
  ls -l ~/.local/bin/agent ~/.local/bin/cursor-agent
  ```

  Expected: both symlinks exist and point to `~/.local/share/cursor-agent/versions/<version>/cursor-agent`.[^install-script-unix]

#### Configuration Options

##### Version Selection

- The official Bash installer itself does not expose a documented version parameter; it installs the version embedded in the served script's download URL template.[^cli-installation][^install-script-unix]
- Ongoing updates are handled by CLI auto-update behavior and the `agent update` command.[^cli-installation][^cli-params]

##### Installation Path

- Script-defined install paths are user-local and fixed by the script:
  - Package dir: `~/.local/share/cursor-agent/versions/<version>`
  - Command symlinks: `~/.local/bin/agent` and `~/.local/bin/cursor-agent`
- No official installer flag is documented to override these paths.[^install-script-unix][^cli-installation]

##### User Targeting

- User-local installation by design (`$HOME` paths only).[^install-script-unix]
- No documented system-wide mode in this installer path.[^cli-installation][^install-script-unix]

##### Required Privileges

- Root/sudo is not required by default because installation targets are within the invoking user's home directory.[^install-script-unix]

##### Tool-Specific Configurations

- Authentication:
  - Browser login flow: `agent login`.
  - API key methods: `CURSOR_API_KEY` env var or `--api-key` flag.[^cli-auth][^cli-params]
- CLI configuration file:
  - Global: `~/.cursor/cli-config.json`
  - Project: `<project>/.cursor/cli.json` (permissions-only at project scope)
  - Config directory overrides: `CURSOR_CONFIG_DIR`, `XDG_CONFIG_HOME`.[^cli-config]
- Permission model (`allow`/`deny`) supports `Shell(...)`, `Read(...)`, `Write(...)`, `WebFetch(...)`, `Mcp(server:tool)` tokens.[^cli-permissions]
- Proxy and enterprise network settings:
  - `HTTP_PROXY`, `HTTPS_PROXY`, `NODE_USE_ENV_PROXY`, optional `NODE_EXTRA_CA_CERTS`
  - Config fallback `network.useHttp1ForAgent` for HTTP/2-incompatible proxy environments.[^cli-config]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Official docs and installer both rely on exposing the installed command through PATH.
- Unix installer expects `~/.local/bin` on PATH and prints shell-specific append/source snippets when missing.[^cli-installation][^install-script-unix]

##### Configuration Files

- CLI config files:
  - `~/.cursor/cli-config.json`
  - `<project>/.cursor/cli.json` (permissions-only scope)
- MCP config files:
  - `~/.cursor/mcp.json`
  - `<project>/.cursor/mcp.json`.[^cli-config][^mcp-docs]

##### Environment Variables

- Common variables:
  - `CURSOR_API_KEY`
  - `CURSOR_CONFIG_DIR`
  - `XDG_CONFIG_HOME`
  - `HTTP_PROXY`, `HTTPS_PROXY`, `NODE_USE_ENV_PROXY`, `NODE_EXTRA_CA_CERTS`.[^cli-auth][^cli-config][^cli-params]

##### Activation Scripts

- Shell integration commands are available:

  ```bash
  agent install-shell-integration
  agent uninstall-shell-integration
  ```

  Command reference indicates installation to `~/.zshrc` for shell integration command behavior.[^cli-params]

##### Cleanup

- Installer script registers a trap to remove its temporary extraction directory on exit.[^install-script-unix]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Official behavior:
  - CLI attempts auto-update by default.
  - Manual update command: `agent update`.[^cli-installation][^cli-params]
- No documented official downgrade flag exists in installation docs for the Unix installer path.[^cli-installation]

##### Uninstallation

- No dedicated `agent uninstall` command is documented.[^cli-params]
- Script-derived manual uninstall flow:

  ```bash
  rm -f ~/.local/bin/agent ~/.local/bin/cursor-agent
  rm -rf ~/.local/share/cursor-agent
  ```

  Optionally remove CLI config/state directory if full local reset is desired:

  ```bash
  rm -rf ~/.cursor
  ```

  PATH cleanup should remove any manually added `~/.local/bin` export lines if they were added specifically for Cursor CLI.[^install-script-unix][^cli-installation][^cli-config]

##### Idempotency

- Re-running the same installer script version is idempotent for that version:
  - Deletes and replaces the current `FINAL_DIR` for that version.
  - Recreates both command symlinks.
- The script only removes the current target version directory, so previously installed different version directories (if present) are not explicitly pruned by this script.[^install-script-unix]

#### Notes and Best Practices

- Official Unix installer currently performs HTTPS download and extraction but does not perform explicit checksum/signature validation in-script before extraction; feature implementers should add independent integrity checks when reproducibility/supply-chain assurance is required.[^install-script-unix]
- Architecture and OS gating are strict in the installer; preflight checks in feature logic should mirror this behavior for clearer errors (`linux|darwin` + `x64|arm64`).[^install-script-unix]
- Official GitHub Actions documentation currently demonstrates adding `$HOME/.cursor/bin` to `GITHUB_PATH`, while the public Unix installer script installs command shims in `~/.local/bin`; treat PATH setup as a behavior to verify in CI images instead of assuming one canonical path in all contexts.[^cli-github-actions][^install-script-unix]

### Official PowerShell Installer (Windows Native)

#### Supported Platforms

- Documented: native Windows via PowerShell installer command.[^cli-installation]
- Script architecture support: Windows `x64` and `arm64` (detected from `Win32_ComputerSystem`).[^install-script-win]

#### Dependencies

##### Common Dependencies

- PowerShell runtime with support for:
  - `Invoke-WebRequest`
  - `Expand-Archive`
  - `Get-WmiObject`
  - environment variable mutation APIs (`[Environment]::SetEnvironmentVariable`).[^install-script-win]
- Writable `%LOCALAPPDATA%` location for user-level installation.[^install-script-win]

##### Platform-Specific Dependencies

- Windows only; installer endpoint and script are native PowerShell-specific.[^cli-installation][^install-script-win]

#### Installation Steps

1. Run:

   ```powershell
   irm 'https://cursor.com/install?win32=true' | iex
   ```

2. Installer flow (from source):
   - Initializes `%LOCALAPPDATA%\cursor-agent` and `%LOCALAPPDATA%\cursor-agent\versions`.
   - Removes any existing `%LOCALAPPDATA%\cursor-agent` directory first.
   - Adds `%LOCALAPPDATA%\cursor-agent` to user PATH and current process PATH.
   - Downloads architecture-specific ZIP from `downloads.cursor.com/lab/<version>/windows/<arch>/agent-cli-package.zip`.
   - Expands archive to versions directory, renames `dist-package` to version folder.
   - Copies `cursor-agent*` launcher files up to `%LOCALAPPDATA%\cursor-agent` and creates `agent*` aliases (`.exe`, `.cmd`, `.ps1`) by copying files.[^cli-installation][^install-script-win]

#### Installation Verification

- Run:

  ```powershell
  agent --version
  ```

  This is the same official verification command used in installation docs.[^cli-installation]

- Optional file-level validation:

  ```powershell
  Test-Path "$env:LOCALAPPDATA\cursor-agent\agent.exe"
  Test-Path "$env:LOCALAPPDATA\cursor-agent\cursor-agent.exe"
  ```

  Expected: `True` for installed launchers.[^install-script-win]

#### Configuration Options

##### Version Selection

- No documented installer parameter for selecting a specific version in the Windows install command; script embeds a specific version string and download prefix.[^cli-installation][^install-script-win]
- Updates are managed by auto-update behavior and `agent update` command.[^cli-installation][^cli-params]

##### Installation Path

- Fixed user-level paths in script:
  - Root: `%LOCALAPPDATA%\cursor-agent`
  - Versions: `%LOCALAPPDATA%\cursor-agent\versions\<version>`.[^install-script-win]

##### User Targeting

- User-scoped installation only (uses user `LOCALAPPDATA` and user PATH variable).[^install-script-win]

##### Required Privileges

- Administrator privileges are not required by script design for default user-local installation path and user PATH updates.[^install-script-win]

##### Tool-Specific Configurations

- Same runtime configuration/authentication model as other platforms:
  - `agent login`, `CURSOR_API_KEY`, `--api-key`
  - `%USERPROFILE%\.cursor\cli-config.json` global config
  - `<project>/.cursor/cli.json` project-level permissions
  - MCP configuration and approvals via `.cursor/mcp.json` and CLI commands.[^cli-auth][^cli-config][^cli-permissions][^mcp-docs][^cli-params]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- PowerShell installer updates both user PATH and current session PATH to include `%LOCALAPPDATA%\cursor-agent`.[^install-script-win]

##### Configuration Files

- Windows global config path: `%USERPROFILE%\.cursor\cli-config.json`.
- Project permissions file: `<project>/.cursor/cli.json`.
- MCP configs follow same `.cursor/mcp.json` conventions (project/global).[^cli-config][^mcp-docs]

##### Environment Variables

- Key runtime variable options remain the same:
  - `CURSOR_API_KEY`
  - proxy/network vars where relevant (`HTTP_PROXY`, `HTTPS_PROXY`, `NODE_USE_ENV_PROXY`, `NODE_EXTRA_CA_CERTS`).[^cli-auth][^cli-config][^cli-params]

##### Activation Scripts

- No dedicated Windows-specific activation script step is required by installer; PATH updates are handled during install.[^install-script-win]

##### Cleanup

- Installer removes its temporary ZIP file in a `finally` block after extraction.[^install-script-win]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Official update model:
  - auto-update enabled by default
  - manual update via `agent update`.[^cli-installation][^cli-params]
- No explicit documented downgrade flag for installer invocation.[^cli-installation]

##### Uninstallation

- No documented dedicated CLI uninstall command exists.[^cli-params]
- Script-derived manual uninstall approach:

  ```powershell
  Remove-Item -Recurse -Force "$env:LOCALAPPDATA\cursor-agent"
  ```

  Then remove `%LOCALAPPDATA%\cursor-agent` from user PATH if still present; optionally remove `%USERPROFILE%\.cursor` for full config/state reset.[^install-script-win][^cli-config]

##### Idempotency

- Windows installer reinitialization is strongly idempotent but destructive for prior install state:
  - `Initialize-CursorAgent` removes `%LOCALAPPDATA%\cursor-agent` before reinstallation.
  - Recreates directory tree and launchers each run.[^install-script-win]

#### Notes and Best Practices

- Because the script recreates `%LOCALAPPDATA%\cursor-agent` each run, custom files placed there by users or automation should be treated as ephemeral and stored elsewhere.[^install-script-win]
- As with Unix installer path, script downloads binaries over HTTPS but does not expose checksum/signature verification steps in the public installer source; add explicit verification controls in managed enterprise feature workflows.[^install-script-win]

## Dev Container Setup

For devcontainer usage, Cursor CLI is typically installed in Linux containers via the same official Unix installer command, then exposed on PATH for the container user.[^cli-installation][^install-script-unix]

Recommended container-oriented setup pattern:

1. Install CLI during image build.
2. Ensure user PATH includes the install location (`~/.local/bin` for the user that will run the CLI).
3. Provide authentication through environment/secret management (`CURSOR_API_KEY`) or interactive login in trusted environments.
4. Use project-level permissions (`.cursor/cli.json`) and MCP configs (`.cursor/mcp.json`) to enforce deterministic behavior in CI and shared dev environments.[^cli-installation][^cli-auth][^cli-config][^cli-permissions][^mcp-docs][^cli-headless][^cli-github-actions]

For CI/headless flows inside containers, use print mode and machine-readable output formats (`--output-format json` or `--output-format stream-json`) with explicit permission strategy (`--force` where intended, or policy-backed allow/deny config) to avoid interactive prompts.[^cli-headless][^cli-output-format][^cli-params][^cli-permissions]

## Plugins and Extensions

Cursor CLI supports the same broader Cursor ecosystem for plugins/rules/skills/agents/hooks/MCP integrations, with two primary operational paths for CLI users:[^plugins-docs][^mcp-docs][^cli-using][^cli-params]

### Marketplace and Local Plugins

- Plugins can package rules, skills, agents, commands, MCP server definitions, and hooks.
- Official plugin discovery/install path is the Cursor Marketplace.
- CLI also supports local plugin loading through `--plugin-dir <path>` (repeatable) for explicit plugin directories at invocation time.[^plugins-docs][^cli-params]

### MCP Servers and Tooling Extensions

- MCP servers are configured in project/global `.cursor/mcp.json` files.
- CLI command group `agent mcp ...` supports listing/enabling/disabling servers and related login flows.
- Permission tokens (`Mcp(server:tool)`) allow restricting/allowlisting MCP tool execution in policy-driven environments.[^mcp-docs][^cli-params][^cli-permissions]

## References

[^cli-homepage]: [Cursor CLI product page](https://cursor.com/cli) — official landing page for Cursor CLI usage model and install entrypoint.
[^cli-overview]: [Cursor Docs — CLI Overview](https://cursor.com/docs/cli/overview) — authoritative high-level behavior, modes, and basic usage examples.
[^cli-installation]: [Cursor Docs — CLI Installation](https://cursor.com/docs/cli/installation) — official installer commands, verification, and update guidance.
[^cli-using]: [Cursor Docs — Using Agent in CLI](https://cursor.com/docs/cli/using) — runtime behavior, worktrees, history, and non-interactive usage details.
[^cli-params]: [Cursor Docs — CLI Parameters](https://cursor.com/docs/cli/reference/parameters) — command/flag reference, including update and integration commands.
[^cli-auth]: [Cursor Docs — CLI Authentication](https://cursor.com/docs/cli/reference/authentication) — login/API key flows and auth troubleshooting.
[^cli-config]: [Cursor Docs — CLI Configuration](https://cursor.com/docs/cli/reference/configuration) — config file locations/schema and environment overrides.
[^cli-permissions]: [Cursor Docs — CLI Permissions](https://cursor.com/docs/cli/reference/permissions) — policy token model and allow/deny semantics.
[^cli-terminal-setup]: [Cursor Docs — Terminal Setup](https://cursor.com/docs/cli/reference/terminal-setup) — terminal behavior, keybinding setup, and Vim mode configuration.
[^cli-shell-mode]: [Cursor Docs — Shell Mode](https://cursor.com/docs/cli/shell-mode) — shell execution constraints and timeout semantics.
[^cli-headless]: [Cursor Docs — Headless CLI](https://cursor.com/docs/cli/headless) — non-interactive script/automation guidance.
[^cli-github-actions]: [Cursor Docs — GitHub Actions](https://cursor.com/docs/cli/github-actions) — CI integration patterns and secret usage.
[^cli-output-format]: [Cursor Docs — Output Format](https://cursor.com/docs/cli/reference/output-format) — machine-readable print output contracts.
[^cli-acp]: [Cursor Docs — ACP](https://cursor.com/docs/cli/acp) — ACP transport/protocol behavior and integration model.
[^plugins-docs]: [Cursor Docs — Plugins](https://cursor.com/docs/plugins) — plugin packaging, marketplace distribution, and local loading model.
[^mcp-docs]: [Cursor Docs — MCP](https://cursor.com/docs/mcp) — MCP configuration, transport modes, auth, and usage model.
[^install-script-unix]: [Cursor official Unix installer script](https://cursor.com/install) — source of OS/arch checks, download URL, install paths, symlink behavior, and cleanup logic.
[^install-script-win]: [Cursor official Windows installer script](https://cursor.com/install?win32=true) — source of Windows download/install paths, PATH mutation, alias file generation, and idempotency behavior.
[^devcontainers-extra-claude-install]: [devcontainers-extra/features — claude-code install.sh](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/claude-code/install.sh) — similar feature implementation using upstream installer and global launcher copy.
[^devcontainers-extra-claude-bootstrap]: [devcontainers-extra/features — claude-code bootstrap.sh](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/claude-code/bootstrap.sh) — analogous installer with checksum validation and platform detection logic.
[^devcontainers-extra-claude-feature-json]: [devcontainers-extra/features — claude-code devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/claude-code/devcontainer-feature.json) — comparable feature options/customizations surface.
[^collection-index]: [devcontainers collection index](https://raw.githubusercontent.com/devcontainers/devcontainers.github.io/refs/heads/gh-pages/_data/collection-index.yml) — catalog used to identify related AI-agent devcontainer feature ecosystems.
[^dc-features-search-cursor]: [GitHub code search — devcontainers/features for "cursor"](https://github.com/devcontainers/features/search?q=cursor&type=code) — reference search for comparable first-party feature implementations.
[^dc-extra-search-cursor]: [GitHub code search — devcontainers-extra/features for "cursor"](https://github.com/devcontainers-extra/features/search?q=cursor&type=code) — reference search in major community feature collection.
[^dc-community-search-cursor]: [GitHub code search — devcontainer-community/devcontainer-features for "cursor"](https://github.com/devcontainer-community/devcontainer-features/search?q=cursor&type=code) — reference search in community collection.