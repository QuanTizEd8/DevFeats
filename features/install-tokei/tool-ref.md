# Feature Reference

Tokei is a fast command-line program written in Rust that displays statistics about source code: number of files, total lines, and counts of code, comments, and blank lines grouped by language. It supports over 150 languages and their extensions, respects `.gitignore` / `.ignore` / `.tokeignore` files, and can output human-readable terminal tables or machine-readable JSON, YAML, or CBOR.[^readme] It is commonly used for codebase metrics, CI reporting, and as a faster alternative to tools like `cloc`.[^readme]

The binary name is `tokei`. Official release tags use a `v` prefix (e.g., `v14.0.0`).[^release-1400] As of v14.0.0, GitHub releases no longer include prebuilt binary assets; the README still references the releases page for manual binary download, but v13.0.0 and v14.0.0 have zero assets.[^release-1400][^disc-1326] The last **stable** release with prebuilt binaries is **v12.1.2** (2021-01-12).[^release-1212] Prebuilt assets stopped appearing starting with **v13.0.0-alpha.1** (2024-03-04); the pre-release **v13.0.0-alpha.0** (2023-03-27) still has 21 assets but should not be treated as a production target.[^release-alpha0][^disc-1330]

- **Homepage**: https://github.com/XAMPPRocky/tokei (canonical); https://tokei.rs listed in `Cargo.toml` but was unreachable (502) as of 2026-06-18[^cargo-toml][^homepage-check]
- **Source Code**: https://github.com/XAMPPRocky/tokei
- **Documentation**: https://github.com/XAMPPRocky/tokei#readme (README), https://docs.rs/tokei (API/library docs)[^readme][^docs-rs]
- **Latest Release**: 14.0.0 (as of 2026-06-18)[^release-1400]

## Tool Architecture

Tokei is a **single, self-contained CLI binary** (`tokei`) written in Rust.[^readme] It is a standalone command-line tool with no client-server architecture, no daemons, and no external service dependencies at runtime.

The crate is both a **binary and a library** (`tokei` on crates.io).[^cargo-toml] The CLI binary is gated behind the `cli` Cargo feature, which is enabled by default.[^cargo-toml][^crates-1400] JSON output is always available (via non-optional `serde_json`). YAML and CBOR output require optional Cargo features (`yaml`, `cbor`, or `all`).[^cargo-toml][^input-rs][^readme]

**Build system**: Rust/Cargo. Minimum supported Rust version (MSRV) is **1.71**.[^cargo-toml][^crates-1400] Release builds in upstream CI use `cargo build --all-features --release` (via `ci/build.bash`).[^build-bash] Official GitHub release binaries (when published) are built with all features enabled, as confirmed by `tokei --version` output on v12.1.2: `compiled with serialization support: json, cbor, yaml`.[^verify-1212]

**Runtime requirements**: Prebuilt Linux `-unknown-linux-gnu` binaries are dynamically linked against glibc.[^release-1212] No JVM, Node.js, or Python runtime is required. The tool reads the filesystem locally; network access is not needed at runtime.

**Configuration at runtime** (not install-time): Tokei reads optional config files named `tokei.toml` or `.tokeirc` from three locations, in decreasing precedence: **current directory**, **home directory**, and **XDG config directory**. When the same setting appears in multiple files, current directory overrides home directory overrides XDG config (per-field merge in `Config::from_config_files()`).[^config][^example-toml]

**Shell completions**: Tokei does not ship shell completion scripts in its repository or release archives.[^readme]

## Installation Methods

Tokei offers eight principal installation routes relevant to a DevFeats feature:

1. **OS Package Manager** — distro-native lifecycle management; best option on distros that package current versions (Arch, Fedora, Debian sid, etc.). **Not available** on Ubuntu Noble (24.04) or Debian Bookworm (12) standard repos. Alpine stable branches may lag edge.
2. **Cargo Install (crates.io)** — builds from source; recommended fallback for Ubuntu Noble and other distros without packages; supports version pinning and feature selection.
3. **Prebuilt Binary Download (GitHub Releases)** — direct install when assets exist; **only viable for versions ≤ v12.1.2 stable**; latest upstream releases (v13+, v14) have no assets.
4. **Homebrew** — macOS and Linux; builds from source tarball or uses bottles; currently ships v14.0.0.
5. **Conda-forge** — cross-platform binary packages; currently ships v14.0.0.
6. **Build From Source** — full control via `cargo build`; useful for custom feature flags or when other methods are unavailable.
7. **Windows Package Manager (winget / Scoop)** — Windows-only; both still pin v12.1.2 due to missing v14 release binaries.
8. **Docker Image** — `ghcr.io/XAMPPRocky/tokei`; suitable for CI, not typical devcontainer PATH install.

Additional upstream-documented methods include Nix, FreeBSD `pkg`, NetBSD `pkgin`, Void `xbps`, OpenSUSE `zypper`, and MacPorts.[^readme] Chocolatey also distributes tokei (README badge) but is out of scope for typical DevFeats Linux/macOS devcontainer targets.[^readme]

### OS Package Manager

#### Supported Platforms

| Package manager | Distro / ecosystem | Package name | Upstream version (verified 2026-06-18) | Notes |
|-----------------|-------------------|--------------|----------------------------------------|-------|
| `apk` | Alpine Linux **edge** (community) | `tokei` | 14.0.0-r0[^alpine-edge] | Latest Alpine packaging |
| `apk` | Alpine Linux **v3.22** stable (community) | `tokei` | 12.1.2-r5[^alpine-v322] | Stable branches lag edge |
| `apk` | Alpine Linux ≥ 3.13 | `tokei` | varies by branch | README documents availability since 3.13[^readme] |
| `pacman` | Arch Linux (extra) | `tokei` | 14.0.0-1[^arch-pkg] | Rolling release |
| `dnf` / `yum` | Fedora 42–44, Rawhide | `tokei` | 14.0.0[^fedora-pkg] | Subpackage of `rust-tokei` |
| `dnf` / `yum` | EPEL 9, EPEL 10.2, EPEL 10.3 | `tokei` | 14.0.0[^fedora-pkg] | |
| `dnf` / `yum` | EPEL 10.1 | `tokei` | 13.0.0-2.el10_1[^fedora-pkg] | |
| `dnf` / `yum` | EPEL 8 | `tokei` | 12.1.2-1.el8[^fedora-pkg] | |
| `zypper` | openSUSE Factory | `tokei` | 14.0.0+git0[^opensuse-factory] | |
| `apt` | Debian sid/trixie/forky | `tokei` | 13.0.0-4[^debian-sid] | Source package: `rust-tokei` |
| `apt` | Ubuntu resolute (26.04) | `tokei` | 13.0.0-2[^ubuntu-resolute] | Not yet in Noble (24.04)[^ubuntu-noble] |
| `apt` | **Ubuntu Noble (24.04)** | — | **Not available**[^ubuntu-noble] | Confirmed gap motivating this feature |
| `apt` | **Debian Bookworm (12)** | — | **Not available**[^debian-bookworm] | |
| `pkg` | FreeBSD (ports) | `tokei` | 14.0.0[^freebsd-port] | Built with `CARGO_FEATURES=all` |
| `pkgin` | NetBSD (pkgsrc) | `tokei` | 14.0.0[^netbsd-pkg] | |
| `xbps-install` | Void Linux | `tokei` | available[^readme] | Version not independently verified |
| `nix-env` | Nix/NixOS | `tokei` | available[^readme] | Version not independently verified |
| `port` | macOS (MacPorts) | `tokei` | available[^readme] | Out of scope for typical DevFeats targets |
| `brew` | macOS, Linux (Homebrew) | `tokei` | 14.0.0[^brew-formula] | See Homebrew section for details |

DevFeats `install-os-pkg-bundle` already lists `tokei` in its `dev_tools` bundle with `when: {pm: [apk, brew, dnf, yum, zypper, pacman]}` — explicitly excluding `apt` because it is unavailable on Ubuntu ≤ 24.04 / Debian ≤ 12.[^devfeats-bundle]

#### Dependencies

##### Common Dependencies

- A working system package manager with configured repositories.
- Network access to package mirrors (unless using a pre-populated offline mirror).

##### Platform-Specific Dependencies

- Linux `apt`/`dnf`/`pacman`/`apk`/`zypper`/`xbps` installs generally require root/sudo.
- Debian/Ubuntu packages depend on `libc6` (≥ 2.39 on most arches)[^debian-sid] and `libgcc-s1`.

#### Installation Steps

Examples from upstream README and distro documentation:[^readme]

```bash
# Alpine Linux (since 3.13)
apk add tokei

# Arch Linux
pacman -S tokei

# Fedora
sudo dnf install tokei

# openSUSE
sudo zypper install tokei

# Void Linux
sudo xbps-install tokei

# FreeBSD
pkg install tokei

# NetBSD
pkgin install tokei

# Nix/NixOS
nix-env -i tokei

# Debian sid / Ubuntu resolute (when available)
sudo apt-get update
sudo apt-get install -y tokei
```

#### Installation Verification

```bash
command -v tokei
tokei --version
```

Expected `--version` output format (v12.1.2 example):[^verify-1212]

```
tokei 12.1.2 compiled with serialization support: json, cbor, yaml
Erin P. <xampprocky@gmail.com> + Contributors
Count your code, quickly.
```

Distro packages built with all features should report serialization support for json, cbor, and yaml. A default `cargo install` (without extra features) supports JSON only; YAML and CBOR require `--features all`.[^readme][^cargo-toml][^input-rs]

Package-manager verification examples:

```bash
# Debian/Ubuntu
dpkg -l tokei

# Fedora
dnf info tokei

# Arch
pacman -Qi tokei

# Alpine
apk info tokei
```

#### Configuration Options

##### Version Selection

- **apt**: `apt-get install tokei=13.0.0-4` (exact version depends on suite).
- **dnf**: version-qualified install when NEVRA is published (e.g., `dnf install tokei-14.0.0`).
- **pacman**, **apk**: rolling/latest in configured repos; no stable version pinning without downgrading.
- For strict cross-platform version pinning on distros without packages (e.g., Ubuntu Noble), use Cargo Install or Conda.

##### Installation Path

- Package-manager managed, typically `/usr/bin/tokei` on Linux.

##### User Targeting

- System-wide only for native Linux package managers (requires root/sudo).

##### Required Privileges

- Root/sudo required for system package manager installs on Linux.

##### Tool-Specific Configurations

- No install-time configuration options for OS package manager installs. Runtime config via `tokei.toml` / `.tokeirc` is optional and separate from installation.[^config]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Not required; package installs to standard system `PATH`.

##### Configuration Files

- None created at install time. Users may optionally create `tokei.toml` or `.tokeirc` later.[^config]

##### Environment Variables

- `NO_COLOR=1` disables colored terminal output at runtime (not an install-time setting).[^readme]

##### Activation Scripts

- None.

##### Shell Completions

- Not provided by upstream or distro packages.

##### Cleanup

- Remove via native package manager (`apt-get remove`, `dnf remove`, `pacman -R`, etc.).

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Use the native package manager upgrade command (`apt-get upgrade`, `dnf upgrade`, `pacman -Syu`, etc.).

##### Uninstallation

```bash
# Examples
sudo apt-get remove -y tokei
sudo dnf remove -y tokei
sudo pacman -R tokei
sudo apk del tokei
```

##### Idempotency

- Package manager reports "already installed" and skips or upgrades as appropriate.

#### Notes and Best Practices

- Ubuntu Noble (24.04) and Debian Bookworm (12) do **not** ship `tokei`; this is the primary gap this DevFeats feature addresses.[^ubuntu-noble][^debian-bookworm]
- Debian sid and Ubuntu resolute (26.04) ship v13.0.0, which lags upstream v14.0.0.[^debian-sid][^ubuntu-resolute]
- Fedora 42+, Arch, and Alpine **edge** ship v14.0.0. Alpine **stable** branches (e.g., v3.22) may ship older versions (12.1.2-r5).[^fedora-pkg][^arch-pkg][^alpine-edge][^alpine-v322]
- EPEL versions vary: EPEL 8 is on 12.1.2, EPEL 10.1 on 13.0.0, EPEL 9/10.2+ on 14.0.0.[^fedora-pkg]

### Cargo Install (crates.io)

#### Supported Platforms

All platforms with a Rust toolchain meeting MSRV 1.71+:[^cargo-toml][^crates-1400]

- macOS (x86_64, arm64)
- Linux (all major distros, glibc and musl via rustup targets)
- Windows (MSVC toolchain)
- BSD and other platforms supported by Rust

#### Dependencies

##### Common Dependencies

- **Rust toolchain** (stable recommended): `rustc` and `cargo` ≥ 1.71.[^cargo-toml]
- C linker and build tools for compiling native dependencies (`gcc`/`g++`/`build-essential` on Debian/Ubuntu, `build-base` on Alpine).
- Network access to crates.io and GitHub (for crate source and dependency fetching).

##### Platform-Specific Dependencies

- Linux: `pkg-config`, `gcc`, `g++` (or equivalent).
- macOS: Xcode Command Line Tools.
- Windows: MSVC Build Tools or Visual Studio with C++ workload.

#### Installation Steps

Basic install (CLI with JSON output; **no** YAML/CBOR):[^readme][^cargo-toml][^input-rs]

```bash
cargo install tokei --locked
```

Recommended install with all serialization formats (matches official release builds):[^readme][^build-bash]

```bash
cargo install tokei --locked --features all
```

Install a specific version:

```bash
cargo install tokei --version 14.0.0 --locked --features all
```

Install from git (latest master):[^readme]

```bash
cargo install --git https://github.com/XAMPPRocky/tokei.git tokei --locked --features all
```

User-local install (default, no sudo):

```bash
cargo install tokei --locked --features all
# Binary installed to ~/.cargo/bin/tokei
```

System-wide install to a custom root:

```bash
cargo install tokei --locked --features all --root /usr/local
# Binary at /usr/local/bin/tokei
```

#### Installation Verification

```bash
command -v tokei
tokei --version
tokei --help
```

Verify JSON output (available with default features):

```bash
tokei --output json . 2>&1 | head -1
# Should produce JSON
```

Verify full serialization support (requires `--features all`):

```bash
tokei --version
# Should report: compiled with serialization support: json, cbor, yaml
```

#### Configuration Options

##### Version Selection

- `cargo install tokei --version X.Y.Z` pins to a specific crates.io release.[^crates-1400]
- `cargo install --git URL --tag vX.Y.Z tokei` pins to a git tag.

##### Installation Path

- Default: `$HOME/.cargo/bin/tokei`.
- `--root <DIR>` installs to `<DIR>/bin/tokei`.

##### User Targeting

- Default is user-local (no sudo).
- System-wide via `--root /usr/local` requires write permission to that directory (typically sudo).

##### Required Privileges

- User-local: none beyond write access to `$HOME/.cargo`.
- System-wide: root/sudo for `/usr/local` or similar paths.

##### Tool-Specific Configurations

Cargo feature flags (from `Cargo.toml`):[^cargo-toml][^crates-1400]

| Feature | Default | Effect |
|---------|---------|--------|
| `cli` | yes | Enables the `tokei` binary (clap, colored output, env_logger, num-format) |
| `cbor` | no | Enables CBOR output (`--output cbor`) |
| `yaml` | no | Enables YAML output (`--output yaml`) |
| `all` | no | Enables both `cbor` and `yaml` features |

JSON output (`--output json`) is available with the default `cli` feature (via `serde_json`, always a dependency).[^cargo-toml] CBOR and YAML require explicit feature enablement.[^readme]

Install command for specific feature sets:

```bash
cargo install tokei --locked --features yaml     # YAML only (plus cli)
cargo install tokei --locked --features cbor     # CBOR only (plus cli)
cargo install tokei --locked --features all      # All formats
```

Release profile uses thin LTO and `panic = "abort"`.[^cargo-toml]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure `$HOME/.cargo/bin` is on `PATH`:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

For persistent setup, add the export to `~/.bashrc`, `~/.zshrc`, or the devcontainer feature's profile hook.

##### Configuration Files

- None created at install time.

##### Environment Variables

- None required at install time.

##### Activation Scripts

- None (unlike rustup-based workflows, `cargo install` does not require sourcing).

##### Shell Completions

- Not provided.

##### Cleanup

```bash
cargo uninstall tokei
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
cargo install tokei --version NEW_VERSION --locked --features all --force
```

The `--force` flag overwrites the existing installation.

##### Uninstallation

```bash
cargo uninstall tokei
```

##### Idempotency

- `cargo install` without `--force` errors if the package is already installed; use `--force` to overwrite.

#### Notes and Best Practices

- **Recommended for Ubuntu Noble**: Since `apt` does not provide `tokei`, `cargo install` is the most reliable way to get v14.0.0.[^ubuntu-noble]
- Always pass `--locked` to respect `Cargo.lock` dependency versions.
- Pass `--features all` if YAML or CBOR output is needed; JSON works without it.[^readme][^input-rs]
- Build time is significant (several minutes on modest hardware); plan for this in devcontainer builds.
- Requires Rust toolchain as a dependency — consider depending on an `install-rust` feature or ensuring rustup/cargo is pre-installed.

### Prebuilt Binary Download (GitHub Releases)

#### Supported Platforms

**Critical limitation**: Prebuilt binaries are **not published** for v13.0.0, v14.0.0, or any release since v13.0.0-alpha.1 (2024-03-04).[^release-1300][^release-1400][^disc-1326] The last **stable** release with assets is **v12.1.2** (2021-01-12).[^release-1212] The pre-release **v13.0.0-alpha.0** (2023-03-27) has 21 assets with the same naming convention, but is not a stable production target.[^release-alpha0]

Assets published for **v12.1.2** (23 files):[^release-1212]

| OS | Architecture | Rust target triple | Asset filename |
|----|-------------|-------------------|---------------|
| Linux | x86_64 (glibc) | `x86_64-unknown-linux-gnu` | `tokei-x86_64-unknown-linux-gnu.tar.gz` |
| Linux | x86_64 (musl) | `x86_64-unknown-linux-musl` | `tokei-x86_64-unknown-linux-musl.tar.gz` |
| Linux | arm64 (glibc) | `aarch64-unknown-linux-gnu` | `tokei-aarch64-unknown-linux-gnu.tar.gz` |
| Linux | armv7 (glibc) | `armv7-unknown-linux-gnueabihf` | `tokei-armv7-unknown-linux-gnueabihf.tar.gz` |
| Linux | arm (glibc) | `arm-unknown-linux-gnueabi` | `tokei-arm-unknown-linux-gnueabi.tar.gz` |
| Linux | i686 (glibc) | `i686-unknown-linux-gnu` | `tokei-i686-unknown-linux-gnu.tar.gz` |
| Linux | i686 (musl) | `i686-unknown-linux-musl` | `tokei-i686-unknown-linux-musl.tar.gz` |
| Linux | s390x | `s390x-unknown-linux-gnu` | `tokei-s390x-unknown-linux-gnu.tar.gz` |
| Linux | ppc64le | `powerpc64le-unknown-linux-gnu` | `tokei-powerpc64le-unknown-linux-gnu.tar.gz` |
| Linux | mips (BE/LE, 32/64) | various | `tokei-mips*.tar.gz` |
| Linux | Solaris | `sparcv9-sun-solaris` | `tokei-sparcv9-sun-solaris.tar.gz` |
| Linux | NetBSD | `x86_64-unknown-netbsd` | `tokei-x86_64-unknown-netbsd.tar.gz` |
| Linux | Android | various | `tokei-*-linux-android.tar.gz` |
| macOS | x86_64 (Intel) | `x86_64-apple-darwin` | `tokei-x86_64-apple-darwin.tar.gz` |
| Windows | x86_64 (MSVC) | `x86_64-pc-windows-msvc` | `tokei-x86_64-pc-windows-msvc.exe` |
| Windows | i686 (MSVC) | `i686-pc-windows-msvc` | `tokei-i686-pc-windows-msvc.exe` |

**Notable absences in v12.1.2:**

- **No** `aarch64-apple-darwin` (Apple Silicon macOS) binary. Apple Silicon Macs must use Homebrew, cargo, or Rosetta with the x86_64 binary.
- **No** `aarch64-unknown-linux-musl` binary.

**Archive structure**: Linux/macOS `.tar.gz` archives contain a **single bare `tokei` binary at the archive root** (no wrapper directory).[^verify-tarball] Windows assets are bare `.exe` files.

**Checksums/signatures**: No SHA256 checksum files or GPG signatures are published alongside release assets.[^release-1212]

#### Dependencies

##### Common Dependencies

- `curl` or `wget` to download.
- `tar` to extract `.tar.gz` archives.

##### Platform-Specific Dependencies

- Root/sudo only when installing to system paths (e.g., `/usr/local/bin`).
- Linux `-unknown-linux-gnu` binaries require glibc (not suitable for pure musl/Alpine without glibc compatibility layer); use `-unknown-linux-musl` on Alpine.

#### Installation Steps

Release tags use a **`v` prefix**. The tag for version 12.1.2 is `v12.1.2`.[^release-1212]

URL pattern: `https://github.com/XAMPPRocky/tokei/releases/download/v{version}/{filename}`

Example — Linux x86_64 (glibc), system-wide install:

```bash
set -e
VERSION="12.1.2"
TARGET="x86_64-unknown-linux-gnu"
ASSET="tokei-${TARGET}.tar.gz"
BASE_URL="https://github.com/XAMPPRocky/tokei/releases/download/v${VERSION}"

curl -fsSL -o "${ASSET}" "${BASE_URL}/${ASSET}"
tar --no-same-owner -xzf "${ASSET}" tokei
sudo install -m 0755 tokei /usr/local/bin/tokei
rm -f "${ASSET}" tokei
```

Example — Linux x86_64 (musl, for Alpine or static-like portability):

```bash
set -e
VERSION="12.1.2"
TARGET="x86_64-unknown-linux-musl"
ASSET="tokei-${TARGET}.tar.gz"
BASE_URL="https://github.com/XAMPPRocky/tokei/releases/download/v${VERSION}"

curl -fsSL -o "${ASSET}" "${BASE_URL}/${ASSET}"
tar --no-same-owner -xzf "${ASSET}" tokei
sudo install -m 0755 tokei /usr/local/bin/tokei
rm -f "${ASSET}" tokei
```

Example — Windows x86_64 (MSVC), user-local install:

```powershell
$Version = "12.1.2"
$Target = "x86_64-pc-windows-msvc"
$Asset = "tokei-$Target.exe"
$BaseUrl = "https://github.com/XAMPPRocky/tokei/releases/download/v$Version"
Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile "$env:LOCALAPPDATA\tokei\tokei.exe"
# Add $env:LOCALAPPDATA\tokei to PATH
```

#### Installation Verification

```bash
tokei --version
# Expected: tokei 12.1.2 compiled with serialization support: json, cbor, yaml
```

No official checksum verification is available. Third-party package managers (Scoop, winget) publish their own SHA256 hashes for v12.1.2 Windows binaries.[^scoop-json][^winget-1212]

#### Configuration Options

##### Version Selection

- Set `VERSION` in the download URL. Only versions with published assets are installable; as of 2026-06-18, the newest installable stable version via this method is **12.1.2**.

##### Installation Path

- Any writable directory on `PATH` (e.g., `/usr/local/bin`, `~/.local/bin`, `$HOME/.cargo/bin`).

##### User Targeting

- User-local: install to `~/.local/bin` without sudo.
- System-wide: install to `/usr/local/bin` with sudo.

##### Required Privileges

- User-local: none.
- System-wide: root/sudo.

##### Tool-Specific Configurations

- None at install time. Official release binaries are built with `--all-features`.[^build-bash][^verify-1212]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure the install directory is on `PATH`.

##### Configuration Files

- None at install time.

##### Environment Variables

- None required.

##### Activation Scripts

- None.

##### Shell Completions

- Not provided.

##### Cleanup

- Remove the installed binary and any downloaded archive files.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Download and overwrite the binary. No built-in upgrade mechanism.

##### Uninstallation

```bash
sudo rm -f /usr/local/bin/tokei
# or
rm -f ~/.local/bin/tokei
```

##### Idempotency

- Overwrites existing binary if re-run with same target path.

#### Details

Upstream CI for building release artifacts is defined in `.github/workflows/mean_bean_deploy.yml`.[^deploy-yml] It triggers on completion of the `Release-plz` workflow, cross-compiles for a large matrix of targets using `cross`, and uploads `tokei-{target}.tar.gz` or `.exe` files.[^deploy-yml] However, since the project switched to `release-plz` for releases (v13+), this deploy workflow has not successfully attached assets to releases.[^release-plz][^disc-1330][^pr-1333] A community PR (#1333) to restore artifact publishing was closed by the maintainer, who stated existing CI should handle it.[^pr-1333]

Asset naming changed between eras:
- **v10.x and earlier**: `tokei-v{version}-{target}.tar.gz`
- **v11.x–v12.x**: `tokei-{target}.tar.gz` (no version in filename)

#### Notes and Best Practices

- **Not recommended for latest version**: Binary download cannot install v14.0.0. Use Cargo Install or OS packages instead.
- If binary download is used, prefer **v12.1.2** assets only when an old version is acceptable, or monitor upstream for restored artifact publishing.
- For Ubuntu Noble devcontainers, binary download of v12.1.2 is a fallback but installs a version **3 major releases behind** upstream.
- Scoop and winget still reference v12.1.2 GitHub release URLs and will not auto-update until upstream publishes new Windows binaries.[^scoop-json][^winget-issue]

### Homebrew

#### Supported Platforms

- macOS (Apple Silicon and Intel) — bottles for arm64 and x86_64.[^brew-formula]
- Linux (arm64 and x86_64) — bottles available.[^brew-formula]

#### Dependencies

##### Common Dependencies

- Homebrew installed and configured.

##### Platform-Specific Dependencies

- When building from source (no bottle): Rust toolchain (`rust` build dependency).[^brew-formula]

#### Installation Steps

```bash
brew install tokei
```

#### Installation Verification

```bash
command -v tokei
tokei --version
brew info tokei
```

#### Configuration Options

##### Version Selection

- Default: latest stable in formula (14.0.0).[^brew-formula]
- `brew install tokei --HEAD` installs from git master.

##### Installation Path

- `$(brew --prefix)/bin/tokei` (typically `/opt/homebrew/bin/tokei` on Apple Silicon, `/usr/local/bin/tokei` on Intel macOS).

##### User Targeting

- User-local within Homebrew prefix; no sudo on default macOS/Linux Homebrew installs.

##### Required Privileges

- None on default Homebrew setup.

##### Tool-Specific Configurations

- None at install time. Homebrew builds from the v14.0.0 source tarball with `--features all` (standard Rust formula behavior).

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure `brew shellenv` is evaluated in shell profile if `tokei` is not found.

##### Configuration Files

- None at install time.

##### Environment Variables

- None required.

##### Activation Scripts

- None.

##### Shell Completions

- Not provided.

##### Cleanup

```bash
brew uninstall tokei
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
brew upgrade tokei
```

##### Uninstallation

```bash
brew uninstall tokei
```

##### Idempotency

- `brew install` on an already-installed formula reports it is installed.

#### Notes and Best Practices

- Homebrew is the recommended macOS install path per upstream README.[^readme]
- On Linux devcontainers with Homebrew, `brew install tokei` provides v14.0.0 without needing Rust, via prebuilt bottles.[^brew-formula]
- Useful as a secondary method in DevFeats when `install-brew` is already a dependency.

### Conda-forge

#### Supported Platforms

Conda-forge packages verified for v14.0.0:[^conda-forge]

| Platform | Package |
|----------|---------|
| linux-64 | `tokei-14.0.0-hdab8a38_0.conda` |
| linux-aarch64 | `tokei-14.0.0-h1ebd7d5_0.conda` |
| linux-ppc64le | `tokei-14.0.0-h0de4f61_0.conda` |
| osx-64 | `tokei-14.0.0-ha35cfd3_0.conda` |
| osx-arm64 | `tokei-14.0.0-h748bcf4_0.conda` |
| win-64 | `tokei-14.0.0-h77a83cd_0.conda` |

#### Dependencies

##### Common Dependencies

- Conda or Mamba/micromamba installed.

##### Platform-Specific Dependencies

- None beyond conda itself.

#### Installation Steps

```bash
conda install -c conda-forge tokei
```

With explicit version:

```bash
conda install -c conda-forge tokei=14.0.0
```

#### Installation Verification

```bash
command -v tokei
tokei --version
conda list tokei
```

#### Configuration Options

##### Version Selection

- `conda install tokei=14.0.0` or `conda install tokei=12.1.2` for older versions.

##### Installation Path

- Conda environment's `bin/` directory (e.g., `$CONDA_PREFIX/bin/tokei`).

##### User Targeting

- User-local within the active conda environment; no root required.

##### Required Privileges

- None (user-local in conda env).

##### Tool-Specific Configurations

- None at install time.

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Activate the conda environment (`conda activate <env>`) so `tokei` is on `PATH`.

##### Configuration Files

- None at install time.

##### Environment Variables

- None required.

##### Activation Scripts

- Standard conda environment activation.

##### Shell Completions

- Not provided.

##### Cleanup

```bash
conda remove tokei
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
conda update tokei
# or
conda install tokei=NEW_VERSION
```

##### Uninstallation

```bash
conda remove tokei
```

##### Idempotency

- Conda skips or upgrades as appropriate.

#### Notes and Best Practices

- Useful when a DevFeats environment already has conda/mamba (e.g., via `install-miniforge` or `install-pixi`).
- Provides v14.0.0 on platforms where apt does not.[^conda-forge]

### Build From Source

#### Supported Platforms

Any platform with Rust ≥ 1.71 and a C toolchain.[^cargo-toml]

#### Dependencies

##### Common Dependencies

- Rust stable toolchain (≥ 1.71).
- C compiler and linker.
- `git` (for git-based checkout).

##### Platform-Specific Dependencies

- Same as Cargo Install.

#### Installation Steps

From a release tag:

```bash
git clone https://github.com/XAMPPRocky/tokei.git
cd tokei
git checkout v14.0.0
cargo build --release --all-features
sudo install -m 0755 target/release/tokei /usr/local/bin/tokei
```

Cross-compilation (as upstream CI does) uses the `cross` tool with targets defined in `mean_bean_deploy.yml`.[^deploy-yml]

#### Installation Verification

```bash
tokei --version
```

#### Configuration Options

##### Version Selection

- Checkout the desired git tag (e.g., `v14.0.0`).

##### Installation Path

- `target/release/tokei` in the build tree; copy to desired location.

##### User Targeting

- User-local or system-wide depending on install destination.

##### Required Privileges

- Root/sudo only for system-wide install paths.

##### Tool-Specific Configurations

- `--all-features` enables all serialization formats (recommended, matches upstream release builds).[^build-bash]
- Individual features: `--features yaml`, `--features cbor`, `--no-default-features` (disables CLI binary).

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Add install directory to `PATH`.

##### Configuration Files

- None.

##### Environment Variables

- None.

##### Activation Scripts

- None.

##### Shell Completions

- Not provided.

##### Cleanup

- Remove build tree; `cargo clean` in source directory.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Rebuild from new tag and overwrite binary.

##### Uninstallation

- Remove installed binary and source tree.

##### Idempotency

- Rebuilding overwrites `target/release/tokei`.

#### Notes and Best Practices

- Functionally equivalent to `cargo install` but provides more control over the build environment.
- Docker image build uses `Earthfile` with `cargo build --release` **without** `--all-features` (Alpine/musl context).[^earthfile] YAML and CBOR output will not work in the Docker image; JSON still works via default `cli` feature.

### Windows Package Manager (winget / Scoop)

#### Supported Platforms

- Windows x86_64 and i686 only.

#### Dependencies

##### Common Dependencies

- `winget` (App Installer) or Scoop installed and configured.
- Network access to GitHub releases (both download v12.1.2 binaries directly).

##### Platform-Specific Dependencies

- None beyond the package manager itself.

#### Installation Steps

**winget** (upstream README):[^readme]

```powershell
winget install XAMPPRocky.tokei
```

**Scoop** (upstream README):[^readme]

```powershell
scoop install tokei
```

Both package manifests download from GitHub release **v12.1.2** because no newer release binaries exist.[^scoop-json][^winget-1212][^winget-issue]

#### Installation Verification

```powershell
tokei --version
# Expected: tokei 12.1.2 compiled with serialization support: json, cbor, yaml
```

#### Configuration Options

##### Version Selection

- Neither winget nor Scoop can install v14.0.0 until upstream publishes new release binaries.[^winget-issue] Scoop's `checkver` regex matches GitHub release asset URLs and will fail to update when assets are absent.

##### Installation Path

- winget: portable install location managed by winget.
- Scoop: `~/scoop/apps/tokei/current/tokei.exe` with shim in `~/scoop/shims`.

##### User Targeting

- User-local; no admin required (Scoop always; winget depending on scope).

##### Required Privileges

- User-level install by default.

##### Tool-Specific Configurations

- Scoop creates an empty `tokei.toml` in the persist directory on first install.[^scoop-json] This is Scoop-specific behavior, not upstream.

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Scoop shims and winget portable paths must be on `PATH` (usually automatic).

##### Configuration Files

- Scoop may create an empty `tokei.toml` for persistence.[^scoop-json]

##### Environment Variables

- None required.

##### Activation Scripts

- None.

##### Shell Completions

- Not provided.

##### Cleanup

```powershell
winget uninstall XAMPPRocky.tokei
scoop uninstall tokei
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Blocked at v12.1.2 until upstream restores GitHub release binaries.[^winget-issue]

##### Uninstallation

- Use the native package manager uninstall command.

##### Idempotency

- Package manager handles re-install/upgrade idempotently.

#### Notes and Best Practices

- Not recommended for DevFeats devcontainer features (Windows-only, pinned to outdated v12.1.2).
- Documented here for completeness because upstream README lists these as primary Windows install methods.[^readme]

### Docker Image

#### Supported Platforms

- Linux containers via Docker or compatible runtimes (image is Alpine-based).[^earthfile][^publish-image]

#### Dependencies

##### Common Dependencies

- Docker or a compatible container runtime.

##### Platform-Specific Dependencies

- None beyond container runtime.

#### Installation Steps

The image is published to `ghcr.io/XAMPPRocky/tokei` on tag push and as `latest` on master branch pushes.[^publish-image] It is not installed into the host PATH; it is invoked via `docker run`:

```bash
docker run --rm -v "$(pwd):/src" ghcr.io/XAMPPRocky/tokei .
```

Build locally with Earthly:[^earthfile][^readme]

```bash
earthly +docker
docker run --rm -v "$(pwd):/src" tokei .
```

#### Installation Verification

```bash
docker run --rm ghcr.io/XAMPPRocky/tokei --version
```

#### Configuration Options

##### Version Selection

- Pull by tag (e.g., `ghcr.io/XAMPPRocky/tokei:v14.0.0`) or `latest`.

##### Installation Path

- N/A (containerized execution).

##### User Targeting

- N/A.

##### Required Privileges

- Docker daemon access.

##### Tool-Specific Configurations

- None at pull/run time. The image is built with `cargo build --release` **without** `--all-features`, so JSON output works but YAML and CBOR do not.[^earthfile]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Not applicable; invoke via `docker run`.

##### Configuration Files

- Mount project directories with `-v` to analyze local code.

##### Environment Variables

- None required.

##### Activation Scripts

- None.

##### Shell Completions

- Not provided.

##### Cleanup

```bash
docker rmi ghcr.io/XAMPPRocky/tokei
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Pull a new tag: `docker pull ghcr.io/XAMPPRocky/tokei:v14.0.0`

##### Uninstallation

- Remove local image copies with `docker rmi`.

##### Idempotency

- `docker pull` is idempotent for the same tag digest.

#### Notes and Best Practices

- Suitable for CI code counting, not for installing `tokei` into a devcontainer's `PATH`.
- For devcontainers needing `tokei` on PATH, prefer cargo, brew, or OS package manager methods.

## Dev Container Setup

**Ubuntu Noble (24.04) devcontainers** — the typical DevFeats development base — do not have `tokei` in apt.[^ubuntu-noble] Recommended install methods for devcontainers:

1. **Cargo install** (if Rust is already present or installed by another feature):
   ```bash
   cargo install tokei --locked --features all
   ```
2. **Homebrew** (if `install-brew` is used):
   ```bash
   brew install tokei
   ```
3. **Conda** (if miniforge/pixi is present):
   ```bash
   conda install -c conda-forge tokei
   ```

**Docker image** (see Docker Image section above): `ghcr.io/XAMPPRocky/tokei` can be used for CI counting but not typically for PATH install in devcontainers.

**Feature design considerations**:

- No root required for user-local `cargo install` (default `~/.cargo/bin`).
- `cargo install` build time is non-trivial; consider caching `$CARGO_HOME`/`~/.cargo/registry` in devcontainer layers.
- If using binary download, only v12.1.2 is available — strongly prefer cargo or brew for current versions.
- The `install-os-pkg-bundle` `dev_tools` bundle already conditionally installs via OS PM on apk/brew/dnf/yum/zypper/pacman but skips apt.[^devfeats-bundle]
- No install-time configuration files need to be created; runtime `tokei.toml` is optional.

**No existing official devcontainer feature** for tokei was found in [devcontainers/features](https://github.com/devcontainers/features), [devcontainers-extra/features](https://github.com/devcontainers-extra/features), or [devcontainer-community/devcontainer-features](https://github.com/devcontainer-community/devcontainer-features). Installation in devcontainers is typically done via Dockerfile `RUN cargo install tokei` or package manager commands.

## Plugins and Extensions

Tokei has no plugin or extension system. Related third-party tools:

- **tokei-pie** (https://github.com/laixintao/tokei-pie): Renders tokei JSON output as an interactive sunburst chart.[^readme] Separate install; not part of this feature.

## References

[^readme]: [GitHub — tokei README](https://github.com/XAMPPRocky/tokei/blob/master/README.md) — Tool description, installation methods (package managers, cargo, manual download), configuration, CLI options, supported languages, and platform availability.

[^cargo-toml]: [GitHub — tokei Cargo.toml](https://github.com/XAMPPRocky/tokei/blob/master/Cargo.toml) — Crate metadata, MSRV (1.71), feature flags (`cli`, `cbor`, `yaml`, `all`), release profile, binary definition.

[^crates-1400]: [crates.io — tokei 14.0.0](https://crates.io/crates/tokei/14.0.0) — Published version, feature list, MSRV, checksum.

[^docs-rs]: [docs.rs — tokei](https://docs.rs/tokei/) — Library API documentation.

[^config]: [GitHub — tokei src/config.rs](https://github.com/XAMPPRocky/tokei/blob/master/src/config.rs) — Config file discovery (`tokei.toml`, `.tokeirc`), search paths (XDG config, home, current dir), and config fields.

[^example-toml]: [GitHub — tokei tokei.example.toml](https://github.com/XAMPPRocky/tokei/blob/master/tokei.example.toml) — Example runtime configuration file.

[^build-bash]: [GitHub — tokei ci/build.bash](https://github.com/XAMPPRocky/tokei/blob/master/ci/build.bash) — Release build command: `cargo build --all-features --release`.

[^deploy-yml]: [GitHub — tokei .github/workflows/mean_bean_deploy.yml](https://github.com/XAMPPRocky/tokei/blob/master/.github/workflows/mean_bean_deploy.yml) — Cross-compilation matrix, asset naming (`tokei-{target}.tar.gz`), trigger on Release-plz completion.

[^release-plz]: [GitHub — tokei .github/workflows/release-plz.yaml](https://github.com/XAMPPRocky/tokei/blob/master/.github/workflows/release-plz.yaml) — Current release automation (crates.io + GitHub release without artifacts).

[^publish-image]: [GitHub — tokei .github/workflows/publish_image.yaml](https://github.com/XAMPPRocky/tokei/blob/master/.github/workflows/publish_image.yaml) — Docker image publish to `ghcr.io/XAMPPRocky/tokei`.

[^earthfile]: [GitHub — tokei Earthfile](https://github.com/XAMPPRocky/tokei/blob/master/Earthfile) — Alpine-based Docker build via `cargo build --release`.

[^release-1400]: [GitHub — tokei v14.0.0 release](https://github.com/XAMPPRocky/tokei/releases/tag/v14.0.0) — Latest release; zero binary assets.

[^release-1300]: [GitHub — tokei v13.0.0 release](https://github.com/XAMPPRocky/tokei/releases/tag/v13.0.0) — First stable v13 release; zero binary assets.

[^release-1212]: [GitHub — tokei v12.1.2 release](https://github.com/XAMPPRocky/tokei/releases/tag/v12.1.2) — Last stable release with 23 prebuilt binary assets; published 2021-01-12.

[^disc-1326]: [GitHub Discussion #1326 — Missing prebuilt binaries](https://github.com/XAMPPRocky/tokei/discussions/1326) — Community report that v13 and v14 lack prebuilt binaries.

[^disc-1330]: [GitHub Discussion #1330 — Add prebuild artifacts](https://github.com/XAMPPRocky/tokei/discussions/1330) — Poll and discussion requesting restoration of release artifacts; notes impact on Chocolatey and winget.

[^pr-1333]: [GitHub PR #1333 — release_artifacts workflow](https://github.com/XAMPPRocky/tokei/pull/1333) — Closed PR to restore artifact publishing; maintainer noted existing CI should handle it.

[^verify-1212]: Empirical verification — `tokei --version` on v12.1.2 `x86_64-unknown-linux-gnu` binary downloaded from GitHub releases (2026-06-18).

[^verify-tarball]: Empirical verification — `tar -tzf tokei-x86_64-unknown-linux-gnu.tar.gz` lists single file `tokei` at archive root (2026-06-18).

[^ubuntu-noble]: [Ubuntu Packages — noble/tokei](https://packages.ubuntu.com/noble/tokei) — "Package not available in this suite."

[^debian-bookworm]: [Debian Packages — bookworm/tokei](https://packages.debian.org/bookworm/tokei) — "Package not available in this suite."

[^debian-sid]: [Debian Packages — sid/tokei](https://packages.debian.org/sid/tokei) — Version 13.0.0-4 in sid/unstable.

[^ubuntu-resolute]: [Ubuntu Packages — resolute/tokei](https://packages.ubuntu.com/resolute/tokei) — Version 13.0.0-2 in Ubuntu 26.04 resolute.

[^fedora-pkg]: [Fedora Packages — tokei](https://packages.fedoraproject.org/pkgs/rust-tokei/tokei/) — Version 14.0.0 on Fedora 42–44, Rawhide, EPEL 9, EPEL 10.2/10.3; 13.0.0 on EPEL 10.1; 12.1.2 on EPEL 8.

[^arch-pkg]: [Arch Linux — tokei 14.0.0-1](https://archlinux.org/packages/extra/x86_64/tokei/) — Extra repository package.

[^alpine-edge]: [Alpine Linux — tokei 14.0.0-r0 (edge/community)](https://pkgs.alpinelinux.org/package/edge/community/x86_64/tokei) — edge/community repository.

[^alpine-v322]: [Alpine Linux — tokei 12.1.2-r5 (v3.22/community)](https://pkgs.alpinelinux.org/package/v3.22/community/x86_64/tokei) — stable v3.22 branch.

[^opensuse-factory]: [openSUSE — pool/tokei](https://src.opensuse.org/pool/tokei) — Factory package updated to 14.0.0+git0 (2026-05-05).

[^freebsd-port]: [FreeBSD ports — devel/tokei Makefile](https://cgit.freebsd.org/ports/plain/devel/tokei/Makefile) — Version 14.0.0, `CARGO_FEATURES=all`.

[^netbsd-pkg]: [NetBSD pkgsrc — devel/tokei](http://ftp3.us.freebsd.org/pub/NetBSD/NetBSD-current/pkgsrc/devel/tokei/index.html) — tokei-14.0.0 binary packages.

[^release-alpha0]: [GitHub — tokei v13.0.0-alpha.0 release](https://github.com/XAMPPRocky/tokei/releases/tag/v13.0.0-alpha.0) — Pre-release with 21 prebuilt binary assets (2023-03-27).

[^homepage-check]: Empirical verification — `https://tokei.rs` returned HTTP 502 when fetched (2026-06-18); v14.0.0 changelog notes removal of tokei.rs references.

[^brew-formula]: [Homebrew Formulae — tokei](https://formulae.brew.sh/formula/tokei) — Version 14.0.0, bottle support for macOS and Linux.

[^conda-forge]: [Anaconda — conda-forge/tokei files](https://anaconda.org/conda-forge/tokei/files) — v14.0.0 packages for linux-64, linux-aarch64, osx-64, osx-arm64, win-64, linux-ppc64le.

[^scoop-json]: [Scoop — tokei.json](https://github.com/ScoopInstaller/Main/blob/master/bucket/tokei.json) — v12.1.2, downloads from GitHub releases, SHA256 hashes.

[^winget-1212]: [winget-pkgs — XAMPPRocky.Tokei 12.1.2 manifest](https://github.com/microsoft/winget-pkgs/tree/master/manifests/x/XAMPPRocky/Tokei/12.1.2) — Portable v12.1.2; downloads from GitHub releases.

[^input-rs]: [GitHub — tokei src/input.rs](https://github.com/XAMPPRocky/tokei/blob/master/src/input.rs) — `Format::Json` is unconditional; YAML/CBOR gated by Cargo features.

[^winget-issue]: [winget-pkgs Issue #336794](https://github.com/microsoft/winget-pkgs/issues/336794) — Update request blocked because v14.0.0 has no precompiled assets.

[^devfeats-bundle]: DevFeats workspace — `features/install-os-pkg-bundle/metadata.yaml` (line 549) — `dev_tools` bundle lists tokei with apt exclusion via `when: {pm: [apk, brew, dnf, yum, zypper, pacman]}`.
