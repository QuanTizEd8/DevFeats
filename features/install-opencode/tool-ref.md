# Feature Reference

[OpenCode](https://opencode.ai) is an open-source AI coding agent designed to operate as a terminal-based interface for code generation, explanation, refactoring, and general development assistance. It supports 75+ LLM providers (including Anthropic, OpenAI, Google, OpenRouter, etc.)[^docs-intro] and can be used interactively via its Terminal UI (TUI), non-interactively for automation via its `run` subcommand, as a web application, as an IDE extension (VS Code, Cursor, Zed, Windsurf, VSCodium), or as a GitHub/GitLab agent for repository automation[^docs-github][^docs-gitlab]. OpenCode is a fully open-source project under the MIT license.

OpenCode is written in TypeScript and compiled into self-contained native binaries using Bun's `compile` feature, meaning it requires no runtime dependencies (such as Node.js, Python, or a JVM) to execute. It uses Bun as the primary runtime environment for development, and the pre-built binaries are standalone executables for Linux, macOS, and Windows on both x64 and arm64 architectures[^src-build].

- **Homepage**: https://opencode.ai
- **Source Code**: https://github.com/anomalyco/opencode
- **Documentation**: https://opencode.ai/docs
- **Latest Release**: v1.17.12 (as of 2026-06-30)[^github-latest-release]

## Tool Architecture

OpenCode is a single, self-contained CLI binary that serves as both a client and server for AI-powered coding assistance. Its architecture[^src-build] includes:

- **Primary binary**: A single executable named `opencode` compiled via `bun build --compile`, which includes an embedded server (using the Hono framework), a TUI renderer (using Ink/React-based terminal UI rendering), an SDK client, a tool registry and execution engine, LSP server management (supporting 20+ languages), a session and agent management system, and provider integrations for 75+ LLM services[^src-package-json].
- **Self-contained**: The compiled binary embeds all dependencies, including a web UI bundle, and requires no external runtime (Node.js, Python, etc.) for normal operation.
- **Client-server architecture**: The TUI runs as a separate thread (Worker Thread) that communicates with the embedded HTTP server via SSE (Server-Sent Events) and RPC[^src-run]. The server process handles all I/O-intensive work (LLM streaming, file operations, MCP connections), while the TUI thread handles rendering and user input. This separation also allows the CLI to connect to a remote `opencode serve` instance, enabling a "local editing, remote inference" workflow[^src-run].
- **No external services required**: OpenCode can be used entirely locally with any configured LLM provider; it does not require a cloud service, although a hosted Zen service is available for curated model access.
- **Development runtime**: During development, OpenCode uses Bun (v1.3.14+) as its runtime with a TypeScript codebase organized as a Turborepo monorepo[^src-package-json].
- **Extensible via plugins**: OpenCode supports a plugin system, MCP (Model Context Protocol) servers, ACP (Agent Communication Protocol) support, custom tools, and agent skills[^docs-plugins].

## Installation Methods

OpenCode offers a wide variety of installation methods[^readme-install]. The most relevant methods for containers, CI/CD, and automated environments are the **install script** (recommended for Dev Container Features) and the **direct binary download** approach, as they do not require Node.js, Homebrew, or any other package manager. The npm-based installation is also viable when a Node.js runtime is already present. Additional package manager methods are documented for completeness.

### Install Script (Recommended)

The official install script at `https://opencode.ai/install` is a self-contained bash script that detects the OS and architecture, downloads the appropriate pre-built binary from the GitHub releases page, installs it to a user-local directory (`$HOME/.opencode/bin`), and optionally adds the installation directory to the user's PATH[^src-installer].

#### Supported Platforms

- Linux (x86_64 with or without AVX2, arm64) with glibc or musl libc (e.g., Alpine Linux)[^src-installer]
- macOS (x86_64 with or without AVX2, arm64, including Apple Silicon via Rosetta 2 detection)[^src-installer]
- Windows (x86_64) — via MINGW/MSYS/Cygwin environments[^src-installer]
- Not supported: 32-bit architectures, non-Linux Unix-like OSes (e.g., FreeBSD), Windows arm64[^src-installer]

#### Dependencies

##### Common Dependencies

- `curl` — for downloading the binary and querying the GitHub API[^src-installer]
- `tar` — required on Linux to extract `.tar.gz` archives[^src-installer]
- `unzip` — required on macOS and Windows to extract `.zip` archives[^src-installer]

##### Platform-Specific Dependencies

- **Linux**: The binary links against glibc by default. For musl-based systems (Alpine Linux), the script detects musl and downloads the `-musl` variant, which is statically linked and has no libc dependency[^src-installer].
- **macOS**: No special dependencies beyond those listed above.
- **Windows**: Requires a Unix-like environment (MINGW, MSYS2, or Cygwin) with `unzip` available[^src-installer].

#### Installation Steps

1. **Option A — Run the install script directly** (piped from curl):
   ```bash
   curl -fsSL https://opencode.ai/install | bash
   ```
   This downloads the script and executes it with `bash`. The script will[^src-installer]:
   - Detect the OS (`darwin`, `linux`, `windows`) and architecture (`x64`, `arm64`)
   - Check for AVX2 CPU support on x64 systems and select the `-baseline` variant if unsupported
   - Check for musl libc on Linux and select the `-musl` variant if needed
   - Determine the latest version via the GitHub API
   - Download the matching binary archive from `https://github.com/anomalyco/opencode/releases/latest/download/`
   - Extract the archive and place the `opencode` binary in `$HOME/.opencode/bin`
   - Set permissions to 755 on the binary
   - Add the install directory to the user's PATH in shell configuration files
   - Print completion message with ASCII art

2. **Option B — Run with specific version**:
   ```bash
   curl -fsSL https://opencode.ai/install | bash -s -- --version 1.0.180
   ```
   Or via the `VERSION` environment variable:
   ```bash
   curl -fsSL https://opencode.ai/install | VERSION=1.0.180 bash
   ```

3. **Option C — Download and run locally**:
   ```bash
   curl -fsSL https://opencode.ai/install -o install-opencode.sh
   chmod +x install-opencode.sh
   ./install-opencode.sh
   ```

4. **Option D — Install from a local binary**:
   ```bash
   ./install-opencode.sh --binary /path/to/opencode
   ```
   This skips all download and detection logic and copies the provided binary to the install directory.

5. **Option E — Install without PATH modification**:
   ```bash
   curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
   ```
   Useful in container builds where PATH is managed externally.

#### Installation Verification

- The script prints a success message with ASCII art and the installed version on completion.
- Verify installation by checking the version:
  ```bash
  opencode --version
  ```
  Should output the installed version (e.g., `1.17.12`).
- Verify the binary exists at the expected path:
  ```bash
  ls -la "$(which opencode)"
  ```
  The binary should have mode 755 (`-rwxr-xr-x`) and be located in the install directory.
- The script does not provide checksums or GPG signatures for the downloaded binaries. Verification relies on HTTPS transport security (GitHub over TLS).

#### Configuration Options

##### Version Selection

- **Via `--version` flag**: `bash -s -- --version <version>` — installs a specific version (e.g., `1.0.180`). Version numbers are specified without the leading `v` prefix[^src-installer].
- **Via `VERSION` environment variable**: `VERSION=<version> bash` — alternative way to specify the version[^src-installer].
- **Default (`latest`)**: When no version is specified, the script fetches the latest release tag from the GitHub API (`https://api.github.com/repos/anomalyco/opencode/releases/latest`)[^src-installer].
- **Version validation**: If a specific version is requested, the script first checks whether the release exists by querying the GitHub releases tag URL (`https://github.com/anomalyco/opencode/releases/tag/v<version>`). If the response is 404, the script exits with an error[^src-installer].

##### Installation Path

The install script reads the install directory from the following priority order as documented in the README[^readme-install], though as of v1.17.12 the script itself does not fully implement this logic — it hardcodes `INSTALL_DIR=$HOME/.opencode/bin`. This is a known limitation tracked in GitHub issue #7675[^gh-issue-7675]:

1. `$OPENCODE_INSTALL_DIR` — Custom installation directory (environment variable)
2. `$XDG_BIN_DIR` — XDG Base Directory Specification compliant path
3. `$HOME/bin` — Standard user binary directory (if it exists or can be created)
4. `$HOME/.opencode/bin` — Default fallback

Examples as documented in the README:
```bash
OPENCODE_INSTALL_DIR=/usr/local/bin curl -fsSL https://opencode.ai/install | bash
XDG_BIN_DIR=$HOME/.local/bin curl -fsSL https://opencode.ai/install | bash
```

**Current behavior**: The script always installs to `$HOME/.opencode/bin` regardless of these environment variables[^src-installer]. Workaround options are discussed in issue #7675[^gh-issue-7675]. For container installations, set `INSTALL_DIR` by editing the script after download, or use the binary download method with an explicit target path.

##### User Targeting

- **User-local installation** (default): When run without `sudo` or by a non-root user, the script installs to `$HOME/.opencode/bin`.
- **System-wide installation**: The script does not directly support system-wide installation via environment variables (see above). For system-wide installation in containers, the recommended approach is to copy the binary after installation or use the binary download method:
  ```bash
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
  cp "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode
  ```
- In a Dev Container context, the script typically runs as `root`, so installing to `$HOME/.opencode/bin` and then symlinking or copying to `/usr/local/bin` is straightforward.

##### Required Privileges

- **User-local**: No special privileges required for default installation (writes to user's home directory).
- **System-wide**: Requires root/sudo when installing to system directories like `/usr/local/bin`.
- In Dev Container builds, the script runs as `root` by default, so system-wide installation is straightforward.

##### Tool-Specific Configurations

- `--no-modify-path`: Prevents the script from modifying shell configuration files (`.bashrc`, `.zshrc`, etc.) to add the install directory to PATH[^src-installer]. This is particularly useful in Dev Container or CI environments where PATH is managed externally.
- `--binary <path>`: Skips download and installs from a pre-downloaded binary at the given path. Useful for air-gapped environments or when the binary is obtained through other means[^src-installer].
- `GITHUB_ACTIONS=true`: In GitHub Actions environments, the script appends the install directory path to the file referenced by `$GITHUB_PATH` (a file path variable set by GitHub Actions), making the binary available in subsequent workflow steps[^src-installer].

#### Post-Installation Steps and Cleanup

##### PATH Setup

The install script automatically adds the installation directory to the user's PATH by modifying shell configuration files. The script[^src-installer]:
1. Detects the current shell (`fish`, `zsh`, `bash`, `ash`, `sh`) from the `$SHELL` environment variable.
2. Searches for existing configuration files in a shell-dependent order of precedence:
   - **fish**: `$HOME/.config/fish/config.fish`
   - **zsh**: `${ZDOTDIR:-$HOME}/.zshrc`, `${ZDOTDIR:-$HOME}/.zshenv`, `$XDG_CONFIG_HOME/zsh/.zshrc`, `$XDG_CONFIG_HOME/zsh/.zshenv`
   - **bash**: `$HOME/.bashrc`, `$HOME/.bash_profile`, `$HOME/.profile`, `$XDG_CONFIG_HOME/bash/.bashrc`, `$XDG_CONFIG_HOME/bash/.bash_profile`
   - **ash/sh**: `$HOME/.ashrc`, `$HOME/.profile`, `/etc/profile`
3. Appends the appropriate PATH-export command to the first configuration file found.
4. **Fish shell**: Uses `fish_add_path $INSTALL_DIR`
5. **Other shells**: Uses `export PATH=$INSTALL_DIR:$PATH`
6. Skips modification if the PATH entry already exists (idempotent).
7. Skips entirely if `--no-modify-path` was specified.

If no configuration file is found, the script prints a warning with manual instructions.

**For container/Dev Container environments**: Using `--no-modify-path` and installing to a system PATH directory (like `/usr/local/bin`) is recommended to avoid shell configuration file modifications.

##### Configuration Files

OpenCode uses the following configuration file hierarchy[^docs-config]:
- **Global config**: `~/.config/opencode/opencode.json` (or `opencode.jsonc`) — user-wide preferences for themes, providers, models, permissions, etc.
- **TUI config**: `~/.config/opencode/tui.json` — TUI-specific settings (keybinds, scroll speed, etc.)
- **Project config**: `opencode.json` in the project root — project-specific settings.
- **Custom path**: Via `OPENCODE_CONFIG` environment variable.
- **Config sources are merged**: Later sources override earlier ones only for conflicting keys. Non-conflicting settings from all sources are preserved.

The configuration files are not created during installation but are generated automatically on first run. By default, OpenCode creates `~/.config/opencode/opencode.json` with a `$schema` reference on first startup. The config directory follows the XDG Base Directory Specification.

**Note on `config.json`**: For backwards compatibility, OpenCode also reads `~/.config/opencode/config.json` (the filename used in older versions), but the primary and recommended filename is `opencode.json`[^src-config-ts].

##### Environment Variables

- `OPENCODE_INSTALL_DIR`: Override the installation directory for the install script (documented but currently not implemented — see notes above).
- `XDG_BIN_DIR`: Override the binary installation directory following XDG conventions (documented but currently not implemented).
- `VERSION`: Specify the version to install (alternative to `--version` flag).
- `XDG_CONFIG_HOME`: Override the configuration directory base path (defaults to `$HOME/.config`)[^src-installer].
- `GITHUB_ACTIONS`: When set to `true`, the script adds the install directory to `$GITHUB_PATH` for GitHub Actions workflows[^src-installer].
- `TMPDIR`: Override the temporary directory used during download and extraction (defaults to `/tmp`)[^src-installer].
- API keys for LLM providers are typically configured via `~/.local/share/opencode/auth.json` or set as environment variables (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)[^docs-config][^docs-providers].

##### Activation Scripts

No activation scripts need to be sourced. After PATH is configured, the `opencode` command is available directly. If the PATH was just modified, the user may need to restart their shell or run `source ~/.bashrc` (or equivalent) to update the current session.

##### Shell Completions

OpenCode does not ship pre-built shell completion scripts with the binary[^docs-cli]. Shell completions can be generated manually if needed, but this is not part of the standard installation process.

##### Cleanup

The install script creates a temporary directory at `${TMPDIR:-/tmp}/opencode_install_$$` for downloading and extracting the archive. This directory is cleaned up automatically after installation. No other cleanup steps are necessary.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

OpenCode includes a built-in `upgrade` command that handles version changes:
```bash
opencode upgrade
```
This command detects the installation method that was used and dispatches to the appropriate upgrade logic[^src-installation]:
- **Install script (`curl`)**: Re-downloads and reinstalls via the install script.
- **npm/bun/pnpm/yarn**: Runs the appropriate package manager update command (e.g., `npm install -g opencode-ai@latest`).
- **Homebrew**: Runs the appropriate Homebrew upgrade command.

To downgrade or install a specific version, re-run the installer with the desired version:
```bash
curl -fsSL https://opencode.ai/install | bash -s -- --version 1.0.180
```
Or via the package manager that was originally used.

The install script checks if the requested version is already installed and exits early in that case (idempotent installation). If a different version is installed, it overwrites it.

##### Uninstallation

To uninstall OpenCode installed via the install script:
```bash
rm -f "$HOME/.opencode/bin/opencode"
# Remove the installation directory:
rm -rf "$HOME/.opencode"
```
For system-wide installations, adjust the path accordingly. Configuration files at `~/.config/opencode` and `~/.local/share/opencode` may also be removed if desired, but they will be left behind by default.

For package manager installations, use the standard removal command for that package manager:
- **npm**: `npm uninstall -g opencode-ai`
- **Homebrew**: `brew uninstall opencode` (for the official formula) or `brew untap anomalyco/tap && brew uninstall opencode` (for the tap)
- **pacman**: `sudo pacman -R opencode`

##### Idempotency

**Install script**: If the tool is already installed at the target path and the version matches the requested version, the script exits early with a message. If the version differs, it overwrites the existing binary. The PATH modification is idempotent (checks for duplicate entries before appending)[^src-installer].

**npm package**: The `postinstall.mjs` script selects the correct platform-specific binary and links it. Re-running `npm install` will overwrite the previous installation.

#### Details

**Install script flow** (in detail)[^src-installer]:

1. **Argument parsing**: Parses `--version`, `--binary`, `--no-modify-path`, and `--help` flags. Unknown flags produce a warning but do not stop execution.

2. **Install directory determination**: Always sets `INSTALL_DIR=$HOME/.opencode/bin` and creates it if it doesn't exist. The `OPENCODE_INSTALL_DIR` and `XDG_BIN_DIR` environment variables are documented in the README but are not recognized by the current version of the script[^gh-issue-7675].

3. **Platform detection** (when `--binary` is not used):
   - OS detection via `uname -s`: maps Darwin→darwin, Linux→linux, MINGW/MSYS/CYGWIN→windows.
   - Architecture detection via `uname -m`: maps aarch64→arm64, x86_64→x64.
   - On darwin x64, checks for Rosetta 2 translation (`sysctl sysctl.proc_translated`) and falls back to arm64 if active.
   - Validates the `$os-$arch` combination against supported values: `linux-x64`, `linux-arm64`, `darwin-x64`, `darwin-arm64`, `windows-x64`.
   - On x64, checks for AVX2 CPU support: Linux reads `/proc/cpuinfo`, Darwin uses `sysctl hw.optional.avx2_0`, Windows uses `kernel32.dll!IsProcessorFeaturePresent(40)`. Falls back to `-baseline` variant if AVX2 is unavailable.
   - On Linux, detects musl libc by checking `/etc/alpine-release` and `ldd --version` output. Appends `-musl` to the target triple if musl is detected.
   - Constructs the filename as `opencode-{target}.tar.gz` (Linux) or `opencode-{target}.zip` (macOS/Windows).

4. **Version resolution**: Without `--version`, fetches the latest release from the GitHub API. The release tag is extracted from the JSON response using `sed`. With `--version`, constructs the download URL for that specific version and verifies the release exists via an HTTP HEAD request.

5. **Download and extraction**: Creates a temporary directory. Attempts a custom progress-bar download (using `curl --trace-ascii` piped through `sed` for progress parsing). Falls back to standard curl (with `-#` progress) on Windows, non-TTY environments, or if the custom download fails. Extracts the archive: `tar -xzf` on Linux, `unzip -q` on macOS/Windows.

6. **Binary placement**: Moves the extracted `opencode` binary to `$INSTALL_DIR/opencode` and sets permissions to 755. Cleans up the temporary directory.

7. **Version check** (before download): If the `opencode` command is already available and its version matches the requested version, the script exits early without downloading.

8. **PATH setup**: Detects the current shell. Finds an existing config file for that shell. If the install directory is not already in PATH, appends the appropriate PATH-export command to the config file. Skips if `--no-modify-path` was specified. In GitHub Actions, appends to `$GITHUB_PATH` instead.

9. **Completion message**: Prints ASCII art and instructions for first use.

### Binary Download (Manual)

For environments where running scripts is restricted or undesirable, the pre-built binary can be downloaded directly from the GitHub releases page.

#### Supported Platforms

Same as the install script — Linux, macOS, and Windows on x64 and arm64, including musl and baseline variants.

#### Dependencies

- `curl` or `wget` for download.
- `tar` (Linux) or `unzip` (macOS/Windows) for extraction.

#### Installation Steps

1. Determine the target triple. Available combinations (as per npm package optional dependencies)[^npm-package]:
   - `opencode-linux-x64.tar.gz` — Linux x86_64 (glibc, AVX2)
   - `opencode-linux-x64-baseline.tar.gz` — Linux x86_64 (glibc, no AVX2)
   - `opencode-linux-x64-musl.tar.gz` — Linux x86_64 (musl, AVX2)
   - `opencode-linux-x64-baseline-musl.tar.gz` — Linux x86_64 (musl, no AVX2)
   - `opencode-linux-arm64.tar.gz` — Linux arm64 (glibc)
   - `opencode-linux-arm64-musl.tar.gz` — Linux arm64 (musl)
   - `opencode-darwin-arm64.zip` — macOS Apple Silicon
   - `opencode-darwin-x64.zip` — macOS Intel (AVX2)
   - `opencode-darwin-x64-baseline.zip` — macOS Intel (no AVX2)
   - `opencode-windows-x64.zip` — Windows x86_64 (AVX2)
   - `opencode-windows-x64-baseline.zip` — Windows x86_64 (no AVX2)
   - `opencode-windows-arm64.zip` — Windows arm64

2. Download and extract:
   ```bash
   # Example for Linux x64 with latest version
   curl -sL https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz -o /tmp/opencode.tar.gz
   tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin/
   chmod 755 /usr/local/bin/opencode
   ```

#### Installation Verification

Check the binary runs and reports its version: `opencode --version`.

#### Configuration Options

##### Version Selection

Replace `latest` in the download URL with a specific tag, e.g.:
```
https://github.com/anomalyco/opencode/releases/download/v1.0.180/opencode-linux-x64.tar.gz
```

##### Installation Path

The binary can be placed in any directory on the system PATH. Common choices: `/usr/local/bin`, `/usr/bin`, `~/.local/bin`.

#### Required Privileges

System-wide installation requires root/sudo. User-local installation to `~/.local/bin` does not.

#### Upgrading/Downgrading

Download and replace the binary at the target path with the new version.

#### Uninstallation

Remove the binary file from the installation directory.

#### Idempotency

Overwriting the binary with the same or different version is safe and produces a working installation.

#### Notes and Best Practices

This is the most straightforward method for container builds. It avoids any runtime script execution risk and gives precise control over the binary location. The only downside is that the user must manually determine the correct target triple for their platform.

### npm Installation

OpenCode is available as the `opencode-ai` npm package, which uses optional platform-specific binary packages[^npm-package].

#### Supported Platforms

Same as the install script — Linux, macOS, and Windows on x64 and arm64. The `opencode-ai` npm package declares `"os": ["darwin", "linux", "win32"]` and `"cpu": ["arm64", "x64"]`[^npm-package].

#### Dependencies

- **Node.js** (any version that supports npm) — only needed to run `npm install`. The binary itself is self-contained.
- `npm`, `bun`, `pnpm`, or `yarn` package manager.
- The package has no runtime Node.js dependencies; it uses optional dependencies for each platform-specific binary (e.g., `opencode-linux-x64`, `opencode-darwin-arm64`). The `postinstall.mjs` script selects and links the correct native binary for the platform[^npm-package].

#### Installation Steps

```bash
npm install -g opencode-ai        # npm
bun install -g opencode-ai        # bun
pnpm install -g opencode-ai       # pnpm
yarn global add opencode-ai       # yarn
```

The `postinstall.mjs` script runs automatically and links the correct binary for the platform. The package structure uses a wrapper strategy: the `opencode` binary exposed via `bin` in `package.json` is a thin executable that invokes the platform-specific binary from the appropriate optional dependency package (e.g., `opencode-linux-x64`)[^npm-package].

#### Installation Verification

`opencode --version`

#### Configuration Options

##### Version Selection

Use standard npm version specifiers:
```bash
npm install -g opencode-ai@latest     # Latest stable
npm install -g opencode-ai@1.0.180    # Specific version
```

##### Required Privileges

- System-wide: May require `sudo` depending on npm global installation prefix configuration.
- User-local: `npm install -g` respects npm prefix configuration.

#### Upgrading/Downgrading

```bash
npm install -g opencode-ai@<version>
```

#### Uninstallation

```bash
npm uninstall -g opencode-ai
```

#### Idempotency

Re-running the install command will update the binary to the specified version.

#### Notes and Best Practices

This method is convenient when a Node.js/npm environment is already present (common in development containers). However, it adds npm as a dependency and may pull in extraneous packages.

### Homebrew Installation (macOS and Linux)

OpenCode can be installed via Homebrew on macOS and Linux[^readme-install].

#### Supported Platforms

- macOS (Intel and Apple Silicon)
- Linux (x86_64, arm64)

#### Dependencies

- Homebrew package manager

#### Installation Steps

**Recommended tap** (always up to date):
```bash
brew install anomalyco/tap/opencode
```

**Official Homebrew formula** (updated less frequently):
```bash
brew install opencode
```

#### Installation Verification

```bash
opencode --version
```

#### Upgrading

```bash
brew upgrade opencode           # For the official formula
brew upgrade anomalyco/tap/opencode  # For the tap
```

#### Uninstallation

```bash
brew uninstall opencode
```

### Arch Linux (AUR) Installation

OpenCode is available in the Arch Linux community repository and the Arch User Repository[^readme-install].

#### Supported Platforms

- Arch Linux (x86_64, aarch64)

#### Installation Steps

**Stable version** (community repository):
```bash
sudo pacman -S opencode
```

**Latest version** (AUR):
```bash
paru -S opencode-bin
```

#### Installation Verification

```bash
opencode --version
```

#### Upgrading

```bash
sudo pacman -Syu
# Or for AUR:
paru -Syu
```

#### Uninstallation

```bash
sudo pacman -R opencode
```

### Additional Package Managers

OpenCode is also available via[^readme-install]:

- **Scoop** (Windows):
  ```bash
  scoop install opencode
  ```
- **Chocolatey** (Windows):
  ```bash
  choco install opencode
  ```
- **Mise** (any OS):
  ```bash
  mise use -g opencode
  ```
- **Nix/NixOS**:
  ```bash
  nix run nixpkgs#opencode
  # Or for latest dev branch:
  nix run github:anomalyco/opencode
  ```
- **Docker**:
  ```bash
  docker run -it --rm ghcr.io/anomalyco/opencode
  ```

## Dev Container Setup

When installing OpenCode in a Dev Container, the following considerations apply:

1. **Recommended method**: Use the install script with `--no-modify-path` and copy the binary to a system-wide location:
   ```bash
   curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
   cp "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode
   ```
   This makes `opencode` available to all users immediately without modifying shell config files.

2. **Alternative (simpler) method**: Use the binary download approach to place the binary directly:
   ```bash
   curl -sL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz" -o /tmp/opencode.tar.gz
   tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin/
   chmod 755 /usr/local/bin/opencode
   rm /tmp/opencode.tar.gz
   ```

3. **Version pinning**: Specify a version to ensure reproducible builds:
   ```bash
   curl -sL "https://github.com/anomalyco/opencode/releases/download/v1.17.12/opencode-linux-x64.tar.gz" -o /tmp/opencode.tar.gz
   tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin/
   ```

4. **Dependencies**: The install script requires `curl`, and on Linux, `tar`. The common-utils devcontainer feature provides these. For Alpine-based images, `curl` and `tar` must be installed explicitly if not already present. For the binary download approach, only `curl` and `tar` (or `wget`) are needed.

5. **Architecture handling**: For arm64 containers (e.g., Apple Silicon Macs), use `opencode-linux-arm64.tar.gz`. For x86_64 containers, use `opencode-linux-x64.tar.gz`. For Alpine-based containers, use the `-musl` variants.

6. **API key configuration**: For using OpenCode with LLM providers inside a Dev Container, API keys can be[^docs-config][^docs-providers]:
   - Mounted from the host via a bind mount of `~/.local/share/opencode/auth.json` to the container (e.g., `/mnt/opencode-auth.json`)
   - Set via environment variables in `devcontainer.json` (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
   - Configured interactively on first run via the `/connect` command

7. **Data persistence**: The OpenCode configuration and data directories (`~/.config/opencode`, `~/.local/share/opencode`) are ephemeral in containers by default. For persistent sessions, consider mounting these from the host.

8. **Terminal emulator**: For the TUI to work properly, the Dev Container host should use a modern terminal emulator (WezTerm, Alacritty, Ghostty, Kitty)[^docs-intro]. The TUI requires proper terminal capabilities for rendering.

9. **Permissions**: Since Dev Container builds run as root, the binary can be placed in system directories without issues. When a non-root `remoteUser` is configured, ensure the binary is world-executable (mode 755) which is the default.

10. **Community Dev Container Features**: Existing community-maintained Dev Container Features for opencode provide reference implementations[^community-feature-stubell][^community-feature-dirien][^community-feature-devcontainer-community]:
    - `ghcr.io/stu-bell/devcontainer-features/open-code` — Installs via the official install script, supporting version selection and Alpine/Debian/Ubuntu[^community-feature-stubell].
    - `ghcr.io/dirien/devcontainer-features/opencode` — Installs via the official install script with API key mounting support[^community-feature-dirien].
    - `ghcr.io/devcontainer-community/devcontainer-features/opencode.ai` — Installs via direct binary download from GitHub releases[^community-feature-devcontainer-community].

## Plugins and Extensions

OpenCode supports several extension mechanisms:

- **Plugins**: OpenCode has a plugin API (`@opencode-ai/plugin`) that allows third-party developers to extend its functionality[^docs-plugins].
- **MCP Servers**: OpenCode can integrate with any MCP (Model Context Protocol) server to provide additional tools and capabilities[^docs-mcp].
- **ACP Support**: OpenCode supports the Agent Communication Protocol for interoperability with other AI agents[^docs-acp].
- **Agent Skills**: Custom skills can be defined to teach OpenCode specialized behaviors[^docs-skills].
- **Custom Tools**: Users can define custom tools accessible via the `/tool` command[^docs-custom-tools].
- **IDE Extensions**: OpenCode offers extensions for VS Code, Cursor, Zed, Windsurf, and VSCodium[^docs-ide].
- **GitHub/GitLab Integration**: OpenCode can be installed as a GitHub App or GitLab integration for repository automation, triggered by issue comments containing `/oc` or `/opencode`[^docs-github][^docs-gitlab].

## References

[^docs-intro]: [OpenCode Documentation – Intro](https://opencode.ai/docs/) — Overview, prerequisites, installation, configuration, initialization, and usage guide.
[^docs-install]: [OpenCode Documentation – Install](https://opencode.ai/docs/#install) — Detailed installation instructions including the install script, npm, Homebrew, AUR, Mise, and Docker methods.
[^docs-config]: [OpenCode Documentation – Config](https://opencode.ai/docs/config/) — Configuration file reference for `opencode.json` (global config at `~/.config/opencode/opencode.json`), precedence order, and all configuration options.
[^docs-providers]: [OpenCode Documentation – Providers](https://opencode.ai/docs/providers/) — LLM provider configuration and API key setup.
[^docs-github]: [OpenCode Documentation – GitHub](https://opencode.ai/docs/github/) — GitHub agent installation and workflow configuration.
[^docs-gitlab]: [OpenCode Documentation – GitLab](https://opencode.ai/docs/gitlab/) — GitLab integration documentation.
[^docs-tui]: [OpenCode Documentation – TUI](https://opencode.ai/docs/tui/) — TUI usage guide covering commands, keybinds, configuration, and customization.
[^docs-cli]: [OpenCode Documentation – CLI](https://opencode.ai/docs/cli/) — CLI commands reference.
[^docs-plugins]: [OpenCode Documentation – Plugins](https://opencode.ai/docs/plugins/) — Plugin API and development guide.
[^docs-mcp]: [OpenCode Documentation – MCP Servers](https://opencode.ai/docs/mcp-servers/) — Model Context Protocol server integration.
[^docs-acp]: [OpenCode Documentation – ACP Support](https://opencode.ai/docs/acp/) — Agent Communication Protocol support.
[^docs-skills]: [OpenCode Documentation – Agent Skills](https://opencode.ai/docs/skills/) — Custom agent skills documentation.
[^docs-custom-tools]: [OpenCode Documentation – Custom Tools](https://opencode.ai/docs/custom-tools/) — Custom tool definition guide.
[^docs-ide]: [OpenCode Download Page](https://opencode.ai/download/) — IDE extensions for VS Code, Cursor, Zed, Windsurf, and VSCodium.
[^readme-install]: [GitHub README – Installation](https://github.com/anomalyco/opencode) — README with installation methods, directory selection order, and examples.
[^src-installer]: [Install Script Source Code (dev branch)](https://raw.githubusercontent.com/anomalyco/opencode/refs/heads/dev/install) — The complete official install script with all logic for platform detection, download, extraction, PATH setup, and shell configuration.
[^src-package-json]: [Root package.json](https://github.com/anomalyco/opencode/blob/dev/package.json) — Project metadata, workspaces, dependency catalogs, and build configuration.
[^src-config-ts]: [Config Source Code](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/config/config.ts) — Source code showing the `globalConfigFile()` function and config loading logic with `opencode.json` as the primary config file and `config.json` as fallback.
[^src-installation]: [Installation Service Source Code](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/installation/index.ts) — Source code for the `Installation.Service` with the `upgrade()` method that dispatches to method-specific upgrade commands (curl, npm, brew, choco, scoop, etc.).
[^src-upgrade-cli]: [Upgrade CLI Command Source Code](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/cli/upgrade.ts) — Source code for the `opencode upgrade` CLI command.
[^src-build]: [Build Script Source Code](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/script/build.ts) — Source code for the CLI build script showing the use of `Bun.build` with `compile` option and the full target matrix (12 platform combinations).
[^src-run]: [CLI Run Command Source Code](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/cli/cmd/run.ts) — Source code for the CLI `run` command implementing interactive mode, Worker Thread initialization, and SSE/RPC-based communication between the TUI and the embedded HTTP server.
[^npm-package]: [npm Registry – opencode-ai](https://registry.npmjs.org/opencode-ai/latest) — npm package metadata with optional platform-specific binary dependencies (12 platform targets).
[^github-latest-release]: [GitHub Releases – Latest](https://api.github.com/repos/anomalyco/opencode/releases/latest) — Latest release metadata (v1.17.12 as of 2026-06-30).
[^gh-issue-7675]: [GitHub Issue #7675 – Install script ignores OPENCODE_INSTALL_DIR](https://github.com/anomalyco/opencode/issues/7675) — Confirmed discrepancy between README documentation and actual install script behavior; the script hardcodes `INSTALL_DIR=$HOME/.opencode/bin` and does not respect `$OPENCODE_INSTALL_DIR` or `$XDG_BIN_DIR`.
[^community-feature-stubell]: [stu-bell/devcontainer-features – open-code](https://github.com/stu-bell/devcontainer-features/tree/main/src/open-code) — Community Dev Container Feature using the install script with version support and Alpine compatibility.
[^community-feature-dirien]: [dirien/devcontainer-features – opencode](https://github.com/dirien/devcontainer-features/tree/main/src/opencode) — Community Dev Container Feature with API key mounting support.
[^community-feature-devcontainer-community]: [devcontainer-community/devcontainer-features – opencode.ai](https://github.com/devcontainer-community/devcontainer-features/tree/main/src/opencode.ai) — Community Dev Container Feature using direct binary download from GitHub releases.
