# Feature Reference

Claude Code (often referred to as the Claude CLI) is Anthropic's terminal-first coding assistant. It combines conversational prompting with direct tooling, including file reads/edits, shell command execution, git workflows, and integrations through MCP servers and IDE extensions.[^docs-setup][^repo-readme]

Operationally, Claude Code is distributed as platform-specific native binaries (macOS, Linux, Windows, x64/ARM64, including musl variants). Official docs enumerate native bootstrap, package-manager, and npm installation paths; additionally, the same release-channel artifacts can be consumed manually because the bootstrap scripts download from `https://downloads.claude.ai/claude-code-releases`.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd][^docs-env]

- **Homepage**: https://code.claude.com
- **Source Code**: https://github.com/anthropics/claude-code
- **Documentation**: https://code.claude.com/docs/en/overview
- **Latest Release**: 2.1.143 (as of 2026-05-17)[^release-latest][^npm-latest]

## Tool Architecture

Claude Code is delivered as a native executable per OS/architecture target. The release channel publishes platform artifacts (for example, `claude-linux-x64.tar.gz`, `claude-win32-x64.zip`), and the npm package references matching per-platform optional dependencies rather than running the CLI inside Node at runtime.[^release-latest][^npm-latest][^docs-setup]

The native bootstrap installers (`install.sh`, `install.ps1`, `install.cmd`) resolve the latest installer version, download a manifest, verify checksums, fetch a platform binary, and execute `claude install` to perform launcher/shell integration. This makes the bootstrap a thin verified downloader around the native `claude` installer workflow.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

Configuration and state are file-based. By default, Claude Code stores credentials, settings, history, and session data under `~/.claude` (override via `CLAUDE_CONFIG_DIR`), with JSON settings layered by scope (user/project/local/managed).[^docs-env][^docs-settings][^docs-setup]

## Installation Methods

Claude Code has three documented end-user installation families: native bootstrap installers, OS package-manager installs, and npm global install. This reference also includes an operator-managed manual workflow using the release-channel artifact bucket consumed by the bootstrap scripts.[^docs-setup][^repo-readme][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

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

2. Bootstraps accept one optional target, detect platform/arch, resolve the installer version from the `latest` endpoint, fetch `manifest.json`, extract `platforms.<platform>.checksum`, download the platform installer into the Claude downloads directory, verify SHA256, run `claude install [target]`, and delete the downloaded installer binary.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
   - POSIX platform mapping includes `darwin-x64`/`darwin-arm64`, `linux-x64`/`linux-arm64`, and `linux-*-musl` when musl is detected.[^src-bootstrap-sh]
   - Windows platform mapping includes `win32-x64` and `win32-arm64` based on processor architecture environment variables.[^src-bootstrap-ps1][^src-bootstrap-cmd]
    - Target validation differs by bootstrap implementation: POSIX and PowerShell use strict full-pattern validation (`stable|latest|X.Y.Z[-suffix]`), while CMD validates `stable/latest` explicitly and otherwise applies a looser semver-prefix check before invoking `claude install`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
   - CMD bootstrap includes a short delay before deletion to avoid file-lock races on Windows.[^src-bootstrap-cmd]
3. Launch Claude Code from the terminal in your project directory with `claude` and complete authentication.[^docs-setup]

#### Installation Verification

- Basic verification: `claude --version`.[^docs-setup]
- Diagnostic verification: `claude doctor`.[^docs-setup]
- Verify release-signing key fingerprint before trusting downloaded release metadata:[^docs-setup]

```bash
curl -fsSL https://downloads.claude.ai/keys/claude-code.asc | gpg --import
gpg --fingerprint security@anthropic.com
```

Expected fingerprint:

```text
31DD DE24 DDFA B679 F42D  7BD2 BAA9 29FF 1A7E CACE
```

- Verify detached manifest signature and then verify the binary checksum against `platforms.<platform>.checksum`:[^docs-setup]

Windows caveat: signature-verification steps that use `gpg` + `curl` must run in a POSIX shell (Git Bash or WSL), even when the target binary is Windows.[^docs-setup]

```bash
REPO=https://downloads.claude.ai/claude-code-releases
VERSION=2.1.89
curl -fsSLO "$REPO/$VERSION/manifest.json"
curl -fsSLO "$REPO/$VERSION/manifest.json.sig"
gpg --verify manifest.json.sig manifest.json
```

Expected `gpg --verify` success indicator:

```text
Good signature from "Anthropic Claude Code Release Signing <security@anthropic.com>"
```

Explicit checksum comparison workflow (example `linux-x64` target):[^docs-setup]

```bash
PLATFORM=linux-x64
curl -fsSLO "$REPO/$VERSION/$PLATFORM/claude"
EXPECTED=$(jq -r ".platforms[\"$PLATFORM\"].checksum" manifest.json)
ACTUAL=$(sha256sum claude | awk '{print $1}')
test "$ACTUAL" = "$EXPECTED"
```

PowerShell comparison example (`win32-x64` target):[^docs-setup]

```powershell
$REPO = "https://downloads.claude.ai/claude-code-releases"
$VERSION = "2.1.89"
$platform = "win32-x64"
Invoke-WebRequest -Uri "$REPO/$VERSION/manifest.json" -OutFile ".\manifest.json"
Invoke-WebRequest -Uri "$REPO/$VERSION/$platform/claude.exe" -OutFile ".\claude.exe"
$manifest = Get-Content .\manifest.json | ConvertFrom-Json
$expected = $manifest.platforms.$platform.checksum.ToLower()
$actual = (Get-FileHash .\claude.exe -Algorithm SHA256).Hash.ToLower()
$actual -eq $expected
```

Hash command equivalents by platform:[^docs-setup]

```bash
sha256sum claude
```

```bash
shasum -a 256 claude
```

```powershell
(Get-FileHash claude.exe -Algorithm SHA256).Hash.ToLower()
```

- Manifest signatures are published for `2.1.89+`; earlier releases provide checksums in `manifest.json` without detached signatures.[^docs-setup]
- Platform code-signature checks:[^docs-setup]
  - macOS: `codesign --verify --verbose ./claude`, signer `Anthropic PBC`, notarized by Apple.
  - Windows: `Get-AuthenticodeSignature .\claude.exe`, signer `Anthropic, PBC`.
  - Linux: no per-binary code signature; integrity is via signed manifest (native) or package-manager repository signature checks.

#### Configuration Options

##### Version Selection

- Default latest channel:[^docs-setup]

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

```powershell
irm https://claude.ai/install.ps1 | iex
```

```bat
curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd
```

- Stable channel:[^docs-setup]

```bash
curl -fsSL https://claude.ai/install.sh | bash -s stable
```

```powershell
& ([scriptblock]::Create((irm https://claude.ai/install.ps1))) stable
```

```bat
curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd stable && del install.cmd
```

- Explicit version pin:[^docs-setup]

```bash
curl -fsSL https://claude.ai/install.sh | bash -s 2.1.89
```

```powershell
& ([scriptblock]::Create((irm https://claude.ai/install.ps1))) 2.1.89
```

```bat
curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd 2.1.89 && del install.cmd
```

- Target validation details by bootstrap implementation:[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
  - POSIX + PowerShell: strict full-pattern validation for `stable`, `latest`, or semver-like target with optional suffix.
  - CMD: explicit `stable/latest` check plus semver-prefix pattern check before forwarding the value.

##### Installation Path

- Bootstraps stage downloaded binaries in `~/.claude/downloads` (or `%USERPROFILE%\.claude\downloads` on Windows scripts) before calling `claude install`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
- Native uninstall docs indicate installed launcher/binaries under `~/.local/bin` and runtime files under `~/.local/share/claude` for POSIX systems.[^docs-setup]

##### User Targeting

- Native install is primarily user-local (home-directory scoped), not system-wide package-manager managed.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Required Privileges

- Native Windows setup explicitly states Administrator privileges are not required.[^docs-setup]
- POSIX native setup runs as a regular user in documented flows (no `sudo` in official commands), staging under `$HOME/.claude/downloads` and installing user-local launcher/runtime paths.[^docs-setup][^src-bootstrap-sh]

##### Tool-Specific Configurations

- `autoUpdatesChannel`: `latest` (default) or `stable` (delayed channel that skips major-regression releases).[^docs-setup][^docs-settings]
- `minimumVersion`: version floor; background updates and `claude update` refuse to install versions below this value.[^docs-setup][^docs-settings]
- `DISABLE_AUTOUPDATER=1`: disables background update checks only; manual `claude update` and `claude install` still work.[^docs-setup][^docs-env]
- `DISABLE_UPDATES=1`: blocks all update paths, including manual update commands.[^docs-setup][^docs-env]
- `CLAUDE_CODE_GIT_BASH_PATH`: Windows path override for `bash.exe` when Git Bash is installed but not discoverable.[^docs-setup][^docs-env]
- `CLAUDE_CODE_USE_POWERSHELL_TOOL`: controls native PowerShell tool availability (`1` opt-in / force-enable context-dependent, `0` opt-out/disable).[^docs-setup][^docs-env]
- `CLAUDE_CONFIG_DIR`: relocates the Claude state/config root (default `~/.claude`).[^docs-env][^docs-setup]
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`: shorthand equivalent to disabling auto-updater, feedback command, error reporting, and telemetry.[^docs-env][^docs-devcontainer]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- `claude install` is invoked by all bootstraps to handle launcher and shell integration.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Configuration Files

- Primary settings are JSON files in user/project/local scopes (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`).[^docs-settings]

##### Environment Variables

- Environment variables can be exported in the shell or set persistently in `settings.json` under `env`.[^docs-env][^docs-settings]
- Install/upgrade behavior variables directly relevant to this feature: `DISABLE_AUTOUPDATER`, `DISABLE_UPDATES`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_GIT_BASH_PATH`, `CLAUDE_CODE_USE_POWERSHELL_TOOL`, `USE_BUILTIN_RIPGREP`.[^docs-env][^docs-setup]

##### Activation Scripts

- No manual activation script is required in normal native flow; bootstrap delegates shell integration to `claude install`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Cleanup

- Bootstrap installers remove temporary downloaded installer artifacts after install attempt.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Upgrade in place with `claude update`.[^docs-setup]
- Change release channel via `autoUpdatesChannel`: `latest` tracks newest releases; `stable` tracks a delayed channel (typically about one week behind) that skips releases with major regressions. Use `minimumVersion` to enforce a non-downgrade floor when moving channels.[^docs-setup][^docs-settings]
- Re-run bootstrap with target argument (`stable` or explicit version) to install a different target build.[^docs-setup]

##### Uninstallation

- Remove native installer binaries/runtime (POSIX):[^docs-setup]

```bash
rm -f ~/.local/bin/claude
rm -rf ~/.local/share/claude
```

- Remove native installer binaries/runtime (Windows PowerShell):[^docs-setup]

```powershell
Remove-Item -Path "$env:USERPROFILE\.local\bin\claude.exe" -Force
Remove-Item -Path "$env:USERPROFILE\.local\share\claude" -Recurse -Force
```

- Optional full config/state cleanup (POSIX):[^docs-setup]

```bash
rm -rf ~/.claude
rm ~/.claude.json
rm -rf .claude
rm -f .mcp.json
```

- Optional full config/state cleanup (Windows PowerShell):[^docs-setup]

```powershell
Remove-Item -Path "$env:USERPROFILE\.claude" -Recurse -Force
Remove-Item -Path "$env:USERPROFILE\.claude.json" -Force
Remove-Item -Path ".claude" -Recurse -Force
Remove-Item -Path ".mcp.json" -Force
```

- Full removal caveat: if the VS Code extension, JetBrains plugin, or Desktop app remains installed, `~/.claude` may be recreated on next run; uninstall those components first for permanent directory removal.[^docs-setup]

##### Idempotency

- Native bootstrap is repeatable but not a no-op: each run re-resolves version metadata, re-downloads installer artifacts, re-verifies checksums, executes `claude install`, and removes temporary artifacts.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Notes and Best Practices

- Prefer signed-manifest verification for manual binary trust checks, especially in controlled or air-gapped deployments.[^docs-setup]
- On Alpine/musl, install required libs and disable builtin ripgrep fallback mismatch issues with `USE_BUILTIN_RIPGREP=0`.[^docs-setup]

### Direct Release Channel Artifact Installation (`downloads.claude.ai/claude-code-releases`)

This method installs from the same release-channel artifact source used by the native bootstrap scripts, but executes the download/verification/install flow manually.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Supported Platforms

- Platform targets in this channel include `darwin-x64`, `darwin-arm64`, `linux-x64`, `linux-arm64`, `linux-x64-musl`, `linux-arm64-musl`, `win32-x64`, and `win32-arm64`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
- WSL uses Linux platform targets.[^docs-setup]

#### Dependencies

##### Common Dependencies

- Network access to release endpoints under `https://downloads.claude.ai/claude-code-releases` and signing key endpoint `https://downloads.claude.ai/keys/claude-code.asc`.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
- `curl` or `wget` for release artifact and metadata downloads.[^src-bootstrap-sh][^src-bootstrap-cmd]
- `gpg` for signing-key import/fingerprint validation and manifest signature checks.[^docs-setup]
- `jq` (or equivalent JSON parsing) for extracting platform checksum values from `manifest.json` in POSIX automation flows.[^src-bootstrap-sh]

##### Platform-Specific Dependencies

- Linux: `sha256sum` for checksum calculation.[^docs-setup]
- macOS: `shasum -a 256` for checksum calculation.[^docs-setup]
- Windows: `Invoke-WebRequest` and `Get-FileHash` in PowerShell; run `gpg` signature commands in Git Bash or WSL.[^docs-setup]

#### Installation Steps

1. Resolve installer artifact version from the `latest` marker (matching native bootstrap behavior), then choose an install target (`latest`, `stable`, or explicit version) for `claude install`:[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd][^docs-setup]

```bash
REPO=https://downloads.claude.ai/claude-code-releases
VERSION=$(curl -fsSL "$REPO/latest")
INSTALL_TARGET=latest  # or stable or 2.1.89
```

2. Verify release signing key and manifest signature before trusting checksums:[^docs-setup]

```bash
curl -fsSL https://downloads.claude.ai/keys/claude-code.asc | gpg --import
gpg --fingerprint security@anthropic.com
curl -fsSLO "$REPO/$VERSION/manifest.json"
curl -fsSLO "$REPO/$VERSION/manifest.json.sig"
gpg --verify manifest.json.sig manifest.json
```

Expected key fingerprint:

```text
31DD DE24 DDFA B679 F42D  7BD2 BAA9 29FF 1A7E CACE
```

3. Download platform artifact, verify checksum against `manifest.json`, and run installer command:

POSIX example (`linux-x64`):[^docs-setup][^src-bootstrap-sh]

```bash
PLATFORM=linux-x64
curl -fsSLO "$REPO/$VERSION/$PLATFORM/claude"
EXPECTED=$(jq -r ".platforms[\"$PLATFORM\"].checksum" manifest.json)
ACTUAL=$(sha256sum claude | awk '{print $1}')
test "$ACTUAL" = "$EXPECTED"
chmod +x ./claude
./claude install "$INSTALL_TARGET"
rm -f ./claude
```

PowerShell example (`win32-x64`):[^docs-setup][^src-bootstrap-ps1]

```powershell
$REPO = "https://downloads.claude.ai/claude-code-releases"
$VERSION = (Invoke-WebRequest -Uri "$REPO/latest" -UseBasicParsing).Content.Trim()
# or pin explicitly: $VERSION = "2.1.89"
$InstallTarget = "latest" # or "stable" or "2.1.89"
$platform = "win32-x64"
Invoke-WebRequest -Uri "$REPO/$VERSION/manifest.json" -OutFile ".\manifest.json"
Invoke-WebRequest -Uri "$REPO/$VERSION/$platform/claude.exe" -OutFile ".\claude.exe"
$manifest = Get-Content .\manifest.json | ConvertFrom-Json
$expected = $manifest.platforms.$platform.checksum.ToLower()
$actual = (Get-FileHash .\claude.exe -Algorithm SHA256).Hash.ToLower()
$actual -eq $expected
.\claude.exe install $InstallTarget
Remove-Item .\claude.exe -Force
```

#### Installation Verification

- Verify command availability with `claude --version` and run diagnostics with `claude doctor`.[^docs-setup]
- Require both manifest-signature success and checksum match before executing `claude install`.[^docs-setup]

#### Configuration Options

##### Version Selection

- Artifact version selection uses release-channel paths (`$REPO/$VERSION/...`) with `VERSION` from `latest` endpoint or explicit pin.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]
- Install channel/target is set by the `claude install` argument (`latest`, `stable`, or explicit version), matching native installer behavior.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Installation Path

- Installed launcher/runtime paths follow native install layout after `claude install` (for example `~/.local/bin` and `~/.local/share/claude` on POSIX).[^docs-setup]

##### User Targeting

- Standard workflow is user-local when executed as non-root user, matching native install behavior.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Required Privileges

- User-local installs do not require elevated privileges; native Windows setup docs explicitly state Administrator is not required.[^docs-setup]

##### Tool-Specific Configurations

- Same runtime controls as native installs apply after install: `autoUpdatesChannel`, `minimumVersion`, `DISABLE_AUTOUPDATER`, `DISABLE_UPDATES`, `CLAUDE_CONFIG_DIR`, and Windows shell-path/tool variables where applicable.[^docs-setup][^docs-settings][^docs-env]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- `claude install` performs launcher/shell integration.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Configuration Files

- Runtime settings/state use standard Claude paths (`~/.claude`, project `.claude/`, `.mcp.json`).[^docs-setup][^docs-settings]

##### Environment Variables

- Environment variables can be exported or set in `settings.json` `env` exactly as with native install flows.[^docs-env][^docs-settings]

##### Activation Scripts

- No additional activation script is required beyond `claude install` integration.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Cleanup

- Manual integrity-verification commands download `manifest.json` and `manifest.json.sig` into the working directory; bootstrap scripts remove their temporary downloaded binary after `claude install`. Apply equivalent cleanup in manual workflows per local policy.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Re-run artifact workflow with a different `VERSION` and/or different `claude install` target, or use `claude update` post-install.[^docs-setup][^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

##### Uninstallation

- Use native-install uninstall commands (launcher/runtime removal plus optional config cleanup).[^docs-setup]

##### Idempotency

- Repeatable but not a no-op: each run re-downloads metadata/artifacts, re-verifies trust, and re-runs `claude install`.[^src-bootstrap-sh][^src-bootstrap-ps1][^src-bootstrap-cmd]

#### Notes and Best Practices

- Anthropic's documented recommendation is native bootstrap installation by default; treat manual release-artifact workflows as advanced operator-managed flows rather than a documented default path.[^docs-setup][^repo-readme]

### OS Package Manager Installation (Homebrew, WinGet, apt, dnf, apk)

#### Supported Platforms

- Homebrew: macOS/Linux environments with Homebrew available.[^docs-setup]
- WinGet: Windows environments with winget available.[^docs-setup]
- apt: Debian/Ubuntu; dnf: Fedora/RHEL; apk: Alpine.[^docs-setup]

#### Dependencies

##### Common Dependencies

- Corresponding package manager command available on target host (`brew`, `winget`, `apt`, `dnf`, or `apk`).[^docs-setup]
- Network access to Anthropic repository endpoints and signing-key endpoints under `downloads.claude.ai`.[^docs-setup]

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

Rolling channel (`latest`) selection for Linux repositories is done by replacing `stable` in repository URLs/suite names:
- apt: replace both `stable` occurrences in the `deb` line (URL path and suite).
- dnf: use `baseurl=https://downloads.claude.ai/claude-code/rpm/latest`.
- apk: use `https://downloads.claude.ai/claude-code/apk/latest` in `/etc/apk/repositories`.[^docs-setup]

#### Installation Verification

- Run `claude --version` and optionally `claude doctor`.[^docs-setup]
- Verify Linux repository signing material before trusting package installation:[^docs-setup]
  - apt key fingerprint:

```bash
gpg --show-keys /etc/apt/keyrings/claude-code.asc
```

Expected fingerprint:

```text
31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE
```

  - dnf first-install fingerprint prompt: confirm it matches `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE` before accepting key import.
  - apk key file checksum:

```sh
sha256sum /etc/apk/keys/claude-code.rsa.pub
```

Expected checksum:

```text
395759c1f7449ef4cdef305a42e820f3c766d6090d142634ebdb049f113168b6
```

#### Configuration Options

##### Version Selection

- Homebrew channel selection is cask-based: `claude-code` tracks stable (delayed channel that skips major-regression releases) and `claude-code@latest` tracks latest.[^docs-setup]
- Linux repo channel selection uses repository path/suite (`stable` vs `latest`).[^docs-setup]

##### Installation Path

- Repository/key configuration paths are explicit in official commands: `apt` uses `/etc/apt/keyrings/claude-code.asc` and `/etc/apt/sources.list.d/claude-code.list`; `dnf` uses `/etc/yum.repos.d/claude-code.repo`; `apk` uses `/etc/apk/keys/claude-code.rsa.pub` and `/etc/apk/repositories`.[^docs-setup]
- Installed launcher path is package-manager controlled; verify effective runtime path with `command -v claude` after install.[^docs-setup]

##### User Targeting

- apt/dnf/apk procedures are system-level package installations that modify system repository configuration under `/etc`.[^docs-setup]
- Homebrew and WinGet installation commands are documented without `sudo`; execution context and scope are determined by local package-manager configuration/policy.[^docs-setup]

##### Required Privileges

- apt and dnf installation/upgrade/removal commands are documented with `sudo` and write system repository files.[^docs-setup]
- apk flow writes under `/etc/apk` and installs/removes system packages, requiring root/elevated context.[^docs-setup]
- Homebrew and WinGet commands are documented without explicit elevation flags.[^docs-setup]

##### Tool-Specific Configurations

- `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` enables background package-manager auto-upgrade for Homebrew and WinGet only; apt/dnf/apk remain manual-update flows by design.[^docs-setup][^docs-env]
- Background auto-upgrade via `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` targets only the Claude Code package (not unrelated packages). On WinGet, upgrades can fail while `claude` is running because Windows locks the executable; Claude then prints the manual upgrade command.[^docs-setup][^docs-env]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- No extra PATH mutation is documented for package-manager installs; verify command resolution with `command -v claude` if invocation fails.[^docs-setup]

##### Configuration Files

- Runtime settings remain the same Claude settings/config files as other methods (`~/.claude`, project `.claude/`).[^docs-settings]

##### Environment Variables

- Same runtime env controls apply as native install, including `CLAUDE_CONFIG_DIR`, `DISABLE_AUTOUPDATER`, `DISABLE_UPDATES`, and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`.[^docs-env]

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

- Homebrew:[^docs-setup]

```bash
brew uninstall --cask claude-code
```

```bash
brew uninstall --cask claude-code@latest
```

- WinGet:[^docs-setup]

```powershell
winget uninstall Anthropic.ClaudeCode
```

- apt:[^docs-setup]

```bash
sudo apt remove claude-code
sudo rm /etc/apt/sources.list.d/claude-code.list /etc/apt/keyrings/claude-code.asc
```

- dnf:[^docs-setup]

```bash
sudo dnf remove claude-code
sudo rm /etc/yum.repos.d/claude-code.repo
```

- apk:[^docs-setup]

```sh
apk del claude-code
sed -i '\|downloads.claude.ai/claude-code/apk|d' /etc/apk/repositories
rm /etc/apk/keys/claude-code.rsa.pub
```

##### Idempotency

- Claude docs define install/upgrade/remove commands but do not provide a package-manager-idempotency contract; repeated runs follow the underlying package manager's state model for installed version, channel, and repository metadata.[^docs-setup]

#### Notes and Best Practices

- For reproducibility, be explicit about channel selection (`stable` vs `latest`) and key verification in provisioning scripts.[^docs-setup]
- Known issue from official docs: update notifications can appear before the new package version reaches Homebrew/WinGet/apt/dnf/apk repositories; if upgrade fails, retry after repository propagation catches up.[^docs-setup]

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

- Install location follows npm global prefix conventions for the executing environment; verify with `npm prefix -g` and `command -v claude` when wiring PATH-sensitive automation.[^docs-setup][^npm-latest]

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

- Re-running `npm install -g @anthropic-ai/claude-code[@specifier]` delegates reconciliation to npm's package state; resulting version depends on the requested specifier and currently installed state. Official docs recommend explicit `@latest` or pinned-version reinstalls instead of `npm update -g` for deterministic upgrades.[^docs-setup][^npm-latest]

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

- Feature tag (for example `:1.0`) pins the feature install script, not the CLI release version; the feature installs latest Claude Code and CLI auto-update remains enabled unless explicitly disabled.[^docs-devcontainer]
- Reproducible pinning path in official docs: do not use the feature for pinning; install explicit CLI version in Dockerfile and disable auto-updater:[^docs-devcontainer]

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@X.Y.Z
```

```json
{
  "containerEnv": {
    "DISABLE_AUTOUPDATER": "1"
  }
}
```

- Persistence across rebuilds requires volume-mounting Claude state directory (example for `remoteUser` `node`):[^docs-devcontainer]

```json
{
  "mounts": [
    "source=claude-code-config,target=/home/node/.claude,type=volume"
  ]
}
```

- If mount target is not `~/.claude`, set `CLAUDE_CONFIG_DIR` to that mounted path so tokens/settings/history persist correctly.[^docs-devcontainer][^docs-env]
- Organization policy inside container can be set via `/etc/claude-code/managed-settings.json`, but repository writers can still alter Dockerfile steps; non-bypassable policy requires server-managed settings or MDM.[^docs-devcontainer][^docs-settings]
- `--dangerously-skip-permissions` is only accepted when running as non-root (`remoteUser` must not be root). Even in containers, bypass mode still permits modification of bind-mounted workspace files and access to allowed network destinations; docs explicitly warn devcontainers are not complete isolation.[^docs-devcontainer]

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

- `enabledPlugins` is a map of `plugin@marketplace` to boolean enablement state; scope precedence is Managed > CLI args > Local > Project > User, so local can disable project-enabled plugins, while managed force-enable/disable cannot be overridden.[^docs-settings]
- `extraKnownMarketplaces` pre-registers named marketplace sources (for example GitHub/git/url/npm/file/directory/settings) and prompts collaborators to trust/install when repository settings include them.[^docs-settings]
- `strictKnownMarketplaces` is managed-settings-only allowlist enforcement applied before network/filesystem operations; `undefined` means unrestricted, `[]` is full lockdown, and explicit source objects allow only exact matches (except regex-based `hostPattern`/`pathPattern`).[^docs-settings]
- Plugin operations (browse/install/enable/disable/update marketplace) are available through `/plugin` and apply across CLI/IDE sessions because both use the same underlying Claude configuration state.[^docs-vscode][^docs-settings]

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