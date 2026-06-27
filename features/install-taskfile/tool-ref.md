# Feature Reference

Task (also known as go-task) is a fast, cross-platform task runner and build tool inspired by Make. It reads task definitions from `Taskfile.yml` (or `.yaml`) files and executes named tasks with dependency resolution, parallel execution, file watching, and templating. Task is widely used as a simpler, modern alternative to Make in development workflows, CI pipelines, and devcontainer build contexts.[^homepage][^docs-install]

- **Homepage**: https://taskfile.dev/
- **Source Code**: https://github.com/go-task/task
- **Documentation**: https://taskfile.dev/docs/
- **Latest Release**: v3.51.1 (as of 2026-06-28)[^gh-api-latest]

## Tool Architecture

Task is a **single static Go binary** named `task`.[^repo] It is compiled with `CGO_ENABLED=0` and has no runtime dependencies — no JVM, Node.js, or Python interpreter is required at runtime.[^goreleaser] The binary is fully self-contained and operates as a **standalone CLI tool** with no client-server architecture and no required external services at runtime.[^repo]

**Programming language and build system**: Go (module path `github.com/go-task/task/v3`).[^go-mod] Minimum Go version required to build from source is **Go 1.25.10** (as declared in `go.mod`).[^go-mod] Official releases are built and packaged by GoReleaser.[^goreleaser]

**Release artifact naming convention** (GoReleaser `name_template`):

| Artifact type | Naming pattern | Example |
|---|---|---|
| Tarball/zip binary archive | `task_{os}_{arch}.{tar.gz\|zip}` | `task_linux_amd64.tar.gz` |
| DEB/RPM/APK packages | `task_{version}_{os}_{arch}.{deb\|rpm\|apk}` | `task_3.51.1_linux_amd64.deb` |
| Checksums file | `task_checksums.txt` | SHA-256 for all release assets |

[^goreleaser]

**Supported build targets** (GoReleaser `builds` matrix):[^goreleaser]

| OS | Architectures |
|---|---|
| linux | 386, amd64, arm (GOARM=6), arm64, riscv64 |
| darwin | amd64, arm, arm64 (386 and riscv64 excluded) |
| windows | 386, amd64, arm64 (arm and riscv64 excluded) |
| freebsd | 386, amd64, arm, arm64 |

**Binary archive contents**: Each tarball/zip contains the `task` binary plus `README.md`, `LICENSE`, and a `completion/` directory with shell completion scripts for bash, zsh, fish, and PowerShell.[^goreleaser][^release-tarball]

**Executable name**: The installed command is always `task`. Package names vary by distribution channel (`task` for official Cloudsmith repos; `go-task` for Homebrew, Arch, and several community packages).[^docs-install][^goreleaser-brews]

**Package conflict**: Official DEB/RPM/APK packages declare a conflict with `taskwarrior` (a separate task-management application that also provides a `task` binary).[^goreleaser-nfpms]

## Installation Methods

Task is distributed through official package repositories (Cloudsmith-hosted apt/dnf/apk, Homebrew, Snap, npm), community package managers, prebuilt GitHub release binaries, an official install script, Go toolchain methods, and a GitHub Actions installer. For DevFeats (macOS and Linux, containers and bare metal), the implementation-relevant methods are:

1. **Official Cloudsmith package repositories** (apt, dnf, apk) — team-maintained, always up-to-date, includes shell completions in package post-install paths.
2. **Homebrew** — primary macOS package-manager path; official tap and core formula both available.
3. **Official install script** (`https://taskfile.dev/install.sh`) — fast CI-oriented binary install with SHA-256 checksum verification.
4. **Manual prebuilt release archive install** — deterministic, auditable binary placement from GitHub Releases.
5. **npm** (`@go-task/cli`) — official cross-platform npm wrapper around the prebuilt binary.
6. **Go toolchain install** (`go install`) — build/install from source when Go is already present.
7. **Go tool tracking** (`go get -tool` / `go tool task`) — project-local tool dependency without global install.
8. **Community package managers** (mise/aqua/ubi, MacPorts, pip, Arch pacman, Nix, etc.) — useful where official repos are unavailable; version freshness not guaranteed by Task team.

GitHub Actions setup (`go-task/setup-task`) is documented under [Dev Container Setup](#dev-container-setup) for CI and devcontainer build contexts.

### Official Cloudsmith Package Repositories (apt / dnf / apk)

These repositories are maintained by the Task team via Cloudsmith and are documented as always up-to-date.[^docs-install][^cloudsmith]

#### Supported Platforms

| Package manager | Supported platforms |
|---|---|
| apt (`.deb`) | Debian-based Linux distributions (Debian, Ubuntu, etc.) |
| dnf (`.rpm`) | Red Hat-based Linux distributions (Fedora, RHEL, CentOS, etc.) |
| apk | Alpine Linux and other apk-based distributions |

#### Dependencies

##### Common Dependencies

- `curl` (to fetch and pipe the Cloudsmith setup script).
- `sudo` or root privileges (setup scripts configure system package sources and install packages system-wide).

##### Platform-Specific Dependencies

- **apt**: `apt` package manager with `dpkg` backend.
- **dnf**: `dnf` or compatible RPM package manager.
- **apk**: Alpine `apk` package manager.

#### Installation Steps

**Step 1 — Configure the Cloudsmith repository** (one-time, requires root):

```bash
# Debian / Ubuntu (apt)
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.deb.sh' | sudo -E bash

# Fedora / RHEL / CentOS (dnf)
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.rpm.sh' | sudo -E bash

# Alpine (apk)
curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.alpine.sh' | sudo -E bash
```

[^docs-install]

**Step 2 — Install the `task` package**:

```bash
# apt
sudo apt install task

# dnf
sudo dnf install task

# apk
sudo apk add task
```

[^docs-install]

#### Installation Verification

```bash
command -v task
task --version
```

Expected version output format: `3.51.1` (no `v` prefix).[^release-tarball]

Package-level verification:

```bash
# apt
dpkg -l task

# dnf
dnf info task

# apk
apk info task
```

#### Configuration Options

##### Version Selection

Determined by the Cloudsmith repository state. Install a specific version if available in the repo:

```bash
# apt (example)
sudo apt install task=3.51.1

# dnf (example)
sudo dnf install task-3.51.1
```

Exact version pinning syntax depends on the package manager and published package versions. For strict version pinning independent of repository lag, prefer [Manual Prebuilt Release Archives](#manual-prebuilt-release-archives-github-releases) or the [Official Install Script](#official-install-script-taskfiledevinstallsh).

##### Installation Path

Package-manager controlled. The `task` binary is installed to system paths (typically `/usr/bin/task` for DEB/RPM/APK packages).

##### User Targeting

System-wide installation only. Requires root/sudo.

##### Required Privileges

Root or sudo required for both repository setup and package installation.

##### Tool-Specific Configurations

None at install time. Official packages include shell completions at standard system paths:[^goreleaser-nfpms]

| Shell | Installed path |
|---|---|
| bash | `/etc/bash_completion.d/task` |
| zsh | `/usr/local/share/zsh/site-functions/_task` |
| fish | `/usr/share/fish/vendor_completions.d/task.fish` |

#### Post-Installation Steps and Cleanup

##### PATH Setup

None required for system-wide installs; `/usr/bin` is on PATH by default.

##### Configuration Files

None required for core Task operation. Task optionally reads `.taskrc.yml` and `Taskfile.yml` at runtime (not created by installation).

##### Environment Variables

None required for core Task operation at runtime.

##### Activation Scripts

None required.

##### Shell Completions

Installed automatically by the package. If completions are not active, generate and load manually (see [Shell Completions](#shell-completions-common-to-all-binary-based-methods) below).

##### Cleanup

```bash
# Debian/Ubuntu container cleanup pattern
apt-get clean
rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Use the native package manager:

```bash
sudo apt update && sudo apt install task        # apt
sudo dnf upgrade task                           # dnf
sudo apk upgrade task                           # apk
```

##### Uninstallation

```bash
sudo apt remove task                            # apt
sudo dnf remove task                            # dnf
sudo apk del task                               # apk
```

Repository configuration files created by the Cloudsmith setup scripts remain after package removal; remove manually if desired.

##### Idempotency

Re-running `apt install task` / `dnf install task` / `apk add task` is idempotent when the package is already installed at the requested version.

#### Notes and Best Practices

- Preferred method for production Linux containers when a supported distro base image is used, because it integrates with native package lifecycle and includes completions.
- Cloudsmith setup scripts are third-party (Cloudsmith) infrastructure; they modify system package source configuration.
- Package name is `task`, not `go-task`. Conflicts with the unrelated `taskwarrior` package.[^goreleaser-nfpms]

### Homebrew

#### Supported Platforms

- macOS (Intel and Apple Silicon).
- Linux (Homebrew on Linux supported).

#### Dependencies

##### Common Dependencies

- Homebrew installed and initialized in the shell environment.

##### Platform-Specific Dependencies

- macOS: Xcode Command Line Tools (installed automatically by Homebrew if missing).
- Linux: Homebrew Linux prerequisites (glibc, etc.).

#### Installation Steps

Two official Homebrew sources are documented:[^docs-install]

**Official tap** (recommended by Task docs):

```bash
brew install go-task/tap/go-task
```

**Homebrew core formula**:

```bash
brew install go-task
```

Both install the `task` binary. The tap formula is published by GoReleaser to `go-task/homebrew-tap`.[^goreleaser-brews]

#### Installation Verification

```bash
command -v task
task --version
brew info go-task
```

#### Configuration Options

##### Version Selection

Determined by Homebrew formula version. Pin with:

```bash
brew install go-task@3.51.1   # if versioned formula exists
# or
brew pin go-task
```

For exact version control, prefer release-archive or install-script methods.

##### Installation Path

Homebrew-controlled prefix:

- Apple Silicon macOS: `/opt/homebrew/bin/task`
- Intel macOS: `/usr/local/bin/task`
- Linux: `$HOMEBREW_PREFIX/bin/task`

##### User Targeting

Typically user-local (default Homebrew prefix owned by the installing user). Can be configured for system-wide use depending on Homebrew installation mode.

##### Required Privileges

Usually no root required for default Homebrew prefix installs.

##### Tool-Specific Configurations

Homebrew formula installs bash, zsh, and fish completions automatically.[^goreleaser-brews]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure Homebrew shell environment is initialized:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"   # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"      # Intel
```

##### Configuration Files

None required.

##### Environment Variables

None required at runtime.

##### Activation Scripts

None required.

##### Shell Completions

Installed by Homebrew formula to Homebrew completion directories. Verify with `brew info go-task`.

##### Cleanup

None required beyond normal Homebrew maintenance (`brew cleanup`).

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
brew upgrade go-task
# or install specific version via brew extract/pin workflows
```

##### Uninstallation

```bash
brew uninstall go-task
```

##### Idempotency

`brew install go-task` is idempotent when already installed; may upgrade if formula version changed.

#### Notes and Best Practices

- Primary recommended method for macOS development environments.
- Formula name is `go-task`; executable name is `task`.
- Homebrew versions may lag slightly behind GitHub release cadence.

### Official Install Script (`https://taskfile.dev/install.sh`)

The hosted install script at `https://taskfile.dev/install.sh` is identical to `install-task.sh` in the official repository.[^src-install-sh][^install-sh-hosted] It was generated by GoDownloader/goreleaser godownloader.[^src-install-sh]

#### Supported Platforms

Auto-detected platforms in `get_binaries()`:[^src-install-sh]

| OS | Architectures |
|---|---|
| darwin | amd64, arm64, arm |
| linux | 386, amd64, arm64, arm |
| windows | 386, amd64, arm64, arm |

**Not supported by the install script** despite release assets existing: `linux/riscv64`, all `freebsd/*` targets. Attempting installation on these platforms causes the script to exit with `platform $PLATFORM is not supported`.[^src-install-sh]

For DevFeats scope (macOS and Linux amd64/arm64), this method is directly applicable.

#### Dependencies

##### Common Dependencies

- POSIX `sh` shell.
- `curl` or `wget` (for HTTP downloads).
- `tar` (for `.tar.gz` archives) or `unzip` (for Windows `.zip` archives).
- `mktemp`, `install`, `grep`, `cut`, `sed`, `tr`.
- SHA-256 checksum utility: `sha256sum`, `gsha256sum`, `shasum`, or `openssl`.

##### Platform-Specific Dependencies

- Write permissions on the destination directory (`BINDIR`).
- `unzip` required only on Windows targets.

#### Installation Steps

Default install to `./bin` relative to the current working directory:

```bash
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d
```

Install to a user-local or system-wide directory:

```bash
# User-local (Linux)
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin

# User-local (alternative)
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/bin

# System-wide (requires root)
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
```

Install a specific version (tag from GitHub releases):

```bash
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d v3.51.1
```

Combined directory and version (parameters are order-specific; version tag is positional after flags):[^docs-install]

```bash
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin v3.51.1
```

#### Installation Verification

```bash
command -v task
task --version
```

The script logs `found version: {VERSION} for {TAG}/{OS}/{ARCH}` to stderr before downloading.[^src-install-sh]

#### Configuration Options

##### Version Selection

- Positional `[tag]` argument after option flags (e.g. `v3.51.1`).
- If omitted, queries `https://github.com/go-task/task/releases/latest` via GitHub API JSON and extracts `tag_name`.[^src-install-sh]
- Version prefix `v` is stripped internally (`VERSION=${TAG#v}`).

Environment variable `TAG` can also be set before invocation (parsed into positional arg by `parse_args`).

##### Installation Path

- `-b BINDIR` flag sets installation directory.
- `BINDIR` environment variable (default: `./bin` if neither flag nor env is set).[^src-install-sh]

On Linux, common choices are `~/.local/bin`, `~/bin` (user-local) or `/usr/local/bin` (system-wide).[^docs-install]

On macOS and Windows, `~/.local/bin` and `~/bin` are **not** on `$PATH` by default; PATH must be configured manually.[^docs-install]

##### User Targeting

User-local by default when destination is a user-writable path. System-wide when destination is a root-owned system path with appropriate privileges.

##### Required Privileges

Depends on write permissions for `BINDIR`. Root/sudo required only for system paths like `/usr/local/bin`.

##### Tool-Specific Configurations

| Flag / env | Description |
|---|---|
| `-b BINDIR` | Installation directory |
| `-d` | Enable debug logging (sets log priority to 10) |
| `-x` | Enable `set -x` shell tracing |
| `-h` | Show usage |
| `BINDIR` env | Default bindir if `-b` not specified |

No `--force` flag; the script always overwrites via `install(1)`.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure `BINDIR` is on `$PATH`:

```bash
export PATH="$PATH:$HOME/.local/bin"
# or
export PATH="$PATH:$HOME/bin"
```

For system-wide installs to `/usr/local/bin`, no PATH change is typically needed.

##### Configuration Files

None required.

##### Environment Variables

None required at runtime. No installer-time auth token support (unlike some other tools' install scripts).

##### Activation Scripts

None required.

##### Shell Completions

Not installed by the script. Install manually after binary placement (see [Shell Completions](#shell-completions-common-to-all-binary-based-methods)).

##### Cleanup

Script removes its temporary download/extraction directory automatically (`rm -rf "${tmpdir}"`).[^src-install-sh]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run the script with the desired tag; the `install` command overwrites the existing binary in `BINDIR`.

##### Uninstallation

```bash
rm -f ~/.local/bin/task
# or remove from whichever -b path was used
```

##### Idempotency

Re-running with the same version and destination overwrites the binary each time (effectively idempotent result, but re-downloads and re-verifies checksums every run).

#### Details

The install script performs these steps in order:[^src-install-sh]

1. **Initialize constants**: `PROJECT_NAME=task`, `OWNER=go-task`, `REPO=task`, `FORMAT=tar.gz`, detect `OS` and `ARCH` via `uname`.
2. **Validate platform**: `uname_os_check` and `uname_arch_check` verify OS/arch are recognized Go values.
3. **Parse arguments**: Process `-b`, `-d`, `-h`, `-x` flags; remaining positional arg becomes `TAG`.
4. **Resolve binaries list**: `get_binaries()` maps `PLATFORM` to `BINARIES="task"`.
5. **Resolve version**: `tag_to_version()` calls `github_release "go-task/task" "${TAG}"` which fetches `https://github.com/go-task/task/releases/{latest\|tag}` with `Accept: application/json` header and extracts `tag_name`.
6. **Adjust format**: Sets `FORMAT=zip` for Windows.
7. **Construct download URLs**:
   - Tarball: `https://github.com/go-task/task/releases/download/${TAG}/task_${OS}_${ARCH}.${FORMAT}`
   - Checksums: `https://github.com/go-task/task/releases/download/${TAG}/task_checksums.txt`
8. **Execute download and install** (`execute()`):
   - Create temp directory with `mktemp -d`.
   - Download tarball and checksums file.
   - Verify SHA-256 via `hash_sha256_verify` (looks up basename in checksums file).
   - Extract archive with `untar()` (`tar --no-same-owner -xzf` for tar.gz; `unzip` for zip).
   - `install -d "${BINDIR}"` if directory missing.
   - `install "${srcdir}/task" "${BINDIR}/"` (appends `.exe` on Windows).
   - Remove temp directory.

**Architecture detection mapping** (`uname_arch`): `x86_64`→`amd64`, `x86`/`i686`/`i386`→`386`, `aarch64`→`arm64`, `armv5*`/`armv6*`/`armv7*`→`arm`.[^src-install-sh]

**OS detection mapping** (`uname_os`): Normalizes Cygwin/MinGW/MSYS to `windows`.[^src-install-sh]

#### Notes and Best Practices

- Recommended by upstream for CI environments over `go install` (faster, more stable).[^docs-install]
- Performs SHA-256 checksum verification against `task_checksums.txt` (stronger integrity guarantee than TLS-only transport).
- Does not install shell completions; handle separately if needed.
- Does not support `linux/riscv64` despite release assets being published; use manual binary download for that platform.
- Official docs reference `go-task/setup-task@v1`; the current action version is `v2`.[^setup-task-readme]

### Manual Prebuilt Release Archives (GitHub Releases)

#### Supported Platforms

Any platform with a published release asset. Latest release (v3.51.1) assets:[^gh-release-v3511]

| Category | Assets |
|---|---|
| Linux tarballs | `task_linux_{386,amd64,arm,arm64,riscv64}.tar.gz` |
| macOS tarballs | `task_darwin_{amd64,arm64}.tar.gz` |
| Windows zips | `task_windows_{386,amd64,arm64}.zip` |
| FreeBSD tarballs | `task_freebsd_{386,amd64,arm,arm64}.tar.gz` |
| Linux packages | `task_3.51.1_linux_{386,amd64,arm,arm64,riscv64}.{deb,rpm,apk}` |
| Checksums | `task_checksums.txt` |

#### Dependencies

##### Common Dependencies

- `curl` or `wget`.
- `tar` (Unix tarballs) or `unzip` (Windows zips).
- SHA-256 checksum utility (`sha256sum`, `shasum`, or `gsha256sum`).
- Write permissions for installation path.

##### Platform-Specific Dependencies

- Optional `install(1)` utility for permission-preserving binary placement.

#### Installation Steps

Example (Linux amd64):

```bash
set -e
ver="v3.51.1"
asset="task_linux_amd64.tar.gz"
base="https://github.com/go-task/task/releases/download/${ver}"

curl -fsSLO "${base}/${asset}"
curl -fsSLO "${base}/task_checksums.txt"
sha256sum --check task_checksums.txt --ignore-missing

tar -xzf "${asset}"
mkdir -p "$HOME/.local/bin"
install -m 0755 task "$HOME/.local/bin/task"
```

Example (macOS arm64):

```bash
set -e
ver="v3.51.1"
asset="task_darwin_arm64.tar.gz"
base="https://github.com/go-task/task/releases/download/${ver}"

curl -fsSLO "${base}/${asset}"
curl -fsSLO "${base}/task_checksums.txt"
shasum -a 256 --check task_checksums.txt --ignore-missing

tar -xzf "${asset}"
mkdir -p "$HOME/.local/bin"
install -m 0755 task "$HOME/.local/bin/task"
```

Example (install DEB package directly):

```bash
curl -fsSLO "https://github.com/go-task/task/releases/download/v3.51.1/task_3.51.1_linux_amd64.deb"
sudo dpkg -i task_3.51.1_linux_amd64.deb
```

#### Installation Verification

```bash
task --version
```

Checksum verification:

```bash
sha256sum --check task_checksums.txt --ignore-missing
# or on macOS:
shasum -a 256 --check task_checksums.txt --ignore-missing
```

Expected checksum file format: `{sha256_hex}  {filename}` (two spaces between hash and filename).[^task-checksums]

#### Configuration Options

##### Version Selection

Directly controlled by release tag in download URL.

##### Installation Path

Any writable directory. Common choices: `$HOME/.local/bin`, `$HOME/bin`, `/usr/local/bin`.

##### User Targeting

Both user-local and system-wide supported depending on destination path and privileges.

##### Required Privileges

Root/sudo only when installing to system paths or installing `.deb`/`.rpm`/`.apk` packages.

##### Tool-Specific Configurations

- Select asset matching host OS/arch (`task_linux_amd64.tar.gz`, `task_darwin_arm64.tar.gz`, etc.).
- Tarballs include `completion/` directory for optional manual completion installation.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Add installation directory to `$PATH` if not already present.

##### Configuration Files

None required.

##### Environment Variables

None required.

##### Activation Scripts

None required.

##### Shell Completions

Available in extracted `completion/` directory. Install manually or use `task --completion` (see [Shell Completions](#shell-completions-common-to-all-binary-based-methods)).

##### Cleanup

```bash
rm -f task_*.tar.gz task_*.zip task_*.deb task_*.rpm task_*.apk task_checksums.txt task
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Download and install a different tagged release, replacing the existing binary.

##### Uninstallation

```bash
rm -f "$HOME/.local/bin/task"
# or: sudo apt remove task / sudo dnf remove task / etc. for package installs
```

##### Idempotency

Re-running with the same version and allowing binary replacement is idempotent.

#### Notes and Best Practices

- Best method for reproducible, auditable installations with explicit checksum verification.
- Prefer pinned release tags over "latest" in automation.
- Supports platforms not covered by the install script (e.g. `linux/riscv64`, FreeBSD).
- Aligns well with immutable container image builds.

### npm (`@go-task/cli`)

Official npm package maintained by the Task team.[^docs-install]

#### Supported Platforms

Cross-platform (macOS, Linux, Windows) via npm's global or project-local install.

#### Dependencies

##### Common Dependencies

- Node.js and npm (or compatible package manager: yarn, pnpm, bun).

##### Platform-Specific Dependencies

None beyond Node.js runtime for the npm wrapper script.

#### Installation Steps

Global install:

```bash
npm install -g @go-task/cli
```

Project dependency:

```bash
npm install --save-dev @go-task/cli
npx task --version
```

Latest npm package version as of 2026-06-28: **3.51.1**.[^npm-cli]

The npm package exposes the binary via `run-task.js` wrapper with bin name `task`.[^npm-cli]

#### Installation Verification

```bash
command -v task
task --version
npm list -g @go-task/cli
```

#### Configuration Options

##### Version Selection

```bash
npm install -g @go-task/cli@3.51.1
```

##### Installation Path

npm global bin directory (typically `$PREFIX/bin` or `~/.npm-global/bin` depending on npm config).

##### User Targeting

User-local by default for global npm installs without root.

##### Required Privileges

Root only if npm global prefix requires it.

##### Tool-Specific Configurations

Standard npm configuration (`--prefix`, `.npmrc` settings) controls install location.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure npm global bin directory is on `$PATH` (`npm bin -g`).

##### Configuration Files

None required for Task itself.

##### Environment Variables

None required at runtime.

##### Activation Scripts

None required.

##### Shell Completions

Not installed by npm package; configure manually.

##### Cleanup

```bash
npm uninstall -g @go-task/cli
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
npm install -g @go-task/cli@3.51.1
```

##### Uninstallation

```bash
npm uninstall -g @go-task/cli
```

##### Idempotency

npm install is idempotent for matching versions.

#### Notes and Best Practices

- Useful in Node.js-centric projects but adds Node.js as an install-time dependency.
- Prefer direct binary methods for minimal container images.

### Snap

#### Supported Platforms

Linux distributions with Snap support. Requires classic confinement.[^docs-install]

#### Dependencies

##### Common Dependencies

- `snapd` installed and running.

##### Platform-Specific Dependencies

- Linux distribution must allow classic confinement for Snaps.

#### Installation Steps

```bash
sudo snap install task --classic
```

[^docs-install]

#### Installation Verification

```bash
task --version
snap info task
```

#### Configuration Options

##### Version Selection

Determined by Snap channel (stable/beta/edge).

##### Installation Path

Snap-managed (`/snap/bin/task` via symlink).

##### User Targeting

System-wide.

##### Required Privileges

Root/sudo required.

##### Tool-Specific Configurations

`--classic` confinement flag is required.[^docs-install]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure `/snap/bin` is on PATH (usually automatic on snap-enabled systems).

##### Shell Completions

Snap package may include completions depending on snap build; verify with `snap info task`.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
sudo snap refresh task
sudo snap refresh task --channel=beta
```

##### Uninstallation

```bash
sudo snap remove task
```

##### Idempotency

`snap install` is idempotent when already installed.

#### Notes and Best Practices

- Less common in container contexts due to snapd dependency and classic confinement requirement.
- Mentioned for completeness on bare-metal Linux hosts.

### Community Package Managers

These methods are community-maintained; the Task team does not control version freshness.[^docs-install]

#### Supported Platforms and Commands

| Manager | Platform | Install command | Package name |
|---|---|---|---|
| mise (aqua backend) | Cross-platform | `mise use -g aqua:go-task/task@latest && mise install` | aqua:go-task/task |
| mise (ubi backend) | Cross-platform | `mise use -g ubi:go-task/task && mise install` | ubi:go-task/task |
| MacPorts | macOS | `sudo port install go-task` | go-task |
| pip | Cross-platform | `pip install go-task-bin` | go-task-bin |
| Arch pacman | Arch Linux | `sudo pacman -S go-task` | go-task |
| Fedora dnf (community) | Fedora | `sudo dnf install go-task` | go-task |
| Nix | NixOS/Nix | `nix-env -iA nixpkgs.go-task` | go-task |
| Scoop | Windows | `scoop install task` | task |
| Chocolatey | Windows | `choco install go-task` | go-task |

[^docs-install]

#### Dependencies

Varies by manager. mise/aqua and mise/ubi install directly from GitHub releases. pip package `go-task-bin` wraps prebuilt binaries (latest: 3.51.1).[^pip-bin]

#### Installation Verification

```bash
task --version
```

#### Configuration Options

##### Version Selection

- mise/aqua: `mise use -g aqua:go-task/task@3.51.1`
- pip: `pip install go-task-bin==3.51.1`
- Nix: determined by nixpkgs channel

##### Installation Path

Manager-specific (mise shims, pip scripts bin, MacPorts `/opt/local/bin`, etc.).

#### Post-Installation Steps and Cleanup

Follow each manager's standard PATH and completion setup. None install Task-specific runtime configuration.

#### Changing Versions and Uninstallation

Use the respective manager's upgrade/remove commands.

#### Notes and Best Practices

- mise/aqua and mise/ubi are recommended by Task docs for mise users because they install directly from GitHub releases.[^docs-install]
- Community Fedora `go-task` dnf package is distinct from the official Cloudsmith `task` package.
- Prefer official Cloudsmith repos over community dnf on Fedora when both are available.

### Build From Source (`go install`)

#### Supported Platforms

Any platform supported by the Go toolchain.

#### Dependencies

##### Common Dependencies

- Go **1.25.10+** (minimum per `go.mod`).[^go-mod]
- Network access to `proxy.golang.org` (or configured Go module proxy).
- C compiler not required (`CGO_ENABLED=0` in official builds; default `go install` also works without CGO for this project).

#### Installation Steps

Install latest release globally:

```bash
go install github.com/go-task/task/v3/cmd/task@latest
```

Install specific version:

```bash
go install github.com/go-task/task/v3/cmd/task@v3.51.1
```

Install to a custom directory:

```bash
env GOBIN=/usr/local/bin go install github.com/go-task/task/v3/cmd/task@v3.51.1
```

[^docs-install]

#### Installation Verification

```bash
command -v task
task --version
```

Binary default location: `$GOPATH/bin` or `$HOME/go/bin` (if `GOBIN` unset).

#### Configuration Options

##### Version Selection

Module version suffix: `@latest`, `@v3.51.1`, or any valid Go module version.

##### Installation Path

- Default: `$GOPATH/bin/task` or `$HOME/go/bin/task`.
- Override with `GOBIN` environment variable.

##### User Targeting

User-local by default (Go bin directory in user home).

##### Required Privileges

Root only if `GOBIN` points to a system directory.

##### Tool-Specific Configurations

- `GOOS` / `GOARCH` / `GOARM` environment variables enable cross-compilation.
- `-ldflags "-s -w"` can reduce binary size (GoReleaser uses these flags).[^goreleaser]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure Go bin directory is on `$PATH`:

```bash
export PATH="$PATH:$(go env GOPATH)/bin"
```

##### Shell Completions

Not installed by `go install`; generate with `task --completion` after install.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
go install github.com/go-task/task/v3/cmd/task@v3.51.1
```

##### Uninstallation

```bash
rm -f "$(go env GOPATH)/bin/task"
```

##### Idempotency

`go install` rebuilds and replaces the binary; idempotent for same version/module sum.

#### Notes and Best Practices

- Upstream recommends the install script over `go install` for CI (faster, downloads prebuilt binary).[^docs-install]
- Useful when Go toolchain is already present in the environment.
- Does not install shell completions.

### Go Tool (`go get -tool` / `go tool task`)

#### Supported Platforms

Go projects using Go 1.24+ tool dependency tracking.

#### Dependencies

##### Common Dependencies

- Go toolchain with `go get -tool` support.
- A `go.mod` file in the project.

#### Installation Steps

Add Task as a tracked tool dependency:

```bash
go get -tool github.com/go-task/task/v3/cmd/task@latest
```

This adds an entry to the `tool` section of `go.mod`.[^docs-install]

Run Task via Go tool dispatch:

```bash
go tool task --version
go tool task build
go tool task {arguments...}
```

[^docs-install]

Go compiles Task on demand before executing when using `go tool task`.

#### Installation Verification

```bash
go tool task --version
grep 'go-task/task' go.mod
```

#### Configuration Options

##### Version Selection

```bash
go get -tool github.com/go-task/task/v3/cmd/task@v3.51.1
```

##### Installation Path

Go tool cache (managed by Go toolchain, not directly user-configurable).

##### User Targeting

Project-local (recorded in `go.mod`).

##### Required Privileges

None (writes to Go module cache and modifies project `go.mod`).

#### Post-Installation Steps and Cleanup

##### PATH Setup

None required; invoke via `go tool task`.

##### Shell Completions

Not applicable for `go tool task` invocation pattern.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
go get -tool github.com/go-task/task/v3/cmd/task@v3.51.1
```

##### Uninstallation

Remove the tool line from `go.mod` and run `go mod tidy`.

##### Idempotency

Repeated `go get -tool` with same version is idempotent.

#### Notes and Best Practices

- Ideal for Go projects wanting pinned Task versions without global installation.
- Works well in CI: no separate install step needed beyond `go mod download`.
- Slower first invocation due to on-demand compilation.

### Shell Completions (Common to All Binary-Based Methods)

Task provides shell completions via the `--completion` flag.[^docs-install-completions]

**Option 1 — Dynamic loading in shell startup (recommended; always up-to-date):**

```bash
# bash (~/.bashrc)
eval "$(task --completion bash)"

# zsh (~/.zshrc)
eval "$(task --completion zsh)"

# fish (~/.config/fish/config.fish)
task --completion fish | source
```

If the executable is not named `task`, set `TASK_EXE` before eval:[^docs-install-completions]

```bash
export TASK_EXE='go-task'
eval "$(task --completion bash)"
```

**Option 2 — Static installation to system completion directories:**

```bash
task --completion bash > /etc/bash_completion.d/task
task --completion zsh  > /usr/local/share/zsh/site-functions/_task
task --completion fish > ~/.config/fish/completions/task.fish
```

**Zsh customization** — hide task descriptions:[^docs-install-completions]

```bash
zstyle ':completion:*:*:task:*' verbose false
```

Prebuilt completion files are also included in release tarballs under `completion/{bash,fish,zsh,ps}/`.[^release-tarball]

## Dev Container Setup

### Existing Community Dev Container Features

The primary community devcontainer feature is published by eitsupi:[^eitsupi-feature]

```json
"features": {
  "ghcr.io/eitsupi/devcontainer-features/go-task:1": {
    "version": "latest"
  }
}
```

Feature options:[^eitsupi-feature-json]

| Option | Type | Default | Description |
|---|---|---|---|
| `version` | string | `latest` | Task version to install |

Supported platforms: `linux/amd64` and `linux/arm64` on Debian and Ubuntu base images.[^eitsupi-feature]

The feature's `install.sh` implementation:[^eitsupi-install-sh]

1. Requires root.
2. Resolves version via `git ls-remote --tags` against `https://github.com/go-task/task` (supports `latest`, semver prefixes).
3. Downloads `task_linux_{amd64|arm64}.tar.gz` from GitHub Releases.
4. Installs binary to `/usr/local/bin/task`.
5. Sets up shell completions (bash, zsh, fish, pwsh) from tarball or `task --completion`.
6. Installs VS Code extension `task.vscode-task` via feature customizations.

No official Task feature exists in `devcontainers/features` as of 2026-06-28.

### GitHub Actions (`go-task/setup-task`)

Official GitHub Action for installing Task in CI workflows.[^docs-install][^setup-task-readme]

```yaml
- name: Install Task
  uses: go-task/setup-task@v2
  with:
    version: 3.x          # default: 3.x; also accepts exact (3.51.1) or range (3.x)
    repo-token: ${{ github.token }}
    max-retries: 3
```

The action downloads `task_{os}_{arch}.{tar.gz|zip}` from GitHub Releases, extracts to a cached tool directory, and adds it to PATH.[^setup-task-installer]

Note: Official installation docs reference `go-task/setup-task@v1`; the current maintained version is `@v2`.[^docs-install][^setup-task-readme]

### DevFeats Implementation Considerations

- **Recommended primary methods for containers**: Cloudsmith apt/apk (when base image matches), official install script, or manual release download with checksum verification.
- **Recommended for macOS**: Homebrew (`go-task/tap/go-task` or `go-task`).
- **Version pinning**: Always prefer explicit version tags (`v3.51.1`) over `latest` in automation.
- **PATH**: For user-local installs, ensure install directory is on PATH for all target users (`remoteUser` in devcontainer context).
- **Completions**: Optional for devcontainers; eitsupi feature installs them but adds complexity. Consider making completions an optional feature flag.
- **No runtime services**: Task requires no daemon, no persistent state beyond optional `.task/` cache directory created at runtime.

## Plugins and Extensions

### VS Code Extension (`task.vscode-task`)

Official VS Code extension for Taskfile authoring and task execution.[^eitsupi-feature-json]

- **Extension ID**: `task.vscode-task`
- **Auto-installed by**: eitsupi devcontainer feature customizations.
- **Install manually**:

```bash
code --install-extension task.vscode-task
```

No other official Task plugins or runtime extensions exist. Task itself has no plugin architecture for extending the task runner.

## References

[^homepage]: [Task Homepage](https://taskfile.dev/) — Official project landing page.
[^docs-install]: [Official Docs – Installation](https://taskfile.dev/docs/installation) — Canonical installation methods, package manager matrix, install script usage, GitHub Actions, build-from-source, and Go tool instructions.
[^docs-install-completions]: [Official Docs – Installation (Setup completions section)](https://taskfile.dev/docs/installation#setup-completions) — Shell completion installation via `--completion` flag and static file placement.
[^repo]: [Official GitHub Repository](https://github.com/go-task/task) — Source code, issue tracker, and release artifacts.
[^go-mod]: [go.mod (main branch)](https://github.com/go-task/task/blob/main/go.mod) — Go module path and minimum Go version (1.25.10).
[^goreleaser]: [GoReleaser Configuration (.goreleaser.yml)](https://github.com/go-task/task/blob/main/.goreleaser.yml) — Build matrix, archive naming, checksum file, and packaging configuration.
[^goreleaser-nfpms]: [GoReleaser nfpms section (.goreleaser.yml)](https://github.com/go-task/task/blob/main/.goreleaser.yml) — DEB/RPM/APK package naming, completion file placement, and taskwarrior conflict declaration.
[^goreleaser-brews]: [GoReleaser brews section (.goreleaser.yml)](https://github.com/go-task/task/blob/main/.goreleaser.yml) — Homebrew formula name, tap repository, and completion installation.
[^src-install-sh]: [install-task.sh (main branch)](https://github.com/go-task/task/blob/main/install-task.sh) — Version-controlled install script source; platform detection, download, checksum verification, and binary placement logic.
[^install-sh-hosted]: [Hosted install script (taskfile.dev/install.sh)](https://taskfile.dev/install.sh) — Script served for curl-pipe install; verified identical to repository `install-task.sh`.
[^gh-api-latest]: [GitHub API – Latest Release](https://api.github.com/repos/go-task/task/releases/latest) — Machine-readable latest stable release metadata (v3.51.1, published 2026-05-16); verified 2026-06-28.
[^gh-release-v3511]: [GitHub Release v3.51.1 Assets](https://github.com/go-task/task/releases/tag/v3.51.1) — Complete list of published binary archives, packages, and checksums file.
[^task-checksums]: [task_checksums.txt (v3.51.1)](https://github.com/go-task/task/releases/download/v3.51.1/task_checksums.txt) — SHA-256 checksums for all v3.51.1 release assets.
[^release-tarball]: Verified by extracting `task_linux_amd64.tar.gz` from v3.51.1 release — contains `task` binary, `completion/`, `LICENSE`, `README.md`; `task --version` outputs `3.51.1`.
[^cloudsmith]: [Cloudsmith – task/task repository](https://cloudsmith.io/~task/repos/task/) — Official apt/dnf/apk package hosting.
[^npm-cli]: [npm – @go-task/cli package](https://www.npmjs.com/package/@go-task/cli) — Official npm wrapper; version 3.51.1 as of 2026-06-28.
[^pip-bin]: [PyPI – go-task-bin package](https://pypi.org/project/go-task-bin/) — Community pip wrapper for prebuilt Task binaries; version 3.51.1 as of 2026-06-28.
[^setup-task-readme]: [go-task/setup-task README](https://github.com/go-task/setup-task/blob/main/README.md) — GitHub Action inputs (`version`, `repo-token`, `max-retries`) and usage examples for `@v2`.
[^setup-task-installer]: [go-task/setup-task installer.ts](https://github.com/go-task/setup-task/blob/main/src/installer.ts) — Action download URL construction (`task_{os}_{arch}.{tar.gz|zip}`), semver resolution, and tool-cache placement.
[^eitsupi-feature]: [eitsupi/devcontainer-features – go-task README](https://github.com/eitsupi/devcontainer-features/blob/main/src/go-task/README.md) — Community devcontainer feature documentation and usage.
[^eitsupi-feature-json]: [eitsupi/devcontainer-features – devcontainer-feature.json](https://github.com/eitsupi/devcontainer-features/blob/main/src/go-task/devcontainer-feature.json) — Feature options, VS Code extension customization, and dependency declarations.
[^eitsupi-install-sh]: [eitsupi/devcontainer-features – install.sh](https://github.com/eitsupi/devcontainer-features/blob/main/src/go-task/install.sh) — Community feature install implementation (GitHub release download to `/usr/local/bin/task`).
[^task-discussion-918]: [go-task/task Discussion #918](https://github.com/go-task/task/discussions/918) — Maintainer acknowledgment of eitsupi devcontainer feature.
