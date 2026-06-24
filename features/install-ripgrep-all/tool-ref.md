# Feature Reference

ripgrep-all (`rga`) is a line-oriented search tool written in Rust that wraps [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) to search for regex patterns inside non-plaintext file formats. It recursively descends into archives and uses format-specific **adapters** to extract searchable text from PDFs, Office documents (DOCX, ODT), EPUBs, SQLite databases, compressed archives (ZIP, tar, gzip, bzip2, xz, zstd), and media files (MKV, MP4, MP3, etc.).[^readme] The primary command is `rga`; it invokes `rg --pre <rga-preproc>` under the hood, so a working `rg` binary on `PATH` is mandatory at runtime.[^rga-main]

The project is licensed under **AGPL-3.0-or-later**.[^cargo-toml] Official releases are published on GitHub; release tags use a `v` prefix (e.g., `v0.10.10`). Unlike ripgrep, ripgrep-all does **not** publish per-asset `.sha256` checksum files alongside release assets; integrity verification must use the GitHub API `digest` field (available for v0.10.10 assets), locally computed SHA256 hashes, or third-party package manager checksums.[^release-01010]

- **Homepage**: https://github.com/phiresky/ripgrep-all
- **Source Code**: https://github.com/phiresky/ripgrep-all
- **Documentation**: https://github.com/phiresky/ripgrep-all/blob/master/README.md (README — installation, adapters, CLI flags, config); https://github.com/phiresky/ripgrep-all/wiki (Wiki — custom adapters, fzf integration)
- **Latest Release**: 0.10.10 (as of 2026-06-18)[^release-latest]

## Tool Architecture

ripgrep-all is a **Rust application** shipping multiple CLI binaries, not a single self-contained tool like `rg`:

| Binary | Required? | Role |
|--------|-----------|------|
| `rga` | **Yes** | Main entrypoint; spawns `rg` with `--pre rga-preproc` and passes through ripgrep arguments[^rga-main] |
| `rga-preproc` | **Yes** | Preprocessor invoked by `rg`; runs format adapters to convert files to plain text before regex matching[^rga-preproc][^rga-main] |
| `rga-fzf` | No | Helper for fzf integration[^release-workflow] |
| `rga-fzf-open` | No | Helper for opening fzf-selected results[^release-workflow] |

**Critical co-location requirement**: `rga` resolves `rga-preproc` via `std::env::current_exe().with_file_name("rga-preproc")` — both binaries **must reside in the same directory**.[^rga-main] Installing only `rga` without `rga-preproc` causes runtime failure.

**ripgrep dependency**: `rga` shells out to `rg` (looked up on `PATH`). If `rg` is missing, `rga` exits with an error: `Please make sure you have ripgrep installed.`[^rga-main] This is a hard runtime dependency, not bundled in the `rga` binary.

**Adapter external tools** (runtime, looked up on `PATH` and in the directory containing `rga`):

| Adapter | External command | Package (Debian/Ubuntu) | Extensions |
|---------|-----------------|------------------------|------------|
| `pandoc` | `pandoc` | `pandoc` | `.epub`, `.odt`, `.docx`, `.fb2`, `.ipynb`, `.html`, `.htm` |
| `poppler` | `pdftotext` | `poppler-utils` | `.pdf` |
| `ffmpeg` | `ffmpeg` | `ffmpeg` | `.mkv`, `.mp4`, `.avi`, `.mp3`, `.ogg`, `.flac`, `.webm` |
| `zip` | (built-in) | — | `.zip`, `.jar` |
| `decompress` | (built-in) | — | `.gz`, `.bz2`, `.xz`, `.zst`, `.tgz`, etc. |
| `tar` | (built-in) | — | `.tar` |
| `sqlite` | (bundled `rusqlite`) | — | `.db`, `.sqlite`, `.sqlite3` |
| `postprocpagebreaks` | (built-in, internal) | — | `.asciipagebreaks` (used by poppler adapter)[^readme] |
| `mail` | (built-in, disabled by default) | — | `.mbox`, `.mbx`, `.eml` |

`rga` prepends its own executable directory (and `lib/` subdirectory) to `PATH` before spawning adapter commands, preferring bundled binaries over system ones.[^rga-main] On Linux/macOS, adapter tools are **not** bundled in GitHub release archives — they must be installed separately for full functionality.[^readme]

**Build system**: Rust/Cargo. Crate name `ripgrep_all` (underscore); crates.io package `ripgrep-all` (hyphen).[^cargo-toml][^crates-io] Minimum supported Rust version is **stable 1.75.0+** per README.[^readme] `Cargo.toml` uses `edition = "2024"`, which requires a recent stable Rust toolchain (Homebrew currently builds with Rust 1.96.0).[^cargo-toml][^brew-formula]

**Cargo features** (compile-time, not exposed in official release binaries):

| Feature | Default | Description |
|---------|---------|-------------|
| `perf-literal` | Yes | Enables `regex/perf-literal` for faster literal matching[^cargo-toml] |

**License**: AGPL-3.0-or-later.[^cargo-toml] Relevant for organizations with copyleft policy constraints.

**Network/services**: Standalone CLI tool; no daemons or external services. Uses a local SQLite cache database for adapter output (disabled with `--rga-no-cache`).[^readme]

**Configuration** (runtime, not install-time): JSONC config file at platform-specific paths (Linux: `~/.config/ripgrep-all/config.jsonc`; macOS: `~/Library/Application Support/ripgrep-all/config.jsonc`; Windows: `%APPDATA%\ripgrep-all\config.jsonc`).[^readme] Cache at `${XDG_CACHE_DIR:-~/.cache}/ripgrep-all` (Linux), `~/Library/Caches/ripgrep-all` (macOS), or `%LOCALAPPDATA%\ripgrep-all` (Windows).[^readme]

## Installation Methods

ripgrep-all offers four principal installation routes relevant to a DevFeats feature:

1. **Prebuilt Binary Download (GitHub Releases)** — direct, version-pinnable; recommended for distros without a native package (e.g., Ubuntu Noble, Alpine, Fedora).
2. **OS Package Manager** — distro-native lifecycle; version may lag upstream; pulls adapter dependencies automatically on Debian sid+.
3. **Cargo Install** — source-level build via crates.io; fallback when no pre-built binary matches the target.
4. **Build From Source** — full control; required for uncommon platforms.

Third-party routes documented upstream but secondary for DevFeats: **Chocolatey** and **Scoop** (Windows), **MacPorts** (macOS), **Nix**, **Gentoo**, **FreeBSD pkg**, **Void**, **Termux**, **MSYS2**.

### Prebuilt Binary Download (GitHub Releases)

#### Supported Platforms

All current release assets (v0.10.10):[^release-01010]

| OS | Architecture | Rust target triple | Asset filename |
|----|-------------|-------------------|---------------|
| Linux | x86_64 (glibc or musl) | `x86_64-unknown-linux-musl` | `ripgrep_all-v{version}-x86_64-unknown-linux-musl.tar.gz` |
| Linux | arm64 (glibc) | `aarch64-unknown-linux-gnu` | `ripgrep_all-v{version}-aarch64-unknown-linux-gnu.tar.gz` |
| Linux | armv7 (glibc, hard-float) | `arm-unknown-linux-gnueabihf` | `ripgrep_all-v{version}-arm-unknown-linux-gnueabihf.tar.gz` |
| macOS | arm64 (Apple Silicon) | `aarch64-apple-darwin` | `ripgrep_all-v{version}-aarch64-apple-darwin.tar.gz` |
| macOS | x86_64 (Intel) | `x86_64-apple-darwin` | `ripgrep_all-v{version}-x86_64-apple-darwin.tar.gz` |

**Notable absences in v0.10.10:**

- **No Windows binary** was published for v0.10.10 despite the CI matrix including a Windows target.[^release-01010][^release-workflow] For Windows, use v0.10.9 (`ripgrep_all-v0.10.9-x86_64-pc-windows-msvc.zip`), Chocolatey, or Scoop.[^release-0109][^choco]
- **No `x86_64-unknown-linux-gnu` binary**. For Linux x86_64 (Debian/Ubuntu/Alpine), use `x86_64-unknown-linux-musl`.[^release-01010]
- **No `aarch64-unknown-linux-musl` binary**. For Alpine Linux arm64, use Cargo install, build from source, or an OS package manager where available (none in Alpine as of 2026-06-18).[^repology][^alpine-ripgrep]

**Platform selection guidance:**

| Environment | Recommended asset |
|-------------|------------------|
| Debian/Ubuntu/Fedora/etc. x86_64 | `x86_64-unknown-linux-musl` |
| Debian/Ubuntu/etc. arm64 | `aarch64-unknown-linux-gnu` |
| Alpine Linux x86_64 | `x86_64-unknown-linux-musl` |
| Alpine Linux arm64 | Build from source or Cargo (no musl arm64 release binary) |
| macOS (detect via `uname -m`) | `aarch64-apple-darwin` or `x86_64-apple-darwin` |
| Windows x86_64 | v0.10.9 zip, Chocolatey, or Scoop (no v0.10.10 Windows asset)[^release-0109] |

#### Dependencies

##### Common Dependencies

- `curl` or `wget` to download the asset.
- `tar` to extract `.tar.gz` archives (or `unzip` for Windows `.zip`).
- **`rg` (ripgrep)** on `PATH` at runtime — install via companion `install-ripgrep` feature or OS package.[^rga-main][^readme]
- **Adapter tools** for full format coverage: `pandoc`, `pdftotext` (from `poppler-utils`), `ffmpeg`.[^readme] Without these, archive/SQLite search still works but PDF/Office/media adapters fail silently or with adapter errors.

##### Platform-Specific Dependencies

- Linux/macOS/BSD: None beyond download/extract tools for the binary install itself.
- Root/sudo required only when writing to a system-wide path (e.g., `/usr/local/bin`).
- When extracting tarballs in containers, use `tar --no-same-owner` to avoid ownership errors from archive metadata.[^ripgrep-tool-ref] Release archives embed uid/gid from the GitHub Actions build environment (1001 on `ubuntu-22.04` runners).[^release-workflow]
- Windows: MSVC runtime (`VCRUNTIME140.DLL`) required; install `vc_redist.x64.exe` if missing.[^readme] Manual release download does **not** include adapter dependencies (pandoc, poppler, ffmpeg) — Chocolatey/Scoop are the supported Windows install paths that pull dependencies.[^readme]

#### Installation Steps

Release tags **use a `v` prefix**. The tag for version 0.10.10 is `v0.10.10`.[^release-01010]

URL pattern: `https://github.com/phiresky/ripgrep-all/releases/download/v{version}/{filename}`

Note the underscore in the archive directory and asset prefix: `ripgrep_all-v{version}-{target}` (not `ripgrep-all`).[^release-workflow]

Each release archive contains a top-level directory `ripgrep_all-v{version}-{target}/` with:

- `rga`, `rga-preproc` (required)
- `rga-fzf`, `rga-fzf-open` (optional fzf helpers)
- `README.md`, `LICENSE.md`, `doc/CHANGELOG.md`[^release-workflow]

Example — Linux x86_64, system-wide install (install **both** `rga` and `rga-preproc`):

```bash
set -e
VERSION="0.10.10"
TAG="v${VERSION}"
TARGET="x86_64-unknown-linux-musl"
ASSET="ripgrep_all-${TAG}-${TARGET}.tar.gz"
STAGING="ripgrep_all-${TAG}-${TARGET}"
BASE_URL="https://github.com/phiresky/ripgrep-all/releases/download/${TAG}"

curl -fsSLO "${BASE_URL}/${ASSET}"
tar --no-same-owner -xzf "${ASSET}" "${STAGING}/rga" "${STAGING}/rga-preproc"
sudo install -m 0755 "${STAGING}/rga" "${STAGING}/rga-preproc" /usr/local/bin/
rm -rf "${ASSET}" "${STAGING}"
```

Example — Linux arm64 (glibc), system-wide install:

```bash
set -e
VERSION="0.10.10"
TAG="v${VERSION}"
TARGET="aarch64-unknown-linux-gnu"
ASSET="ripgrep_all-${TAG}-${TARGET}.tar.gz"
STAGING="ripgrep_all-${TAG}-${TARGET}"
BASE_URL="https://github.com/phiresky/ripgrep-all/releases/download/${TAG}"

curl -fsSLO "${BASE_URL}/${ASSET}"
tar --no-same-owner -xzf "${ASSET}" "${STAGING}/rga" "${STAGING}/rga-preproc"
sudo install -m 0755 "${STAGING}/rga" "${STAGING}/rga-preproc" /usr/local/bin/
rm -rf "${ASSET}" "${STAGING}"
```

Example — macOS arm64, system-wide install:

```bash
set -e
VERSION="0.10.10"
TAG="v${VERSION}"
TARGET="aarch64-apple-darwin"
ASSET="ripgrep_all-${TAG}-${TARGET}.tar.gz"
STAGING="ripgrep_all-${TAG}-${TARGET}"
BASE_URL="https://github.com/phiresky/ripgrep-all/releases/download/${TAG}"

curl -fsSLO "${BASE_URL}/${ASSET}"
tar -xzf "${ASSET}" "${STAGING}/rga" "${STAGING}/rga-preproc"
sudo install -m 0755 "${STAGING}/rga" "${STAGING}/rga-preproc" /usr/local/bin/
rm -rf "${ASSET}" "${STAGING}"
```

Example — Windows x86_64 (v0.10.9 — last release with Windows asset):

```powershell
$Version = "0.10.9"
$Tag = "v$Version"
$Target = "x86_64-pc-windows-msvc"
$Asset = "ripgrep_all-$Tag-$Target.zip"
$Staging = "ripgrep_all-$Tag-$Target"
$BaseUrl = "https://github.com/phiresky/ripgrep-all/releases/download/$Tag"
Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $Asset
Expand-Archive -Path $Asset -DestinationPath .
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null
Copy-Item "$Staging\rga.exe", "$Staging\rga-preproc.exe" "$env:USERPROFILE\.local\bin\"
```

#### Installation Verification

Verify with the version flag:

```bash
rga --version
# Expected output:
# ripgrep-all 0.10.10
```

Verify ripgrep integration:

```bash
rga --rg-version
# Expected: ripgrep version string from the rg on PATH
```

Verify adapters are discoverable:

```bash
rga --rga-list-adapters
# Lists enabled and disabled adapters with their extensions
```

Verify `rga-preproc` co-location (both in same directory):

```bash
dirname "$(command -v rga)"
ls -la "$(dirname "$(command -v rga)")/rga-preproc"
```

**Checksum verification**: ripgrep-all releases do **not** publish `.sha256` sidecar files. Options:[^release-01010]

1. **GitHub API `digest` field** (SHA256, available for v0.10.10 assets):

   ```bash
   # Example digest for x86_64-unknown-linux-musl v0.10.10:
   # sha256:a969c25b182ac84aa672518313b5f741091decf7d93d03a020bcfe517b9ff4e8
   sha256sum "${ASSET}"
   ```

2. **Compute locally** after download with `sha256sum` / `shasum -a 256`.

3. **Third-party checksums**: Chocolatey and Scoop publish SHA256 hashes for Windows packages.[^choco][^scoop]

**No GPG/PGP signatures** are provided.

#### Configuration Options

##### Version Selection

Pass the desired `VERSION` when constructing the download URL. Tags require the `v` prefix. Resolve latest at install time:

```bash
TAG=$(curl -fsSL "https://api.github.com/repos/phiresky/ripgrep-all/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/')
VERSION="${TAG#v}"
```

##### Installation Path

Any writable directory on `PATH`. **Both `rga` and `rga-preproc` must be installed to the same directory.**[^rga-main]

Common choices:

- System-wide: `/usr/local/bin/` (Linux/macOS) or `C:\Program Files\rga\` (Windows)
- User-local: `$HOME/.local/bin/` (Linux/macOS) or `%USERPROFILE%\.local\bin\` (Windows)

Debian/Ubuntu packages install to `/usr/bin/rga` and `/usr/bin/rga-preproc`.[^debian-files]

##### User Targeting

- **System-wide**: install to `/usr/local/bin` (or `/usr/bin` via OS package) with root privileges.
- **User-local**: install to `$HOME/.local/bin/` without sudo.

##### Required Privileges

Root/sudo required only when the target directory is root-owned. User-local installs require no elevated privileges.

##### Tool-Specific Configurations

Install-time configuration for a DevFeats feature should cover:

| Option | Description | Reference |
|--------|-------------|-----------|
| **Version** | Pin to a specific release (e.g., `0.10.10`) | GitHub releases[^release-latest] |
| **Binaries to install** | At minimum `rga` + `rga-preproc`; optionally `rga-fzf`, `rga-fzf-open` | Release archive contents[^release-workflow] |
| **ripgrep dependency** | Ensure `rg` is on `PATH` (via `install-ripgrep` feature or OS package) | `rga` runtime[^rga-main] |
| **Adapter dependencies** | Install `pandoc`, `poppler-utils`, `ffmpeg` for full format support | README Debian instructions[^readme]; Debian package depends[^debian-pkg] |
| **Adapter selection** | Runtime via `--rga-adapters=+mail` etc.; not an install-time setting but feature may document | README[^readme] |

Adapter dependency install (Debian/Ubuntu — recommended alongside binary install):

```bash
sudo apt-get install -y ripgrep pandoc poppler-utils ffmpeg
```

If `ripgrep` is unavailable in apt (not the case on Ubuntu Noble, which ships `ripgrep`[^ubuntu-ripgrep]), install `rg` from the `install-ripgrep` feature or GitHub releases.[^readme]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure the install directory is on `PATH`. For user-local installs:

```bash
# Add to shell profile if not already present:
export PATH="$HOME/.local/bin:$PATH"
```

`rga` also prepends its own directory to `PATH` at runtime for adapter tool discovery.[^rga-main]

##### Configuration Files

No configuration files are created during installation. Users may optionally create `config.jsonc` at the platform-specific config path (see Tool Architecture).[^readme]

##### Environment Variables

No persistent environment variables are required. Optional runtime variables:

| Variable | Purpose |
|----------|---------|
| `RUST_LOG` | Enable debug logging (e.g., `debug`)[^readme] |
| `RUST_BACKTRACE` | Enable backtraces for debugging[^readme] |
| `XDG_CACHE_DIR` | Override cache location (Linux)[^readme] |

##### Activation Scripts

None required.

##### Shell Completions

ripgrep-all does not ship shell completion scripts in release archives. No completions are installed by Debian packages either.[^debian-files]

##### Cleanup

Remove downloaded archives and extracted staging directories after install.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Download and install the new version over the existing binaries in the same directory. Ensure `rga-preproc` is updated alongside `rga`.

##### Uninstallation

```bash
sudo rm -f /usr/local/bin/rga /usr/local/bin/rga-preproc /usr/local/bin/rga-fzf /usr/local/bin/rga-fzf-open
# Or for user-local:
rm -f "$HOME/.local/bin/rga" "$HOME/.local/bin/rga-preproc"
```

Clear cache if desired: `rm -rf ~/.cache/ripgrep-all` (Linux).[^readme]

##### Idempotency

Re-running a binary install overwrites existing binaries in the target directory. Idempotent when using the same version and path.

#### Details

The release CI workflow (`.github/workflows/release.yml`) builds release binaries using `cross` with nightly Rust for cross-compilation targets.[^release-workflow] Archives are assembled by copying `rga`, `rga-preproc`, `rga-fzf`, `rga-fzf-open`, `README.md`, `LICENSE.md`, and `CHANGELOG.md` into a staging directory, then creating `.tar.gz` (Unix) or `.zip` (Windows).[^release-workflow]

At runtime, `rga` constructs an `rg` command:

```rust
let exe = std::env::current_exe().expect("Could not get executable location");
let preproc_exe = exe.with_file_name("rga-preproc");
let mut cmd = Command::new("rg");
cmd.args(["--no-line-number", "--smart-case"])
   .arg("--pre").arg(preproc_exe)
   .arg("--pre-glob").arg(pre_glob)
   .args(passthrough_args);
```

[^rga-main]

#### Notes and Best Practices

- **Always install `rga-preproc` alongside `rga`** in the same directory.[^rga-main]
- **Always ensure `rg` is available** — declare a dependency on the `install-ripgrep` feature or install `ripgrep` via OS package manager.[^rga-main]
- **Install adapter dependencies** (`pandoc`, `poppler-utils`, `ffmpeg`) for PDF/Office/media search; archive and SQLite adapters work without them.[^readme]
- The musl x86_64 binary runs on both glibc and musl Linux (including Alpine x86_64).[^release-01010]
- v0.10.10 Windows asset is missing; pin Windows installs to v0.10.9 GitHub zip, or use Chocolatey/Scoop (both still ship **v0.10.9** as of 2026-06-18).[^release-01010][^release-0109][^choco][^scoop]
- AGPL-3.0 license may affect distribution in some organizational contexts.[^cargo-toml]

---

### OS Package Manager

#### Supported Platforms

**Documented in the official README** (installation section):[^readme]

- **Arch Linux**: `sudo pacman -S ripgrep-all`
- **Gentoo**: `sudo emerge sys-apps/ripgrep-all`
- **Nix**: `nix-env -iA nixpkgs.ripgrep-all`
- **Homebrew / Linuxbrew**: `brew install ripgrep-all` (also known as `rga`)[^readme][^brew-formula]
- **MacPorts** (macOS): `sudo port install ripgrep-all`[^readme][^macports]
- **Debian-based (manual)**: download GitHub release binary; install adapter deps via `apt install ripgrep pandoc poppler-utils ffmpeg`[^readme]
- **Windows Chocolatey**: `choco install ripgrep-all`[^readme][^choco]
- **Windows Scoop**: `scoop install rga`[^readme][^scoop]
- **Compile from source**: `cargo install --locked ripgrep_all`[^readme]

**Available via OS package managers but not listed in README** (verified via distro package indexes and Repology):[^repology]

- **Debian sid, forky, trixie-backports**: `sudo apt-get install ripgrep-all`[^debian-pkg][^debian-forky][^debian-trixie-backports]
- **Devuan unstable** (syncs from Debian sid): `sudo apt-get install ripgrep-all`[^repology]
- **Ubuntu 26.04 (Resolute) and newer**: `sudo apt-get install ripgrep-all` (universe)[^ubuntu-2604]
- **FreeBSD**: `sudo pkg install ripgrep-all`[^repology]
- **Void Linux**: `sudo xbps-install -Syv ripgrep-all`[^repology]
- **Solus**: `ripgrep-all`[^repology]
- **Termux**: `pkg install ripgrep-all`[^repology]
- **MSYS2**: `mingw-w64-*-ripgrep-all`[^repology]

**Not available** in official repositories (as of 2026-06-18):

- **Debian bookworm (oldstable), Debian trixie (stable) main** — not in main suites; trixie users may use **trixie-backports**[^debian-trixie][^debian-trixie-backports]
- **Debian forky (testing), sid (unstable)** — available via `apt install ripgrep-all`[^debian-pkg][^debian-forky]
- **Ubuntu Noble (24.04) and earlier Ubuntu LTS releases** — confirmed absent; DevFeats `install-os-pkg-bundle` gates `ripgrep-all` to non-apt package managers only.[^bundle-metadata]
- **Alpine Linux** — no `ripgrep-all` apk package[^repology][^alpine-ripgrep]
- **Fedora / RHEL / EPEL** — not in official Fedora repos; only an outdated unofficial Copr exists[^fedora-discussion][^copr]
- **openSUSE** — not packaged in official repos per Repology[^repology]

**Windows third-party version lag** (as of 2026-06-18):

| Channel | Ships version | Notes |
|---------|--------------|-------|
| GitHub releases (latest) | 0.10.10 | No Windows asset in v0.10.10[^release-01010] |
| GitHub releases (v0.10.9 zip) | 0.10.9 | Last published Windows MSVC zip[^release-0109] |
| Chocolatey | 0.10.9 | Downloads v0.10.9 zip[^choco] |
| Scoop | 0.10.9 | Manifest pins v0.10.9 zip[^scoop] |

#### DevFeats-supported package managers — availability matrix

DevFeats `ospkg` supports **`apt`**, **`apk`**, **`brew`**, **`dnf`/`yum`**, **`pacman`**, and **`zypper`**.

| PM | Typical distros / images | Package name | In default repos? | Notes |
|----|--------------------------|--------------|-------------------|-------|
| **apt** | Debian sid, forky, trixie-backports; Ubuntu ≥ 26.04 | `ripgrep-all` | **Yes** (recent suites only) | **Not** in Debian bookworm/trixie main or Ubuntu Noble. Version `0.10.10+dfsg-*`. Hard-depends on `ripgrep`, `pandoc`, `poppler-utils`, `ffmpeg`.[^debian-pkg] |
| **apt** | Ubuntu Noble (24.04), Debian bookworm/trixie main | — | **No** | Use binary or Cargo install. Trixie may enable `trixie-backports`.[^bundle-metadata][^debian-trixie-backports] |
| **apk** | Alpine | — | **No** | Use binary (x86_64 musl) or Cargo.[^repology] |
| **brew** | macOS, Linuxbrew | `ripgrep-all` | **Yes** | Depends on `ripgrep` formula. Bottles for macOS (arm64/x86_64) and Linux (arm64/x86_64).[^brew-formula] |
| **dnf / yum** | Fedora, RHEL-family | — | **No** | Not in official repos. Use binary or Cargo.[^fedora-discussion] |
| **pacman** | Arch | `ripgrep-all` | **Yes** | v0.10.10-1 in extra. Hard depends on `ripgrep`, `xz`; optdepends on adapter tools.[^arch-pkg] |
| **zypper** | openSUSE | — | **No** | Not packaged per Repology.[^repology] |

#### Dependencies

##### Common Dependencies

A working, configured system package manager.

##### Platform-Specific Dependencies

- Linux package managers generally require root/sudo.
- Homebrew requires a working Homebrew installation.
- Debian `ripgrep-all` package depends on: `ripgrep`, `pandoc`, `poppler-utils`, `ffmpeg`, plus runtime libs (`libc6`, `libsqlite3-0`, `liblzma5`, `libzstd1`).[^debian-pkg]
- Arch `ripgrep-all` hard-depends on `ripgrep` and `xz`; adapter tools are **optdepends**: `ffmpeg`, `pandoc`, `poppler`, `graphicsmagick`, `tesseract`.[^arch-pkg]
- Homebrew depends on `ripgrep`; adapter tools installed separately.[^brew-formula]
- Chocolatey depends on `ripgrep`, `pandoc`, `poppler`, `ffmpeg`.[^choco]
- Scoop depends on `ffmpeg`, `pandoc`, `poppler`, `ripgrep`.[^scoop]

#### Installation Steps

```bash
# Arch
sudo pacman -S --noconfirm ripgrep-all

# Debian sid / forky / Ubuntu 26.04+ / trixie-backports
sudo apt-get update
sudo apt-get install -y ripgrep-all

# Homebrew (macOS/Linux)
brew install ripgrep-all

# Recommended adapter deps (Homebrew — not auto-installed):
brew install pandoc poppler ffmpeg

# Gentoo
sudo emerge sys-apps/ripgrep-all

# Nix
nix-env -iA nixpkgs.ripgrep-all

# Windows (Chocolatey)
choco install ripgrep-all

# Windows (Scoop)
scoop install rga
```

#### Installation Verification

```bash
command -v rga
rga --version
rga --rg-version
rga --rga-list-adapters
```

Package-manager level verification:

```bash
# Debian/Ubuntu
dpkg -s ripgrep-all

# Arch
pacman -Qi ripgrep-all

# Homebrew
brew info ripgrep-all
```

#### Configuration Options

##### Version Selection

Package managers install the version available in their repositories. Homebrew stable is 0.10.10.[^brew-formula] For strict version pinning, use the Prebuilt Binary or Cargo method.

##### Installation Path

Managed by the package manager:

| Package manager | `rga` path | `rga-preproc` path |
|----------------|-----------|-------------------|
| Debian/Ubuntu | `/usr/bin/rga` | `/usr/bin/rga-preproc` |
| Arch | `/usr/bin/rga` | `/usr/bin/rga-preproc` |
| Homebrew | `$(brew --prefix)/bin/rga` | `$(brew --prefix)/bin/rga-preproc` |

##### User Targeting

- Linux package managers: system-wide.
- Homebrew: user-local within the Homebrew prefix.

##### Required Privileges

Root/sudo required for Linux package managers. Homebrew does not require sudo.

##### Tool-Specific Configurations

| Option | Notes |
|--------|-------|
| **Adapter optdepends (Arch)** | `ffmpeg`, `pandoc`, `poppler` (and others) are optional; install for full adapter coverage[^arch-pkg] |
| **Adapter depends (Debian)** | `pandoc`, `poppler-utils`, `ffmpeg`, `ripgrep` are hard package depends[^debian-pkg] |
| **`registers_as`** | Should be `ripgrep-all` (the OS package name), not `rga` (the binary name) |

#### Post-Installation Steps and Cleanup

##### PATH Setup

Not required for system package managers (binaries in `/usr/bin`).

##### Configuration Files

None created during install.

##### Environment Variables

None required persistently.

##### Activation Scripts

None required.

##### Shell Completions

Not provided by distro packages.

##### Cleanup

```bash
apt-get clean && rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
brew upgrade ripgrep-all            # Homebrew
apt-get install -y ripgrep-all      # Debian/Ubuntu
pacman -Syu ripgrep-all             # Arch
```

##### Uninstallation

```bash
brew uninstall ripgrep-all          # Homebrew
apt-get remove -y ripgrep-all       # Debian/Ubuntu
pacman -R --noconfirm ripgrep-all   # Arch
```

##### Idempotency

Package manager installs are idempotent.

#### Details

Distro packages are built from upstream source tarballs (Debian: `ripgrep-all_{version}+dfsg.orig.tar.gz` with `cargo` and `dh-cargo`), not from GitHub release binaries.[^debian-pkg] The Debian package installs all four binaries to `/usr/bin/` and declares hard dependencies on `ripgrep`, `pandoc`, `poppler-utils`, and `ffmpeg`.[^debian-files][^debian-pkg]

Homebrew installs via `cargo install` from the upstream source tarball (`v0.10.10.tar.gz`), **not** from GitHub release archives. Pre-built **bottles** are available on supported macOS and Linux platforms; bottles are used by default when available.[^brew-formula] Homebrew hard-depends on the `ripgrep` formula.

Arch builds from source with `cargo build --frozen --release` and installs four binaries to `/usr/bin/`; adapter tools are optdepends.[^arch-pkg][^arch-files]

Chocolatey and Scoop download the v0.10.9 Windows GitHub release zip and install dependencies (`ripgrep`, `pandoc`, `poppler`, `ffmpeg`) via their respective dependency mechanisms.[^choco][^scoop]

#### Notes and Best Practices

- Ubuntu Noble devcontainers (common DevFeats base) **cannot** use `method=package` for ripgrep-all — use binary or Cargo.[^bundle-metadata]
- Debian sid, forky, trixie-backports, and Ubuntu 26.04+ packages install all four binaries (`rga`, `rga-preproc`, `rga-fzf`, `rga-fzf-open`) and pull adapter dependencies automatically.[^debian-files]
- Homebrew ships bottles on supported platforms; builds from upstream source via `cargo install` when no bottle applies — never uses GitHub release archives.[^brew-formula]
- Fedora/RHEL users must use binary or Cargo; no official RPM.[^fedora-discussion]
- Alpine users must use binary (x86_64) or Cargo (arm64); no apk package.[^repology]
- Windows Chocolatey/Scoop remain on v0.10.9 while GitHub latest is v0.10.10 without a Windows asset.[^choco][^scoop][^release-01010]

---

### Cargo Install

#### Supported Platforms

Any platform where Rust stable 1.75.0+ is installed and the target architecture has a working Rust toolchain. `Cargo.toml` uses `edition = "2024"`, which requires a **newer** stable Rust than the README's 1.75.0 minimum (Homebrew currently builds with Rust 1.96.0).[^readme][^cargo-toml][^brew-formula]

#### Dependencies

##### Common Dependencies

- Rust stable 1.75.0+ (README minimum); edition 2024 realistically requires a newer stable toolchain than 1.75.[^readme][^cargo-toml][^brew-formula]
- Network access to `crates.io` and `static.crates.io`.
- **`rg` on PATH** at runtime (not a compile-time dependency).[^rga-main]
- Adapter tools (`pandoc`, `pdftotext`, `ffmpeg`) at runtime for full format support.[^readme]

##### Platform-Specific Dependencies

- C compiler and build tools for some transitive native dependencies (SQLite is bundled via `rusqlite` with `bundled` feature).[^cargo-toml]
- `strip` (optional) to reduce binary size.

#### Installation Steps

Crate name uses underscore: `ripgrep_all`.[^crates-io]

```bash
cargo install --locked ripgrep_all

# Pin to a specific version:
cargo install --locked ripgrep_all --version 0.10.10
```

Installs four binaries to `$CARGO_HOME/bin/` (default `~/.cargo/bin/`): `rga`, `rga-preproc`, `rga-fzf`, `rga-fzf-open`.[^crates-io]

Install adapter dependencies (Debian/Ubuntu example):

```bash
sudo apt-get install -y pandoc poppler-utils ffmpeg ripgrep
```

#### Installation Verification

```bash
rga --version
# Expected: ripgrep-all 0.10.10

ls -la "$(dirname "$(command -v rga)")/rga-preproc"
# rga-preproc must be in the same directory as rga
```

#### Configuration Options

##### Version Selection

Specify via `--version {X.Y.Z}` or by pinning in the install command.

##### Installation Path

`$CARGO_HOME/bin/` (default `~/.cargo/bin/`). Override with `CARGO_HOME` or `cargo install --root /path/to/root`.

##### User Targeting

Always user-local. No sudo required.

##### Required Privileges

No elevated privileges required.

##### Tool-Specific Configurations

| Option | Description |
|--------|-------------|
| `--locked` | Use versions from `Cargo.lock` for reproducible builds (recommended by README)[^readme] |
| `--features perf-literal` | Default feature; enabled by default[^cargo-toml] |
| `--no-default-features` | Disable `perf-literal` (not recommended) |

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure `$CARGO_HOME/bin` is on `PATH`:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

##### Configuration Files

None created during install.

##### Environment Variables

Standard Rust/Cargo variables (`CARGO_HOME`, `RUSTUP_HOME`) if non-default paths are used.

##### Activation Scripts

None required.

##### Shell Completions

Not provided by `cargo install`.

##### Cleanup

Build artifacts cached in Cargo registry. Clear with `cargo uninstall ripgrep_all`.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
cargo install --locked ripgrep_all --force  # reinstall/upgrade
cargo install --locked ripgrep_all --version 0.10.9 --force  # downgrade
```

##### Uninstallation

```bash
cargo uninstall ripgrep_all
```

Removes all four binaries from `$CARGO_HOME/bin/`.

##### Idempotency

`cargo install` without `--force` skips if already installed. With `--force`, overwrites.

#### Details

`cargo install` downloads the crate source from crates.io, compiles all four binaries (`rga`, `rga-preproc`, `rga-fzf`, `rga-fzf-open`) with the locked dependency versions from `Cargo.lock`, and installs them to `$CARGO_HOME/bin/`.[^crates-io][^readme] The `--locked` flag is recommended by upstream README for reproducible builds.[^readme] SQLite support is statically linked via the `rusqlite` crate's `bundled` feature; no system SQLite dev package is required.[^cargo-toml]

#### Notes and Best Practices

- README recommends `cargo install --locked ripgrep_all`.[^readme]
- Compilation is significantly slower than binary download but works on any platform with Rust.
- All four binaries are installed to the same `$CARGO_HOME/bin/` directory, satisfying the co-location requirement.
- Nix package wraps all binaries with `PATH` containing adapter tools.[^nix-pkg]

---

### Build From Source

#### Supported Platforms

Any platform with Rust stable 1.75.0+ and a C toolchain. Primary fallback for platforms without pre-built binaries (Alpine arm64, uncommon architectures).

#### Dependencies

##### Common Dependencies

- Rust stable toolchain (1.75.0+ per README; edition 2024 requires newer stable Rust in practice)[^readme][^cargo-toml][^brew-formula]
- `cargo`, `rustc`
- `rg` on PATH at runtime
- Adapter tools for full format support: `pandoc`, `poppler-utils`/`poppler`, `ffmpeg`[^readme]

##### Platform-Specific Dependencies

- `build-essential` (Debian/Ubuntu) or equivalent C build tools
- Network access to fetch Cargo dependencies and the source archive

#### Installation Steps

```bash
# Debian/Ubuntu build deps:
sudo apt-get install -y build-essential pandoc poppler-utils ffmpeg ripgrep cargo

# Clone or extract source:
git clone https://github.com/phiresky/ripgrep-all.git
cd ripgrep-all
git checkout v0.10.10

# Build:
cargo build --release --locked

# Install (both required binaries to same directory):
sudo install -m 0755 target/release/rga target/release/rga-preproc /usr/local/bin/
# Optional:
sudo install -m 0755 target/release/rga-fzf target/release/rga-fzf-open /usr/local/bin/
```

#### Installation Verification

Same as Cargo Install method.

#### Configuration Options

##### Version Selection

Check out the desired git tag (e.g., `v0.10.10`).

##### Installation Path

Any writable directory on `PATH`; install all required binaries to the same directory.

##### User Targeting

System-wide (with sudo) or user-local.

##### Required Privileges

Root/sudo for system-wide install paths.

##### Tool-Specific Configurations

| Option | Description |
|--------|-------------|
| `--release` | Optimized build (recommended) |
| `--locked` | Reproducible dependency versions |
| `RUSTFLAGS="-C debuginfo=none"` | Nixpkgs overrides upstream `debug=true` in release profile[^nix-pkg] |

#### Post-Installation Steps and Cleanup

Same as Prebuilt Binary method.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Check out the new git tag and rebuild:

```bash
git fetch --tags
git checkout v0.10.10
cargo build --release --locked
sudo install -m 0755 target/release/rga target/release/rga-preproc /usr/local/bin/
```

##### Uninstallation

Remove binaries from the install path:

```bash
sudo rm -f /usr/local/bin/rga /usr/local/bin/rga-preproc /usr/local/bin/rga-fzf /usr/local/bin/rga-fzf-open
```

##### Idempotency

Re-running `cargo build --release` and `install` overwrites binaries in the target directory.

#### Details

Source builds follow the same `cargo build --release --locked` flow documented in the README.[^readme] The release profile in `Cargo.toml` sets `debug = true`, producing binaries with debug info unless stripped.[^cargo-toml] Nixpkgs overrides this with `RUSTFLAGS="-C debuginfo=none"`.[^nix-pkg] Arch builds with `cargo build --frozen --release`.[^arch-pkg]

#### Notes and Best Practices

- Arch package builds from upstream v0.10.10 source with `cargo build --frozen --release`.[^arch-pkg]
- Nix uses `rustPlatform.buildRustPackage` with `makeWrapper` to inject adapter tool paths into all binaries.[^nix-pkg]
- Release profile in `Cargo.toml` sets `debug = true` (binaries include debug info unless stripped).[^cargo-toml]

---

## Dev Container Setup

ripgrep-all works in standard devcontainer environments with these considerations:

- **Companion feature**: Declare a dependency on `install-ripgrep` (or ensure `ripgrep` OS package) so `rg` is on `PATH`. `rga` fails without it.[^rga-main]
- **Recommended install method by image**:
  - **Ubuntu Noble (24.04) devcontainers** (common DevFeats base): **binary** (`x86_64-unknown-linux-musl` or `aarch64-unknown-linux-gnu`) or **Cargo** — apt package is unavailable.[^bundle-metadata]
  - **Ubuntu 26.04+ / Debian sid**: **package** (`apt-get install ripgrep-all`) or binary.
  - **Alpine x86_64**: **binary** (`x86_64-unknown-linux-musl`).
  - **Alpine arm64**: **Cargo** or build from source (no binary, no apk).
  - **Arch devcontainers**: **package** (`pacman -S ripgrep-all`).
  - **Fedora/RHEL devcontainers**: **binary** or **Cargo** (no official RPM).
- **Adapter dependencies**: Install `pandoc`, `poppler-utils`, `ffmpeg` alongside `rga` for full format support. The DevFeats feature should offer an option to install these (similar to README's `apt install ripgrep pandoc poppler-utils ffmpeg`).[^readme][^bundle-metadata]
- **Binary install in containers**: Use `tar --no-same-owner` when extracting. Install **both** `rga` and `rga-preproc` to the same directory (e.g., `/usr/local/bin/`).[^ripgrep-tool-ref][^rga-main]
- **No entrypoint, lifecycle commands, volume mounts, or special privileges** beyond standard devcontainer feature install.
- **Cache directory**: rga creates `~/.cache/ripgrep-all` (or XDG equivalent) at runtime; no install-time setup needed.[^readme]

**Comparable devcontainer features:**

| Feature | Tool | Method | Notes |
|---------|------|--------|-------|
| `devcontainer-community/ripgrep` | `rg` only | GitHub release binary | Does not install `rga`[^community-ripgrep] |
| `devcontainers/features` | — | — | No ripgrep-all feature exists |
| `install-os-pkg-bundle` (text_processing) | `rga` | OS package (apk, brew, dnf, pacman, zypper only) | Explicitly excludes apt due to Noble unavailability[^bundle-metadata] |

**Suggested DevFeats feature design:**

- Primary binary: `rga`; also install `rga-preproc` to the same prefix.
- `_dependencies.run`: `install-ripgrep` (or `ripgrep` via `method-package`).
- Optional adapter dependency packages: `pandoc`, `poppler-utils`, `ffmpeg` (configurable).
- `registers_as: ripgrep-all` for OS package version detection.
- Default method: `binary` (works on Noble and all common devcontainer bases).

## Plugins and Extensions

### fzf Integration

ripgrep-all provides optional fzf helpers (`rga-fzf`, `rga-fzf-open`) and documents integration on the project wiki.[^readme][^wiki-fzf]

- **Wiki**: https://github.com/phiresky/ripgrep-all/wiki/fzf-Integration
- **Optional dependency**: `fzf` (suggested by Scoop manifest)[^scoop]

### Custom Adapters

Users can define custom adapters in the JSONC config file. Documentation on the project wiki.[^readme][^wiki]

- **Wiki**: https://github.com/phiresky/ripgrep-all/wiki

### VS Code

VS Code's built-in search uses its own bundled `rg` via `@vscode/ripgrep`; installing `rga` does not affect VS Code's internal search. Terminal usage and scripts benefit from a system-installed `rga`.

## References

[^readme]: [ripgrep-all Official README](https://raw.githubusercontent.com/phiresky/ripgrep-all/master/README.md) — Primary reference for tool overview, installation methods, adapters, CLI flags, config paths, and compile-from-source instructions.

[^cargo-toml]: [ripgrep-all Cargo.toml](https://raw.githubusercontent.com/phiresky/ripgrep-all/master/Cargo.toml) — Crate metadata, version, license, edition, features, and dependencies.

[^release-latest]: [GitHub API — Latest Release](https://api.github.com/repos/phiresky/ripgrep-all/releases/latest) — Confirms v0.10.10 as latest stable release (published 2025-11-09).

[^release-01010]: [GitHub API — v0.10.10 Release Assets](https://api.github.com/repos/phiresky/ripgrep-all/releases/tags/v0.10.10) — Asset list, SHA256 digests, and absence of Windows binary.

[^release-0109]: [GitHub API — v0.10.9 Release Assets](https://api.github.com/repos/phiresky/ripgrep-all/releases/tags/v0.10.9) — Last release with Windows x86_64 MSVC zip.

[^release-workflow]: [Release CI Workflow](https://raw.githubusercontent.com/phiresky/ripgrep-all/master/.github/workflows/release.yml) — Cross-compilation targets, archive assembly, and binary names.

[^rga-main]: [rga Main Binary Source](https://raw.githubusercontent.com/phiresky/ripgrep-all/master/src/bin/rga.rs) — Shows `rg` invocation, `rga-preproc` co-location, and PATH manipulation.

[^rga-preproc]: [rga-preproc Binary Source](https://raw.githubusercontent.com/phiresky/ripgrep-all/master/src/bin/rga-preproc.rs) — Preprocessor that runs format adapters.

[^crates-io]: [crates.io — ripgrep_all](https://crates.io/api/v1/crates/ripgrep-all) — Crate versions, binary names, and checksums.

[^brew-formula]: [Homebrew Formula — ripgrep-all](https://formulae.brew.sh/formula/ripgrep-all) — Version, bottles, dependencies on ripgrep and rust.

[^debian-pkg]: [Debian Package — ripgrep-all (sid)](https://packages.debian.org/sid/ripgrep-all) — Package dependencies including ripgrep, pandoc, poppler-utils, ffmpeg.

[^debian-forky]: [Debian Package — ripgrep-all (forky)](https://packages.debian.org/forky/ripgrep-all) — Confirms availability in Debian forky suite.

[^debian-trixie]: [Debian Package — ripgrep-all (trixie)](https://packages.debian.org/trixie/utils/ripgrep-all) — Confirms package is **not** in trixie main suite.

[^debian-trixie-backports]: [Debian Package — ripgrep-all (trixie-backports)](https://packages.debian.org/trixie-backports/utils/ripgrep-all) — Backports availability for trixie users.

[^debian-files]: [Debian File List — ripgrep-all amd64](https://packages.debian.org/sid/amd64/ripgrep-all/filelist) — Installed paths for all four binaries.

[^repology]: [Repology — ripgrep-all](https://repology.org/project/ripgrep-all) — Cross-distro package availability and versions.

[^bundle-metadata]: [DevFeats install-os-pkg-bundle metadata](https://github.com/devfeats/devfeats/blob/main/features/install-os-pkg-bundle/metadata.yaml) — `ripgrep-all` gated to `when: {pm: [apk, brew, dnf, yum, zypper, pacman]}` (excludes apt).

[^ubuntu-ripgrep]: [Ubuntu Noble — ripgrep package](https://packages.ubuntu.com/noble/ripgrep) — Confirms `ripgrep` (rg) is available in Noble but `ripgrep-all` is not.

[^ubuntu-2604]: [UbuntuUpdates — ripgrep-all (Resolute 26.04)](https://ubuntuupdates.org/package/core/resolute/universe/updates/ripgrep-all) — Package availability in Ubuntu 26.04 universe.

[^alpine-ripgrep]: [Alpine Package — ripgrep](https://pkgs.alpinelinux.org/package/edge/community/x86_64/ripgrep) — Confirms ripgrep (rg) is packaged but ripgrep-all is not.

[^arch-pkg]: [Arch Linux — ripgrep-all 0.10.10-1](https://archlinux.org/packages/extra/x86_64/ripgrep-all/) — Current version, depends, optdepends, and build info.

[^arch-files]: [Arch Linux — ripgrep-all file list](https://archlinux.org/packages/extra/x86_64/ripgrep-all/files/) — Installed binary paths.

[^choco]: [Chocolatey — ripgrep-all](https://community.chocolatey.org/packages/ripgrep-all) — Windows install script (v0.10.9 zip), checksum, and dependencies.

[^scoop]: [Scoop Manifest — rga](https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/rga.json) — Windows install URL (v0.10.9), hash, and depends.

[^macports]: [MacPorts — ripgrep-all](https://ports.macports.org/port/ripgrep-all/) — macOS port, version 0.10.10.

[^nix-pkg]: [Nixpkgs — ripgrep-all](https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/ri/ripgrep-all/package.nix) — Build, wrapProgram PATH injection, and runtime dependencies.

[^fedora-discussion]: [Fedora Discussion — ripgrep-all packaging](https://discussion.fedoraproject.org/t/will-ripgrep-all-be-packaged-on-fedora-package-team/128033) — Confirms not in official Fedora repos.

[^copr]: [Copr — returntrip/ripgrep-all](https://copr.fedorainfracloud.org/coprs/returntrip/ripgrep-all/) — Unofficial, outdated Copr repository.

[^ripgrep-tool-ref]: [DevFeats install-ripgrep tool-ref](https://github.com/devfeats/devfeats/blob/main/features/install-ripgrep/tool-ref.md) — Container tar extraction practice (`tar --no-same-owner`).

[^community-ripgrep]: [devcontainer-community/ripgrep feature](https://github.com/devcontainer-community/devcontainer-features/tree/main/src/ripgrep) — Installs `rg` only, not `rga`.

[^wiki-fzf]: [ripgrep-all Wiki — fzf Integration](https://github.com/phiresky/ripgrep-all/wiki/fzf-Integration) — fzf setup instructions.

[^wiki]: [ripgrep-all Wiki](https://github.com/phiresky/ripgrep-all/wiki) — Custom adapters and additional documentation.
