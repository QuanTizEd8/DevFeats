# Feature Reference

[OpenCode](https://opencode.ai) is an open-source AI coding agent designed to operate as a terminal-based interface for code generation, explanation, refactoring, and general development assistance. It supports 75+ LLM providers (including Anthropic, OpenAI, Google, OpenRouter, etc.)[^docs-intro] and can be used interactively via its Terminal UI (TUI), non-interactively for automation via its `run` subcommand, as a web application, as an IDE extension (VS Code, Cursor, Zed, Windsurf, VSCodium), or as a GitHub/GitLab agent for repository automation[^docs-github][^docs-gitlab]. OpenCode is a fully open-source project under the MIT license.

OpenCode is written in TypeScript and compiled into self-contained native binaries using Bun's `compile` feature, meaning it requires no runtime dependencies (such as Node.js, Python, or a JVM) to execute. It uses Bun as the primary runtime environment for development, and the pre-built binaries are standalone executables for Linux, macOS, and Windows on both x64 and arm64 architectures[^deepwiki-arch].

- **Homepage**: https://opencode.ai
- **Source Code**: https://github.com/anomalyco/opencode
- **Documentation**: https://opencode.ai/docs
- **Latest Release**: v1.17.12 (as of 2026-06-30)[^github-latest-release]

## Tool Architecture

OpenCode is a single, self-contained CLI binary that serves as both a client and server for AI-powered coding assistance. Its architecture[^deepwiki-arch][^blog-arch] includes:

- **Primary binary**: A single executable named `opencode` compiled via `bun build --compile`, which includes an embedded server (using the Hono framework), a TUI renderer (using Ink/React-based terminal UI rendering), an SDK client, a tool registry and execution engine, LSP server management (supporting 20+ languages), a session and agent management system, and provider integrations for 75+ LLM services[^src-package-json].
- **Self-contained**: The compiled binary embeds all dependencies, including a web UI bundle, and requires no external runtime (Node.js, Python, etc.) for normal operation.
- **Client-server architecture**: The TUI runs as a separate thread (Worker Thread) that communicates with the embedded HTTP server via SSE (Server-Sent Events) and RPC. The server process handles all I/O-intensive work (LLM streaming, file operations, MCP connections), while the TUI thread handles rendering and user input. This separation also allows the CLI to connect to a remote `opencode serve` instance, enabling a "local editing, remote inference" workflow[^cli-source-analysis].
- **No external services required**: OpenCode can be used entirely locally with any configured LLM provider; it does not require a cloud service, although a hosted Zen service is available for curated model access.
- **Development runtime**: During development, OpenCode uses Bun (v1.3.14+) as its runtime with a TypeScript codebase organized as a Turborepo monorepo[^src-package-json].
- **Extensible via plugins**: OpenCode supports a plugin system, MCP (Model Context Protocol) servers, ACP (Agent Communication Protocol) support, custom tools, and agent skills[^docs-plugins].

## Installation Methods

OpenCode offers a wide variety of installation methods[^readme-install]. The most relevant methods for containers, CI/CD, and automated environments are the **install script** (recommended for Dev Container Features) and the **direct binary download** approach, as they do not require Node.js, Homebrew, or any other package manager. The npm-based installation is also viable when a Node.js runtime is already present.

### Install Script (Recommended)

The official install script at `https://opencode.ai/install` is a self-contained bash script that detects the OS and architecture, downloads the appropriate pre-built binary from the GitHub releases page, installs it to a user-local directory, and optionally adds the installation directory to the user's PATH[^src-installer].

#### Supported Platforms

- Linux (x86_64 with or without AVX2, arm64) with glibc or musl libc (e.g., Alpine Linux)[^src-installer]
- macOS (x86_64 with or without AVX2, arm64, including Apple Silicon via Rosetta 2 detection)[^src-installer]
- Windows (x86_64, arm64) — via MINGW/MSYS/Cygwin environments[^src-installer]
- Not supported: 32-bit architectures, non-Linux Unix-like OSes (e.g., FreeBSD)[^src-installer]

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
   - Extract the archive and place the `opencode` binary in the install directory
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
  Expected output: `-rwxr-xr-x` (mode 755) pointing to the install directory.
- The script does not provide checksums or GPG signatures for the downloaded binaries. Verification relies on HTTPS transport security (GitHub over TLS).

#### Configuration Options

##### Version Selection

- **Via `--version` flag**: `bash -s -- --version <version>` — installs a specific version (e.g., `1.0.180`). Version numbers are specified without the leading `v` prefix[^src-installer].
- **Via `VERSION` environment variable**: `VERSION=<version> bash` — alternative way to specify the version[^src-installer].
- **Default (`latest`)**: When no version is specified, the script fetches the latest release tag from the GitHub API (`https://api.github.com/repos/anomalyco/opencode/releases/latest`)[^src-installer].
- **Version validation**: If a specific version is requested, the script first checks whether the release exists by querying the GitHub releases tag URL (`https://github.com/anomalyco/opencode/releases/tag/v<version>`). If the response is 404, the script exits with an error[^src-installer].

##### Installation Path

The install script determines the installation directory using the following priority order[^readme-install]:

1. `$OPENCODE_INSTALL_DIR` — Custom installation directory (environment variable)
2. `$XDG_BIN_DIR` — XDG Base Directory Specification compliant path
3. `$HOME/bin` — Standard user binary directory (if it exists or can be created)
4. `$HOME/.opencode/bin` — Default fallback

Examples:
```bash
OPENCODE_INSTALL_DIR=/usr/local/bin curl -fsSL https://opencode.ai/install | bash
XDG_BIN_DIR=$HOME/.local/bin curl -fsSL https://opencode.ai/install | bash
```

Note: The default install directory (`$HOME/.opencode/bin`) is a user-local path, which is appropriate for non-root installations. For system-wide container installations, the `OPENCODE_INSTALL_DIR` variable should be set to a system-wide location like `/usr/local/bin`[^src-installer].

##### User Targeting

- **User-local installation** (default): When run without `sudo` or by a non-root user, the script installs to `$HOME/.opencode/bin` (or one of the alternatives above)[^src-installer].
- **System-wide installation**: Setting `OPENCODE_INSTALL_DIR=/usr/local/bin` before running the script achieves system-wide installation, but requires write access to the target directory (root/sudo)[^src-installer].
- In a Dev Container context, the script typically runs as `root`, so setting `OPENCODE_INSTALL_DIR` to `/usr/local/bin` is the recommended approach for making the binary available to all users.

##### Required Privileges

- **User-local**: No special privileges required for default installation (writes to user's home directory).
- **System-wide**: Requires root/sudo when installing to system directories like `/usr/local/bin`.
- In Dev Container builds, the script runs as `root` by default, so system-wide installation is straightforward.

##### Tool-Specific Configurations

- `--no-modify-path`: Prevents the script from modifying shell configuration files (`.bashrc`, `.zshrc`, etc.) to add the install directory to PATH[^src-installer]. This is particularly useful in Dev Container or CI environments where PATH is managed externally.
- `--binary <path>`: Skips download and installs from a pre-downloaded binary at the given path. Useful for air-gapped environments or when the binary is obtained through other means[^src-installer].
- `GITHUB_ACTIONS=true`: In GitHub Actions environments, the script appends the install directory to `$GITHUB_PATH` to make the binary available in subsequent workflow steps[^src-installer].
- **Docker usage**: OpenCode can be run directly via Docker without installation:
  ```bash
  docker run -it --rm ghcr.io/anomalyco/opencode
  ```
  This method runs the CLI in a container and is useful for ephemeral usage[^docs-install].

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

**For container/Dev Container environments**: Using `--no-modify-path` and setting `OPENCODE_INSTALL_DIR` to a system PATH directory (like `/usr/local/bin`) is recommended to avoid shell configuration file modifications.

##### Configuration Files

OpenCode uses a configuration file at `~/.config/opencode/config.json` for persistent settings (themes, keybindings, model configuration, etc.)[^docs-config]. This file is not created during installation but is generated automatically on first run or can be created manually. The configuration directory follows the XDG Base Directory Specification.

##### Environment Variables

- `OPENCODE_INSTALL_DIR`: Override the installation directory for the install script.
- `XDG_BIN_DIR`: Override the binary installation directory following XDG conventions.
- `VERSION`: Specify the version to install (alternative to `--version` flag).
- `XDG_CONFIG_HOME`: Override the configuration directory base path (defaults to `$HOME/.config`)[^src-installer].
- `GITHUB_ACTIONS`: When set to `true`, the script adds the install directory to `$GITHUB_PATH` for GitHub Actions workflows[^src-installer].
- `TMPDIR`: Override the temporary directory used during download and extraction (defaults to `/tmp`)[^src-installer].
- API keys for LLM providers are typically configured via `~/.local/share/opencode/auth.json` or set as environment variables (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)[^docs-config][^docs-providers].

##### Activation Scripts

No activation scripts need to be sourced. After PATH is configured, the `opencode` command is available directly. If the PATH was just modified, the user may need to restart their shell or run `source ~/.bashrc` (or equivalent) to update the current session.

##### Shell Completions

OpenCode does not ship pre-built shell completion scripts with the binary. Shell completions can be generated manually if needed, but this is not part of the standard installation process.

##### Cleanup

The install script creates a temporary directory at `${TMPDIR:-/tmp}/opencode_install_$$` for downloading and extracting the archive. This directory is cleaned up automatically after installation. No other cleanup steps are necessary.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

OpenCode includes a built-in `upgrade` command that handles version changes[^deepwiki-install]:
```bash
opencode upgrade
```
This command detects the installation method that was used (via `Installation.Service`) and dispatches to the appropriate upgrade logic:
- **Install script (`curl`)**: Re-downloads and reinstalls via the install script.
- **npm/bun/pnpm/yarn**: Runs the appropriate package manager update command (e.g., `npm install -g opencode-ai@latest`).
- **Homebrew**: Runs `brew upgrade opencode`.

To downgrade or install a specific version, re-run the installer with the desired version:
```bash
curl -fsSL https://opencode.ai/install | bash -s -- --version 1.0.180
```
Or via the package manager that was originally used.

The install script checks if the requested version is already installed and exits early in that case (idempotent installation). If a different version is installed, it overwrites it.

##### Uninstallation

To uninstall OpenCode installed via the install script:
```bash
rm -f "$(which opencode)"
# If installed to the default directory:
rm -rf "$HOME/.opencode"
```
For system-wide installations, use `sudo rm` as needed. Configuration files at `~/.config/opencode` and `~/.local/share/opencode/` may also be removed if desired, but they will be left behind by default.

For package manager installations, use the standard removal command for that package manager:
- **npm**: `npm uninstall -g opencode-ai`
- **Homebrew**: `brew uninstall opencode`
- **pacman**: `sudo pacman -R opencode`

##### Idempotency

**Install script**: If the tool is already installed at the target path and the version matches the requested version, the script exits early with a message. If the version differs, it overwrites the existing binary. The PATH modification is idempotent (checks for duplicate entries before appending)[^src-installer].

**npm package**: The `postinstall.mjs` script selects the correct platform-specific binary and links it. Re-running `npm install` will overwrite the previous installation.

### Binary Download (Manual)

For environments where running scripts is restricted or undesirable, the pre-built binary can be downloaded directly from the GitHub releases page.

#### Supported Platforms

Same as the install script — Linux, macOS, and Windows on x64 and arm64, including musl and baseline variants.

#### Dependencies

- `curl` or `wget` for download.
- `tar` (Linux) or `unzip` (macOS/Windows) for extraction.

#### Installation Steps

1. Determine the target triple:
   - Linux glibc x64: `opencode-linux-x64.tar.gz`
   - Linux glibc x64 (no AVX2): `opencode-linux-x64-baseline.tar.gz`
   - Linux arm64: `opencode-linux-arm64.tar.gz`
   - Linux musl x64: `opencode-linux-x64-musl.tar.gz`
   - macOS arm64: `opencode-darwin-arm64.zip`
   - macOS x64: `opencode-darwin-x64.zip`
   - Windows x64: `opencode-windows-x64.zip`

2. Download and extract:
   ```bash
   # Example for Linux x64
   curl -sL https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz -o /tmp/opencode.tar.gz
   tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin/
   chmod 755 /usr/local/bin/opencode
   ```

3. Verify: `opencode --version`

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

The `postinstall.mjs` script runs automatically and links the correct binary for the platform[^deepwiki-install].

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

## Dev Container Setup

When installing OpenCode in a Dev Container, the following considerations apply:

1. **Recommended method**: Use the install script with `OPENCODE_INSTALL_DIR=/usr/local/bin` and `--no-modify-path` to install system-wide without modifying shell configuration files:
   ```bash
   OPENCODE_INSTALL_DIR=/usr/local/bin curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
   ```
   This places `opencode` in `/usr/local/bin`, making it available to all users immediately.

2. **Version pinning**: Specify a version to ensure reproducible builds:
   ```bash
   OPENCODE_INSTALL_DIR=/usr/local/bin curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path --version 1.17.12
   ```

3. **Dependencies**: The install script requires `curl`, and on Linux, `tar`. The common-utils devcontainer feature provides these. For Alpine-based images, `curl` and `tar` must be installed explicitly if not already present.

4. **API key configuration**: For using OpenCode with LLM providers inside a Dev Container, API keys can be[^docs-config][^docs-providers]:
   - Mounted from the host via a bind mount of `~/.local/share/opencode/auth.json` to the container (e.g., `/mnt/opencode-auth.json`)
   - Set via environment variables in `devcontainer.json` (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
   - Configured interactively on first run via `/connect` command

5. **Data persistence**: The OpenCode configuration and data directories (`~/.config/opencode`, `~/.local/share/opencode`) are ephemeral in containers by default. For persistent sessions, consider mounting these from the host.

6. **Terminal emulator**: For the TUI to work properly, the Dev Container host should use a modern terminal emulator (WezTerm, Alacritty, Ghostty, Kitty)[^docs-intro]. The TUI requires proper terminal capabilities for rendering.

7. **Permissions**: Since Dev Container builds run as root, the install script can write to system directories without issues. However, the binary should be made available to the non-root `remoteUser` if one is configured. Installing to `/usr/local/bin` (which is world-readable and world-executable) handles this.

8. **Community Dev Container Features**: Existing community-maintained Dev Container Features for opencode provide reference implementations[^community-feature-stubell][^community-feature-dirien][^community-feature-devcontainer-community]:
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
[^docs-config]: [OpenCode Documentation – Config](https://opencode.ai/docs/config/) — Configuration file reference for `~/.config/opencode/config.json`.
[^docs-providers]: [OpenCode Documentation – Providers](https://opencode.ai/docs/providers/) — LLM provider configuration and API key setup.
[^docs-github]: [OpenCode Documentation – GitHub](https://opencode.ai/docs/github/) — GitHub agent installation and workflow configuration.
[^docs-gitlab]: [OpenCode Documentation – GitLab](https://opencode.ai/docs/gitlab/) — GitLab integration documentation.
[^docs-plugins]: [OpenCode Documentation – Plugins](https://opencode.ai/docs/plugins/) — Plugin API and development guide.
[^docs-mcp]: [OpenCode Documentation – MCP Servers](https://opencode.ai/docs/mcp-servers/) — Model Context Protocol server integration.
[^docs-acp]: [OpenCode Documentation – ACP Support](https://opencode.ai/docs/acp/) — Agent Communication Protocol support.
[^docs-skills]: [OpenCode Documentation – Agent Skills](https://opencode.ai/docs/skills/) — Custom agent skills documentation.
[^docs-custom-tools]: [OpenCode Documentation – Custom Tools](https://opencode.ai/docs/custom-tools/) — Custom tool definition guide.
[^docs-ide]: [OpenCode Download Page](https://opencode.ai/download/) — IDE extensions for VS Code, Cursor, Zed, Windsurf, and VSCodium.
[^readme-install]: [GitHub README – Installation](https://github.com/anomalyco/opencode) — README with installation methods, directory selection order, and examples.
[^src-installer]: [Install Script Source Code](https://raw.githubusercontent.com/anomalyco/opencode/refs/heads/dev/install) — The complete official install script with all logic for platform detection, download, extraction, PATH setup, and shell configuration.
[^src-package-json]: [Root package.json](https://github.com/anomalyco/opencode/blob/dev/package.json) — Project metadata, workspaces, dependency catalogs, and build configuration.
[^npm-package]: [npm Registry – opencode-ai](https://registry.npmjs.org/opencode-ai/latest) — npm package metadata with optional platform-specific binary dependencies.
[^github-latest-release]: [GitHub Releases – Latest](https://api.github.com/repos/anomalyco/opencode/releases/latest) — Latest release metadata (v1.17.12 as of 2026-06-30).
[^deepwiki-arch]: [DeepWiki – Repository Structure & Packages](https://deepwiki.com/anomalyco/opencode/1.1-repository-structure-and-packages) — Monorepo organization, package structure, and technology stack (Bun, TypeScript, Turborepo).
[^deepwiki-platform-builds]: [DeepWiki – Platform-Specific Builds](https://deepwiki.com/anomalyco/opencode/9.4-platform-specific-builds) — Build matrix for all 12 target combinations, binary naming conventions, and build toolchain.
[^deepwiki-install]: [DeepWiki – Installation and Setup](https://deepwiki.com/sst/opencode/1.3-installation-and-setup) — Analysis of installation methods, platform detection, binary resolution, and the upgrade mechanism.
[^cli-source-analysis]: [CLI Source Code Analysis](https://www.opencode.asia/source-code/cli/) — Architecture of the CLI, TUI, and Server components, SSE event streaming, and Worker Thread communication.
[^blog-arch]: [Dissecting OpenCode: Architecture Analysis](https://zengineer.blog/blog/tech/opencode-architecture-deep-dive-en/) — Detailed architectural breakdown of OpenCode's layers, runtime, tool system, and agent scheduler.
[^community-feature-stubell]: [stu-bell/devcontainer-features – open-code](https://github.com/stu-bell/devcontainer-features/tree/main/src/open-code) — Community Dev Container Feature using the install script with version support and Alpine compatibility.
[^community-feature-dirien]: [dirien/devcontainer-features – opencode](https://github.com/dirien/devcontainer-features/tree/main/src/opencode) — Community Dev Container Feature with API key mounting support.
[^community-feature-devcontainer-community]: [devcontainer-community/devcontainer-features – opencode.ai](https://github.com/devcontainer-community/devcontainer-features/tree/main/src/opencode.ai) — Community Dev Container Feature using direct binary download from GitHub releases.
