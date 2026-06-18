# Feature Reference

ripgrep (`rg`) is a line-oriented search tool written in Rust that recursively searches the current directory for a regex pattern. By default, it respects `.gitignore` rules and automatically skips hidden files/directories and binary files. It is designed as a fast, user-friendly alternative to tools like grep, ack, and The Silver Searcher, with first-class support on Windows, macOS, and Linux.[^readme] Pre-built release binaries are statically linked on Linux and Windows, making them straightforward to install without runtime dependencies.[^readme]

The binary name is `rg`. Official releases are published on GitHub with per-asset SHA256 checksum files; GPG/PGP signatures are not provided.[^release-1510] Release tags use a plain semver format without a `v` prefix (e.g., `15.1.0`).[^release-workflow]

- **Homepage**: https://github.com/BurntSushi/ripgrep
- **Source Code**: https://github.com/BurntSushi/ripgrep
- **Documentation**: https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md (User Guide), https://github.com/BurntSushi/ripgrep/blob/master/FAQ.md (FAQ)
- **Latest Release**: 15.1.0 (as of 2026-06-18)[^release-latest]

## Tool Architecture

ripgrep is a **single, self-contained binary** (`rg`) written in Rust. The official pre-built Linux and Windows release binaries are static executables with no runtime library dependencies.[^readme] macOS release binaries are also distributed as standalone executables inside the release archives.

The project is organized as a Cargo workspace. The main binary is built from `crates/core/main.rs` and named `rg`.[^cargo-toml] The workspace includes internal crates for glob matching (`globset`), regex/search (`grep`, `regex`, `searcher`), directory traversal with gitignore support (`ignore`), CLI parsing (`cli`), and output formatting (`printer`).[^cargo-toml]

**Runtime requirements**: None beyond a compatible operating system kernel. No JVM, Node.js, Python, or other runtime is needed when using pre-built binaries.

**Optional compile-time feature — PCRE2**: ripgrep supports an optional `pcre2` Cargo feature that enables look-around, backreferences, and other PCRE2-only regex syntax via `-P/--pcre2` or `--engine pcre2`.[^readme][^faq-pcre2] All official GitHub release binaries are built with `PCRE2_SYS_STATIC=1` and the `pcre2` feature enabled.[^release-workflow] Builds without PCRE2 report `PCRE2 is not available in this build of ripgrep` when `-P` is used.[^faq-pcre2]

**Build system**: Rust/Cargo. Minimum supported Rust version is **1.85.0** (stable).[^readme][^cargo-toml]

**Network/services**: ripgrep is a standalone CLI tool with no client-server architecture, no daemons, and no external service dependencies at runtime.

## Installation Methods

ripgrep offers five principal installation routes relevant to a DevFeats feature:

1. **Prebuilt Binary Download (GitHub Releases)** — direct, deterministic, version-pinnable; the recommended method for DevFeats/devcontainer features.
2. **Debian Package (.deb from GitHub Releases)** — official `.deb` for Debian/Ubuntu amd64; installs binary, man page, and shell completions system-wide.
3. **OS Package Manager** — distro-native lifecycle management; version may lag upstream.
4. **Cargo Install** — source-level build via crates.io; useful as a fallback when no pre-built binary matches the target platform.
5. **Build From Source** — full control; required for uncommon platforms or custom feature flags.

### Prebuilt Binary Download (GitHub Releases)

#### Supported Platforms

All current release assets (15.1.0):[^release-1510]

| OS | Architecture | Rust target triple | Asset filename |
|----|-------------|-------------------|---------------|
| Linux | x86_64 (glibc or musl) | `x86_64-unknown-linux-musl` | `ripgrep-{version}-x86_64-unknown-linux-musl.tar.gz` |
| Linux | arm64 (glibc) | `aarch64-unknown-linux-gnu` | `ripgrep-{version}-aarch64-unknown-linux-gnu.tar.gz` |
| Linux | armv7 (glibc) | `armv7-unknown-linux-gnueabihf` | `ripgrep-{version}-armv7-unknown-linux-gnueabihf.tar.gz` |
| Linux | armv7 (musl, hard-float) | `armv7-unknown-linux-musleabihf` | `ripgrep-{version}-armv7-unknown-linux-musleabihf.tar.gz` |
| Linux | armv7 (musl, soft-float) | `armv7-unknown-linux-musleabi` | `ripgrep-{version}-armv7-unknown-linux-musleabi.tar.gz` |
| Linux | i686 (32-bit x86) | `i686-unknown-linux-gnu` | `ripgrep-{version}-i686-unknown-linux-gnu.tar.gz` |
| Linux | s390x | `s390x-unknown-linux-gnu` | `ripgrep-{version}-s390x-unknown-linux-gnu.tar.gz` |
| macOS | arm64 (Apple Silicon) | `aarch64-apple-darwin` | `ripgrep-{version}-aarch64-apple-darwin.tar.gz` |
| macOS | x86_64 (Intel) | `x86_64-apple-darwin` | `ripgrep-{version}-x86_64-apple-darwin.tar.gz` |
| Windows | x86_64 (MSVC) | `x86_64-pc-windows-msvc` | `ripgrep-{version}-x86_64-pc-windows-msvc.zip` |
| Windows | x86_64 (GNU/MinGW) | `x86_64-pc-windows-gnu` | `ripgrep-{version}-x86_64-pc-windows-gnu.zip` |
| Windows | arm64 (MSVC) | `aarch64-pc-windows-msvc` | `ripgrep-{version}-aarch64-pc-windows-msvc.zip` |
| Windows | i686 (32-bit) | `i686-pc-windows-msvc` | `ripgrep-{version}-i686-pc-windows-msvc.zip` |

**Notable absences in v15.1.0:**

- There is **no** `x86_64-unknown-linux-gnu` binary. For Linux x86_64 (including Debian/Ubuntu and Alpine x86_64), use the `x86_64-unknown-linux-musl` static binary.[^release-1510][^release-workflow]
- There is **no** `aarch64-unknown-linux-musl` binary in any published release (the CI matrix includes this target, but no release has ever published this asset across all 74 GitHub releases as of 2026-06-18). For Linux arm64 on **musl-based** distros (e.g., Alpine Linux arm64), use the OS package manager (`apk add ripgrep`) or build from source; the `aarch64-unknown-linux-gnu` binary requires glibc and will not run on pure musl systems.[^release-1510][^release-workflow][^repology-alpine]

**Platform selection guidance:**

| Environment | Recommended asset |
|-------------|------------------|
| Debian/Ubuntu/ Fedora/etc. x86_64 | `x86_64-unknown-linux-musl` |
| Debian/Ubuntu/etc. arm64 | `aarch64-unknown-linux-gnu` |
| Alpine Linux x86_64 | `x86_64-unknown-linux-musl` |
| Alpine Linux arm64 | OS package manager (no musl arm64 release binary) |
| macOS (detect via `uname -m`) | `aarch64-apple-darwin` or `x86_64-apple-darwin` |
| Windows (default) | `x86_64-pc-windows-msvc` (also the target of `winget install BurntSushi.ripgrep.MSVC`)[^readme] |

#### Dependencies

##### Common Dependencies

- `curl` or `wget` to download the asset and checksum file.
- `tar` (for `.tar.gz` archives) or `unzip` (for `.zip` archives on Windows) to extract.
- `sha256sum` or `shasum -a 256` to verify the checksum.

##### Platform-Specific Dependencies

- Linux/macOS/BSD: None beyond download/extract/checksum tools.
- Root/sudo required only when writing to a system-wide path (e.g., `/usr/local/bin`).
- When extracting tarballs in restricted environments (e.g., some containers), use `tar --no-same-owner` to avoid ownership errors from archive metadata.

#### Installation Steps

Release tags do **not** use a `v` prefix. The tag for version 15.1.0 is `15.1.0`, not `v15.1.0`.[^release-workflow][^release-1510]

URL pattern: `https://github.com/BurntSushi/ripgrep/releases/download/{tag}/{filename}`

Each release archive contains a top-level directory named `ripgrep-{version}-{target-triple}/` with the `rg` binary (or `rg.exe` on Windows), documentation, license files, man page, and shell completion scripts.[^release-workflow]

Example — Linux x86_64, system-wide install:

```bash
set -e
VERSION="15.1.0"
TARGET="x86_64-unknown-linux-musl"
ASSET="ripgrep-${VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/${ASSET}.sha256"
sha256sum -c "${ASSET}.sha256"
tar --no-same-owner -xzf "${ASSET}" "${ASSET%.tar.gz}/rg"
sudo install -m 0755 "${ASSET%.tar.gz}/rg" /usr/local/bin/rg
rm -rf "${ASSET}" "${ASSET}.sha256" "${ASSET%.tar.gz}"
```

Example — Linux arm64 (glibc), system-wide install:

```bash
set -e
VERSION="15.1.0"
TARGET="aarch64-unknown-linux-gnu"
ASSET="ripgrep-${VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/${ASSET}.sha256"
sha256sum -c "${ASSET}.sha256"
tar --no-same-owner -xzf "${ASSET}" "${ASSET%.tar.gz}/rg"
sudo install -m 0755 "${ASSET%.tar.gz}/rg" /usr/local/bin/rg
rm -rf "${ASSET}" "${ASSET}.sha256" "${ASSET%.tar.gz}"
```

Example — macOS arm64, system-wide install (note: use `shasum -a 256` instead of `sha256sum`):

```bash
set -e
VERSION="15.1.0"
TARGET="aarch64-apple-darwin"
ASSET="ripgrep-${VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/${ASSET}.sha256"
shasum -a 256 -c "${ASSET}.sha256"
tar -xzf "${ASSET}" "${ASSET%.tar.gz}/rg"
sudo install -m 0755 "${ASSET%.tar.gz}/rg" /usr/local/bin/rg
rm -rf "${ASSET}" "${ASSET}.sha256" "${ASSET%.tar.gz}"
```

Example — Windows x86_64 (MSVC), user-local install:

```powershell
$Version = "15.1.0"
$Target = "x86_64-pc-windows-msvc"
$Asset = "ripgrep-$Version-$Target.zip"
$BaseUrl = "https://github.com/BurntSushi/ripgrep/releases/download/$Version"
Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $Asset
Invoke-WebRequest -Uri "$BaseUrl/$Asset.sha256" -OutFile "$Asset.sha256"
# Windows .sha256 files use certutil multi-line format; hash is on line 2:
$ExpectedHash = (Get-Content "$Asset.sha256")[1].Trim()
$ActualHash = (Get-FileHash -Algorithm SHA256 $Asset).Hash.ToLower()
if ($ActualHash -ne $ExpectedHash) { throw "Checksum mismatch for $Asset" }
Expand-Archive -Path $Asset -DestinationPath .
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null
Copy-Item "ripgrep-$Version-$Target\rg.exe" "$env:USERPROFILE\.local\bin\rg.exe"
```

#### Installation Verification

Verify with the version flag:

```bash
rg --version
# Expected output (example for 15.1.0):
# ripgrep 15.1.0 (rev af60c2de9d)
#
# features:+pcre2
# simd(compile):+SSE2,-SSSE3,-AVX2
# simd(runtime):+SSE2,+SSSE3,+AVX2
#
# PCRE2 10.45 is available (JIT is available)
```

The revision hash (`rev ...`) and SIMD/PCRE2 details vary by platform and build; the version number and `features:+pcre2` line confirm a standard release binary.[^release-workflow]

Checksum verification uses per-asset `.sha256` files published alongside each release asset. The format is **platform-dependent**:[^release-1510][^release-workflow]

- **Unix/macOS/Linux `.tar.gz` and `.deb` assets**: single-line `shasum -a 256` format: `{hash}  {filename}` (hash, two spaces, filename). Verify with:

  ```bash
  sha256sum -c "${ASSET}.sha256"
  # Expected output: {ASSET}: OK
  ```

- **Windows `.zip` assets**: multi-line `certutil` output format (three lines: header, hash, footer). Example:

  ```
  SHA256 hash of ripgrep-15.1.0-x86_64-pc-windows-msvc.zip:
  124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a
  CertUtil: -hashfile command completed successfully.
  ```

  Extract the hash from line 2 and compare against `Get-FileHash -Algorithm SHA256`, or use `certutil -hashfile $Asset SHA256` and compare manually.

**No GPG/PGP signatures** are provided for ripgrep releases. Checksum verification is the available integrity check.[^release-1510]

#### Configuration Options

##### Version Selection

Pass the desired `VERSION` when constructing the download URL. The string `"latest"` is not a valid release tag; resolve the latest version at install time from the GitHub API:

```bash
VERSION=$(curl -fsSL "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/')
```

Release tags use plain semver without a `v` prefix (e.g., `15.1.0`). When resolving a specific version, query the releases API and match the tag that equals `{version}`. Some third-party install scripts defensively accept an optional `v` prefix in tag-matching regexes, but ripgrep release tags themselves have never used a `v` prefix.[^release-workflow][^community-install]

##### Installation Path

Any writable directory on `PATH`. Common choices:

- System-wide: `/usr/local/bin/rg` (Linux/macOS) or `C:\Program Files\ripgrep\rg.exe` (Windows; requires admin)
- User-local: `$HOME/.local/bin/rg` (Linux/macOS) or `%USERPROFILE%\.local\bin\rg.exe` (Windows)

The official `.deb` package installs to `/usr/bin/rg`.[^deb-contents]

##### User Targeting

- **System-wide**: install to `/usr/local/bin` (or `/usr/bin` via `.deb`) with root privileges.
- **User-local**: install to `$HOME/.local/bin/rg` without sudo; requires `$HOME/.local/bin` on PATH.

##### Required Privileges

Root/sudo is required only when the target directory is root-owned (e.g., `/usr/local/bin`, `/usr/bin`). User-local installs require no elevated privileges.

##### Tool-Specific Configurations

No install-time flags for the binary download method. Runtime configuration is done via:

- **Configuration file**: set `RIPGREP_CONFIG_PATH` to a file path; each non-comment line is a shell argument applied before CLI flags.[^guide-config]
- **CLI flags**: passed on the command line; later flags override config file settings.[^guide-config]
- **`--no-config`**: disables all config file loading.[^guide-config]

Optional build-time configurations (relevant only for source/cargo builds, not pre-built binaries):

| Flag / env var | Description |
|----------------|-------------|
| `--features pcre2` | Enable PCRE2 regex engine support (enabled in all official release binaries)[^readme][^release-workflow] |
| `PCRE2_SYS_STATIC=1` | Statically link PCRE2 (used in official release CI)[^release-workflow] |
| `--target x86_64-unknown-linux-musl` | Build a fully static Linux binary[^readme] |

#### Post-Installation Steps and Cleanup

##### PATH Setup

- If installing to `/usr/local/bin` or `/usr/bin` (already on system PATH), no additional configuration is needed.
- If installing to a user-local directory, ensure it is on PATH:

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  # Add to ~/.bashrc or ~/.zshrc for persistence.
  ```

##### Configuration Files

ripgrep does **not** auto-load a configuration file and has no default config path. To use one, set `RIPGREP_CONFIG_PATH` persistently to any file path (the GUIDE uses `$HOME/.ripgreprc` as an example; other paths such as `$HOME/.config/ripgrep/rc` are equally valid):[^guide-config]

```bash
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/rc"
```

Example config file format (one flag per line, `#` for comments):

```
# ~/.config/ripgrep/rc
--max-columns=150
--max-columns-preview
--hidden
```

##### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `RIPGREP_CONFIG_PATH` | No | Path to a configuration file whose contents are prepended as default CLI arguments[^guide-config] |

No other persistent environment variables are required for default operation.

##### Activation Scripts

None required. ripgrep is invoked directly as `rg`.

##### Shell Completions

Official release archives include pre-generated completion scripts in the `complete/` subdirectory:[^release-workflow]

| Shell | File in archive | Recommended install location |
|-------|----------------|-------------------------------|
| bash | `complete/rg.bash` | `$XDG_CONFIG_HOME/bash_completion/rg.bash` (user-local)[^faq-complete] or `/usr/share/bash-completion/completions/rg` (system-wide, as in `.deb`)[^deb-contents] |
| fish | `complete/rg.fish` | `$XDG_CONFIG_HOME/fish/completions/rg.fish` (user-local)[^faq-complete] or `/usr/share/fish/vendor_completions.d/rg.fish` (system-wide)[^deb-contents] |
| zsh | `complete/_rg` | Add containing directory to `fpath` in `~/.zshrc` (user-local)[^faq-complete] or `/usr/share/zsh/vendor-completions/` (system-wide)[^deb-contents] |
| PowerShell | `complete/_rg.ps1` | Source from PowerShell profile[^faq-complete] |

Completions can also be generated at install time from the installed binary:

```bash
rg --generate complete-bash > /usr/share/bash-completion/completions/rg
rg --generate complete-fish > /usr/share/fish/vendor_completions.d/rg.fish
rg --generate complete-zsh > /usr/share/zsh/vendor-completions/_rg
rg --generate man > /usr/share/man/man1/rg.1
```

The `.deb` package installs bash, fish, zsh completions and the man page automatically.[^deb-contents]

Shell completion installation is **optional** for a DevFeats feature; the binary alone is sufficient for all search functionality.

##### Cleanup

```bash
rm -f "${ASSET}" "${ASSET}.sha256"
rm -rf "${ASSET%.tar.gz}"
```

No package caches or build artifacts remain after a binary install.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run the download and install steps with the desired version; the binary file is overwritten in place.

##### Uninstallation

```bash
# System-wide (binary install)
sudo rm -f /usr/local/bin/rg

# User-local
rm -f "$HOME/.local/bin/rg"

# Debian package
sudo dpkg -r ripgrep
```

Remove any installed completion files and the `RIPGREP_CONFIG_PATH` file/variable if configured. Uninstalling the binary does not remove user configuration files.

##### Idempotency

Re-running the install with the same version and target path overwrites the binary in-place. Checksum verification and version checks (`rg --version`) can be used to skip re-download when the desired version is already installed.

#### Details

The release CI workflow (`.github/workflows/release.yml`) builds all release binaries:[^release-workflow]

1. Triggers on push of tags matching `[0-9]+.[0-9]+.[0-9]+` (no `v` prefix).
2. Verifies the tag version matches `version` in `Cargo.toml`.
3. Builds with `cargo build --profile release-lto --features pcre2` (or `cross` for cross-compilation targets).
4. Sets `PCRE2_SYS_STATIC=1` for static PCRE2 linking.
5. Strips release binaries on macOS and cross-compiled Linux targets via explicit `strip` commands. Windows builds have no explicit `strip` workflow step, but the `release-lto` Cargo profile sets `strip = "symbols"`, so Cargo strips debug symbols during the Windows build as well. On Windows MSVC, `build.rs` additionally sets `/WX` (linker warnings as errors) and embeds a Windows manifest for long-path support.[^release-workflow][^build-rs][^cargo-toml]
6. Assembles each archive directory:

   ```
   ripgrep-{version}-{target}/
     rg                    # the binary
     README.md, COPYING, LICENSE-MIT, UNLICENSE
     doc/CHANGELOG.md, doc/FAQ.md, doc/GUIDE.md, doc/rg.1
     complete/rg.bash, complete/rg.fish, complete/_rg, complete/_rg.ps1
   ```

7. Creates `.tar.gz` (Unix) or `.zip` (Windows) archives.
8. Generates per-asset SHA256 checksum files: `shasum -a 256` on Unix/macOS/Linux, `certutil -hashfile ... SHA256` on Windows.
9. Uploads assets to the GitHub release.

Asset URL format:

```
https://github.com/BurntSushi/ripgrep/releases/download/{tag}/ripgrep-{version}-{target-triple}.tar.gz
https://github.com/BurntSushi/ripgrep/releases/download/{tag}/ripgrep-{version}-{target-triple}.zip
```

Where `{tag}` equals `{version}` for current releases (e.g., `15.1.0`).

The `x86_64-unknown-linux-musl` binary is a static PIE executable verified to run on glibc-based Linux systems without musl installed.[^verify-musl]

#### Notes and Best Practices

- Always verify the SHA256 checksum against the per-asset `.sha256` file before executing the binary.
- There are no GPG signatures for ripgrep releases.
- For Linux x86_64, always use the `x86_64-unknown-linux-musl` asset; there is no glibc-linked x86_64 release binary.
- For Linux arm64 on musl systems (Alpine arm64), no official pre-built binary is available in v15.1.0; use the OS package manager or build from source.
- All official release binaries include PCRE2 support (`features:+pcre2` in `rg --version` output).
- Use `tar --no-same-owner` when extracting in containers to avoid ownership errors.
- The devcontainer-community ripgrep feature downloads only the `*-unknown-linux-musl` tarball and maps Debian architectures via `debian_get_target_arch()`. This produces broken URLs for **arm64** (`aarch64-unknown-linux-musl`, which does not exist) and **armhf** (`arm-unknown-linux-musl`, which also does not exist; actual arm assets use `armv7-*` triples). Only **amd64** (`x86_64-unknown-linux-musl`) works correctly.[^community-install]

---

### Debian Package (.deb from GitHub Releases)

#### Supported Platforms

- Debian and Debian derivatives (Ubuntu, etc.) on **amd64** only.
- Official release asset: `ripgrep_{version}-1_amd64.deb` (note: underscore between name and version, `-1` Debian revision suffix).[^release-1510]
- **Filename format history**: releases ≤ 13.0.0 used `ripgrep_{version}_amd64.deb` (no `-1` revision suffix); releases ≥ 14.0.0 use `ripgrep_{version}-1_amd64.deb`. Version-selection logic must account for this when pinning older versions.[^release-1300][^release-1400]

#### Dependencies

##### Common Dependencies

- `curl` or `wget` to download the `.deb` and checksum file.
- `sha256sum` or `shasum -a 256` for checksum verification.
- `dpkg` to install the package.

##### Platform-Specific Dependencies

- Root/sudo required for `dpkg -i`.
- The `.deb` is built from the `x86_64-unknown-linux-musl` target internally and installs a static binary to `/usr/bin/rg`.[^release-workflow][^deb-contents]

#### Installation Steps

```bash
set -e
VERSION="15.1.0"
DEB="ripgrep_${VERSION}-1_amd64.deb"
BASE_URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}"

curl -fsSLO "${BASE_URL}/${DEB}"
curl -fsSLO "${BASE_URL}/${DEB}.sha256"
sha256sum -c "${DEB}.sha256"
sudo dpkg -i "${DEB}"
rm -f "${DEB}" "${DEB}.sha256"
```

If `dpkg -i` reports missing dependencies, run `sudo apt-get install -f`.

#### Installation Verification

```bash
rg --version
dpkg -s ripgrep
command -v rg   # Expected: /usr/bin/rg
```

#### Configuration Options

##### Version Selection

Same as the Prebuilt Binary method; construct the `.deb` filename from the version.

##### Installation Path

Fixed at `/usr/bin/rg` by the package. Completions install to `/usr/share/bash-completion/completions/rg`, `/usr/share/fish/vendor_completions.d/rg.fish`, `/usr/share/zsh/vendor-completions/_rg`, and man page to `/usr/share/man/man1/rg.1.gz`.[^deb-contents]

##### User Targeting

System-wide only.

##### Required Privileges

Root/sudo required.

##### Tool-Specific Configurations

The `.deb` is built with the `pcre2` feature enabled (`cargo deb --profile deb`).[^release-workflow]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Not required; `/usr/bin` is on PATH by default.

##### Configuration Files

Same as Prebuilt Binary method (`RIPGREP_CONFIG_PATH`).

##### Environment Variables

Same as Prebuilt Binary method.

##### Activation Scripts

None required.

##### Shell Completions

Installed automatically by the `.deb` package.[^deb-contents]

##### Cleanup

```bash
rm -f "${DEB}" "${DEB}.sha256"
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Download and install the new `.deb` version; `dpkg -i` replaces the existing package.

##### Uninstallation

```bash
sudo dpkg -r ripgrep
```

##### Idempotency

Re-running `dpkg -i` with the same version is a no-op or reinstall.

#### Details

The `build-release-deb` CI job:[^release-workflow]

1. Builds a debug binary to generate man page and completions via `rg --generate`.
2. Places generated files in `deployment/deb/`.
3. Runs `cargo deb --profile deb --target x86_64-unknown-linux-musl`.
4. Uploads `ripgrep_{version}-1_amd64.deb` and its `.sha256` checksum.

#### Notes and Best Practices

- The `.deb` is only published for amd64. For arm64 Debian/Ubuntu systems, use the Prebuilt Binary method with `aarch64-unknown-linux-gnu` or the OS package manager.
- This method is convenient for Debian/Ubuntu devcontainers because it installs completions and man page automatically.
- The README documents this approach with an example using version 14.1.1; the URL pattern is the same for all versions.[^readme]

---

### OS Package Manager

#### Supported Platforms

Documented in the official README:[^readme]

- macOS and Linux via **Homebrew** / **Linuxbrew**: `brew install ripgrep`
- **MacPorts** (macOS): `sudo port install ripgrep`
- **Arch Linux**: `sudo pacman -S ripgrep`
- **Debian / Debian derivatives**: `sudo apt-get install ripgrep` (available in Debian stable; version may lag upstream)[^readme]
- **Ubuntu Cosmic (18.10) and newer**: `sudo apt-get install ripgrep` (same `rust-ripgrep` packaging as Debian)[^readme]
- **Fedora**: `sudo dnf install ripgrep` (official Fedora repositories)[^readme][^fedora-pkg]
- **openSUSE Tumbleweed / Leap ≥ 15.1**: `sudo zypper install ripgrep`
- **RHEL-compatible enterprise Linux (RHEL, Rocky, Alma, CentOS Stream, Amazon Linux 2023, etc.)**: **not** in base OS repositories; requires **EPEL** (and usually **CRB / PowerTools / codeready-builder**) before `dnf install ripgrep` works[^readme][^fedora-pkg][^epel-docs]
- **CentOS Stream 10 / RHEL 10 / Rocky Linux 10**: EPEL setup examples in the README (see below)[^readme]
- **Gentoo**: `sudo emerge sys-apps/ripgrep` (portage category `sys-apps/ripgrep`, not plain `ripgrep`)[^readme]
- **FreeBSD**: `sudo pkg install ripgrep`
- **OpenBSD**: `doas pkg_add ripgrep`
- **NetBSD**: `sudo pkgin install ripgrep`
- **Void Linux**: `sudo xbps-install -Syv ripgrep`
- **Nix**: `nix-env --install ripgrep`
- **Guix**: `guix install ripgrep`
- **Flox**: `flox install ripgrep`[^readme]
- **ALT Linux**: `sudo apt-get install ripgrep`[^readme]
- **Haiku x86_64**: `sudo pkgman install ripgrep`; **Haiku x86_gcc2**: `sudo pkgman install ripgrep_x86`[^readme]
- **Windows Chocolatey**: `choco install ripgrep`
- **Windows Scoop**: `scoop install ripgrep`
- **Windows Winget**: `winget install BurntSushi.ripgrep.MSVC`

Also available via OS package managers not listed in the README but widely packaged (e.g., **Alpine Linux** via `apk add ripgrep` in the `community` repository, including **arm64**).[^repology-alpine][^alpine-pkg]

**Not recommended**: Ubuntu Snap packages for ripgrep exist but are explicitly **not recommended** by the maintainer due to unresolved bugs; the README advises against using them.[^readme]

**README nuance — Debian vs Ubuntu**: For **Debian** users, the README presents the official GitHub `.deb` download **before** the `apt-get install ripgrep` option, noting that Debian stable's apt version may be older than the release `.deb`.[^readme] Ubuntu 18.10+ is documented as having `ripgrep` in the standard archive without mentioning the `.deb` shortcut.

#### DevFeats-supported package managers — availability matrix

DevFeats `ospkg` supports **`apt`**, **`apk`**, **`brew`**, **`dnf`/`yum`**, **`pacman`**, and **`zypper`**. The table below states whether `ripgrep` (package name **`ripgrep`**, binary **`rg`**) is installable with a **plain** `method-package` manifest (`packages: [ripgrep]`) — i.e., without adding extra repositories, keys, or vendor-specific `upstream-package` manifests.

| PM | Typical distros / images | Package name | In default repos? | Extra repo / key setup required? | Notes |
|----|--------------------------|--------------|-------------------|----------------------------------|-------|
| **apt** | Debian, Ubuntu | `ripgrep` | **Yes** (Ubuntu ≥ 18.10; Debian stable)[^readme] | **No** | Version may lag upstream; pin via `ripgrep=VERSION-*` when available. |
| **apk** | Alpine | `ripgrep` | **Yes** (`community`; enabled on standard Alpine images)[^repology-alpine][^alpine-pkg] | **No** | Practical fallback on **Alpine arm64** (no official musl arm64 GitHub binary). |
| **brew** | macOS, Linuxbrew | `ripgrep` | **Yes** (`homebrew-core`)[^brew-formula] | **No** (but Homebrew itself must be installed) | Bottles include PCRE2; current stable 15.1.0. |
| **dnf / yum** | Fedora | `ripgrep` | **Yes** (Fedora `rust-ripgrep`)[^fedora-pkg] | **No** | In official Fedora repos only — not the same as RHEL-family. |
| **dnf / yum** | RHEL, Rocky, Alma, CentOS Stream, Amazon Linux 2023 | `ripgrep` | **No** (base OS repos) | **Yes — EPEL + CRB**[^epel-docs][^fedora-pkg] | README documents EL **10** examples only; EPEL **8** and **9** also ship `ripgrep` (14.1.1 as of 2026-06-18).[^fedora-pkg] A vanilla `packages: [ripgrep]` install **fails** until EPEL (and usually CRB/PowerTools) is configured. |
| **pacman** | Arch | `ripgrep` | **Yes** | **No** | Official Arch repos. |
| **zypper** | openSUSE Leap ≥ 15.1, Tumbleweed | `ripgrep` | **Yes**[^readme] | **No** | README documents Leap ≥ 15.1 explicitly. |

**Not covered by DevFeats `ospkg` today** (documented upstream only): MacPorts, Gentoo (`sys-apps/ripgrep`), FreeBSD/OpenBSD/NetBSD pkg, Void, Nix, Guix, Flox, ALT, Haiku (`ripgrep` / `ripgrep_x86`), Windows package managers.

**Implementation implication**: A DevFeats feature using only `method.package: {}` and `_dependencies.run.method-package: [ripgrep]` works on **apt, apk, brew, Fedora dnf, pacman, and zypper** out of the box. It does **not** work on **RHEL-family dnf/yum** unless the dependency manifest also enables **EPEL** (and CRB where required) — this is standard third-party repo setup, not a vendor-hosted repo like Lefthook's Cloudsmith `upstream-package`. There is no ripgrep-specific vendor repository; EPEL is the official path.

#### Dependencies

##### Common Dependencies

A working, configured system package manager.

##### Platform-Specific Dependencies

- Linux package managers generally require root/sudo.
- Homebrew requires a working Homebrew installation.
- **RHEL-family (dnf/yum)**: EPEL release package + GPG key (installed by `epel-release` RPM) and **CRB / codeready-builder / PowerTools** repository enabled per EPEL documentation.[^epel-docs][^readme] EPEL packages may have runtime dependencies on CRB-provided libraries.

#### Installation Steps

```bash
# Debian / Ubuntu (standard archive — no extra repos)
sudo apt-get update
sudo apt-get install -y ripgrep

# Fedora (base repos — no EPEL)
sudo dnf install -y ripgrep

# Alpine (community repo)
sudo apk add --no-cache ripgrep

# Arch
sudo pacman -S --noconfirm ripgrep

# openSUSE
sudo zypper install -y ripgrep

# Homebrew (macOS/Linux)
brew install ripgrep
```

EPEL setup (required on **RHEL-compatible** systems before `dnf install ripgrep`; **not** required on Fedora):[^readme][^epel-docs][^fedora-pkg]

The upstream README documents **EL 10** only. EPEL also publishes `ripgrep` for **EL 8** and **EL 9** (`14.1.1-1.el8`, `14.1.1-1.el9`).[^fedora-pkg] Replace `{N}` with `8`, `9`, or `10` and adjust CRB repo names for the target major version.

```bash
# Pattern for RHEL-compatible clones (Rocky/Alma/CentOS Stream) — EL 10 example from README:
sudo dnf config-manager --set-enabled crb
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
sudo dnf install -y ripgrep

# RHEL 10 (subscription-managed) — from README:
sudo subscription-manager repos --enable codeready-builder-for-rhel-10-$(arch)-rpms
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
sudo dnf install -y ripgrep

# Rocky Linux 10 — from README (no CRB step listed; EPEL docs still recommend CRB on RHEL-compatible systems):
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
sudo dnf install -y ripgrep

# EL 9 example (not in README; same package name, different epel-release URL):
sudo dnf config-manager --set-enabled crb   # or: subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo dnf install -y ripgrep

# EL 8 example (not in README):
sudo subscription-manager repos --enable codeready-builder-for-rhel-8-$(arch)-rpms   # RHEL; on CentOS Stream 8 use: dnf config-manager --set-enabled powertools
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
sudo dnf install -y ripgrep
```

#### Installation Verification

```bash
command -v rg
rg --version
```

Package-manager level verification:

```bash
# Debian/Ubuntu
dpkg -s ripgrep

# Fedora
dnf info ripgrep

# Alpine
apk info ripgrep

# Homebrew
brew info ripgrep
```

#### Configuration Options

##### Version Selection

Package managers install the version available in their repositories, which may lag upstream. Homebrew stable is currently 15.1.0.[^brew-formula] For strict version pinning, use the Prebuilt Binary or `.deb` method.

Some managers support version pinning (e.g., `apt-get install ripgrep=15.1.0-*`), but availability depends on repository contents.

##### Installation Path

Managed by the package manager: typically `/usr/bin/rg` (Linux) or `$(brew --prefix)/bin/rg` (Homebrew).

##### User Targeting

- Linux/Alpine/BSD package managers: system-wide.
- Homebrew: user-local within the Homebrew prefix.

##### Required Privileges

Root/sudo required for Linux/Alpine/BSD package managers. Homebrew does not require sudo.

##### Tool-Specific Configurations

Distro packages may or may not include PCRE2 support depending on how they were built. Verify with `rg --version` (look for `features:+pcre2`). Official GitHub release binaries and Homebrew bottles include PCRE2.[^brew-formula][^release-workflow] Debian/Ubuntu packages built from the `rust-ripgrep` source package typically include PCRE2, but the exact feature set depends on the distro's build flags — always verify at install time rather than assuming.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Not required for system package managers. For Homebrew, ensure brew shellenv is initialized.

##### Configuration Files

Same as Prebuilt Binary method (`RIPGREP_CONFIG_PATH`).

##### Environment Variables

Same as Prebuilt Binary method.

##### Activation Scripts

None required.

##### Shell Completions

May be installed automatically by the package manager (as with the official `.deb`). If not, generate from the installed binary (see Prebuilt Binary method).

##### Cleanup

```bash
apt-get clean && rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
brew upgrade ripgrep            # Homebrew
apt-get install -y ripgrep      # Debian/Ubuntu
dnf upgrade ripgrep             # Fedora
apk upgrade ripgrep             # Alpine
```

##### Uninstallation

```bash
brew uninstall ripgrep          # Homebrew
apt-get remove -y ripgrep       # Debian/Ubuntu
dnf remove -y ripgrep          # Fedora
apk del ripgrep                 # Alpine
pacman -R --noconfirm ripgrep   # Arch
```

##### Idempotency

Package manager installs are idempotent; re-running install on an already-installed package is a no-op or upgrade.

#### Notes and Best Practices

- Repository versions may lag upstream; Debian stable in particular often ships older versions.[^readme] For Debian **amd64** with strict version requirements, the official GitHub `.deb` (separate install method) may be preferable to apt.
- Alpine's `ripgrep` package is the practical install method for **Alpine arm64** where no official musl arm64 GitHub binary exists.[^repology-alpine][^alpine-pkg]
- **Do not conflate Fedora and RHEL-family**: `dnf install ripgrep` succeeds on Fedora without EPEL but **fails** on stock RHEL/Rocky/Alma/CentOS Stream/Amazon Linux 2023 images until EPEL (and typically CRB) is configured.[^fedora-pkg][^epel-docs]
- The upstream README EPEL section covers **EL 10** only; EPEL **8** and **9** also ship `ripgrep` with the same package name but different `epel-release-latest-{N}.rpm` URLs.[^fedora-pkg]
- EPEL is the official third-party repository path — there is **no** ripgrep vendor-hosted apt/dnf repo (unlike tools that use Cloudsmith/PPA `upstream-package` patterns). DevFeats should model RHEL-family support as **EPEL (+ CRB) entries in the `method-package` dependency manifest**, not as a separate vendor `upstream-package` method, unless the project adds a generic EPEL bootstrap feature.
- **`registers_as: ripgrep`** should be set when the primary binary is `rg` so `method=auto` PM version checks query `ripgrep`, not `rg`.
- The jungaretti devcontainer ripgrep feature uses `apt-get install ripgrep` (Debian-only, no version pinning).[^jungaretti-install]

---

### Cargo Install

#### Supported Platforms

Any platform where Rust 1.85.0+ is installed and the target architecture has a working Rust toolchain.

#### Dependencies

##### Common Dependencies

- Rust 1.85.0 or later (stable).[^readme][^cargo-toml]
- Network access to `crates.io` and `static.crates.io` (or a configured `CARGO_REGISTRY`/`CARGO_NET`).

##### Platform-Specific Dependencies

- For PCRE2 support: a C compiler and optionally `pkg-config` and system PCRE2 library (or PCRE2 built from source).[^readme]
- `strip` (optional) to remove debug symbols and reduce binary size.[^readme]

#### Installation Steps

```bash
# Latest from crates.io (may include debug symbols):
cargo install ripgrep

# Pin to a specific version:
cargo install ripgrep --version 15.1.0

# With PCRE2 support (matches official releases):
cargo install ripgrep --features pcre2

# Pin version with PCRE2:
cargo install ripgrep --version 15.1.0 --features pcre2
```

The binary is placed in `$CARGO_HOME/bin/rg` (default `~/.cargo/bin/rg`).

Alternatively, use `cargo binstall` to download a pre-built binary from GitHub without compiling locally:[^readme]

```bash
cargo binstall ripgrep
```

#### Installation Verification

```bash
rg --version
```

Note: `cargo install` builds include debug symbols by default, producing a larger binary than official releases. Run `strip $(which rg)` to reduce size.[^readme]

#### Configuration Options

##### Version Selection

Specify via `--version {X.Y.Z}` or by pinning the crate version in the install command.

##### Installation Path

`$CARGO_HOME/bin/rg` (default `~/.cargo/bin/rg`). Override with the `CARGO_HOME` environment variable or `cargo install --root /path/to/root`.

##### User Targeting

Always user-local. No sudo required.

##### Required Privileges

No elevated privileges required.

##### Tool-Specific Configurations

| Option | Description |
|--------|-------------|
| `--features pcre2` | Enable PCRE2 regex engine (recommended to match official releases)[^readme] |
| `--locked` | Use versions from Cargo.lock for reproducible builds |
| `PCRE2_SYS_STATIC=1` | Statically link PCRE2[^readme] |

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure `$CARGO_HOME/bin` (typically `~/.cargo/bin`) is on PATH:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

##### Configuration Files

Same as Prebuilt Binary method.

##### Environment Variables

Same as Prebuilt Binary method, plus standard Rust/Cargo variables (`CARGO_HOME`, `RUSTUP_HOME`, etc.) if non-default paths are used.

##### Activation Scripts

None required.

##### Shell Completions

Generate manually from the installed binary (see Prebuilt Binary method).

##### Cleanup

Build artifacts are cached in the Cargo registry and target directories. Clear with `cargo clean` if needed.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run `cargo install ripgrep --version {version}`.

##### Uninstallation

```bash
rm -f "$HOME/.cargo/bin/rg"
cargo uninstall ripgrep  # if tracked in cargo install list
```

##### Idempotency

Re-running with the same version overwrites the binary.

#### Notes and Best Practices

- Use this method as a fallback when no pre-built binary is available for the target platform.
- Official release binaries are built with `--profile release-lto` and include PCRE2; `cargo install` defaults to the `release` profile with debug symbols. Use `--features pcre2` and `strip` for a closer match.
- Minimum Rust version is 1.85.0; older toolchains may fail to compile current ripgrep releases.[^cargo-toml]

---

### Build From Source

#### Supported Platforms

Linux, macOS, Windows, and other platforms supported by the Rust toolchain. Most portable method when pre-built binaries and package managers are insufficient.

#### Dependencies

##### Common Dependencies

- Rust 1.85.0+ (stable).[^readme][^cargo-toml]
- `git` (for cloning the repository).
- C toolchain (for PCRE2 feature, which links against C code).

##### Platform-Specific Dependencies

- For MUSL static builds on Linux: `musl-tools` / `musl-gcc`.[^readme]
- For PCRE2 with MUSL: `musl-gcc` installed separately.[^readme]
- On macOS: Xcode command line tools.

#### Installation Steps

From git clone (standard release build):

```bash
set -e
git clone https://github.com/BurntSushi/ripgrep.git
cd ripgrep
cargo build --release --features pcre2
sudo install -m 0755 target/release/rg /usr/local/bin/rg
rg --version
```

From git clone (LTO release matching official binaries):

```bash
set -e
git clone https://github.com/BurntSushi/ripgrep.git
cd ripgrep
cargo build --profile release-lto --features pcre2
sudo install -m 0755 target/release-lto/rg /usr/local/bin/rg
rg --version
```

MUSL static build (Linux x86_64):

```bash
set -e
rustup target add x86_64-unknown-linux-musl
git clone https://github.com/BurntSushi/ripgrep.git
cd ripgrep
cargo build --profile release-lto --features pcre2 --target x86_64-unknown-linux-musl
# Binary at: target/x86_64-unknown-linux-musl/release-lto/rg
```

Pin to a specific release tag:

```bash
git clone --branch 15.1.0 --depth 1 https://github.com/BurntSushi/ripgrep.git
```

#### Installation Verification

Build-time:

```bash
cargo test --all
```

Runtime:

```bash
rg --version
command -v rg
```

#### Configuration Options

##### Version Selection

Check out the desired git tag (e.g., `15.1.0`) before building.

##### Installation Path

Controlled by `cargo install --root` or manual `install`/`cp` to the desired directory.

##### User Targeting

Supports both system-wide and user-local depending on install destination.

##### Required Privileges

Required only for root-owned install paths.

##### Tool-Specific Configurations

| Option | Description |
|--------|-------------|
| `--features pcre2` | Enable PCRE2 support[^readme] |
| `--profile release-lto` | LTO-optimized build matching official releases[^cargo-toml][^release-workflow] |
| `--target {triple}` | Cross-compile to a specific target[^readme] |
| `PCRE2_SYS_STATIC=1` | Statically link PCRE2[^release-workflow] |

#### Post-Installation Steps and Cleanup

##### PATH Setup

Add the install directory to PATH if not a standard system path.

##### Configuration Files

Same as Prebuilt Binary method.

##### Environment Variables

Same as Prebuilt Binary method.

##### Activation Scripts

None required.

##### Shell Completions

Generate from the built binary:

```bash
rg --generate complete-bash > /usr/share/bash-completion/completions/rg
rg --generate complete-fish > /usr/share/fish/vendor_completions.d/rg.fish
rg --generate complete-zsh > /usr/share/zsh/vendor-completions/_rg
rg --generate man > /usr/share/man/man1/rg.1
```

##### Cleanup

```bash
cargo clean
cd .. && rm -rf ripgrep
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Check out the new tag and rebuild/reinstall.

##### Uninstallation

Remove the installed binary from the target path. If installed via `cargo install`, use `cargo uninstall ripgrep`.

##### Idempotency

Rebuilding and reinstalling the same version to the same path overwrites the binary.

#### Details

The official release CI uses:[^release-workflow]

- Profile: `release-lto` (fat LTO, `opt-level = 3`, `strip = "symbols"`, `panic = "abort"`)
- Features: `pcre2`
- Environment: `PCRE2_SYS_STATIC=1`
- Cross-compilation via `cross` v0.2.5 for non-native Linux targets

#### Notes and Best Practices

- Use release tarballs/tags for reproducible builds rather than arbitrary commits.
- Run `cargo test --all` during CI validation.
- Building with PCRE2 on MUSL requires `musl-gcc`.[^readme]
- The `simd-accel` nightly feature has been removed; do not attempt to enable it.[^readme]

---

## Dev Container Setup

ripgrep works correctly in standard devcontainer environments without special container configuration. Key considerations:

- **Recommended install method**: Prebuilt Binary Download to `/usr/local/bin/rg` (system-wide, accessible by all users). For Debian/Ubuntu amd64-only images, the official `.deb` from GitHub releases is an alternative that also installs completions and man page.
- **Platform mapping in containers**:
  - Debian/Ubuntu devcontainers (x86_64): prefer **binary** (`x86_64-unknown-linux-musl` tarball) or apt `ripgrep`; `.deb` from GitHub is an alternative on amd64.
  - Debian/Ubuntu devcontainers (arm64): prefer **binary** (`aarch64-unknown-linux-gnu` tarball) or apt `ripgrep`.
  - Alpine devcontainers (x86_64): prefer **binary** (`x86_64-unknown-linux-musl`) or `apk add ripgrep`.
  - Alpine devcontainers (arm64): use **`method=package`** (`apk add ripgrep`) — no official musl arm64 GitHub binary.
  - **RHEL-family devcontainers** (Rocky, Alma, UBI, Amazon Linux 2023): **`method=package` requires EPEL (+ CRB) in the dependency manifest** before `ripgrep` resolves; otherwise use **binary** where a matching GitHub asset exists.
- **Dependencies during build**: ensure `curl`, `ca-certificates`, and `tar` are available before downloading. The devcontainer-community feature depends on a `ca-certificates` feature via `installsAfter`.[^community-feature-json]
- **No entrypoint or lifecycle commands** are needed; ripgrep is a user-space CLI tool with no daemons.
- **No volume mounts or special privileges** are required beyond root access during feature install (standard for devcontainer features).[^devcontainer-spec]
- **Configuration**: optionally set `RIPGREP_CONFIG_PATH` in the devcontainer user's environment if project-specific defaults are desired. This is not required for basic operation.
- **Shell completions**: optional; not required for VS Code or terminal usage. Install from the release archive's `complete/` directory or generate via `rg --generate`.
- **VS Code integration**: VS Code uses its own bundled ripgrep binary via the `@vscode/ripgrep` npm module for search functionality; installing `rg` on PATH benefits terminal usage and extensions that invoke `rg` directly, but VS Code's built-in search does not depend on a system-installed `rg`.[^vscode-ripgrep]

**Comparable devcontainer features:**

| Feature | Method | Version pinning | Notes |
|---------|--------|----------------|-------|
| `devcontainer-community/ripgrep` | GitHub release binary (musl tarball) | Yes (`version` option) | Debian-only; only amd64 works — arm64 and armhf URLs are broken[^community-install] |
| `devcontainers-contrib/ripgrep` | GitHub release via `ghcr.io/devcontainers-extra/features/gh-release:1.0.25` | Yes (`version` option) | Delegates to the devcontainers-extra gh-release feature (currently at version 1.0.26 in upstream; contrib pins 1.0.25)[^contrib-install][^gh-release-feature] |
| `jungaretti/ripgrep` | `apt-get install ripgrep` | No | Simple but no version control[^jungaretti-install] |

## Plugins and Extensions

### VS Code Ripgrep (`@vscode/ripgrep`)

Microsoft publishes `@vscode/ripgrep`, an npm module that bundles pre-built ripgrep binaries for VS Code's internal search. It is not installed by a DevFeats feature but is relevant context for devcontainer users.

- **Homepage**: https://github.com/microsoft/vscode-ripgrep
- **Source Code**: https://github.com/microsoft/vscode-ripgrep
- **npm package**: `@vscode/ripgrep`

**Architecture**: Pure JavaScript wrapper around platform-specific binary packages (`@vscode/ripgrep-{platform}-{arch}`). Binaries are built in [`microsoft/ripgrep-prebuilt`](https://github.com/microsoft/ripgrep-prebuilt), downloaded at npm publish time by `build/prepare-binaries.js` from that project's release assets, verified against `binaries.lock.json` (SHA256), and shipped inside the npm tarball. No runtime network access or postinstall download.[^vscode-ripgrep][^ripgrep-prebuilt]

**Usage** (Node.js):

```js
const { rgPath } = require('@vscode/ripgrep');
// child_process.spawn(rgPath, ...)
```

**Notes**: VS Code's built-in search uses this bundled binary, not a system-installed `rg`. Installing `rg` via a DevFeats feature benefits terminal usage, scripts, and third-party tools (e.g., fzf `:Rg` integration), but does not affect VS Code's internal search engine.

### ripgrep-all (`rga`)

ripgrep-all extends ripgrep to search inside PDFs, Office documents, archives, and other non-plaintext formats. It is a separate tool that wraps `rg`.

- **Homepage**: https://github.com/phiresky/ripgrep-all
- **Source Code**: https://github.com/phiresky/ripgrep-all

**Notes**: ripgrep-all depends on a working `rg` binary on PATH. It is out of scope for the `install-ripgrep` feature but may be installed as a separate feature.

## References

[^readme]: [ripgrep Official README](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/README.md) — Primary reference for tool overview, installation methods (all package managers), binary download information, cargo/build instructions, and PCRE2/MUSL build options.

[^cargo-toml]: [ripgrep `Cargo.toml`](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/Cargo.toml) — Crate metadata; specifies version 15.1.0, minimum Rust 1.85.0, binary name `rg`, `pcre2` feature, and `release-lto` profile settings.

[^release-latest]: [GitHub API — latest ripgrep release](https://api.github.com/repos/BurntSushi/ripgrep/releases/latest) — Authoritative latest release metadata, confirming version 15.1.0 published 2025-10-22.

[^release-1510]: [GitHub — ripgrep 15.1.0 release page](https://github.com/BurntSushi/ripgrep/releases/tag/15.1.0) — Complete list of downloadable binary assets, `.deb` package, and per-asset `.sha256` checksum files; confirms no GPG signatures and no `x86_64-unknown-linux-gnu` or `aarch64-unknown-linux-musl` assets.

[^release-workflow]: [ripgrep `.github/workflows/release.yml`](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/.github/workflows/release.yml) — Official release CI; documents tag format (no `v` prefix), build flags (`release-lto`, `pcre2`, `PCRE2_SYS_STATIC=1`), archive contents, checksum generation, and `.deb` build process.

[^guide-config]: [ripgrep GUIDE.md — Configuration file](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/GUIDE.md) — Documents `RIPGREP_CONFIG_PATH`, config file format, and `--no-config` flag.

[^faq-complete]: [ripgrep FAQ.md — Shell auto-completion](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/FAQ.md) — Documents completion generation and install locations for bash, fish, zsh, and PowerShell.

[^faq-pcre2]: [ripgrep FAQ.md — PCRE2](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/FAQ.md) — Documents PCRE2 availability in official builds vs. custom builds, and the error message when PCRE2 is unavailable.

[^build-rs]: [ripgrep `build.rs`](https://raw.githubusercontent.com/BurntSushi/ripgrep/master/build.rs) — Build script; embeds git revision hash and Windows manifest options.

[^verify-musl]: Empirical verification (2026-06-18, Linux x86_64 devcontainer) — downloaded `ripgrep-15.1.0-x86_64-unknown-linux-musl.tar.gz` and its `.sha256` from GitHub releases; `sha256sum -c` passed; `ldd` on extracted `rg` reports `statically linked`; `rg --version` outputs `ripgrep 15.1.0 (rev af60c2de9d)` with `features:+pcre2`.

[^deb-contents]: Verified by downloading `ripgrep_15.1.0-1_amd64.deb` from GitHub releases (2026-06-18) and inspecting contents via `dpkg-deb -c` — installs `/usr/bin/rg`, man page at `/usr/share/man/man1/rg.1.gz`, and bash/fish/zsh completions at documented paths.

[^brew-formula]: [Homebrew ripgrep formula](https://formulae.brew.sh/formula/ripgrep) — Homebrew install command, current stable version 15.1.0, supported bottle platforms (macOS arm64/x86_64, Linux x86_64/arm64).

[^fedora-pkg]: [Fedora Packages — rust-ripgrep / ripgrep](https://packages.fedoraproject.org/pkgs/rust-ripgrep/ripgrep/) — Confirms `ripgrep` in Fedora base repos and EPEL 8, 9, and 10 (version 14.1.1 as of 2026-06-18).

[^epel-docs]: [Fedora EPEL documentation — Getting started](https://docs.fedoraproject.org/en-US/epel/getting-started/) — Documents EPEL installation and the requirement to enable CRB (RHEL 8/9/10), PowerTools (CentOS Stream 8), or equivalent before using many EPEL packages.

[^alpine-pkg]: [Alpine Linux packages — ripgrep (aarch64, v3.23)](https://pkgs.alpinelinux.org/package/v3.23/community/aarch64/ripgrep) — Confirms `ripgrep` package in Alpine `community` repository on arm64 (15.1.0-r0 as of 2025-10-24).

[^repology-alpine]: [Repology — ripgrep packages](https://repology.org/project/ripgrep/packages) — Cross-distro package index confirming ripgrep availability in Alpine Linux (`ripgrep` package in community repository) and other distros not individually listed in the README.

[^release-1300]: [GitHub — ripgrep 13.0.0 release page](https://github.com/BurntSushi/ripgrep/releases/tag/13.0.0) — Documents older `.deb` naming format: `ripgrep_13.0.0_amd64.deb` (no `-1` revision suffix).

[^release-1400]: [GitHub — ripgrep 14.0.0 release page](https://github.com/BurntSushi/ripgrep/releases/tag/14.0.0) — Documents current `.deb` naming format: `ripgrep_14.0.0-1_amd64.deb`.

[^gh-release-feature]: [devcontainers-extra gh-release `devcontainer-feature.json`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/gh-release/devcontainer-feature.json) — gh-release feature metadata: version 1.0.26, options for repo, binaryNames, version, assetRegex, binLocation.

[^ripgrep-prebuilt]: [microsoft/ripgrep-prebuilt](https://github.com/microsoft/ripgrep-prebuilt) — Source of pre-built ripgrep binaries used by `@vscode/ripgrep`; binaries are published as release assets of this repository, not BurntSushi/ripgrep releases.

[^community-install]: [devcontainer-community ripgrep `install.sh`](https://raw.githubusercontent.com/devcontainer-community/devcontainer-features/main/src/ripgrep/install.sh) — Community devcontainer feature; documents Debian-only binary download using musl tarballs; architecture mapping produces broken URLs for arm64 (`aarch64-unknown-linux-musl`) and armhf (`arm-unknown-linux-musl`); only amd64 works.

[^community-feature-json]: [devcontainer-community ripgrep `devcontainer-feature.json`](https://raw.githubusercontent.com/devcontainer-community/devcontainer-features/main/src/ripgrep/devcontainer-feature.json) — Community feature metadata: version 1.0.3, `version` option (latest or X.Y.Z), `installsAfter` dependency on ca-certificates.

[^contrib-install]: [devcontainers-contrib ripgrep `install.sh`](https://raw.githubusercontent.com/devcontainers-contrib/features/main/src/ripgrep/install.sh) — Community feature delegating to gh-release nanolayer module for GitHub release binary install.

[^jungaretti-install]: [jungaretti ripgrep `install.sh`](https://raw.githubusercontent.com/jungaretti/features/main/src/ripgrep/install.sh) — Community feature using `apt-get install ripgrep` with no version option.

[^devcontainer-spec]: [Dev Container Features Specification — Invoking install.sh](https://raw.githubusercontent.com/devcontainers/spec/main/docs/specs/devcontainer-features.md) — Documents that feature install scripts run as root during container build.

[^vscode-ripgrep]: [VS Code Ripgrep README](https://raw.githubusercontent.com/microsoft/vscode-ripgrep/main/README.md) — Documents the `@vscode/ripgrep` npm module architecture, binary bundling, and platform package structure.
