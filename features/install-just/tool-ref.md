# Feature Reference

just is a command runner that executes named recipes from a justfile. The project documents installation via package managers, prebuilt binaries, an official installer script, and Rust tooling. For DevFeats, the practical installation approaches are: OS package managers, the official install script, manual release-asset installation, container-image copy from GHCR, and Rust toolchain installation.

- **Homepage**: https://just.systems/
- **Source Code**: https://github.com/casey/just
- **Documentation**: https://just.systems/man/en/
- **Latest Release**: 1.50.0 (as of 2026-04-26)

## Available Installation Methods

just is distributed through many channels. For a DevFeats feature targeting macOS and Linux across containers and bare metal, the implementation-relevant methods are:

1. OS package manager install for distro-native lifecycle management.
2. Official installer script (`just.systems/install.sh`) for fast binary install with optional version pinning.
3. Manual prebuilt release archive install from GitHub Releases for deterministic and auditable installs.
4. Container-image copy from `ghcr.io/casey/just` for Docker/devcontainer build contexts.
5. Rust ecosystem install (`cargo install` / `cargo binstall`) when Rust toolchain-based workflows are preferred.

### OS Package Manager

#### Supported Platforms

- macOS via Homebrew (`brew`) and MacPorts (`port`).
- Linux distributions with published packages, including Alpine (`apk`), Arch (`pacman`), Debian 13 and Ubuntu 24.04 derivatives (`apt`), Fedora (`dnf`), Gentoo (`emerge`), NixOS (`nix-env`), openSUSE (`zypper`), Solus (`eopkg`), and Void (`xbps-install`).
- BSD package managers are also documented upstream, but DevFeats scope here is macOS and Linux.

#### Dependencies

- **Common Dependencies**: A functioning system package manager and configured repositories.
- **Platform-Specific Dependencies**:
  - Linux package-manager installs generally require root privileges.
  - Homebrew and MacPorts require their own bootstrap/runtime environment.
  - Runtime shell requirement: just expects a usable `sh` by default (or explicit shell configuration in justfile settings).

#### Installation Steps

1. Refresh package metadata if needed.
2. Install package `just` via the native package manager.

Examples:

```bash
# Debian / Ubuntu
sudo apt-get update
sudo apt-get install -y just

# Fedora
sudo dnf install -y just

# Alpine
sudo apk add --no-cache just

# Arch
sudo pacman -S --noconfirm just

# openSUSE
sudo zypper in -y just

# Gentoo
sudo emerge -av dev-build/just

# NixOS
nix-env -iA nixos.just

# Solus
sudo eopkg install just

# Void
sudo xbps-install -S just

# macOS Homebrew
brew install just

# macOS MacPorts
sudo port install just
```

#### Installation Verification

```bash
command -v just
just --version
```

Optional package-level verification:

```bash
# Debian / Ubuntu
apt-cache policy just

# Fedora
dnf info just

# Alpine
apk info just

# Homebrew
brew info just
```

#### Configuration Options

- **Version Selection**:
  - Depends on package manager and repository availability.
  - Exact-version pinning can be inconsistent across distros; for strict pinning, prefer release-archive or installer-script methods.
- **Installation Path**:
  - Package-manager controlled, typically system paths (`/usr/bin`, `/usr/local/bin`, or manager-specific prefix).
- **User Targeting**:
  - Generally system-wide.
  - Homebrew may install under user-owned prefix depending on setup.
- **Required Privileges**:
  - Usually root on Linux; Homebrew often runs as non-root in user prefix.
- **Tool-Specific Configurations**:
  - No just-specific install-time flags through OS package managers.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Usually none for system packages.
  - Ensure Homebrew shell environment is initialized if `just` is not found in PATH.
- **Configuration Files**:
  - None required for core just operation.
- **Environment Variables**:
  - None required for core just operation.
- **Activation Scripts**:
  - None required.
- **Cleanup**:

```bash
# Common Debian/Ubuntu container cleanup pattern
apt-get clean
apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Use package-manager native upgrade or version-specific install syntax where supported.
- **Uninstallation**:

```bash
# Debian / Ubuntu
sudo apt-get remove -y just

# Fedora
sudo dnf remove -y just

# Alpine
sudo apk del just

# Arch
sudo pacman -R --noconfirm just

# macOS Homebrew
brew uninstall just

# macOS MacPorts
sudo port uninstall just
```

- **Idempotency**:
  - Re-running install is package-manager idempotent; package remains installed and may be upgraded based on repository state.

#### Notes and Best Practices

- Package-manager installation is usually the simplest default and integrates with host lifecycle tooling.
- Repository versions may lag upstream release cadence.
- Community devcontainer feature implementations show mixed strategies: direct package-manager install, direct release-binary download, and delegation to the official installer script.

### Official Installer Script (`https://just.systems/install.sh`)

#### Supported Platforms

- Linux and macOS with automatic target detection in the script.
- Windows support exists in script logic for `x86_64-pc-windows-msvc` targets.
- For DevFeats scope, this method is directly applicable to macOS and Linux.

#### Dependencies

- **Common Dependencies**: `bash`, `curl` or `wget`, `mkdir`, `mktemp`, `uname` (for auto target detection).
- **Platform-Specific Dependencies**:
  - `tar` for non-Windows target archives.
  - `unzip` for Windows zip archive flow.
  - `grep` and `cut` when `--tag` is omitted (script uses GitHub API to resolve latest).
  - `cut` when `--target` is omitted.

#### Installation Steps

1. Run the official installer script and choose destination.
2. Optionally pin tag and target.

Examples:

```bash
# Install latest to default ~/bin
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash

# Install specific version to ~/.local/bin
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
  | bash -s -- --tag 1.50.0 --to "$HOME/.local/bin"

# Overwrite existing binary
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
  | bash -s -- --tag 1.50.0 --to "$HOME/.local/bin" --force
```

#### Installation Verification

```bash
command -v just
just --version
```

The script logs chosen repository/tag/target/archive before download, which can be used for audit logs in CI.

#### Configuration Options

- **Version Selection**:
  - `--tag TAG` pins explicit version.
  - If omitted, script calls GitHub API for latest release.
- **Installation Path**:
  - `--to LOCATION`, default `~/bin`.
- **User Targeting**:
  - User-local installation by default.
  - System-wide possible by setting destination to root-owned path (for example `/usr/local/bin`) with appropriate privileges.
- **Required Privileges**:
  - Depends on destination write permissions.
- **Tool-Specific Configurations**:
  - `--force` to overwrite existing destination binary.
  - `--target TARGET` for explicit target triple.
  - `GITHUB_TOKEN` env var can be set to authenticate GitHub API requests and reduce anonymous rate-limit failures when resolving latest tag.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure destination directory is on PATH. For default user-local flow:

```bash
export PATH="$PATH:$HOME/bin"
```

- **Configuration Files**:
  - None required.
- **Environment Variables**:
  - No runtime env var required by just itself.
  - `GITHUB_TOKEN` is optional installer-time auth only.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Installer script removes its temporary extraction directory automatically.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Re-run installer with `--tag` to target desired version.
  - Use `--force` when replacing existing binary in place.
- **Uninstallation**:

```bash
rm -f "$HOME/bin/just"
# or remove from whichever --to path was used
```

- **Idempotency**:
  - Not fully idempotent by default: script fails if destination already exists unless `--force` is set.

#### Details

The install script performs these steps in order:

1. **Argument parsing**: processes flags `--force`/`-f`, `--tag`, `--target`, `--to`; defaults destination to `$HOME/bin`.
2. **Downloader detection**: requires `curl` or `wget` and enforces TLS 1.2 explicitly (`--proto =https --tlsv1.2` for curl; `--https-only --secure-protocol=TLSv1_2` for wget).
3. **Version resolution**: if `--tag` is omitted, queries `https://api.github.com/repos/casey/just/releases/latest` and extracts `tag_name` via `grep` + `cut`. Passes `Authorization: Bearer $GITHUB_TOKEN` when the variable is set.
4. **Target triple detection**: if `--target` is omitted, constructs `$(uname -m)-$(uname -s | cut -d- -f1)` (stripping MINGW version suffixes) and maps via `case` to a Rust triple. Auto-detected triples: `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl`, `arm-unknown-linux-musleabihf` (armv6l), `armv7-unknown-linux-musleabihf` (armv7l), `loongarch64-unknown-linux-musl`, `x86_64-apple-darwin`, `aarch64-apple-darwin`, `x86_64-pc-windows-msvc` (MINGW/Windows). No 32-bit x86, no FreeBSD, no riscv64 auto-detection.
5. **Archive format selection**: `.zip` (requires `unzip`) for `x86_64-pc-windows-msvc`; `.tar.gz` (requires `tar`) for all others.
6. **Download URL construction**: `https://github.com/casey/just/releases/download/$tag/just-$tag-$target.$extension`.
7. **Download and extraction**: streams archive via pipe directly into `tar -C "$td" -xz` (Unix) or downloads to temp dir then `unzip` (Windows).
8. **Overwrite guard**: if the destination binary already exists and `--force` is not set, exits with an error. When `--force` is set, unconditionally overwrites.
9. **Installation**: `mkdir -p "$dest"`, then `cp "$td/just" "$dest/just"` and `chmod 755`.
10. **Temp directory cleanup**: `rm -rf "$td"` always runs after extraction.

No checksum or signature verification is performed at any point.

#### Notes and Best Practices

- Installer convenience is high, but integrity checks are implicit TLS transport only; checksum verification is not performed by the script itself.
- In CI environments behind shared IPs, latest-tag API calls can hit rate limits. Prefer explicit `--tag` for reproducibility and reliability.
- Upstream release matrix currently includes targets not auto-detected by installer (for example `riscv64gc-unknown-linux-musl`).
- The release matrix includes `aarch64-pc-windows-msvc`, but current installer zip-handling logic explicitly branches only on `x86_64-pc-windows-msvc`, so Windows ARM64 is not covered by the script's default archive-selection behavior.

### Manual Prebuilt Release Archives (GitHub Releases)

#### Supported Platforms

- Any platform/architecture with published release assets.
- Latest release assets include: `aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-unknown-linux-musl`, `x86_64-unknown-linux-musl`, `arm-unknown-linux-musleabihf`, `armv7-unknown-linux-musleabihf`, `loongarch64-unknown-linux-musl`, `riscv64gc-unknown-linux-musl`, and Windows MSVC zip assets.

#### Dependencies

- **Common Dependencies**: `curl` or `wget`, archive extraction tools (`tar`/`unzip`), checksum utility (`shasum` or `sha256sum`).
- **Platform-Specific Dependencies**:
  - Write permissions for chosen installation path.
  - Optional `install` utility for permission-preserving placement.

#### Installation Steps

1. Choose version tag and matching target asset.
2. Download archive and `SHA256SUMS`.
3. Verify checksum.
4. Extract and install binary.

Example (Linux x86_64):

```bash
set -e
ver="1.50.0"
asset="just-${ver}-x86_64-unknown-linux-musl.tar.gz"
base="https://github.com/casey/just/releases/download/${ver}"

curl -fsSLO "${base}/${asset}"
curl -fsSLO "${base}/SHA256SUMS"
shasum --algorithm 256 --ignore-missing --check SHA256SUMS

tar -xzf "${asset}"
mkdir -p "$HOME/.local/bin"
install -m 0755 just "$HOME/.local/bin/just"
```

Example (macOS arm64):

```bash
set -e
ver="1.50.0"
asset="just-${ver}-aarch64-apple-darwin.tar.gz"
base="https://github.com/casey/just/releases/download/${ver}"

curl -fsSLO "${base}/${asset}"
curl -fsSLO "${base}/SHA256SUMS"
shasum --algorithm 256 --ignore-missing --check SHA256SUMS

tar -xzf "${asset}"
mkdir -p "$HOME/.local/bin"
install -m 0755 just "$HOME/.local/bin/just"
```

#### Installation Verification

```bash
just --version
```

Checksum verification command (officially documented by project):

```bash
shasum --algorithm 256 --ignore-missing --check SHA256SUMS
```

#### Configuration Options

- **Version Selection**:
  - Directly controlled by release tag used in URL.
- **Installation Path**:
  - Any writable directory (`$HOME/.local/bin`, `/usr/local/bin`, etc.).
- **User Targeting**:
  - Works for both user-local and system-wide installs.
- **Required Privileges**:
  - Only needed when writing to privileged paths.
- **Tool-Specific Configurations**:
  - Target triple selection must match host ABI expectations.
  - Release archives contain `just` plus `Cargo.lock`, `Cargo.toml`, `GRAMMAR.md`, `LICENSE`, `README.md`, `completions/`, and `man/just.1`.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Add target bin directory to PATH if needed.
- **Configuration Files**:
  - None required.
- **Environment Variables**:
  - None required.
- **Activation Scripts**:
  - None required.
- **Cleanup**:

```bash
rm -f just-*.tar.gz just-*.zip SHA256SUMS
```

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Install a different tagged release and replace binary.
- **Uninstallation**:

```bash
rm -f "$HOME/.local/bin/just"
# or whichever install location was used
```

- **Idempotency**:
  - Re-running with same version/path is idempotent when replacement is allowed.

#### Notes and Best Practices

- This method gives the best control for reproducible and auditable installations.
- Prefer explicit tag pinning in automation rather than "latest".
- For container builds, this method aligns well with immutable-image workflows.

### Container Image Copy (GHCR)

#### Supported Platforms

- Container builds that can use multi-stage `COPY --from=` with images from `ghcr.io/casey/just`.
- Official release workflow publishes multi-arch image variants for `linux/amd64` and `linux/arm64`.

#### Dependencies

- **Common Dependencies**: Docker-compatible build system with network access to GHCR.
- **Platform-Specific Dependencies**:
  - Linux container context (the published image content is a Linux binary at `/just`).
  - Registry access controls/credentials as required by environment.

#### Installation Steps

In a Dockerfile, copy the binary from official image into target image:

```dockerfile
COPY --from=ghcr.io/casey/just:latest /just /usr/local/bin/just
```

For reproducibility, pin version tag instead of `latest`:

```dockerfile
COPY --from=ghcr.io/casey/just:1.50.0 /just /usr/local/bin/just
```

#### Installation Verification

```dockerfile
RUN just --version
```

At runtime, validate with:

```bash
command -v just
just --version
```

#### Configuration Options

- **Version Selection**:
  - Controlled by image tag (`ghcr.io/casey/just:<tag>`).
  - Prefer pinned release tags over `latest`.
- **Installation Path**:
  - Destination path in final image is user-defined (`/usr/local/bin/just` is common).
- **User Targeting**:
  - System-wide within image filesystem.
- **Required Privileges**:
  - Depends on effective user in Docker build stage; root is common in build stages.
- **Tool-Specific Configurations**:
  - Upstream image is `FROM scratch` and only contains `/just`, so this is a minimal-copy install path.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure destination path is on PATH in target image.
- **Configuration Files**:
  - None required.
- **Environment Variables**:
  - None required by just runtime.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Multi-stage copy avoids residual package-manager caches and installer artifacts in final image.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Change source image tag and rebuild image.
- **Uninstallation**:
  - Remove copied binary path in image build recipe or base image layer.
- **Idempotency**:
  - Docker builds are deterministic per Dockerfile and image tag; repeated builds produce equivalent result when inputs are unchanged.

#### Notes and Best Practices

- Best suited for container-focused provisioning and CI image builds.
- Does not provide host-level package management; this is an image-build installation strategy.
- Keep tag pinning explicit in production images to avoid drift.

### Rust Toolchain Installation (`cargo install` / `cargo binstall`)

#### Supported Platforms

- Platforms where Rust toolchain and Cargo are supported.
- Suitable on macOS and Linux developer systems and build containers with Rust toolchain present.

#### Dependencies

- **Common Dependencies**: Rust toolchain (`rustup`, `cargo`), network access to crate/index and source artifacts.
- **Platform-Specific Dependencies**:
  - `cargo install` from source may require C toolchain/linker components depending on host setup.
  - `cargo-binstall` requires separate install of `cargo-binstall` itself.

#### Installation Steps

```bash
# Build from source
cargo install just

# Version pin
cargo install --version 1.50.0 just

# Binary-oriented cargo flow (if cargo-binstall is installed)
cargo binstall just
```

#### Installation Verification

```bash
command -v just
just --version
cargo install --list | grep '^just '
```

#### Configuration Options

- **Version Selection**:
  - `cargo install --version X.Y.Z just`.
- **Installation Path**:
  - Default under Cargo bin path (typically `$HOME/.cargo/bin`).
  - Can be customized with Cargo options such as `--root`.
- **User Targeting**:
  - Typically user-local installation.
- **Required Privileges**:
  - Usually no root required.
- **Tool-Specific Configurations**:
  - `cargo install --locked` is an optional Cargo-side hardening flag for more reproducible dependency resolution.
  - `cargo install --root <path>` controls install prefix.
  - `cargo install --force` replaces existing installs when changing versions in place.
  - `cargo binstall` may reduce build time by fetching binaries where available.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure Cargo bin directory is on PATH.
- **Configuration Files**:
  - None required by just.
- **Environment Variables**:
  - None required by just runtime.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Cargo caches can be cleaned according to local policy if needed.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:

```bash
cargo install --force --version 1.50.0 just
```

- **Uninstallation**:

```bash
cargo uninstall just
```

- **Idempotency**:
  - `cargo install` is generally idempotent for already-installed matching artifacts; `--force` ensures replacement.

#### Notes and Best Practices

- Useful when Rust toolchain is already part of environment.
- Typically slower than direct prebuilt archive install on clean systems.
- Prefer explicit version pinning in CI for reproducibility.

## References

- [just Homepage](https://just.systems/) - Official project landing page and installation entrypoint.
- [just Programmer's Manual](https://just.systems/man/en/) - Official released documentation set.
- [just README (Installation)](https://github.com/casey/just#installation) - Canonical install methods, package-manager matrix, binary install guidance, and verification command examples.
- [Published Installer Script](https://just.systems/install.sh) - Script actually executed by curl-pipe install flow; source of options, dependency checks, and target detection logic.
- [Installer Source in Repository](https://github.com/casey/just/blob/master/www/install.sh) - Version-controlled installer implementation.
- [GitHub Releases](https://github.com/casey/just/releases) - Official release tags and downloadable artifacts.
- [Latest Release API Endpoint](https://api.github.com/repos/casey/just/releases/latest) - Machine-readable latest stable release metadata.
- [Release Workflow](https://github.com/casey/just/blob/master/.github/workflows/release.yaml) - Official packaging target matrix, checksum publication step, and Docker publishing flow.
- [Packaging Script](https://github.com/casey/just/blob/master/bin/package) - Defines archive contents and packaging behavior per target/OS.
- [Official Dockerfile](https://github.com/casey/just/blob/master/etc/Dockerfile) - Shows container image payload (`/just`) used for Docker-based installation patterns.
- [Available Dev Container Features Index](https://containers.dev/features) - Source for discovering existing just feature implementations for comparison.
- [guiyomh just Feature](https://github.com/guiyomh/features/tree/main/src/just) - Community feature using release download/version resolution helper patterns.
- [jsburckhardt just Feature](https://github.com/jsburckhardt/devcontainer-features/tree/main/src/just) - Community feature illustrating explicit fallback version strategy under API constraints.
- [schlich just Feature](https://github.com/schlich/devcontainer-features/tree/main/src/just) - Community feature using apt repository installation approach.
- [pirpedro just Feature](https://github.com/pirpedro/features/tree/main/src/just) - Community feature delegating install to official `just.systems/install.sh` with user-local destination options.
