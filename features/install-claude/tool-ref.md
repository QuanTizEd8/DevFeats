# Feature Reference

Claude Code (often referred to as the Claude CLI) is Anthropic's terminal-first coding assistant. It combines conversational prompting with direct tooling, including file reads/edits, shell command execution, git workflows, and integrations through MCP servers and IDE extensions.[^docs-setup][^repo-readme]

Operationally, Claude Code is distributed as platform-specific native binaries (macOS, Linux, Windows, x64/ARM64, including musl variants) and can be installed through multiple channels: Anthropic's native bootstrap installers, package managers (Homebrew, WinGet, apt/dnf/apk), and npm global installation. The same CLI state and settings live under the Claude config directory (`~/.claude` by default) across these channels.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd][^docs-env]

- **Homepage**: https://claude.ai/claude-code
- **Source Code**: https://github.com/anthropics/claude-code
- **Documentation**: https://code.claude.com/docs/en/overview
- **Latest Release**: 2.1.143 (as of 2026-05-17)[^release-latest][^npm-latest]

## Tool Architecture

Claude Code is delivered as a native executable per OS/architecture target. The release channel publishes platform artifacts (for example, `claude-linux-x64.tar.gz`, `claude-win32-x64.zip`), and the npm package references matching per-platform optional dependencies rather than running the CLI inside Node at runtime.[^release-latest][^npm-latest][^docs-setup]

The native bootstrap installers (`install.sh`, `install.ps1`, `install.cmd`) resolve the latest installer version, download a manifest, verify checksums, fetch a platform binary, and execute `claude install` to perform launcher/shell integration. This makes the bootstrap a thin verified downloader around the native `claude` installer workflow.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

Configuration and state are file-based. By default, Claude Code stores credentials, settings, history, and session data under `~/.claude` (override via `CLAUDE_CONFIG_DIR`), with JSON settings layered by scope (user/project/local/managed).[^docs-env][^docs-settings][^docs-setup]

## Installation Methods

Claude Code supports three primary installation families relevant to this feature: native bootstrap installers, OS package-manager installs, and npm global install. Anthropic currently recommends native installers as the default path in project docs.[^docs-setup][^repo-readme]

### Native Bootstrap Installer (`install.sh`, `install.ps1`, `install.cmd`)

#### Supported Platforms

- macOS, Linux, and WSL via `curl -fsSL https://claude.ai/install.sh | bash`.[^docs-setup]
- WSL support is specifically documented for WSL 2; WSL 1 is marked unsupported.[^docs-setup]
- Windows PowerShell via `irm https://claude.ai/install.ps1 | iex` and Windows CMD via `install.cmd` bootstrap.[^docs-setup]
- System requirements include macOS 13+, Windows 10 1809+/Server 2019+, Ubuntu 20.04+, Debian 10+, Alpine 3.19+, x64/ARM64, and 4 GB+ RAM.[^docs-setup]
- POSIX bootstrap script itself explicitly rejects Windows and performs Darwin/Linux detection; Windows support is provided by PowerShell/CMD bootstraps.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Dependencies

##### Common Dependencies

- Network access to Anthropic distribution endpoints is required.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
- `curl` or `wget` is required for POSIX bootstrap downloads.[^src-bootstrap-sh]
- `jq` is optional in POSIX bootstrap; fallback JSON parsing is built in.[^src-bootstrap-sh]

##### Platform-Specific Dependencies

- Alpine/musl setups require `libgcc`, `libstdc++`, and `ripgrep`, with `USE_BUILTIN_RIPGREP=0` recommended in settings.[^docs-setup]
- Windows bootstrap relies on PowerShell web cmdlets (`Invoke-RestMethod`/`Invoke-WebRequest`) or `curl` + `certutil` in CMD mode.[^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Installation Steps

1. Run the native install command for your shell/OS:[^docs-setup]

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

```powershell
irm https://claude.ai/install.ps1 | iex
```

```bat
curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd
```

2. Bootstrap validates target parameter (`stable`, `latest`, or semver), detects platform/arch, downloads latest installer metadata, verifies checksum, runs `claude install`, and removes temporary downloaded installer binary.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
3. Launch Claude Code from the terminal in your project directory with `claude` and complete authentication.[^docs-setup]

#### Installation Verification

- Basic verification: `claude --version`.[^docs-setup]
- Diagnostic verification: `claude doctor`.[^docs-setup]
- Supply-chain verification guidance includes signed manifest validation (available from release `2.1.89` onward), signing-key fingerprint checks, and platform code-signature verification guidance for macOS and Windows.[^docs-setup]

#### Configuration Options

##### Version Selection

- Native installer accepts `latest` (default), `stable`, or explicit version argument for all bootstrap variants.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Installation Path

- Bootstraps stage downloaded binaries in `~/.claude/downloads` (or `%USERPROFILE%\.claude\downloads` on Windows scripts) before calling `claude install`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
- Native uninstall docs indicate installed launcher/binaries under `~/.local/bin` and runtime files under `~/.local/share/claude` for POSIX systems.[^docs-setup]

##### User Targeting

- Native install is primarily user-local (home-directory scoped), not system-wide package-manager managed.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Required Privileges

- Native Windows path does not require Administrator privileges in normal flow.[^docs-setup]
- POSIX native install path does not document `sudo` as required for standard user-local installation.[^docs-setup]

##### Tool-Specific Configurations

- Update behavior controls: `autoUpdatesChannel`, `minimumVersion`, `DISABLE_AUTOUPDATER`, `DISABLE_UPDATES`.[^docs-setup][^docs-settings][^docs-env]
- Windows shell controls: `CLAUDE_CODE_GIT_BASH_PATH`, `CLAUDE_CODE_USE_POWERSHELL_TOOL`.[^docs-setup][^docs-env]
- Config root relocation: `CLAUDE_CONFIG_DIR`.[^docs-env][^docs-setup]
- Privacy/network control for enterprise setups includes `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` and related env settings.[^docs-env][^docs-devcontainer]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- `claude install` is invoked by all bootstraps to handle launcher and shell integration.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Configuration Files

- Primary settings are JSON files in user/project/local scopes (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`).[^docs-settings]

##### Environment Variables

- Claude Code supports extensive environment-variable configuration (`env-vars` reference), including auth, updater, networking, telemetry, and path behavior.[^docs-env]

##### Activation Scripts

- No manual activation script is required in normal native flow; bootstrap delegates shell integration to `claude install`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Cleanup

- Bootstrap installers remove temporary downloaded installer artifacts after install attempt.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Upgrade in place with `claude update`.[^docs-setup]
- Change release channel via `autoUpdatesChannel` (`latest`/`stable`) and optionally pin `minimumVersion` floor.[^docs-setup][^docs-settings]
- Re-run bootstrap with target argument (`stable` or explicit version) to install a different target build.[^docs-setup]

##### Uninstallation

- Native uninstall commands remove installed binaries/state paths; additional commands remove `~/.claude`, `.claude`, and `.mcp.json` data if full cleanup is desired.[^docs-setup]

##### Idempotency

- Re-running bootstrap is effectively idempotent at workflow level: it re-resolves installer version, verifies checksums, invokes `claude install`, and removes temp downloads without requiring manual pre-clean.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Notes and Best Practices

- Prefer signed-manifest verification for manual binary trust checks, especially in controlled or air-gapped deployments.[^docs-setup]
- On Alpine/musl, install required libs and disable builtin ripgrep fallback mismatch issues with `USE_BUILTIN_RIPGREP=0`.[^docs-setup]

### OS Package Manager Installation (Homebrew, WinGet, apt, dnf, apk)

#### Supported Platforms

- Homebrew: macOS/Linux environments with Homebrew available.[^docs-setup]
- WinGet: Windows environments with winget available.[^docs-setup]
- apt: Debian/Ubuntu; dnf: Fedora/RHEL; apk: Alpine.[^docs-setup]

#### Dependencies

##### Common Dependencies

- Appropriate package manager installed and configured for host OS.[^docs-setup]
- Network access to package and key repositories.[^docs-setup]

##### Platform-Specific Dependencies

- Linux package-manager setup requires adding Anthropic repository signing keys (`claude-code.asc` for apt/dnf, `claude-code.rsa.pub` for apk).[^docs-setup]

#### Installation Steps

Homebrew:[^docs-setup]

```bash
brew install --cask claude-code
```

WinGet:[^docs-setup]

```powershell
winget install Anthropic.ClaudeCode
```

apt (Debian/Ubuntu):[^docs-setup]

```bash
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" | sudo tee /etc/apt/sources.list.d/claude-code.list
sudo apt update
sudo apt install claude-code
```

dnf (Fedora/RHEL):[^docs-setup]

```bash
sudo tee /etc/yum.repos.d/claude-code.repo <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
EOF
sudo dnf install claude-code
```

apk (Alpine):[^docs-setup]

```sh
wget -O /etc/apk/keys/claude-code.rsa.pub https://downloads.claude.ai/keys/claude-code.rsa.pub
echo "https://downloads.claude.ai/claude-code/apk/stable" >> /etc/apk/repositories
apk add claude-code
```

#### Installation Verification

- Run `claude --version` and optionally `claude doctor`.[^docs-setup]
- Follow package-manager key verification guidance before trusting repository configuration (including the explicit apt fingerprint check documented by Anthropic).[^docs-setup]

#### Configuration Options

##### Version Selection

- Homebrew channel selection is cask-based: `claude-code` (stable) vs `claude-code@latest` (latest).[^docs-setup]
- Linux repo channel selection uses repository path/suite (`stable` vs `latest`).[^docs-setup]

##### Installation Path

- Binary/install paths are package-manager managed and generally system-standard for each manager.[^docs-setup]

##### User Targeting

- apt/dnf/apk flows are system-package installations, while Homebrew and WinGet are typically run in user-context package-manager workflows.[^docs-setup]

##### Required Privileges

- apt and dnf commands require elevated privileges (`sudo`).[^docs-setup]
- Homebrew and WinGet are typically run in user context, with privilege requirements dependent on local policy/configuration.[^docs-setup]

##### Tool-Specific Configurations

- `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` enables background package-manager auto-upgrade for Homebrew and WinGet only; apt/dnf/apk remain manual-update flows by design.[^docs-setup][^docs-env]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Package managers place launcher in standard executable locations; no extra PATH steps are documented in standard flows.[^docs-setup]

##### Configuration Files

- Runtime settings remain the same Claude settings/config files as other methods (`~/.claude`, project `.claude/`).[^docs-settings]

##### Environment Variables

- Same environment-variable controls as native install apply after package-manager install.[^docs-env]

##### Activation Scripts

- No explicit activation script step is documented for package-manager installs.[^docs-setup]

##### Cleanup

- Homebrew note: run `brew cleanup` periodically after upgrades to reclaim disk space.[^docs-setup]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Homebrew: `brew upgrade claude-code` or `brew upgrade claude-code@latest`.[^docs-setup]
- WinGet: `winget upgrade Anthropic.ClaudeCode`.[^docs-setup]
- apt: `sudo apt update && sudo apt upgrade claude-code`.[^docs-setup]
- dnf: `sudo dnf upgrade claude-code`.[^docs-setup]
- apk: `apk update && apk upgrade claude-code`.[^docs-setup]

##### Uninstallation

- Homebrew, WinGet, apt, dnf, apk uninstall/remove commands are documented with repository cleanup steps for Linux package-manager methods.[^docs-setup]

##### Idempotency

- Package managers are transaction/state-aware and handle repeated install/upgrade commands without requiring manual cleanup of previous state.[^docs-setup]

#### Notes and Best Practices

- For reproducibility, be explicit about channel selection (`stable` vs `latest`) and key verification in provisioning scripts.[^docs-setup]
- Expect occasional lag between upstream release notification and package-manager availability (known issue noted in official docs).[^docs-setup]

### npm Global Installation (`@anthropic-ai/claude-code`)

#### Supported Platforms

- Supported npm binary targets: `darwin-arm64`, `darwin-x64`, `linux-x64`, `linux-arm64`, `linux-x64-musl`, `linux-arm64-musl`, `win32-x64`, `win32-arm64`.[^docs-setup]

#### Dependencies

##### Common Dependencies

- Node.js 18+ and npm are required.[^docs-setup][^npm-latest]
- npm must allow optional dependencies because platform binary packages are optional deps.[^docs-setup][^npm-latest]

##### Platform-Specific Dependencies

- Platform matching is handled by optional dependency selection during npm install.[^docs-setup][^npm-latest]

#### Installation Steps

```bash
npm install -g @anthropic-ai/claude-code
```

The npm package's postinstall step links the native executable into place; runtime CLI execution is native binary, not a Node runtime shim.[^docs-setup][^npm-latest]

#### Installation Verification

- Verify command availability and version with `claude --version`.[^docs-setup]

#### Configuration Options

##### Version Selection

- Install latest explicitly: `npm install -g @anthropic-ai/claude-code@latest`.[^docs-setup]
- Pin version: `npm install -g @anthropic-ai/claude-code@X.Y.Z`.[^docs-setup]

##### Installation Path

- Install location follows npm global prefix/bin conventions for the current user/environment.[^docs-setup][^npm-latest]

##### User Targeting

- Intended as global npm install under current user environment; avoid privileged sudo installs.[^docs-setup]

##### Required Privileges

- Official docs explicitly warn against `sudo npm install -g` due to permission/security risks.[^docs-setup]

##### Tool-Specific Configurations

- Same Claude runtime settings/env vars apply after npm installation as with other channels.[^docs-env][^docs-settings]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure npm global bin directory is in PATH if `claude` is not found (standard npm global prerequisite).[^docs-setup]

##### Configuration Files

- Uses the same Claude config locations (`~/.claude`, `.claude/`, `.mcp.json`) as other install methods.[^docs-setup][^docs-settings]

##### Environment Variables

- Managed through shell or `settings.json` `env` stanza, as documented in env vars reference.[^docs-env][^docs-settings]

##### Activation Scripts

- No additional activation step is documented for npm installs beyond verifying `claude --version` and running `claude`.[^docs-setup]

##### Cleanup

- npm cleanup/removal is documented through `npm uninstall -g @anthropic-ai/claude-code`, with optional broader Claude config cleanup covered in the uninstall section.[^docs-setup]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Use explicit reinstall with version/tag (`@latest` or pinned version).
- Official docs advise avoiding `npm update -g` because semver range constraints may not move to newest release.[^docs-setup]

##### Uninstallation

```bash
npm uninstall -g @anthropic-ai/claude-code
```

[^docs-setup]

##### Idempotency

- Re-running npm install updates package state in place according to requested version/specifier and npm semantics.[^docs-setup][^npm-latest]

#### Notes and Best Practices

- Anthropic repository README marks npm installation as deprecated in favor of native/package-manager paths; docs still document npm as an available advanced option.[^repo-readme][^docs-setup]

## Dev Container Setup

The official Dev Container integration path is Anthropic's feature image reference:

```json
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
  }
}
```

[^docs-devcontainer]

Key implementation and operational notes:

- Feature tag pins the feature installer implementation, not the Claude Code CLI version; by default, feature install resolves latest CLI and normal CLI auto-update behavior still applies.[^docs-devcontainer]
- For reproducible CLI pinning, docs recommend installing pinned npm version in Dockerfile (`npm install -g @anthropic-ai/claude-code@X.Y.Z`) and setting `DISABLE_AUTOUPDATER`.[^docs-devcontainer]
- Persist `~/.claude` using named volume mounts and optionally set `CLAUDE_CONFIG_DIR` if using non-default mount paths.[^docs-devcontainer]
- Use `containerEnv` for policy-related env settings (for example, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_AUTOUPDATER`).[^docs-devcontainer]
- Running with `--dangerously-skip-permissions` in containers still requires strict trust/network controls; docs strongly warn against assuming complete isolation.[^docs-devcontainer]

Comparison with established feature implementations:

- Anthropic official feature (`anthropics/devcontainer-features`) exposes no custom options, installs after Node feature, adds VS Code extension customization, and install script can bootstrap Node via apt/apk/dnf/yum when absent before `npm install -g @anthropic-ai/claude-code`.[^anth-feature-json][^anth-feature-install]
- devcontainers-extra feature exposes a `version` option, uses a vendored bootstrap script, and then copies installed `claude` from `$HOME/.local/bin` into `/usr/local/bin` in its install script.[^extra-feature-json][^extra-feature-install][^extra-bootstrap]
- The containers.dev collection index includes Anthropic's dedicated Claude Code Feature entry, confirming ecosystem visibility of this install channel.[^collection-index]

## Plugins and Extensions

### VS Code Extension (`anthropic.claude-code`)

The VS Code extension is the recommended IDE experience for Claude Code in VS Code. It provides a native panel UI, inline diff review/approval, session management, and command workflows while sharing the same core CLI capabilities and settings model.[^docs-vscode]

- Prerequisite: VS Code 1.98.0+.[^docs-vscode]
- Install sources: VS Code Marketplace/Open VSX (for compatible forks) with extension ID `anthropic.claude-code`.[^docs-vscode]
- Interop: extension includes/uses CLI functionality; running `claude` in integrated terminal remains supported and shares history/configuration expectations.[^docs-vscode]

### Claude Code Plugin System

Claude Code supports plugins and marketplaces controlled through settings and `/plugin` workflows (`enabledPlugins`, `extraKnownMarketplaces`, and managed restrictions such as `strictKnownMarketplaces`).[^docs-settings][^repo-readme]

- Plugin operations are available from both CLI and IDE-connected workflows (with shared underlying configuration state).[^docs-vscode][^docs-settings]
- For managed/enterprise usage, plugin marketplace and plugin enablement can be policy-controlled through managed settings precedence.[^docs-settings]

## References

[^docs-setup]: [Claude Code Docs - Advanced setup](https://code.claude.com/docs/en/setup) - Official system requirements, install/update/uninstall methods, package-manager commands, and signing guidance.
[^docs-env]: [Claude Code Docs - Environment variables](https://code.claude.com/docs/en/env-vars) - Complete environment-variable reference including updater, path, privacy, and provider controls.
[^docs-settings]: [Claude Code Docs - Settings](https://code.claude.com/docs/en/settings) - Settings hierarchy, scope behavior, and keys such as `autoUpdatesChannel` and `minimumVersion`.
[^docs-devcontainer]: [Claude Code Docs - Development containers](https://code.claude.com/docs/en/devcontainer) - Official devcontainer integration guidance, persistence, policy, and hardening notes.
[^docs-vscode]: [Claude Code Docs - Use Claude Code in VS Code](https://code.claude.com/docs/en/vs-code) - Extension capabilities, prerequisites, and installation details.
[^src-bootstrap-sh]: [Claude native bootstrap installer (POSIX)](https://downloads.claude.ai/claude-code-releases/bootstrap.sh) - Installer source showing platform detection, checksum verification, and `claude install` invocation.
[^src-bootstrap-ps1]: [Claude native bootstrap installer (PowerShell)](https://downloads.claude.ai/claude-code-releases/bootstrap.ps1) - Windows PowerShell bootstrap source.
[^src-bootstrap-cmd]: [Claude native bootstrap installer (CMD)](https://downloads.claude.ai/claude-code-releases/bootstrap.cmd) - Windows CMD bootstrap source.
[^release-latest]: [GitHub API - anthropics/claude-code latest release](https://api.github.com/repos/anthropics/claude-code/releases/latest) - Latest stable release tag and publish timestamp.
[^npm-latest]: [npm registry - @anthropic-ai/claude-code latest](https://registry.npmjs.org/@anthropic-ai/claude-code/latest) - Published npm version metadata, engines, and optional binary dependency matrix.
[^repo-readme]: [anthropics/claude-code README](https://raw.githubusercontent.com/anthropics/claude-code/main/README.md) - Official repository overview and install-path recommendation notes (including npm deprecation note).
[^anth-feature-json]: [anthropics/devcontainer-features `src/claude-code/devcontainer-feature.json`](https://raw.githubusercontent.com/anthropics/devcontainer-features/main/src/claude-code/devcontainer-feature.json) - Feature metadata and customization defaults.
[^anth-feature-install]: [anthropics/devcontainer-features `src/claude-code/install.sh`](https://raw.githubusercontent.com/anthropics/devcontainer-features/main/src/claude-code/install.sh) - Official feature install implementation.
[^extra-feature-json]: [devcontainers-extra/features `src/claude-code/devcontainer-feature.json`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/claude-code/devcontainer-feature.json) - Alternative community feature metadata and version option.
[^extra-feature-install]: [devcontainers-extra/features `src/claude-code/install.sh`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/claude-code/install.sh) - Alternative feature install flow.
[^extra-bootstrap]: [devcontainers-extra/features `src/claude-code/bootstrap.sh`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/claude-code/bootstrap.sh) - Vendored bootstrap logic used by devcontainers-extra.
[^collection-index]: [Dev Container features collection index](https://raw.githubusercontent.com/devcontainers/devcontainers.github.io/refs/heads/gh-pages/_data/collection-index.yml) - Public catalog of feature providers including Anthropic Claude Code feature entry.