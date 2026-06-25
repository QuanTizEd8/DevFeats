# Feature Reference

Git LFS (Large File Storage) is a Git extension that replaces large binary files in a repository with lightweight text pointer files while storing the actual file contents on a remote LFS server (e.g., GitHub, GitLab, Bitbucket). It integrates with Git via smudge/clean/process filters and a pre-push hook, enabling transparent versioning of large assets (datasets, model weights, media, binaries) without bloating the Git object database.[^readme][^git-lfs-site]

The client is a single Go binary (`git-lfs`) invoked as `git lfs <subcommand>`. Installing the binary alone is **not sufficient** — Git must be configured once per scope (system, global user, or local repository) via `git lfs install`, which wires the LFS filter into Git config.[^readme][^man-install] Most Linux distro packages (Ubuntu/Debian, Alpine, Fedora/RHEL, packagecloud `.deb`/`.rpm`) run `git lfs install --skip-repo --system` automatically in their post-install scripts; binary installs, Homebrew, and Arch Linux packages do not.[^deb-postinst][^ubuntu-postinst][^alpine-post-install][^fedora-spec][^arch-pkgbuild][^brew-formula]

Release tags use a `v` prefix (e.g., `v3.7.1`). Pre-built release binaries are statically linked on Linux.[^release-latest][^binary-test]

- **Homepage**: https://git-lfs.com/
- **Source Code**: https://github.com/git-lfs/git-lfs
- **Documentation**: https://github.com/git-lfs/git-lfs/tree/main/docs (man pages in `docs/man/`), https://github.com/git-lfs/git-lfs/wiki/Installation (community install guide)
- **Latest Release**: 3.7.1 (as of 2026-06-18)[^release-latest]

## Tool Architecture

Git LFS is a **single, self-contained CLI binary** (`git-lfs`, or `git-lfs.exe` on Windows) written in Go. Official Linux release binaries are statically linked ELF executables with no runtime library dependencies.[^binary-test] macOS and Windows release binaries are also standalone executables distributed in release archives.

**Git integration model**: Git LFS is not a standalone VCS or daemon. It operates as a Git extension:

- Git discovers `git-lfs` on `$PATH` and delegates `git lfs …` subcommands to it.
- `git lfs install` configures Git's `filter.lfs` smudge/clean/process filters in Git config (system, global, local, or worktree scope).[^man-install]
- In repositories, a `pre-push` hook (installed by `git lfs install` unless `--skip-repo` is used) calls `git-lfs pre-push` to upload LFS objects.[^man-install][^man-main]
- Per-repository file tracking is defined in `.gitattributes` (via `git lfs track`), not by the install step itself.

**Runtime requirements**:

- **Git** ≥ 2.0.0 is required (official recommendation: use a recent Git version for best performance).[^readme-limits][^deb-depends]
- No JVM, Node.js, Python, or other runtime is needed when using pre-built binaries.

**Build system**: Go modules (`github.com/git-lfs/git-lfs/v3`); `go 1.23.0` minimum in v3.7.1 `go.mod`.[^go-mod] Official releases are built with Go 1.25+ in CI.[^release-workflow] Build also requires GNU `make` and `asciidoctor` (for man pages).[^readme-build][^brew-formula]

**Network/services**: Git LFS is a client-side tool. At runtime it communicates with Git remotes and LFS API endpoints configured via Git/`lfs.*` config keys; no local daemon is required.[^man-config]

**Important**: The Go module explicitly states it does **not** maintain a stable Go API; Git LFS is intended solely as a compiled binary utility.[^go-mod]

## Installation Methods

Git LFS offers six principal installation routes relevant to a DevFeats feature:

1. **Prebuilt Binary Download (GitHub Releases)** — direct, version-pinnable; recommended when distro packages lag upstream or a specific version is required.
2. **Official Linux Packages (packagecloud apt/deb and yum/rpm)** — upstream-maintained packages with automatic `git lfs install --system` in post-install scripts; version tracks latest upstream releases.
3. **OS Package Manager (distro-native)** — fast, no extra repositories; version often lags upstream significantly (e.g., Ubuntu Noble ships 3.4.1 vs upstream 3.7.1).
4. **Homebrew** — recommended automated path for macOS; also provides Linux bottles; does **not** auto-run `git lfs install`.
5. **Windows Installer (.exe)** — signed InnoSetup installer for standalone Windows installs; Git for Windows also bundles Git LFS.
6. **Build From Source** — architecture-agnostic fallback; requires Go toolchain.

Supplementary routes (mise, Conda, Chocolatey) are noted under [Notes and Best Practices](#notes-and-best-practices) in the Binary Download section; they are not primary DevFeats install methods and are not given full subsections here.[^readme-mise][^wiki-install]

### Prebuilt Binary Download (GitHub Releases)

#### Supported Platforms

All current release assets (v3.7.1):[^release-latest]

| OS | Architecture | Asset filename |
|----|-------------|---------------|
| Linux | amd64 (x86_64) | `git-lfs-linux-amd64-v{version}.tar.gz` |
| Linux | arm64 (aarch64) | `git-lfs-linux-arm64-v{version}.tar.gz` |
| Linux | 386 (i686) | `git-lfs-linux-386-v{version}.tar.gz` |
| Linux | arm (armv7/armhf) | `git-lfs-linux-arm-v{version}.tar.gz` |
| Linux | loong64 | `git-lfs-linux-loong64-v{version}.tar.gz` |
| Linux | ppc64le | `git-lfs-linux-ppc64le-v{version}.tar.gz` |
| Linux | riscv64 | `git-lfs-linux-riscv64-v{version}.tar.gz` |
| Linux | s390x | `git-lfs-linux-s390x-v{version}.tar.gz` |
| macOS | amd64 (Intel) | `git-lfs-darwin-amd64-v{version}.zip` |
| macOS | arm64 (Apple Silicon) | `git-lfs-darwin-arm64-v{version}.zip` |
| FreeBSD | amd64 | `git-lfs-freebsd-amd64-v{version}.tar.gz` |
| FreeBSD | 386 | `git-lfs-freebsd-386-v{version}.tar.gz` |
| Windows | amd64 | `git-lfs-windows-amd64-v{version}.zip` |
| Windows | 386 | `git-lfs-windows-386-v{version}.zip` |
| Windows | arm64 | `git-lfs-windows-arm64-v{version}.zip` |
| Windows | all (installer) | `git-lfs-windows-v{version}.exe` |
| Source tarball | all | `git-lfs-v{version}.tar.gz` |

**Architecture mapping for Linux containers** (dpkg/RPM arch → release asset suffix):

| Package manager arch | Release asset suffix |
|---------------------|---------------------|
| `amd64` | `amd64` |
| `arm64` | `arm64` |
| `armhf` | `arm` |
| `i386` | `386` |

**Archive layout**: Linux/macOS/FreeBSD tarballs and macOS zips contain a top-level directory `git-lfs-{version}/` (version **without** `v` prefix, e.g., `git-lfs-3.7.1/`) with the `git-lfs` binary, `install.sh` (Linux/macOS/FreeBSD only), man pages, and documentation.[^binary-install-sh] Windows `.zip` archives contain `git-lfs.exe` and documentation but **no** `install.sh`.[^windows-zip]

#### Dependencies

##### Common Dependencies

- `curl` or `wget` to download assets and checksum/signature files.
- `tar` (for `.tar.gz`) or `unzip` (for `.zip`) to extract.
- `gpg`, `sha256sum` (or `shasum -a 256` on macOS) for release verification.
- **Git** ≥ 2.0.0 must be installed before running `git lfs install`.[^deb-depends][^readme-limits]

##### Platform-Specific Dependencies

- Linux/macOS/BSD: None beyond download/extract/verify tools.
- Root/sudo required only when installing to system-wide paths (e.g., `/usr/local/bin`, `/usr/bin`).
- Windows: no `install.sh`; binary must be placed on `PATH` manually or via the `.exe` installer.

#### Installation Steps

Release tags use a **`v` prefix** (e.g., `v3.7.1`). Asset filenames embed the version with the `v` prefix (e.g., `git-lfs-linux-amd64-v3.7.1.tar.gz`).[^release-latest]

URL pattern: `https://github.com/git-lfs/git-lfs/releases/download/v{version}/{filename}`

Example — Linux amd64, using upstream `install.sh` (installs to `/usr/local/bin` and runs `git lfs install`):

```bash
set -e
VERSION="3.7.1"
ARCH="amd64"
ASSET="git-lfs-linux-${ARCH}-v${VERSION}.tar.gz"
BASE_URL="https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/sha256sums.asc"
# Verify with GPG (see Installation Verification)
tar -xzf "${ASSET}"
cd "git-lfs-${VERSION}"
sudo ./install.sh          # system-wide: /usr/local/bin + git lfs install (global)
# Or user-local:
# ./install.sh --local       # $HOME/.local/bin + git lfs install (global for current user)
```

Example — Linux amd64, manual binary install (no `install.sh` side effects):

```bash
set -e
VERSION="3.7.1"
ARCH="amd64"
ASSET="git-lfs-linux-${ARCH}-v${VERSION}.tar.gz"
BASE_URL="https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
tar -xzf "${ASSET}" "${ASSET%.tar.gz}/git-lfs"
sudo install -m 0755 "${ASSET%.tar.gz}/git-lfs" /usr/local/bin/git-lfs
rm -rf "${ASSET}" "${ASSET%.tar.gz}"
# REQUIRED post-step — choose scope (see Tool-Specific Configurations):
sudo git lfs install --skip-repo --system
```

Example — macOS arm64:

```bash
set -e
VERSION="3.7.1"
ASSET="git-lfs-darwin-arm64-v${VERSION}.zip"
BASE_URL="https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
unzip -q "${ASSET}"
cd "git-lfs-${VERSION}"
sudo ./install.sh
```

Example — Windows amd64 (manual, no installer):

```powershell
$Version = "3.7.1"
$Asset = "git-lfs-windows-amd64-v$Version.zip"
$BaseUrl = "https://github.com/git-lfs/git-lfs/releases/download/v$Version"
Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $Asset
Expand-Archive -Path $Asset -DestinationPath .
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\Programs\Git LFS" | Out-Null
Copy-Item "git-lfs-$Version\git-lfs.exe" "$env:LOCALAPPDATA\Programs\Git LFS\git-lfs.exe"
# Add directory to PATH, then:
git lfs install
```

#### Installation Verification

Verify the binary:

```bash
git-lfs version
# Expected output (example for 3.7.1 on Linux amd64):
# git-lfs/3.7.1 (GitHub; linux amd64; go 1.25.3; git b84b3384)
```

Verify Git integration after `git lfs install`:

```bash
git lfs env
git config --get-regexp 'filter\.lfs'
# Expected keys include:
# filter.lfs.clean git-lfs clean -- %f
# filter.lfs.smudge git-lfs smudge -- %f
# filter.lfs.process git-lfs filter-process
# filter.lfs.required true
```

**GPG-signed checksum verification** (recommended):[^readme-verify][^devcontainer-gpg]

Releases publish `sha256sums.asc` (OpenPGP-signed SHA-256 checksums). Core team GPG keys are distributed via:

```bash
curl -L https://api.github.com/repos/git-lfs/git-lfs/tarball/core-gpg-keys | tar -Ozxf -
```

Known signing key IDs (from devcontainers reference implementation; first two match Arch Linux package `validpgpkeys`):[^devcontainer-install][^arch-pkgbuild]

- `0x88ACE9B29196305BA9947552F1BA225C0223B187` (Brian M. Carlson)
- `0x86CD3297749375BCF8206715F54FE648088335A9` (Chris Darroch)
- `0xAA3B3450295830D2DE6DB90CABA67BE5A5795889` (used by devcontainers; verify against current release signatures)

Verification workflow:

```bash
curl -fsSLO "https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}/sha256sums.asc"
gpg --recv-keys 0x88ace9b29196305ba9947552f1ba225c0223b187 \
                 0x86cd3297749375bcf8206715f54fe648088335a9 \
                 0xaa3b3450295830d2de6db90caba67be5a5795889
gpg --decrypt sha256sums.asc > sha256sums
sha256sum --ignore-missing -c sha256sums
```

Individual asset SHA-256 digests are also listed in GitHub release notes.[^release-latest]

#### Configuration Options

##### Version Selection

Pass the desired version when constructing download URLs. Resolve latest at install time:

```bash
TAG=$(curl -fsSL "https://api.github.com/repos/git-lfs/git-lfs/releases/latest" \
  | jq -r '.tag_name')          # e.g. v3.7.1
VERSION="${TAG#v}"               # e.g. 3.7.1 (strip v prefix for directory names)
```

Release tags always use the `v` prefix. Version resolution scripts should use `tags/v` as the git tag prefix when matching semver strings.[^devcontainer-install]

##### Installation Path

The release `install.sh` supports:[^binary-install-sh]

| Mechanism | Default / target path |
|-----------|----------------------|
| Default (no flags) | `/usr/local/bin/` |
| `--local` flag | `$HOME/.local/bin/` |
| `PREFIX` environment variable | `$PREFIX/bin/` |
| `BOXEN_HOME` environment variable | `$BOXEN_HOME/bin/` (macOS Boxen users) |

Manual install: any directory on `PATH` (commonly `/usr/local/bin`, `/usr/bin`, or `$HOME/.local/bin`).

The script installs all files matching `git*` in the archive directory (currently just `git-lfs`).

##### User Targeting

- **System-wide binary**: install to `/usr/local/bin` or `/usr/bin` with root/sudo.
- **User-local binary**: install to `$HOME/.local/bin` without sudo (via `./install.sh --local` or manual `install`).

Binary placement and Git config scope (`git lfs install`) are independent choices — see Tool-Specific Configurations.

##### Required Privileges

- Writing to `/usr/local/bin`, `/usr/bin`, or `/etc/gitconfig` (via `git lfs install --system`) requires root/sudo.
- User-local binary install and `git lfs install` (global user config) require no elevation.

##### Tool-Specific Configurations

**`git lfs install`** is the critical post-install configuration step. It:[^man-install]

1. Sets up the `lfs` smudge, clean, and filter-process entries in Git config.
2. Installs a `pre-push` hook in the current repository (unless `--skip-repo`).

| Flag | Scope | Effect |
|------|-------|--------|
| *(none)* / `--global` | Global user (`~/.gitconfig`) | Default scope; sets filters if not already present |
| `--system` | System (`/etc/gitconfig`) | All users on the machine; requires root |
| `--local` | Repository (`$GIT_DIR/config`) | Current repo only |
| `--worktree` | Worktree config | Requires Git ≥ 2.20 with `worktreeConfig` enabled |
| `--file=<file>` | Custom config file | Writes filters to the specified Git config file |
| `--force` / `-f` | (with above scope) | Overwrites existing `filter.lfs` values |
| `--skip-repo` | (modifier) | Skips pre-push hook installation in current repo |
| `--skip-smudge` / `-s` | (modifier) | Disables automatic LFS download on clone/checkout/pull |
| `--manual` / `-m` | (modifier) | Prints manual hook integration instructions instead of modifying hooks |

**Scope selection guidance for DevFeats/devcontainers:**

| Scenario | Recommended command |
|----------|-------------------|
| Feature runs as root; all container users need LFS | `git lfs install --skip-repo --system` |
| Feature runs as root; single non-root `remoteUser` | `git lfs install --skip-repo --system` **or** run `git lfs install --skip-repo` as `remoteUser` in a post-install hook |
| Binary install via `install.sh` (default) | Runs `git lfs install` → global config for **installing user only** (typically root's `~/.gitconfig`) |
| `.deb`/`.rpm` from packagecloud or Ubuntu/Debian | `postinst` runs `git lfs install --skip-repo --system` automatically[^deb-postinst][^ubuntu-postinst] |
| Homebrew | **No** auto-install; user must run `git lfs install` manually[^brew-formula] |

**`git lfs uninstall`** reverses filter configuration for the chosen scope; official packages run `git lfs uninstall --skip-repo --system` in `prerm`.[^deb-postinst][^ubuntu-postinst][^man-uninstall]

**Runtime Git LFS configuration** (post-install, optional): Git LFS reads standard Git config keys under `[lfs]` and `[remote.*.lfs*]` (e.g., `lfs.url`, `lfs.storage`, `lfs.fetchinclude`). These are runtime/project settings, not install-time requirements.[^man-config]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- System paths (`/usr/bin`, `/usr/local/bin`): already on PATH in most containers; no action needed.
- User-local (`$HOME/.local/bin`): ensure `$HOME/.local/bin` is on PATH.
- Windows: restart the shell after PATH changes so Git can locate `git-lfs.exe`.[^readme-binary]

##### Configuration Files

`git lfs install` modifies Git configuration files:

| Scope | File modified |
|-------|--------------|
| `--system` | `/etc/gitconfig` |
| default (global) | `~/.gitconfig` (or `$GIT_CONFIG_GLOBAL`) |
| `--local` | `.git/config` in the current repository |
| `--worktree` | per-worktree config (Git ≥ 2.20) |

Content added (filter section):[^man-install-test]

```ini
[filter "lfs"]
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
    process = git-lfs filter-process
    required = true
```

With `--skip-smudge`, the smudge filter is configured to skip automatic downloads.

Repository-level `.gitattributes` and `.lfsconfig` are **not** created by `git lfs install`; they are managed per-project via `git lfs track` and manual configuration.[^man-config]

##### Environment Variables

No persistent environment variables are required for basic operation. Git LFS respects standard Git environment variables (`GIT_CONFIG_SYSTEM`, `GIT_CONFIG_GLOBAL`, `HOME`) and Git credential helpers. Optional runtime variables include `GIT_LFS_SKIP_SMUDGE=1` (equivalent to `--skip-smudge` behavior).[^man-config]

##### Activation Scripts

None. Git LFS is invoked via `git lfs …` once the binary is on PATH and `git lfs install` has been run.

##### Shell Completions

Generate tab completions from the installed binary:[^man-completion]

```bash
git lfs completion bash  > /etc/bash_completion.d/git-lfs
git lfs completion fish  > /usr/share/fish/vendor_completions.d/git-lfs.fish
git lfs completion zsh   > /usr/share/zsh/vendor-completions/_git-lfs
```

Completions integrate with Git's completion system when `git lfs …` tab completion is desired. Official `.deb`/`.rpm` packages install compressed man pages but not shell completions. Completion installation is optional for a DevFeats feature.

##### Cleanup

```bash
rm -f "${ASSET}" sha256sums.asc sha256sums
rm -rf "git-lfs-${VERSION}"
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- **Binary**: re-run download/install; overwrite the binary in place; re-run `git lfs install --force` if filter config must be updated.
- **packagecloud/distro packages**: `apt-get upgrade git-lfs` / `dnf upgrade git-lfs`.

##### Uninstallation

```bash
# Remove Git LFS config (match the scope used at install time):
sudo git lfs uninstall --skip-repo --system   # if installed with --system
# OR: git lfs uninstall                       # if installed globally for current user

# Remove binary:
sudo rm -f /usr/local/bin/git-lfs   # or /usr/bin/git-lfs

# Package manager:
sudo apt-get remove git-lfs         # prerm runs git lfs uninstall --skip-repo --system
sudo dnf remove git-lfs
```

##### Idempotency

- `git lfs install` without `--force` is idempotent: it skips filter setup if already configured.[^man-install]
- Re-installing the same binary version to the same path overwrites the binary in place.
- Package manager re-install/upgrade is idempotent.

#### Details

The release `install.sh` script (Linux/macOS/FreeBSD tarballs):[^binary-install-sh]

```bash
#!/usr/bin/env bash
set -eu
prefix="/usr/local"   # or $HOME/.local with --local; PREFIX/BOXEN_HOME env vars
# ... permission check on $prefix ...
mkdir -p "$prefix/bin"
rm -rf "$prefix/bin/git-lfs*"
for g in git*; do install "$g" "$prefix/bin/$g"; done
PATH+=:"$prefix/bin"
git lfs install    # global user scope; includes repo hook if inside a git repo
```

**Critical difference from packages**: `install.sh` runs `git lfs install` (global user scope, no `--skip-repo`), whereas official `.deb`/`.rpm` packages run `git lfs install --skip-repo --system` in `postinst`.[^deb-postinst][^binary-install-sh]

Starting around v3.2.0, release tarball directory layout changed from flat (with `install.sh` at top level) to nested `git-lfs-{version}/` directory. Install scripts must handle both layouts.[^devcontainer-install]

#### Notes and Best Practices

- Always run `git lfs install` after binary installation. If the binary is not on PATH, Git reports `git: 'lfs' is not a git command`. If the binary is present but `git lfs install` was never run, LFS-tracked files fail at smudge/checkout time rather than at command dispatch.[^wiki-install]
- Prefer `--system --skip-repo` in container/feature installs so all users inherit LFS filters without modifying build-time working directories that may be Git repos.
- Use `--skip-smudge` or `GIT_LFS_SKIP_SMUDGE=1` in CI/containers when LFS file content is not needed at clone time; run `git lfs pull` explicitly when needed.[^devcontainer-feature-json]
- v3.7.1 includes security fixes (CVE-2025-26625) for checkout/pull path handling; prefer ≥ 3.7.1 over older distro packages when possible.[^release-notes]
- **Supplementary install routes** (not primary DevFeats methods): `mise use --global git-lfs@latest` (mise-en-place), `conda install -c conda-forge git-lfs` (Conda, v3.7.1 on conda-forge as of 2026-06-18), `choco install git-lfs.install` (Chocolatey on Windows). All require manual `git lfs install` afterward.[^readme-mise][^wiki-install]
- Releases also publish `hashes.asc` (BSD-format signed hashes for all assets) as an alternative to `sha256sums.asc`.[^readme-verify]

---

### Official Linux Packages (packagecloud apt/deb and yum/rpm)

#### Supported Platforms

Official packages are published on [packagecloud.io/github/git-lfs](https://packagecloud.io/github/git-lfs) for:[^installing-md][^release-notes]

**Debian/Ubuntu (apt/deb):**

| Distribution | Codename | amd64 | arm64 |
|-------------|----------|-------|-------|
| Debian 11 | bullseye | ✓ | — |
| Debian 12 | bookworm | ✓ | ✓ (recent versions) |
| Ubuntu 20.04 | focal | ✓ | ✓ |
| Ubuntu 22.04 | jammy | ✓ | ✓ |
| Ubuntu 24.04 | noble | ✓ | ✓ |
| RHEL 8 / Rocky 8 | el/8 | ✓ (RPM) | — |
| RHEL 9 / Rocky 9 | el/9 | ✓ (RPM) | ✓ (RPM, recent) |
| RHEL 10 / Rocky 10 | el/10 | ✓ (RPM) | — |

For downstream distros without exact packagecloud entries, override detection variables when running the setup script (see Installation Steps).[^installing-md]

**Not covered by packagecloud**: Alpine Linux, Arch Linux, openSUSE, musl-only environments — use binary download or distro packages.

#### Dependencies

##### Common Dependencies

- `curl`, `ca-certificates`, `gpg`/`gnupg`, `apt-transport-https` (apt) or `yum`/`dnf` (rpm).
- **Git** ≥ 2.0.0 (declared as package dependency: `git (>= 2.0.0)`).[^deb-depends]

##### Platform-Specific Dependencies

- Debian: `debian-archive-keyring` recommended.[^devcontainer-install]
- Root/sudo required for repository setup and package installation.

#### Installation Steps

**Step 1 — Add packagecloud repository:**

```bash
# apt/deb (auto-detects distro):
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash

# yum/rpm:
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | sudo bash
```

For downstream Ubuntu derivatives (example — Linux Mint 22.1 Xia):

```bash
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh \
  | os=debian dist=xia sudo -E bash
```

For Ubuntu-based distros with non-matching codenames:

```bash
(. /etc/lsb-release &&
 curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh \
 | sudo env os=ubuntu dist="${DISTRIB_CODENAME}" bash)
```

Behind a proxy, preserve environment with `sudo -E`.[^installing-md]

**Step 2 — Install package:**

```bash
# apt/deb:
sudo apt-get update && sudo apt-get install -y git-lfs
# Pin version:
sudo apt-get install -y git-lfs=3.7.1

# yum/rpm:
sudo yum install -y git-lfs
```

The devcontainers reference implementation adds the packagecloud repo manually (without the setup script) using:[^devcontainer-install]

```bash
curl -sSL https://packagecloud.io/github/git-lfs/gpgkey | gpg --dearmor \
  > /usr/share/keyrings/gitlfs-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gitlfs-archive-keyring.gpg] \
  https://packagecloud.io/github/git-lfs/${ID} ${VERSION_CODENAME} main" \
  > /etc/apt/sources.list.d/git-lfs.list
apt-get update && apt-get install -y git-lfs
```

#### Installation Verification

```bash
git-lfs version
git config --system --get-regexp 'filter\.lfs'   # postinst configures system scope
```

Expected package contents (packagecloud `.deb`):[^deb-contents]

- `/usr/bin/git-lfs` (binary)
- `/usr/share/man/man1/git-lfs*.1.gz` (man pages)
- `/usr/share/doc/git-lfs/` (changelog, copyright)

#### Configuration Options

##### Version Selection

Pin with apt version suffix: `git-lfs=3.7.1`. Soft-match a semver prefix against GitHub release tags (as devcontainers feature does) when an exact package version is unavailable.[^devcontainer-install]

##### Installation Path

Fixed by package: `/usr/bin/git-lfs`.

##### User Targeting

System-wide only (requires root).

##### Required Privileges

Root/sudo for repository setup and package installation.

##### Tool-Specific Configurations

**Automatic post-install**: package `postinst` runs:[^deb-postinst]

```sh
git lfs install --skip-repo --system
```

Package `prerm` runs `git lfs uninstall --skip-repo --system`. No manual `git lfs install` is needed after package installation.

Additional `git lfs install` flags (`--skip-smudge`, `--force`, etc.) are not exposed by the package; apply manually if needed after install.

#### Post-Installation Steps and Cleanup

##### PATH Setup

`/usr/bin` is on PATH by default. No action needed.

##### Configuration Files

`/etc/gitconfig` is modified by `postinst` (system-scope LFS filters). No other persistent files created.

##### Environment Variables

None required.

##### Activation Scripts

None.

##### Shell Completions

Not included in official packages; generate from binary if desired.

##### Cleanup

Remove repository list if install fails:

```bash
rm -f /etc/apt/sources.list.d/git-lfs.list
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

`apt-get upgrade git-lfs` / `dnf upgrade git-lfs`. Postinst re-runs on upgrade.

##### Uninstallation

```bash
sudo apt-get remove git-lfs    # prerm removes system LFS config
sudo yum remove git-lfs
```

##### Idempotency

Re-running `apt-get install git-lfs` when already installed is a no-op (or upgrades if newer version available).

#### Details

Packages are built in Docker via `git-lfs/build-dockers` and uploaded to packagecloud by `script/packagecloud.rb` during the release CI workflow.[^release-workflow] amd64 packages are built for all listed distros; arm64 Debian packages are built only for recent versions due to emulation cost.[^readme-binary]

#### Notes and Best Practices

- packagecloud packages track upstream releases closely (3.7.1 as of 2026-06-18); preferred over stale distro repos when a current version is needed.
- Adding the packagecloud repo modifies system apt/yum configuration; consider cleanup policy for ephemeral CI containers.
- The devcontainers git-lfs feature falls back to GitHub binary download when the running codename is not in its allowlist (`stretch buster bullseye bionic focal jammy`) — Noble and Bookworm require either updating the allowlist or using binary fallback.[^devcontainer-install]

---

### OS Package Manager (Distro-Native)

#### Supported Platforms

| Platform | Package name | Notes |
|----------|-------------|-------|
| Debian/Ubuntu | `git-lfs` | In universe/main depending on release; **lags upstream** |
| Fedora | `git-lfs` | Available in official repos |
| RHEL/CentOS 7+ | `git-lfs` | May require EPEL or powertools |
| Alpine Linux | `git-lfs` | community repo |
| Arch Linux | `git-lfs` | extra repo |
| openSUSE | `git-lfs` | |
| macOS (Homebrew) | `git-lfs` | See [Homebrew](#homebrew) section (not duplicated here) |

#### Dependencies

##### Common Dependencies

- `git` (package managers declare or assume Git is present).

##### Platform-Specific Dependencies

- Ubuntu Noble (24.04): `git-lfs` depends on `git, libc6 (>= 2.34)`.[^ubuntu-apt]

#### Installation Steps

| Platform | Command |
|----------|---------|
| Debian/Ubuntu | `sudo apt-get install -y git-lfs` |
| Fedora/RHEL 8+ | `sudo dnf install -y git-lfs` |
| Alpine | `sudo apk add --no-cache git-lfs` |
| Arch | `sudo pacman -S --noconfirm git-lfs` |
| macOS | `brew install git-lfs` |

**Version lag example (Ubuntu Noble, verified 2026-06-18):**

| Source | Version |
|--------|---------|
| Ubuntu Noble (`apt`) | 3.4.1-1ubuntu0.4[^ubuntu-apt] |
| packagecloud (noble) | 3.7.1[^packagecloud-noble] |
| GitHub latest | 3.7.1[^release-latest] |

#### Installation Verification

```bash
git-lfs version
git config --system --get-regexp 'filter\.lfs'   # if postinst ran
```

#### Configuration Options

##### Version Selection

Determined by distro freeze point; no arbitrary version pinning without a separate repo (packagecloud, GitHub binary).

##### Installation Path

Distro-defined (typically `/usr/bin/git-lfs`).

##### User Targeting

System-wide.

##### Required Privileges

Root/sudo.

##### Tool-Specific Configurations

**Post-install hook wiring by distro:**

| Distro / package source | Auto-runs `git lfs install`? | Command / script |
|------------------------|------------------------------|------------------|
| Ubuntu/Debian (native apt) | Yes | `postinst`: `git lfs install --skip-repo --system`[^ubuntu-postinst] |
| packagecloud `.deb`/`.rpm` | Yes | `postinst`/`%post`: `git lfs install --skip-repo --system`[^deb-postinst] |
| Alpine (`apk`) | Yes | `git-lfs.post-install`: `git-lfs install --skip-repo --system`[^alpine-post-install] |
| Fedora/RHEL (native `dnf`/`yum`) | Yes (unless opted out) | `%post`: `git lfs install --system --skip-repo` unless `fedora.git-lfs.no-modify-config=true`[^fedora-spec] |
| Arch Linux (`pacman`) | **No** | PKGBUILD has no `.install` hook; user must run `git lfs install` manually[^arch-pkgbuild] |
| Homebrew | **No** | Formula caveats instruct manual `git lfs install`[^brew-formula] |

#### Post-Installation Steps and Cleanup

##### PATH Setup

None required.

##### Configuration Files

Ubuntu/Debian: `/etc/gitconfig` modified by postinst.

##### Environment Variables

None required.

##### Activation Scripts

None.

##### Shell Completions

Varies by distro packaging; often not included.

##### Cleanup

Standard package manager cleanup.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Standard package manager upgrade commands.

##### Uninstallation

```bash
sudo apt-get remove git-lfs   # Ubuntu/Debian prerm runs git lfs uninstall --skip-repo --system
```

##### Idempotency

Standard package manager semantics.

#### Details

The `install-os-pkg-bundle` `vcs_tools` bundle includes `git-lfs` via plain `apt-get install git-lfs`. On Ubuntu/Debian this triggers the distro postinst (`git lfs install --skip-repo --system`), satisfying hook wiring without a custom feature hook — but delivers an older version (3.4.1 on Noble vs 3.7.1 upstream).[^bundle-vcs-tools][^ubuntu-apt]

#### Notes and Best Practices

- Fastest method; acceptable when version lag is tolerable.
- For Noble and other recent distros needing ≥ 3.7.x, prefer packagecloud repo or GitHub binary over plain distro apt.
- Distro packages on Ubuntu/Debian automatically handle `git lfs install --system`; no additional feature hook needed for filter wiring when using this method.

---

### Homebrew

#### Supported Platforms

macOS (Intel and Apple Silicon) and Linux (x86_64 and arm64 bottles).[^brew-formula]

#### Dependencies

##### Common Dependencies

Build (for `--build-from-source`): `go`, `asciidoctor`.

Bottle install: none (self-contained).

##### Platform-Specific Dependencies

- macOS: Xcode CLT not required for bottle install.
- Git must be installed separately for `git lfs` invocation.

#### Installation Steps

```bash
brew install git-lfs
# REQUIRED manual post-step:
git lfs install            # or: git lfs install --system (with sudo, for all users)
```

Homebrew builds from the source tarball `git-lfs-v{version}.tar.gz` when building from source; bottles install `/opt/homebrew/bin/git-lfs` (Apple Silicon) or `/usr/local/bin/git-lfs` (Intel).[^brew-formula]

#### Installation Verification

```bash
git-lfs version
git config --get-regexp 'filter\.lfs'   # only after manual git lfs install
```

#### Configuration Options

##### Version Selection

```bash
brew install git-lfs
brew upgrade git-lfs
```

Homebrew maintains a single unversioned `git-lfs` formula (currently 3.7.1) resolved via `strategy :github_latest`. There is no `git-lfs@3.7.1` versioned formula; pin a specific release via GitHub binary download instead.[^brew-formula]

##### Installation Path

Bottle cellar path linked into `$HOMEBREW_PREFIX/bin/git-lfs`.

##### User Targeting

User-local by default (Homebrew prefix); use `git lfs install --system` for system-wide Git config.

##### Required Privileges

None for default Homebrew install; sudo for `--system` Git config.

##### Tool-Specific Configurations

Homebrew **does not** run `git lfs install`. The formula prints caveats instructing the user to run it manually.[^brew-formula]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Homebrew bin directory must be on PATH (standard Homebrew shell setup).

##### Configuration Files

None until user runs `git lfs install`.

##### Environment Variables

None.

##### Activation Scripts

None.

##### Shell Completions

Generated via `generate_completions_from_executable` in the formula (bash/fish/zsh).[^brew-formula]

##### Cleanup

`brew uninstall git-lfs`

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

`brew upgrade git-lfs`

##### Uninstallation

```bash
brew uninstall git-lfs
git lfs uninstall          # clean up Git config manually
```

##### Idempotency

`brew install git-lfs` when already installed is a no-op.

#### Details

Homebrew formula runs `make`, `make man`, installs binary and man pages, generates shell completions.[^brew-formula]

#### Notes and Best Practices

- Always run `git lfs install` after `brew install git-lfs`.
- On Apple Silicon, ensure Homebrew's bin directory (`/opt/homebrew/bin`) is on PATH.[^wiki-install]

---

### Windows Installer (.exe) and Git for Windows

#### Supported Platforms

Windows (amd64 primary; arm64 packages also published).

#### Dependencies

##### Common Dependencies

- Git for Windows (recommended companion; bundles Git LFS as an optional component).
- Administrator privileges for system-wide `.exe` installer.

##### Platform-Specific Dependencies

None beyond Git.

#### Installation Steps

**Option A — Git for Windows (recommended on Windows):**

Install [Git for Windows](https://gitforwindows.org/) with the "Git LFS" optional component selected during installation. Git LFS is included in the Git for Windows distribution.[^readme-windows][^wiki-install]

**Option B — Standalone `.exe` installer:**

Download `git-lfs-windows-v{version}.exe` from GitHub releases and run the signed InnoSetup installer.[^release-latest][^release-workflow]

**Option C — Portable `.zip`:**

Extract `git-lfs-windows-amd64-v{version}.zip` and add the containing directory to `PATH`. No `install.sh` is included.[^windows-zip]

After any method, run:

```powershell
git lfs install
```

#### Installation Verification

```powershell
git-lfs version
git lfs env
```

The `.exe` installer is Azure code-signed in the release CI workflow.[^release-workflow]

#### Configuration Options

##### Version Selection

Download specific version from GitHub releases.

##### Installation Path

Installer-managed (typically `%LOCALAPPDATA%\Programs\Git LFS\` or Git for Windows directory).

##### User Targeting

Installer supports per-user and system-wide scopes (InnoSetup).

##### Required Privileges

Administrator for system-wide install.

##### Tool-Specific Configurations

Same `git lfs install` options as Linux/macOS.[^man-install]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Restart shell after install so PATH changes take effect.[^readme-binary]

##### Configuration Files

Git config modified by `git lfs install` (global user scope by default on Windows).

##### Environment Variables

None required.

##### Activation Scripts

None.

##### Shell Completions

Generate via `git lfs completion bash|fish|zsh` if using a Unix-like shell on Windows (Git Bash).

##### Cleanup

Use Windows "Add/Remove Programs" for `.exe` install; run `git lfs uninstall` first.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run newer `.exe` installer or download updated binary.

##### Uninstallation

```powershell
git lfs uninstall
# Then remove via Add/Remove Programs or delete binary directory
```

##### Idempotency

Installer handles upgrade in place.

#### Details

Windows release CI builds three zip architectures plus a signed `.exe` via InnoSetup, with Azure artifact signing.[^release-workflow]

#### Notes and Best Practices

- Git for Windows is the recommended comprehensive Git+LFS environment on Windows.
- Chocolatey (`choco install git-lfs.install`) is an alternative Windows package route.[^readme-windows]

---

### Build From Source

#### Supported Platforms

All platforms with Go ≥ 1.23.0, GNU `make`, and a standard build environment. Windows additionally requires `goversioninfo`.[^readme-build][^go-mod]

#### Dependencies

##### Common Dependencies

- Go ≥ 1.23.0 (1.25+ used in official CI)[^go-mod][^release-workflow]
- GNU `make`
- `asciidoctor` (for man page generation)
- Git (for `git describe` versioning)

##### Platform-Specific Dependencies

- Windows: `go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@latest`[^readme-build]

#### Installation Steps

```bash
set -e
VERSION="3.7.1"
curl -fsSL "https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}/git-lfs-v${VERSION}.tar.gz" \
  | tar -xz
cd "git-lfs-${VERSION}"
# Upstream's default target builds the local binary in bin/git-lfs.
# Do not use `make all` here: that target builds the full cross-platform
# release matrix, not a single local install artifact.
make
sudo install -m 0755 bin/git-lfs /usr/local/bin/git-lfs
# Optional man pages:
make man && sudo cp man/man1/*.1 /usr/share/man/man1/
# REQUIRED:
sudo git lfs install --skip-repo --system
```

Cross-compilation: `CGO_ENABLED=0` (used in official Linux release builds).[^release-workflow]

#### Installation Verification

```bash
git-lfs version
```

#### Configuration Options

##### Version Selection

Build from release source tarball or git tag checkout.

##### Installation Path

Any writable directory on PATH.

##### User Targeting

Supports both system-wide and user-local install paths.

##### Required Privileges

Required for system-wide paths and `--system` Git config.

##### Tool-Specific Configurations

Same `git lfs install` options. No build-time feature flags exposed beyond standard Go build tags.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure install directory is on PATH.

##### Configuration Files

Modified by `git lfs install`.

##### Environment Variables

`GIT_LFS_SHA`, `VERSION`, `VENDOR`, `DWARF`, `LDFLAGS` — build-time Makefile variables.[^makefile]

##### Activation Scripts

None.

##### Shell Completions

Generate from built binary via `git lfs completion`.

##### Cleanup

```bash
rm -rf "git-lfs-${VERSION}"
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Rebuild and reinstall.

##### Uninstallation

Remove binary; run `git lfs uninstall`.

##### Idempotency

Rebuilding same version overwrites binary.

#### Details

Official release CI uses Go 1.26.x, `CGO_ENABLED=0 make release` on Linux, with separate Docker-based package builds for `.deb`/`.rpm`.[^release-workflow]

#### Notes and Best Practices

- Reserve for platforms without pre-built binaries or when patching source.
- Official binaries are preferred over source builds in containers for speed and reproducibility.

---

## Dev Container Setup

Git LFS requires special consideration in devcontainer environments beyond placing the binary on PATH:

### Git dependency

Git LFS cannot function without Git. Ensure `git` is installed (via `install-git` feature, base image, or package dependency) **before** Git LFS installation and `git lfs install`.[^deb-depends]

### Mandatory `git lfs install` hook wiring

| Install method | Auto-runs `git lfs install`? | Scope | Action needed |
|---------------|------------------------------|-------|---------------|
| packagecloud `.deb`/`.rpm` | Yes (postinst/`%post`) | `--system --skip-repo` | None |
| Ubuntu/Debian distro `apt` | Yes (postinst) | `--system --skip-repo` | None |
| Alpine `apk` | Yes (`.post-install`) | `--system --skip-repo` | None |
| Fedora/RHEL `dnf`/`yum` | Yes (`%post`, unless opted out) | `--system --skip-repo` | None |
| Arch `pacman` | **No** | — | **Must run `git lfs install`** |
| GitHub binary / `install.sh` | Partial (global user of installing account only) | installing user's `~/.gitconfig` | **Run `--system` explicitly** or run as `remoteUser` |
| GitHub binary (manual) | No | — | **Must run `git lfs install`** |
| Homebrew | No | — | **Must run `git lfs install`** |

**Recommended for DevFeats feature (all methods where not automatic):**

```bash
git lfs install --skip-repo --system
```

Use `--skip-repo` during feature install to avoid modifying Git hooks in the build working tree (which may itself be a Git repository, e.g., when `/` or `$PWD` is inside a repo).[^deb-postinst][^man-install]

### User scope vs system scope in containers

Devcontainer features typically run as **root** during build. If only `git lfs install` (without `--system`) is run, filters are written to `/root/.gitconfig`. A non-root `remoteUser` (e.g., `vscode`) will **not** inherit LFS configuration.[^vscode-issue]

**Fix**: always prefer `--system` in container/feature installs, or run `git lfs install` as the `remoteUser` in a `postCreateCommand`.

The devcontainers git-lfs feature runs `git lfs install --skip-repo` (without `--system`) after packagecloud apt install, which configures root's global config only.[^devcontainer-install] Combined with VS Code's `.gitconfig` copy behavior, this has caused issues where user gitconfig is overwritten; workarounds include `postStartCommand: "git lfs install"`.[^vscode-issue]

### Version selection in containers

- **Default distro apt** (Noble): 3.4.1 — missing CVE-2025-26625 fix and other 3.5–3.7 improvements.[^ubuntu-apt][^release-notes]
- **packagecloud apt** (Noble): 3.7.1 — current upstream.[^packagecloud-noble]
- **GitHub binary**: 3.7.1 — version-pinnable, no extra repo.[^release-latest]

For a dedicated `install-git-lfs` feature, support version pinning via GitHub releases (binary method) or packagecloud (when codename is supported).

### Optional: auto-pull LFS content

The devcontainers git-lfs feature generates `/usr/local/share/pull-git-lfs-artifacts.sh` and sets it as `postCreateCommand` to run `git lfs pull` when `autoPull=true`.[^devcontainer-feature-json] This is a **runtime/project-level** concern, not part of Git LFS installation itself. Consider as an optional feature flag.

### Recommended install strategy for `install-git-lfs`

1. **`package` (default)**: Install via OS package manager. On Debian/Ubuntu, optionally add packagecloud repo when `version=latest` or pinned version exceeds distro version (internal optimization, similar to `install-git` PPA pattern).
2. **`binary`**: Download from GitHub releases; deterministic version pinning; requires explicit `git lfs install --skip-repo --system` hook.
3. **`build`**: Source build fallback (rarely needed).

**Custom `install.bash` hook assessment:**

| Scenario | Custom hook needed? |
|----------|----------------------|
| `method=package` on Ubuntu/Debian (distro or packagecloud apt) | **No** — postinst handles `--system --skip-repo` filter wiring |
| `method=package` on Alpine or Fedora/RHEL | **No** — package post-install/`%post` handles `--system --skip-repo`[^alpine-post-install][^fedora-spec] |
| `method=package` on Arch Linux | **Yes** — no `.install` hook; must run `git lfs install` after package install[^arch-pkgbuild] |
| `method=binary` (GitHub release) | **Yes** — must run `git lfs install` with configurable scope after binary install |
| Any method with `skipSmudge=true` option | **Yes** — pass `-s`/`--skip-smudge` to `git lfs install` |
| Any method with user-scope install targeting `remoteUser` | **Yes** — run `git lfs install` as that user |

### Comparable devcontainer features

| Feature | Method | Version pinning | Hook wiring | Notes |
|---------|--------|----------------|-------------|-------|
| `devcontainers/features/git-lfs` | packagecloud apt (fallback: GitHub binary) | Yes (`version` option) | `git lfs install --skip-repo` (global root only) | Noble/Bookworm need binary fallback; `autoPull` option[^devcontainer-feature-json] |
| `devcontainers-extra/features/git-lfs` | GitHub release via `gh-release` | Yes (`version` option) | **None** — no `git lfs install` | Requires hook in consuming feature[^extra-feature] |
| `install-os-pkg-bundle/vcs_tools` | distro apt | No | Automatic via Ubuntu postinst | Delivers stale 3.4.1 on Noble[^bundle-vcs-tools] |

### No special container configuration otherwise

- No daemons, volume mounts, or privileged capabilities required beyond standard root access during feature install.
- No VS Code extension is required; Git LFS operates through Git CLI integration.

## Plugins and Extensions

Git LFS does not support third-party plugins. Relevant integrations:

### Git for Windows bundled LFS

Git for Windows optionally installs Git LFS as part of the main Git installer, providing a unified Git+LFS environment on Windows. This is the recommended Windows distribution path.[^readme-windows][^wiki-install]

### VS Code / devcontainer `.gitconfig` interaction

VS Code copies the local `.gitconfig` into containers during setup. If a feature runs `git lfs install` as root before this copy, the container user's gitconfig may contain only LFS filter entries and the credential helper unless VS Code's merge fix is applied (VS Code ≥ fixed version). Workaround: run `git lfs install` in `postStartCommand` as the container user.[^vscode-issue]

## References

[^readme]: [Git LFS README — overview, installation summary, build instructions](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^readme-limits]: [Git LFS README — Limitations section (Git ≥ 2.0.0 requirement)](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^readme-binary]: [Git LFS README — "From binary" section (install.sh behavior, PATH note)](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^readme-build]: [Git LFS README — "From source" build steps](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^readme-verify]: [Git LFS README — "Verifying releases" (GPG keys, sha256sums.asc)](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^readme-mise]: [Git LFS README — mise-en-place installation](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^readme-windows]: [Git LFS README — Windows (Git for Windows, Chocolatey)](https://github.com/git-lfs/git-lfs/blob/main/README.md)
[^git-lfs-site]: [git-lfs.com — Getting Started (`git lfs install` once per user account)](https://git-lfs.com/)
[^installing-md]: [Git LFS INSTALLING.md — packagecloud apt/rpm setup scripts](https://github.com/git-lfs/git-lfs/blob/main/INSTALLING.md)
[^wiki-install]: [Git LFS Wiki — Installation guide (distro packages, manual binary, Git for Windows)](https://github.com/git-lfs/git-lfs/wiki/Installation)
[^man-install]: [git-lfs-install(1) man page — install options and behavior](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-install.adoc)
[^man-uninstall]: [git-lfs-uninstall(1) man page](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-uninstall.adoc)
[^man-main]: [git-lfs(1) man page — architecture overview](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs.adoc)
[^man-config]: [git-lfs-config(5) man page — runtime configuration keys](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-config.adoc)
[^man-completion]: [git-lfs-completion(1) man page — shell completion generation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-completion.adoc)
[^release-latest]: [GitHub Releases — v3.7.1 assets and checksums (API verified 2026-06-18)](https://github.com/git-lfs/git-lfs/releases/tag/v3.7.1)
[^release-notes]: [GitHub Release v3.7.1 notes — CVE-2025-26625, package links](https://github.com/git-lfs/git-lfs/releases/tag/v3.7.1)
[^release-workflow]: [Git LFS .github/workflows/release.yml — CI build, signing, packagecloud upload](https://github.com/git-lfs/git-lfs/blob/main/.github/workflows/release.yml)
[^binary-install-sh]: [Git LFS v3.7.1 linux-amd64 release tarball — `install.sh` contents (extracted from `git-lfs-linux-amd64-v3.7.1.tar.gz`)](https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-linux-amd64-v3.7.1.tar.gz)
[^binary-test]: [Git LFS v3.7.1 linux-amd64 binary — release asset; statically linked ELF verified via `file` and `git-lfs version`](https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-linux-amd64-v3.7.1.tar.gz)
[^windows-zip]: [Git LFS v3.7.1 windows-amd64 release zip — contains `git-lfs.exe` but no `install.sh`](https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-windows-amd64-v3.7.1.zip)
[^man-install-test]: [git-lfs-install(1) — filter.lfs config keys written by `git lfs install`](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-install.adoc)
[^deb-postinst]: [packagecloud git-lfs_3.7.1_amd64.deb — postinst/prerm scripts (`git lfs install/uninstall --skip-repo --system`)](https://packagecloud.io/github/git-lfs/packages/ubuntu/noble/git-lfs_3.7.1_amd64.deb)
[^ubuntu-postinst]: [Ubuntu Noble git-lfs_3.4.1-1ubuntu0.4_amd64.deb — postinst/prerm scripts](http://archive.ubuntu.com/ubuntu/pool/universe/g/git-lfs/git-lfs_3.4.1-1ubuntu0.4_amd64.deb)
[^deb-contents]: [packagecloud git-lfs_3.7.1_amd64.deb — `/usr/bin/git-lfs` and man page file list](https://packagecloud.io/github/git-lfs/packages/ubuntu/noble/git-lfs_3.7.1_amd64.deb)
[^deb-depends]: [packagecloud git-lfs_3.7.1_amd64.deb control metadata — `Depends: git (>= 2.0.0)`](https://packagecloud.io/github/git-lfs/packages/ubuntu/noble/git-lfs_3.7.1_amd64.deb)
[^ubuntu-apt]: [Ubuntu Noble apt repository — `git-lfs` candidate 3.4.1-1ubuntu0.4 (verified via `apt-cache policy git-lfs` 2026-06-18)](http://archive.ubuntu.com/ubuntu/pool/universe/g/git-lfs/)
[^alpine-post-install]: [Alpine aports git-lfs.post-install — `git-lfs install --skip-repo --system`](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/git-lfs/git-lfs.post-install)
[^fedora-spec]: [Fedora git-lfs.spec rawhide — `%post` runs `git lfs install --system --skip-repo`](https://src.fedoraproject.org/rpms/git-lfs/raw/rawhide/f/git-lfs.spec)
[^arch-pkgbuild]: [Arch Linux git-lfs PKGBUILD — no `.install` hook; binary and completions only](https://gitlab.archlinux.org/archlinux/packaging/packages/git-lfs/-/blob/main/PKGBUILD)
[^packagecloud-noble]: [packagecloud — ubuntu/noble git-lfs_3.7.1_amd64.deb](https://packagecloud.io/github/git-lfs/packages/ubuntu/noble/git-lfs_3.7.1_amd64.deb)
[^brew-formula]: [Homebrew git-lfs formula — v3.7.1, caveats requiring manual git lfs install](https://formulae.brew.sh/formula/git-lfs)
[^go-mod]: [Git LFS v3.7.1 go.mod — go 1.23.0, no stable API](https://github.com/git-lfs/git-lfs/blob/v3.7.1/go.mod)
[^makefile]: [Git LFS Makefile — build variables](https://github.com/git-lfs/git-lfs/blob/main/Makefile)
[^devcontainer-install]: [devcontainers/features git-lfs install.sh — apt repo, GitHub fallback, git lfs install --skip-repo](https://github.com/devcontainers/features/blob/main/src/git-lfs/install.sh)
[^devcontainer-feature-json]: [devcontainers/features git-lfs devcontainer-feature.json — options and postCreateCommand](https://github.com/devcontainers/features/blob/main/src/git-lfs/devcontainer-feature.json)
[^devcontainer-gpg]: [devcontainers/features git-lfs install.sh — GPG key IDs for checksum verification](https://github.com/devcontainers/features/blob/main/src/git-lfs/install.sh)
[^extra-feature]: [devcontainers-extra/features git-lfs — gh-release wrapper, no git lfs install](https://github.com/devcontainers-extra/features/blob/main/src/git-lfs/install.sh)
[^vscode-issue]: [VS Code Remote — git-lfs feature vs .gitconfig copy issue and postStartCommand workaround](https://github.com/microsoft/vscode-remote-release/issues/6810)
[^bundle-vcs-tools]: [DevFeats install-os-pkg-bundle vcs_tools bundle — lists `git-lfs` as an apt package (no hook documentation in bundle YAML)](features/install-os-pkg-bundle/bundle-docs/vcs-tools.yaml)
