# Feature Reference

GitHub Copilot CLI provides an agentic command-line interface (`copilot`) for working with code and GitHub directly from a terminal. It supports interactive sessions and one-shot programmatic prompts, and is designed to perform tasks such as code edits, debugging, repository operations, and pull request workflows with tool permissions and safety controls.[^about-cli][^cmd-ref]

For feature implementers, the key practical point is that Copilot CLI is distributed through multiple channels (npm, WinGet, Homebrew, install script, and direct release assets), while runtime behavior is configured through files and environment variables under a per-user configuration directory (default `~/.copilot`) plus optional repository-local settings. Plugin and MCP/LSP extensibility are first-class and affect how a feature should treat installation, updates, and policy controls.[^install-docs][^config-dir][^plugin-ref]

- **Homepage**: https://github.com/features/copilot
- **Source Code**: https://github.com/github/copilot-cli[^repo-source]
- **Documentation**: https://docs.github.com/en/copilot/how-tos/copilot-cli
- **Latest Release**: v1.0.48 (as of 2026-05-17)[^release-latest]

## Tool Architecture

Copilot CLI is exposed as a single command (`copilot`) with both interactive and programmatic invocation modes (`copilot` and `copilot -p ...`). The CLI orchestrates model calls and tool execution locally while integrating with GitHub services for authentication and GitHub operations.[^about-cli][^cmd-ref]

The runtime is extensible through plugin packages and configuration files. Plugins can contribute custom agents, skills, hooks, MCP server definitions, and LSP server definitions. The CLI also supports user-level and repository-level configuration layering and permission persistence.[^plugin-about][^plugin-ref][^config-dir]

Distribution architecture is mixed:

- GitHub publishes platform binaries and installers in release assets (for example Linux/macOS tarballs and Windows MSI/ZIP). The latest release metadata also includes `github-copilot-<version>-<platform>.tgz` npm tarball assets.[^release-latest][^releases-page]
- The public `github/copilot-cli` repository root listing currently exposes support artifacts such as `README.md`, `changelog.md`, and `install.sh`, plus metadata directories (for example `.github`).[^repo-contents]

Authentication is supported via OAuth login flow (`copilot login`) and environment token precedence (`COPILOT_GITHUB_TOKEN`, then `GH_TOKEN`, then `GITHUB_TOKEN`). The CLI stores state/config in the config directory (default `~/.copilot`, overridable by `COPILOT_HOME`), with a separate cache directory (`COPILOT_CACHE_HOME` override available).[^cmd-ref][^config-dir]

## Installation Methods

Copilot CLI is officially installable via npm, WinGet, Homebrew, a shell installer, and direct release downloads from GitHub. Method choice primarily affects dependency surface, privilege model, and update/uninstall mechanics.[^install-docs]

### Common Post-Install Validation (Authentication and First Run)

After any installation method, complete an authentication-capable sanity check before treating the install as production-ready:

1. Authenticate using either:
  - `copilot login`, or
  - one of the supported token environment variables (`COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`).[^install-docs][^cmd-ref]
2. Run a minimal prompt-mode invocation:

  ```bash
  copilot -p "Reply with OK" -s
  ```

This verifies end-to-end auth/model access, not just local binary presence. For organization-managed users, confirm Copilot CLI policy is enabled if authentication fails despite valid credentials.[^about-cli][^install-docs][^cmd-ref]

### npm (All Platforms)

#### Supported Platforms

- Linux, macOS, and Windows (all platforms in official install docs).[^install-docs]
- On Windows, PowerShell v6+ is listed as a prerequisite for Copilot CLI usage.[^install-docs]

#### Dependencies

##### Common Dependencies

- Active GitHub Copilot subscription.[^install-docs]
- Node.js 22 or later.[^install-docs]
- npm global package installation support.[^npm-global][^npm-install]

##### Platform-Specific Dependencies

- Windows: PowerShell v6 or higher.[^install-docs]

#### Installation Steps

1. Install globally:

   ```bash
   npm install -g @github/copilot
   ```

2. If `ignore-scripts=true` is configured in `~/.npmrc`, install with scripts explicitly enabled:

   ```bash
   npm_config_ignore_scripts=false npm install -g @github/copilot
   ```

3. For prerelease channel:

   ```bash
   npm install -g @github/copilot@prerelease
   ```

These commands are documented by GitHub for Copilot CLI and align with npm global install behavior.[^install-docs][^npm-global][^npm-install]

#### Installation Verification

- Verify command availability and version:

  ```bash
  copilot version
  ```

- Optionally verify command help:

  ```bash
  copilot help
  ```

`copilot version` and `copilot help` are first-class commands in the CLI command reference.[^cmd-ref]

#### Configuration Options

##### Version Selection

- Stable/latest: `npm install -g @github/copilot`
- Prerelease: `npm install -g @github/copilot@prerelease`
- Specific versions/tags are supported by npm package spec syntax (`name@tag`, `name@version`).[^install-docs][^npm-install]

##### Installation Path

- npm global mode installs under npm `prefix`, linking binaries into `{prefix}/bin`.[^npm-install]

##### User Targeting

- npm global install target is determined by npm prefix/user environment. User-local and system-like prefixes are both possible depending on npm configuration.[^npm-install][^npm-global]

##### Required Privileges

- Depends on npm prefix permissions. npm documents that global install can trigger EACCES issues if prefix ownership/permissions are not configured for the current user.[^npm-global]

##### Tool-Specific Configurations

- Authentication environment variables are supported by CLI runtime after install: `COPILOT_GITHUB_TOKEN` (highest), `GH_TOKEN`, `GITHUB_TOKEN`.[^cmd-ref]
- Configuration/state location can be redirected with `COPILOT_HOME`; cache location with `COPILOT_CACHE_HOME`.[^cmd-ref][^config-dir]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure npm global bin directory is in `PATH` (npm global mode links executable shims in `{prefix}/bin`).[^npm-install]

##### Configuration Files

- Copilot CLI settings live in `~/.copilot/settings.json` (or `$COPILOT_HOME/settings.json`).[^config-dir]

##### Environment Variables

- Common persistent vars: `COPILOT_GITHUB_TOKEN`, `COPILOT_HOME`, `COPILOT_CACHE_HOME`, optional model/provider vars.[^cmd-ref][^about-cli]

##### Activation Scripts

- Optional shell completion can be enabled via:

  ```bash
  copilot completion bash
  copilot completion zsh
  copilot completion fish
  ```

with shell-specific install patterns from command reference.[^cmd-ref]

##### Cleanup

- Standard npm cleanup (cache/log management) is optional and outside Copilot-specific requirements.[^npm-install]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Upgrade/switch versions by reinstalling desired npm package spec (for example `@latest`, `@prerelease`, or explicit version).[^npm-install][^install-docs]
- CLI also provides `copilot update`, but for npm-managed installs prefer npm-based upgrades to keep package-manager state aligned.[^cmd-ref][^npm-install]

##### Uninstallation

```bash
npm uninstall -g @github/copilot
```

Global uninstall behavior is documented by npm.[^npm-uninstall]

##### Idempotency

- Re-running npm global install is idempotent in the package-manager sense (ensures requested package spec is installed in global prefix).[^npm-install]

#### Notes and Best Practices

- Prefer explicit channel/version pinning in automation (`@prerelease` or `@<version>`), rather than floating defaults, when reproducibility is required.[^npm-install][^install-docs]

### WinGet (Windows)

#### Supported Platforms

- Windows via WinGet.[^install-docs]

#### Dependencies

##### Common Dependencies

- Active GitHub Copilot subscription.[^install-docs]
- WinGet client (`winget`).[^install-docs][^winget-install]

##### Platform-Specific Dependencies

- PowerShell v6+ prerequisite noted by GitHub docs.[^install-docs]

#### Installation Steps

1. Stable:

   ```powershell
   winget install GitHub.Copilot
   ```

2. Prerelease:

   ```powershell
   winget install GitHub.Copilot.Prerelease
   ```

3. For unattended installs, WinGet supports flags such as `--accept-source-agreements`, `--accept-package-agreements`, and `--silent`.[^winget-install]

#### Installation Verification

- Verify executable:

  ```powershell
  copilot version
  ```

- Optionally inspect installed package with WinGet package queries/list workflows.[^winget-install][^cmd-ref]

#### Configuration Options

##### Version Selection

- Official package IDs select stable vs prerelease channel.
- WinGet supports explicit `--version` selection on install/upgrade commands.[^install-docs][^winget-install][^winget-upgrade]

##### Installation Path

- WinGet-managed installer determines destination path according to package manifest/installer behavior.[^winget-install]

##### User Targeting

- WinGet supports `--scope` (`user` or `machine`) for install/upgrade/uninstall selection.[^winget-install][^winget-upgrade][^winget-uninstall]

##### Required Privileges

- Privilege requirements are installer and scope dependent (`machine` vs `user`). Use appropriate shell elevation policy in automation.[^winget-install]

##### Tool-Specific Configurations

- Runtime config and auth environment behavior is identical across install methods (`~/.copilot`, token precedence, optional provider env vars).[^cmd-ref][^config-dir][^about-cli]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- WinGet-installed CLI should become available via standard command discovery; restart shell if PATH changes are not visible immediately.[^winget-install]

##### Configuration Files

- CLI creates/uses `~/.copilot` (Windows equivalent under `%USERPROFILE%\.copilot` unless `COPILOT_HOME` is set).[^config-dir]

##### Environment Variables

- Same runtime variables as other methods (`COPILOT_GITHUB_TOKEN`, `COPILOT_HOME`, etc.).[^cmd-ref][^config-dir]

##### Activation Scripts

- Optional completion scripts are supported by CLI command reference; shell-specific persistence differs on Windows shells.[^cmd-ref]

##### Cleanup

- WinGet logs and package state can be inspected via WinGet diagnostics options as needed.[^winget-install][^winget-uninstall]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Upgrade:

  ```powershell
  winget upgrade --id GitHub.Copilot
  ```

- Explicit target version via `--version` is supported by WinGet.[^winget-upgrade]

##### Uninstallation

```powershell
winget uninstall --id GitHub.Copilot --source winget
```

Using `--source winget` avoids Microsoft Store agreement prompts in mixed-source environments.[^winget-uninstall]

##### Idempotency

- WinGet handles already-installed packages through its install/upgrade resolution logic (`--no-upgrade` and related behavior available).[^winget-install][^winget-upgrade]

#### Notes and Best Practices

- In CI/scripting, include agreement flags and source scoping for deterministic behavior.[^winget-install][^winget-uninstall]

### Homebrew (macOS and Linux)

#### Supported Platforms

- macOS and Linux through Homebrew formulae.[^install-docs]

#### Dependencies

##### Common Dependencies

- Active GitHub Copilot subscription.[^install-docs]
- Homebrew installed and initialized in shell environment.[^brew-man]

##### Platform-Specific Dependencies

- None beyond Homebrew-supported host constraints for each OS.[^brew-man]

#### Installation Steps

1. Stable:

   ```bash
   brew install copilot-cli
   ```

2. Prerelease:

   ```bash
   brew install copilot-cli@prerelease
   ```

#### Installation Verification

- Verify executable:

  ```bash
  copilot version
  ```

- Verify Homebrew package state:

  ```bash
  brew list --versions copilot-cli
  ```

#### Configuration Options

##### Version Selection

- GitHub docs explicitly define stable and prerelease formula options via distinct formula names.[^install-docs]

##### Installation Path

- Installed into Homebrew prefix and linked into Homebrew bin path.[^brew-man]

##### User Targeting

- Homebrew manages packages inside its own prefix; this is generally user-scoped to the Homebrew installation context.[^brew-man]

##### Required Privileges

- Homebrew is designed to avoid mandatory `sudo` for normal formula operations in properly configured installations.[^brew-man]

##### Tool-Specific Configurations

- Copilot runtime config/auth variables are unchanged by Homebrew channel choice.[^cmd-ref][^config-dir]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure Homebrew environment exports are loaded (for example via `brew shellenv`) so linked binaries are on `PATH`.[^brew-man]

##### Configuration Files

- Copilot files appear under `~/.copilot` on first use.[^config-dir]

##### Environment Variables

- Optional Copilot variables for auth/config/model remain method-independent.[^cmd-ref][^about-cli]

##### Activation Scripts

- Optional `copilot completion` setup for shell tab completion.[^cmd-ref]

##### Cleanup

- Homebrew cleanup routines (`brew cleanup`) are available but not Copilot-specific requirements.[^brew-man]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Upgrade Homebrew formula:

  ```bash
  brew upgrade copilot-cli
  ```

- Switch channel by uninstalling one formula and installing the other (`copilot-cli` vs `copilot-cli@prerelease`).[^install-docs][^brew-man]

##### Uninstallation

```bash
brew uninstall copilot-cli
# or
brew uninstall copilot-cli@prerelease
```

##### Idempotency

- `brew install` on existing formula follows Homebrew install semantics (including upgrade behavior when outdated unless configured otherwise).[^brew-man]

#### Notes and Best Practices

- Pin formula/channel explicitly in automation when reproducibility matters.[^brew-man][^install-docs]

### Install Script (macOS/Linux Primary, Winget Fallback on Windows)

#### Supported Platforms

- Official docs position this method for macOS and Linux.[^install-docs]
- Installer source detects `Darwin`/`Linux` directly; on other platforms it attempts `winget install GitHub.Copilot` when `winget` is present.[^repo-install-script]
- Architecture support in script for tarball flow is `x64` and `arm64` only.[^repo-install-script]

#### Dependencies

##### Common Dependencies

- `bash` interpreter (official invocation pipes installer content to `bash`, and installer source uses bash shebang/features).[^install-docs][^repo-install-script]
- `curl` or `wget` for downloads.[^repo-install-script][^install-docs]
- `tar` for extraction.[^repo-install-script]

##### Platform-Specific Dependencies

- `git` is required when `VERSION=prerelease` is requested.[^repo-install-script]
- `sha256sum` or `shasum` is used for checksum validation when available (optional but recommended).[^repo-install-script]

#### Installation Steps

1. Run installer:

   ```bash
   curl -fsSL https://gh.io/copilot-install | bash
   # or
   wget -qO- https://gh.io/copilot-install | bash
   ```

2. For root/system install into `/usr/local/bin`:

   ```bash
   curl -fsSL https://gh.io/copilot-install | sudo bash
   ```

3. For custom install path/version:

   ```bash
   curl -fsSL https://gh.io/copilot-install | VERSION="v1.0.48" PREFIX="$HOME/custom" bash
   ```

Behavior from source code:

- Builds platform+arch tarball URL.
- Downloads tarball and `SHA256SUMS.txt`.
- Validates checksum when checksum utility exists.
- Verifies tarball readability (`tar -tzf`).
- Extracts `copilot` into `$PREFIX/bin` and marks executable.
- Prompts interactively to append PATH export to shell profile when needed.[^repo-install-script][^install-docs]

#### Installation Verification

- Script-level verification:
  - SHA256 verification against release checksum file when possible.
  - tarball integrity check via `tar -tzf`.
- Post-install verification:

  ```bash
  copilot version
  ```

[^repo-install-script][^cmd-ref]

#### Configuration Options

##### Version Selection

- `VERSION` environment variable:
  - unset or `latest` -> latest release download URL
  - `prerelease` -> resolves highest remote tag via `git ls-remote --tags --sort version:refname | tail -1`
  - explicit version (auto-prefixed with `v` if needed)

[^repo-install-script][^install-docs]

##### Installation Path

- `PREFIX` controls install root; binary path is `$PREFIX/bin/copilot`.
- Defaults:
  - root: `/usr/local`
  - non-root: `$HOME/.local`

[^repo-install-script][^install-docs]

##### User Targeting

- Non-root installs to user-local prefix by default.
- Root installs to system-like prefix by default.

[^repo-install-script]

##### Required Privileges

- Root is not strictly required if user-writable prefix is used.
- Root/sudo is required for default `/usr/local` install when current user cannot write there.[^repo-install-script][^install-docs]

##### Tool-Specific Configurations

- Installer uses `GITHUB_TOKEN` for authenticated GitHub API/download and tag lookup paths when present.[^repo-install-script]
- Runtime auth and config vars after install include `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, `COPILOT_HOME`, and `COPILOT_CACHE_HOME`.[^cmd-ref][^config-dir]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- If install directory is not already on PATH, installer proposes shell-specific updates:
  - zsh: `~/.zprofile`
  - bash: `~/.bash_profile`/`~/.bash_login`/`~/.profile`
  - fish: `~/.config/fish/conf.d/copilot.fish`

[^repo-install-script]

##### Configuration Files

- No Copilot runtime config files are force-written by installer itself; runtime creates/uses `~/.copilot` on use.[^repo-install-script][^config-dir]

##### Environment Variables

- Installer-time: `VERSION`, `PREFIX`, optional `GITHUB_TOKEN`.
- Runtime: `COPILOT_*`/token vars per command reference and config docs.[^repo-install-script][^cmd-ref][^config-dir]

##### Activation Scripts

- Optional completion activation via `copilot completion <shell>` after install.[^cmd-ref]

##### Cleanup

- Installer removes temporary download directory via trap (`mktemp -d` + cleanup on exit).[^repo-install-script]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Re-run installer with desired `VERSION` value.
- Alternatively, `copilot update` upgrades to latest available CLI release.

[^repo-install-script][^cmd-ref]

##### Uninstallation

- No dedicated uninstall command is documented for this method; remove installed binary (`$PREFIX/bin/copilot`) and any PATH lines added to shell profile.[^install-docs][^cmd-ref][^repo-install-script]

##### Idempotency

- Script is rerunnable and replaces existing binary if already present (`Notice: Replacing copilot binary ...`).[^repo-install-script]

#### Notes and Best Practices

- Prefer explicit `VERSION` pinning in infrastructure automation for deterministic builds.
- Keep checksum tools available (`sha256sum`/`shasum`) to preserve integrity verification.

### Direct Release Asset Download (GitHub Releases)

#### Supported Platforms

- Release assets currently include Linux/macOS tarballs and Windows ZIP/MSI variants for x64 and arm64.[^release-latest][^releases-page]

#### Dependencies

##### Common Dependencies

- Ability to download from GitHub releases.
- Archive extraction tooling (`tar` for `.tar.gz`, unzip/MSI handling on Windows).

[^release-latest][^releases-page]

##### Platform-Specific Dependencies

- OS-native installer/archive tooling varies by selected asset format (for example MSI on Windows).[^release-latest]

#### Installation Steps

1. Open releases page and select desired version/tag.
2. Download matching asset for OS/arch.
3. Extract/install asset and place `copilot` executable on PATH.

GitHub docs explicitly support this method as "Download from GitHub.com".[^install-docs][^releases-page]

#### Installation Verification

- Verify checksums using release checksum data (`SHA256SUMS.txt`/asset digest metadata) and then run:

  ```bash
  copilot version
  ```

[^release-latest][^cmd-ref]

#### Configuration Options

##### Version Selection

- Determined by release tag selected (`vX.Y.Z`).[^release-latest][^releases-page]

##### Installation Path

- User/operator controlled; depends on where binary is extracted or installer target path is configured.

##### User Targeting

- Either user-local or system-wide depending on destination directory chosen by operator.

##### Required Privileges

- Depends on destination path and installer type (for example system directories may require elevation).

##### Tool-Specific Configurations

- Same runtime configuration surface (`~/.copilot`, token and provider vars) applies after binary is in PATH.[^cmd-ref][^config-dir][^about-cli]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure final binary location is in PATH.

##### Configuration Files

- Runtime configuration in `~/.copilot` created/used on first run.[^config-dir]

##### Environment Variables

- Optional runtime env vars from command reference/config docs.[^cmd-ref][^config-dir]

##### Activation Scripts

- Optional `copilot completion` activation for shell completion.[^cmd-ref]

##### Cleanup

- Remove downloaded archives/installers after successful installation as needed.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Replace binary/install package with desired release asset version.
- `copilot update` can be used for latest update path after initial install.[^cmd-ref]

##### Uninstallation

- Remove installed binary/installer-managed package from selected target path.

##### Idempotency

- Replacing same version binary is effectively idempotent; replacing with different version performs explicit version switch.

#### Notes and Best Practices

- Use release checksums/digests and avoid unauthenticated mirrors for supply-chain integrity.[^release-latest]

## Dev Container Setup

The upstream `devcontainers/features` project includes an official `copilot-cli` feature (`ghcr.io/devcontainers/features/copilot-cli:1`) that can be used as reference behavior. It is Debian/Ubuntu oriented and installs Copilot CLI from GitHub release assets.[^devcontainers-readme][^devcontainers-install]

Key implementation details in that reference feature:

- Option surface: `version` with `latest` (default) or `prerelease` proposals.[^devcontainers-feature-json]
- Install script requires root and installs dependencies via apt (`wget tar ca-certificates git`) before downloading binary tarball.[^devcontainers-install]
- Architecture mapping uses `amd64 -> x64` and `arm64` support, then downloads `copilot-linux-<arch>.tar.gz`.[^devcontainers-install]
- For floating channels (`latest`/`prerelease`), it writes `/etc/devcontainer-copilot-cli/auto-update` and uses `postStartCommand` to run `copilot update` on container start.[^devcontainers-install][^devcontainers-feature-json]

Example `devcontainer.json` snippet:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/copilot-cli:1": {
      "version": "latest"
    }
  }
}
```

For this repository's feature design, the most relevant takeaways are channel pinning policy (`latest` vs explicit), root/non-root behavior, and whether to auto-update on lifecycle hooks versus immutable image builds.[^devcontainers-feature-json][^devcontainers-install]

## Plugins and Extensions

Copilot CLI has built-in plugin management (`copilot plugin ...`) and supports plugin marketplaces.[^cmd-ref][^plugin-ref][^plugin-about]

Plugin capabilities include packaging of custom agents, skills, hooks, MCP server definitions, and LSP server definitions.[^plugin-about][^plugin-ref]

### Marketplace Extension: copilot-plugins

#### Summary

`copilot-plugins` is one of the two marketplaces registered by default in Copilot CLI. It provides a curated plugin catalog that includes GitHub-owned entries and externally sourced plugin definitions.[^plugin-find-install][^marketplace-copilot-plugins]

#### Source and Manifest

- Marketplace repository: `github/copilot-plugins`.
- Marketplace manifest: `.github/plugin/marketplace.json` with top-level metadata and a `plugins` array (for example entries such as `workiq`, `spark`, and `advanced-security`).[^marketplace-copilot-plugins]

#### Installation and Management

Use CLI plugin commands:

```bash
copilot plugin marketplace list
copilot plugin marketplace browse copilot-plugins
copilot plugin install PLUGIN-NAME@copilot-plugins
copilot plugin list
copilot plugin update PLUGIN-NAME
copilot plugin uninstall PLUGIN-NAME
```

Command patterns above are documented in plugin how-to and plugin reference.[^plugin-find-install][^plugin-ref]

#### Notes

- Plugin files install under `~/.copilot/installed-plugins/<marketplace>/<plugin>/`.[^plugin-ref][^config-dir]
- Marketplace removal fails if plugins from that marketplace remain installed unless forced (`--force`).[^plugin-find-install]

### Marketplace Extension: awesome-copilot

#### Summary

`awesome-copilot` is also registered by default and is positioned as a community-driven catalog of plugins, agents, prompts, and skills.[^plugin-find-install][^marketplace-awesome-copilot]

#### Source and Manifest

- Marketplace repository: `github/awesome-copilot`.
- Marketplace manifest: `.github/plugin/marketplace.json` with extensive plugin entries and metadata fields (`name`, `source`, `description`, `version`, optional repository/author fields).[^marketplace-awesome-copilot][^plugin-ref]

#### Installation and Management

```bash
copilot plugin marketplace browse awesome-copilot
copilot plugin install PLUGIN-NAME@awesome-copilot
copilot plugin list
```

Example from docs:

```bash
copilot plugin install database-data-management@awesome-copilot
```

[^plugin-find-install]

#### Notes

- For deterministic environments, pin plugin names/versions and record marketplace source in infra docs.[^plugin-ref][^plugin-find-install]

### Cross-Marketplace Behavior and Safety

Installation sources include marketplace specs, GitHub repositories, Git URLs, and local paths; additional marketplaces can be registered with `copilot plugin marketplace add`.[^plugin-ref][^plugin-find-install][^plugin-marketplace]

Operational precedence and storage details that affect implementation:

- Installed plugin filesystem roots are under `~/.copilot/installed-plugins/...` (direct installs under `_direct`).[^plugin-ref][^config-dir]
- Name collision behavior differs by component type:
  - Agents/skills: first-found-wins.
  - MCP servers: last-wins.

[^plugin-ref]

These semantics matter for enterprise policy, reproducibility, and debugging when features preconfigure plugin stacks.[^plugin-ref][^config-dir]

## References

[^about-cli]: [GitHub Docs - About GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli) - Primary conceptual reference for CLI purpose, modes, security model, and supported OS.
[^install-docs]: [GitHub Docs - Installing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) - Official installation channels, prerequisites, and install commands.
[^cmd-ref]: [GitHub Docs - GitHub Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference) - Authoritative command, option, environment variable, and completion reference.
[^config-dir]: [GitHub Docs - GitHub Copilot CLI configuration directory](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference) - Config/state layout, cascading settings, and path overrides.
[^plugin-about]: [GitHub Docs - About plugins for GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-plugins) - Plugin architecture and use-cases.
[^plugin-ref]: [GitHub Docs - GitHub Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference) - Plugin commands, manifests, paths, and precedence details.
[^plugin-find-install]: [GitHub Docs - Finding and installing plugins for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing) - Default marketplaces and install/update/remove workflows.
[^plugin-marketplace]: [GitHub Docs - Creating a plugin marketplace for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-marketplace) - Marketplace structure and registration flow.
[^repo-source]: [GitHub Repository - github/copilot-cli](https://github.com/github/copilot-cli) - Upstream project repository.
[^repo-contents]: [GitHub API - Repository root contents for github/copilot-cli](https://api.github.com/repos/github/copilot-cli/contents) - Confirms public root layout and installer/support artifacts.
[^repo-install-script]: [Installer source - github/copilot-cli/install.sh](https://raw.githubusercontent.com/github/copilot-cli/main/install.sh) - Exact installer behavior (dependencies, checksum, PATH handling, version/prefix logic).
[^releases-page]: [GitHub Releases - github/copilot-cli](https://github.com/github/copilot-cli/releases) - Official direct-download release channel.
[^release-latest]: [GitHub API - Latest release for github/copilot-cli](https://api.github.com/repos/github/copilot-cli/releases/latest) - Latest version/date and current asset matrix with digests.
[^npm-global]: [npm Docs - Downloading and installing packages globally](https://docs.npmjs.com/downloading-and-installing-packages-globally) - Global npm installation behavior and permission considerations.
[^npm-install]: [npm CLI Docs - npm install](https://docs.npmjs.com/cli/v11/commands/npm-install) - Global mode semantics and version/tag package spec syntax.
[^npm-uninstall]: [npm CLI Docs - npm uninstall](https://docs.npmjs.com/cli/v11/commands/npm-uninstall) - Global uninstall semantics.
[^winget-install]: [Microsoft Learn - winget install](https://learn.microsoft.com/en-us/windows/package-manager/winget/install) - WinGet install syntax/options.
[^winget-upgrade]: [Microsoft Learn - winget upgrade](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade) - WinGet upgrade/version targeting semantics.
[^winget-uninstall]: [Microsoft Learn - winget uninstall](https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall) - WinGet uninstall semantics and source-scoping note.
[^brew-man]: [Homebrew Documentation - brew(1) manpage](https://docs.brew.sh/Manpage) - Homebrew install/upgrade/uninstall and prefix/path behaviors.
[^devcontainers-install]: [devcontainers/features - copilot-cli install.sh](https://raw.githubusercontent.com/devcontainers/features/main/src/copilot-cli/install.sh) - Reference devcontainer installation implementation.
[^devcontainers-feature-json]: [devcontainers/features - copilot-cli devcontainer-feature.json](https://raw.githubusercontent.com/devcontainers/features/main/src/copilot-cli/devcontainer-feature.json) - Feature options, postStartCommand, and install ordering metadata.
[^devcontainers-readme]: [devcontainers/features - copilot-cli README](https://raw.githubusercontent.com/devcontainers/features/main/src/copilot-cli/README.md) - Usage example and platform support notes for the reference feature.
[^marketplace-copilot-plugins]: [copilot-plugins marketplace manifest](https://raw.githubusercontent.com/github/copilot-plugins/main/.github/plugin/marketplace.json) - Default marketplace manifest schema and representative plugin entries.
[^marketplace-awesome-copilot]: [awesome-copilot marketplace manifest](https://raw.githubusercontent.com/github/awesome-copilot/main/.github/plugin/marketplace.json) - Community marketplace manifest and representative plugin catalog entries.