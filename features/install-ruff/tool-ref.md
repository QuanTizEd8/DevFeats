# Feature Reference

Ruff is an extremely fast Python linter and code formatter from Astral, written in Rust. It ships as a single `ruff` CLI binary that combines linting (`ruff check`), formatting (`ruff format`), import sorting, auto-fixes, a built-in language server (`ruff server`), and static analysis utilities. Ruff is designed as a drop-in replacement for Flake8 (plus many plugins), Black, isort, pydocstyle, pyupgrade, and autoflake, with configuration via `pyproject.toml`, `ruff.toml`, or `.ruff.toml`.[^readme][^docs-linter][^docs-formatter]

Upstream documents installation via `uvx`, `uv`/`pip`/`pipx`, standalone installers (since 0.5.0), OS package managers, Conda, Docker images, and related channels.[^docs-install] Additional distribution paths used in practice but not covered in the installation guide include direct GitHub release artifacts (published by cargo-dist) and `cargo install` from crates.io.[^release-01520][^crates-io] For DevFeats/devcontainer features, the **standalone installer** or **direct GitHub release binary download** are the recommended methods: they install a self-contained prebuilt binary with no Python runtime dependency, support explicit version pinning, and match how comparable community devcontainer features install Ruff.[^extra-feature]

- **Homepage**: https://astral.sh/ruff
- **Source Code**: https://github.com/astral-sh/ruff
- **Documentation**: https://docs.astral.sh/ruff/
- **Latest Release**: 0.15.20 (as of 2026-06-29)[^release-latest]

## Tool Architecture

Ruff is a **single, self-contained binary** (`ruff`, or `ruff.exe` on Windows) written in Rust. Official prebuilt release binaries require no Python, JVM, Node.js, or other runtime to execute.[^readme][^docs-install]

The project is organized as a Cargo workspace. The main CLI binary is built from `crates/ruff` and exposes subcommands including `check`, `format`, `server`, `clean`, `rule`, `config`, `linter`, `version`, and `analyze graph`.[^args-rs] Shell completions are generated via a hidden `generate-shell-completion` subcommand.[^args-rs]

**Client-server architecture**: Ruff includes a built-in language server invoked as `ruff server`, used by the official VS Code extension and other editors. This is optional for CLI-only usage; no background daemon is required for linting or formatting.[^docs-editors-setup]

**Network/services**: Ruff is a standalone CLI tool. Linting and formatting operate on local files. No external services are required at runtime. Caching is local (default cache directory `.ruff_cache` in the project tree; cleared with `ruff clean`).[^docs-config-defaults][^args-rs]

**Build system**: Rust/Cargo. Minimum supported Rust version (MSRV) for building from source is **1.94** (from workspace `Cargo.toml` at 0.15.20).[^cargo-toml] PyPI wheels bundle prebuilt binaries and do not require Rust at install time.[^pypi-json]

**Self-update**: Unlike Astral's `uv`, Ruff's cargo-dist configuration sets `install-updater = false`; release artifacts do not ship an updater binary, and there is no `ruff self update` subcommand. Version changes require reinstalling via the chosen package manager or installer.[^dist-workspace][^installer-sh]

**Runtime configuration** (relevant when scaffolding project defaults or wiring editor integration): Ruff accepts equivalent configuration in `pyproject.toml` (`[tool.ruff]` sections), `ruff.toml`, or `.ruff.toml`. In the same directory, precedence is `.ruff.toml` > `ruff.toml` > `pyproject.toml`.[^docs-config] Ruff uses hierarchical config discovery (closest config file per analyzed file; no implicit parent merge except via `extend`).[^docs-config-discovery] CLI `--config` overrides file settings; `--isolated` ignores all config files.[^docs-config][^args-rs]

When no project config exists, built-in defaults apply (line length 88, rules `E4`/`E7`/`E9`/`F`, target Python 3.10, etc.).[^docs-config-defaults] As a last resort, Ruff searches the user config directory for, in order: `.ruff.toml`, `ruff.toml`, `pyproject.toml` under `${config_dir}/ruff/` (on macOS/Linux typically `~/.config/ruff/`; on Windows `~\AppData\Roaming\ruff\` per FAQ).[^src-user-config][^docs-faq-user-config]

Primary CLI commands: `ruff check` (lint), `ruff format` (format), `ruff server` (language server), `ruff clean` (clear `.ruff_cache`), `ruff version` / `ruff --version`.[^docs-linter][^docs-formatter][^args-rs] Import sorting: `ruff check --select I --fix` then `ruff format`.[^docs-formatter-imports] Ruff uses a custom pre-1.0 versioning scheme where minor versions may break and patch versions fix bugs.[^docs-versioning]

## Installation Methods

Upstream installation methods documented in the official installation guide include: `uvx` ephemeral invocation, `uv tool install` / `uv add --dev`, `pip` / `pipx`, standalone installer scripts, Homebrew/Linuxbrew, Conda, pkgx, distro packages (Arch, Alpine, openSUSE), and Docker images.[^docs-install] This reference additionally covers direct GitHub release artifacts and Cargo installation as implementer-relevant paths not described in that guide.[^release-01520][^crates-io]

### Standalone Installer Script

#### Supported Platforms

- Shell installer (`install.sh`) targets macOS and Linux; PowerShell installer (`install.ps1`) targets Windows.[^docs-install]
- User-facing installer URLs (`https://astral.sh/ruff/install.sh`) redirect to the versioned script hosted at `releases.astral.sh` (equivalent to the `ruff-installer.sh` asset on GitHub Releases).[^docs-install][^installer-sh]
- **Published 0.15.20 release assets** (query release API/tags; do not assume all `dist-workspace.toml` build targets are published for every release): `aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-unknown-linux-gnu`, `aarch64-unknown-linux-musl`, `x86_64-unknown-linux-gnu`, `x86_64-unknown-linux-musl`, `arm-unknown-linux-musleabihf`, `armv7-unknown-linux-gnueabihf`, `armv7-unknown-linux-musleabihf`, `i686-unknown-linux-gnu`, `i686-unknown-linux-musl`, `powerpc64le-unknown-linux-gnu`, `riscv64gc-unknown-linux-gnu`, `s390x-unknown-linux-gnu`, `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`, `i686-pc-windows-msvc`.[^release-01520]
- `dist-workspace.toml` also lists `powerpc64-unknown-linux-gnu` as a CI build target, but that triple is **not** among 0.15.20 published assets.[^dist-workspace][^release-01520]
- Linux installer detects glibc vs musl via `ldd` and selects gnu or musl artifacts. For glibc targets, if glibc is below 2.31, the installer falls back to the musl static artifact where available (e.g. `x86_64-unknown-linux-gnu` → `x86_64-unknown-linux-musl`).[^installer-sh]
- macOS Rosetta 2 is corrected via `sysctl hw.optional.arm64`.[^installer-sh]

#### Dependencies

##### Common Dependencies

- `curl` or `wget` for downloading the installer and artifacts.
- Basic Unix tools used by the script: `uname`, `mktemp`, `chmod`, `mkdir`, `rm`, `tar`, `grep`, `cat`, `sed`.

##### Platform-Specific Dependencies

- Linux: `ldd` for libc detection; `sha256sum` for embedded checksum verification (verification is skipped with a warning when `sha256sum` is unavailable — there is no `shasum` fallback in the installer).[^installer-sh]
- Windows PowerShell installer: PowerShell 5+, permissive execution policy, TLS 1.2.

#### Installation Steps

1. Install latest on macOS/Linux:
   - `curl -LsSf https://astral.sh/ruff/install.sh | sh`
2. Alternative downloader:
   - `wget -qO- https://astral.sh/ruff/install.sh | sh`
3. Pin a specific version by URL path:
   - `curl -LsSf https://astral.sh/ruff/0.15.20/install.sh | sh`
4. Install latest on Windows:
   - `powershell -c "irm https://astral.sh/ruff/install.ps1 | iex"`
5. Pin a specific Windows installer version:
   - `powershell -c "irm https://astral.sh/ruff/0.15.20/install.ps1 | iex"`
6. The installer detects platform, downloads from mirror-first URLs (`releases.astral.sh`), verifies embedded SHA256 checksums when tools are available, extracts the `ruff` binary, installs to the resolved executable directory, writes an install receipt, and optionally updates PATH.[^docs-install][^installer-sh][^dist-workspace]

#### Installation Verification

- Command checks:
  - `ruff --version`
- Integrity checks:
  - Unix shell installer embeds expected SHA256 values per artifact and verifies them with `sha256sum` when available; verification is skipped with a warning otherwise (no `shasum` fallback).[^installer-sh]
  - GitHub release attestations are published for release artifacts (`github-attestations = true` in dist config).[^dist-workspace]

#### Configuration Options

##### Version Selection

- Pin by versioned installer URL: `https://astral.sh/ruff/<version>/install.sh` (no `v` prefix in version path; tag is `0.15.20`).[^docs-install][^release-latest]

##### Installation Path

- Default executable directory resolution order:[^dist-workspace][^installer-sh]
  1. `$XDG_BIN_HOME`
  2. `$XDG_DATA_HOME/../bin`
  3. `$HOME/.local/bin`
- Override with `RUFF_INSTALL_DIR` (forces flat layout at that path).

##### User Targeting

- Default is user-local install; no root/sudo required for default paths.
- System-wide install possible by setting `RUFF_INSTALL_DIR` (or `RUFF_UNMANAGED_INSTALL`) to a privileged path such as `/usr/local/bin` and running with appropriate permissions.

##### Required Privileges

- None for user-local install.
- Root/sudo only when targeting system-wide privileged directories.

##### Tool-Specific Configurations

Environment variables read by the Unix shell installer:[^installer-sh]

| Variable | Effect |
|----------|--------|
| `RUFF_INSTALL_DIR` | Force install directory (flat layout) |
| `RUFF_NO_MODIFY_PATH=1` | Disable PATH mutation (alias: `INSTALLER_NO_MODIFY_PATH`) |
| `RUFF_UNMANAGED_INSTALL=/path` | Fixed install path; disables PATH mutation and receipt/updater behavior |
| `RUFF_DISABLE_UPDATE=1` | Sets `INSTALL_UPDATER=0`, which skips updater download **and** install receipt writing[^installer-sh] |
| `RUFF_DOWNLOAD_URL` | Override artifact download base URL |
| `RUFF_INSTALLER_GITHUB_BASE_URL` / `RUFF_INSTALLER_GHE_BASE_URL` | Override GitHub base URLs for downloads |
| `RUFF_GITHUB_TOKEN` | Token for authenticated GitHub downloads |
| `RUFF_PRINT_VERBOSE` / `RUFF_PRINT_QUIET` | Control installer verbosity |
| `CARGO_DIST_FORCE_INSTALL_DIR` | Legacy alias for forced install directory |

Script flags: `--help`, `--verbose`, `--quiet`, deprecated `--no-modify-path` (use `RUFF_NO_MODIFY_PATH=1`).[^installer-sh]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- By default the installer writes `env`/`env.fish` helper scripts and adds source lines to detected shell profile files (`~/.profile`, `~/.bashrc`, zsh startup files, fish `conf.d/`). Also appends install dir to `$GITHUB_PATH` in GitHub Actions when present.[^installer-sh]
- Disable with `RUFF_NO_MODIFY_PATH=1`.
- In devcontainers, prefer `RUFF_UNMANAGED_INSTALL` or `RUFF_NO_MODIFY_PATH=1` and install to a path already on `PATH` (e.g. `/usr/local/bin`).

##### Configuration Files

- Standalone installs write an install receipt at `$XDG_CONFIG_HOME/ruff/ruff-receipt.json` (or `%LOCALAPPDATA%/ruff/` on Windows POSIX shells).[^installer-sh]
- Ruff project configuration (`pyproject.toml` / `ruff.toml`) is not created by the installer; it is project-specific.

##### Environment Variables

- No mandatory runtime environment variables for normal CLI usage.
- Optional: project-specific Ruff settings belong in config files, not env vars.

##### Activation Scripts

- Unix: profile updates source generated `env`/`env.fish` in the install directory when PATH modification is enabled.[^installer-sh]

##### Shell Completions

- Generate via hidden CLI subcommand: `ruff generate-shell-completion <shell>` where `<shell>` is a clap-supported shell (bash, zsh, fish, etc.).[^args-rs]
- Not installed automatically by the standalone installer.

##### Cleanup

- Installer removes its temporary download directory after installation.[^installer-sh]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Re-run the installer with a versioned URL to replace the binary in place.
- No built-in self-update command (`install-updater = false`).[^dist-workspace]
- For PyPI/OS-package installs, use the respective package manager.

##### Uninstallation

- Remove the binary from the install directory (typically `~/.local/bin/ruff`).
- Remove install receipt: `$XDG_CONFIG_HOME/ruff/ruff-receipt.json`.
- Remove shell profile source lines for `env`/`env.fish` if PATH mutation was enabled.
- Optional: `ruff clean` to clear project caches; remove `~/.config/ruff/` user config if present.

##### Idempotency

- Re-running the installer is safe: it updates binaries in place, reuses existing env scripts, and avoids duplicate shell-profile entries when install dir is already on `PATH`.[^installer-sh]

#### Details

The Unix shell installer is generated by **cargo-dist 0.31.0** and performs:[^installer-sh][^dist-workspace]

1. **Configuration from environment**: reads download URL overrides, PATH/update flags, and auth token.
2. **Architecture detection** (`get_architecture`): `uname -s`/`uname -m`, Linux libc via `ldd`, macOS Rosetta correction, Android/illumos/CYGWIN handling, CPU alias normalization.
3. **Archive selection** (`select_archive_for_arch`): maps arch+libc to best artifact; glibc minimum 2.31 checks with musl fallback chains for common Linux arches.
4. **Embedded checksums**: per-artifact SHA256 verified post-download when tools available.
5. **Multi-URL download**: tries `releases.astral.sh` first, then GitHub releases fallback (`hosting = ["simple", "github"]`).
6. **Install receipt**: writes JSON receipt with install prefix, binary list, version, provider metadata.
7. **PATH modification**: writes env helper scripts and profile snippets unless disabled or install dir already on `PATH`.
8. **`RUFF_UNMANAGED_INSTALL` mode**: fixed path, no PATH mutation, no receipt — intended for scripted/ephemeral/CI environments.

#### Notes and Best Practices

- In CI/devcontainers, prefer `RUFF_UNMANAGED_INSTALL=/usr/local/bin` or direct binary install to avoid shell profile mutation.
- Pin explicit versioned installer URLs for reproducibility.
- Standalone binary install avoids coupling the devcontainer to a specific Python version.

### Direct GitHub Release Artifact Installation

#### Supported Platforms

All release assets for 0.15.20:[^release-01520]

| OS | Architecture | Rust target triple | Asset filename |
|----|-------------|-------------------|---------------|
| Linux | x86_64 (glibc ≥2.31) | `x86_64-unknown-linux-gnu` | `ruff-{version}-x86_64-unknown-linux-gnu.tar.gz` |
| Linux | x86_64 (musl / old glibc fallback) | `x86_64-unknown-linux-musl` | `ruff-{version}-x86_64-unknown-linux-musl.tar.gz` |
| Linux | arm64 (glibc ≥2.31) | `aarch64-unknown-linux-gnu` | `ruff-{version}-aarch64-unknown-linux-gnu.tar.gz` |
| Linux | arm64 (musl) | `aarch64-unknown-linux-musl` | `ruff-{version}-aarch64-unknown-linux-musl.tar.gz` |
| Linux | armv7 (glibc) | `armv7-unknown-linux-gnueabihf` | `ruff-{version}-armv7-unknown-linux-gnueabihf.tar.gz` |
| Linux | armv7 (musl) | `armv7-unknown-linux-musleabihf` | `ruff-{version}-armv7-unknown-linux-musleabihf.tar.gz` |
| Linux | armv6 | `arm-unknown-linux-musleabihf` | `ruff-{version}-arm-unknown-linux-musleabihf.tar.gz` |
| Linux | i686 (glibc) | `i686-unknown-linux-gnu` | `ruff-{version}-i686-unknown-linux-gnu.tar.gz` |
| Linux | i686 (musl) | `i686-unknown-linux-musl` | `ruff-{version}-i686-unknown-linux-musl.tar.gz` |
| Linux | ppc64le | `powerpc64le-unknown-linux-gnu` | `ruff-{version}-powerpc64le-unknown-linux-gnu.tar.gz` |
| Linux | riscv64 | `riscv64gc-unknown-linux-gnu` | `ruff-{version}-riscv64gc-unknown-linux-gnu.tar.gz` |
| Linux | s390x | `s390x-unknown-linux-gnu` | `ruff-{version}-s390x-unknown-linux-gnu.tar.gz` |
| macOS | arm64 | `aarch64-apple-darwin` | `ruff-{version}-aarch64-apple-darwin.tar.gz` |
| macOS | x86_64 | `x86_64-apple-darwin` | `ruff-{version}-x86_64-apple-darwin.tar.gz` |
| Windows | x86_64 (MSVC) | `x86_64-pc-windows-msvc` | `ruff-{version}-x86_64-pc-windows-msvc.zip` |
| Windows | arm64 (MSVC) | `aarch64-pc-windows-msvc` | `ruff-{version}-aarch64-pc-windows-msvc.zip` |
| Windows | i686 (MSVC) | `i686-pc-windows-msvc` | `ruff-{version}-i686-pc-windows-msvc.zip` |

**Platform selection guidance for devcontainers:**

| Environment | Recommended asset |
|-------------|------------------|
| Debian/Ubuntu/Fedora x86_64 (glibc) | `x86_64-unknown-linux-gnu` (or `x86_64-unknown-linux-musl` for broader portability) |
| Debian/Ubuntu arm64 | `aarch64-unknown-linux-gnu` |
| Alpine x86_64 | `x86_64-unknown-linux-musl` |
| Alpine arm64 | `aarch64-unknown-linux-musl` |
| macOS (Apple Silicon) | `aarch64-apple-darwin` |
| macOS (Intel) | `x86_64-apple-darwin` |

Release tags use plain semver **without** a `v` prefix (e.g. `0.15.20`).[^release-latest]

URL pattern: `https://github.com/astral-sh/ruff/releases/download/{tag}/{filename}`

Each archive contains a top-level directory `ruff-{version}-{target-triple}/` with the `ruff` binary (or `ruff.exe` on Windows). Per-asset `.sha256` sidecar files and a `sha256.sum` manifest are published.[^release-01520]

#### Dependencies

##### Common Dependencies

- `curl` or `wget`, `tar` (`.tar.gz`) or `unzip` (`.zip`), `sha256sum` or `shasum`.

##### Platform-Specific Dependencies

- Root/sudo only for system-wide install paths.

#### Installation Steps

Example — Linux x86_64, system-wide install:

```bash
set -e
VERSION="0.15.20"
TARGET="x86_64-unknown-linux-gnu"
ASSET="ruff-${VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/astral-sh/ruff/releases/download/${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/${ASSET}.sha256"
sha256sum -c "${ASSET}.sha256"
tar --no-same-owner -xzf "${ASSET}" "${ASSET%.tar.gz}/ruff"
sudo install -m 0755 "${ASSET%.tar.gz}/ruff" /usr/local/bin/ruff
rm -rf "${ASSET}" "${ASSET}.sha256" "${ASSET%.tar.gz}"
```

#### Installation Verification

- `ruff --version`
- Checksum verification against `.sha256` sidecar or `sha256.sum`.

#### Configuration Options

- **Version Selection**: explicit release tag and asset filename.
- **Installation Path**: fully user-controlled destination.
- **User Targeting**: user-local (`~/.local/bin`) or system-wide (`/usr/local/bin`).
- **Required Privileges**: only for privileged install paths.
- **Tool-Specific Configurations**: none on the artifact itself.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: manual unless destination is already on `PATH`.
- **Configuration Files**: none auto-created.
- **Environment Variables**: none required.
- **Shell Completions**: optional; generate with `ruff generate-shell-completion`.
- **Cleanup**: remove downloaded archives after extraction.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: replace binary with another release artifact.
- **Uninstallation**: remove installed binary; optional receipt/cache cleanup.
- **Idempotency**: deterministic overwrite when using `install -m 0755`.

#### Notes and Best Practices

- Preferred when avoiding `curl | sh` or when mirroring artifacts in controlled build pipelines.
- Community devcontainer feature `devcontainers-extra/ruff` uses this approach via `gh-release` helper.[^extra-feature]
- Always resolve the asset list from the target release tag; `dist-workspace.toml` targets may exceed published artifacts for any given version.

#### Details

1. **Tag format**: plain semver without `v` prefix (`0.15.20`).
2. **Download**: `curl -fsSLO` asset and `.sha256` sidecar from `https://github.com/astral-sh/ruff/releases/download/{tag}/`.
3. **Verify**: `sha256sum -c` (Linux) or `shasum -a 256 -c` (macOS) against sidecar.
4. **Extract**: archive contains `ruff-{version}-{triple}/ruff`; use `tar --no-same-owner` in containers if needed.
5. **Install**: `install -m 0755` to target bin directory already on `PATH`.
6. **No receipt**: unlike standalone installer, manual extraction does not write `$XDG_CONFIG_HOME/ruff/ruff-receipt.json`.

### PyPI Installation (`uv tool`, `pipx`, or `pip`)

#### Supported Platforms

- Prebuilt `py3-none` wheels for many platforms (Linux manylinux/musllinux, macOS, Windows, armv6l, riscv64, etc.).[^pypi-json]
- `requires-python: >=3.7` on PyPI; the installed `ruff` binary itself does not require Python at runtime.[^pypi-json]

#### Dependencies

##### Common Dependencies

- Python 3.7+ environment with `pip`, `pipx`, or `uv`.
- Rust toolchain only if pip falls back to source build (unusual; wheels are published for all tier-1 targets).

#### Installation Steps

Recommended global install via `uv`:[^docs-install]

```bash
uv tool install ruff@latest
uv tool install ruff@0.15.20   # pin version
```

Project dev dependency:

```bash
uv add --dev ruff
```

Alternatives:

```bash
pipx install ruff
pipx install ruff==0.15.20
pip install ruff
pip install ruff==0.15.20
```

#### Installation Verification

- `ruff --version`

#### Configuration Options

- **Version Selection**: `ruff==<version>`, `ruff@<version>` (uv), or `@latest`.
- **Installation Path**: `uv tool` installs to uv's tool directory; `pipx` to `~/.local/pipx/venvs/`; `pip` to active environment.
- **User Targeting**: user-local by default for `pipx`/`uv tool`; `pip --user` or venv-scoped for `pip`.
- **Required Privileges**: none for user-local; system `pip install` may need root.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: ensure `~/.local/bin` (pip/pipx) or uv tool bin directory is on `PATH`.
- **Activation Scripts**: venv activation if installed into a project venv via `pip`.

#### Changing Versions and Uninstallation

- `uv tool upgrade ruff` / `uv tool uninstall ruff`
- `pipx upgrade ruff` / `pipx uninstall ruff`
- `pip uninstall ruff`

#### Notes and Best Practices

- Convenient when Python/uv is already a feature dependency (e.g. `install-uv` + `uv tool install ruff`).
- Couples Ruff version management to Python tooling rather than standalone binary lifecycle.

### Ephemeral Invocation (`uvx`)

#### Supported Platforms

- Any platform where `uv` is installed and can reach PyPI to resolve the `ruff` package.

#### Dependencies

##### Common Dependencies

- `uv` on `PATH`.
- Network access to PyPI (unless `uv` tool cache already contains the requested version).

##### Platform-Specific Dependencies

- None beyond `uv`'s own platform requirements.

#### Installation Steps

No persistent installation; `uvx` creates an ephemeral environment per invocation:[^docs-install]

```bash
uvx ruff check
uvx ruff format
uvx ruff@0.15.20 check   # pin version for this invocation
```

#### Installation Verification

- Command succeeds and prints expected lint/format output.
- `uvx ruff --version` prints the resolved version.

#### Configuration Options

- **Version Selection**: `uvx ruff@<version>` per invocation; defaults to latest resolvable from PyPI.
- **Installation Path**: ephemeral; no persistent binary location.
- **User Targeting**: runs as invoking user; uses uv cache directories.
- **Required Privileges**: none for user invocation.
- **Tool-Specific Configurations**: defers to project `pyproject.toml`/`ruff.toml` like a normal `ruff` invocation.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: only `uv` must be on `PATH`.
- **Configuration Files**: uses project config files; does not create install-time config.
- **Environment Variables**: none required beyond uv's own configuration.
- **Activation Scripts**: none.
- **Shell Completions**: not applicable (no persistent `ruff` binary).
- **Cleanup**: ephemeral environments cleaned by `uv` cache policies.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: change the `@version` suffix per invocation.
- **Uninstallation**: not applicable; clear uv cache if desired.
- **Idempotency**: each invocation resolves independently.

#### Notes and Best Practices

- Useful for one-off CI steps but not ideal as the sole devcontainer install method.
- Requires network on cold resolution unless uv cache is pre-warmed.

### OS Package Manager

#### Supported Platforms

Upstream documents packages for:[^docs-install]

| Manager | Package | Install command |
|---------|---------|-----------------|
| Homebrew / Linuxbrew | `ruff` | `brew install ruff` |
| Conda (conda-forge) | `ruff` | `conda install -c conda-forge ruff` |
| pkgx | `ruff` | `pkgx install ruff` |
| Arch Linux | `ruff` | `pacman -S ruff` |
| Alpine | `ruff` | `apk add ruff` |
| openSUSE Tumbleweed | `python3-ruff` | `zypper install python3-ruff` |

Broader distro coverage is indexed via Repology (linked from upstream installation docs).[^docs-install] Nix/Nixpkgs packages exist via Repology but are not documented in upstream installation.md; treat as out-of-scope unless explicitly added to the feature's OS package manifest.

`devcontainers/features` Python feature can install `ruff` among alternate Python tools via pip in the devcontainer Python environment.[^devcontainers-python]

#### Dependencies

##### Common Dependencies

- Working OS package manager and configured repositories (Conda channels, Homebrew taps, etc.).

##### Platform-Specific Dependencies

- Root/sudo for system-wide package installation on most distros.

#### Installation Steps

Example (Debian/Ubuntu via apt if packaged, or Homebrew on macOS):

```bash
brew install ruff
# or
sudo apt-get update && sudo apt-get install -y ruff   # when available in configured repos
```

#### Installation Verification

- `ruff --version`

#### Configuration Options

- **Version Selection**: package-manager version pins only (e.g. `brew install ruff@0.15.20` when supported); often tracks distro/brew latest.
- **Installation Path**: distro-defined (`/usr/bin`, Homebrew prefix, etc.).
- **User Targeting**: system-wide by default.
- **Required Privileges**: root/sudo on most Linux distros.
- **Tool-Specific Configurations**: none at install time.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: package manager places binary on default system `PATH`.
- **Configuration Files**: none created by package install.
- **Environment Variables**: none required.
- **Activation Scripts**: none.
- **Shell Completions**: may be packaged by distro/Homebrew; not guaranteed.
- **Cleanup**: use package manager remove/purge commands.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: `brew upgrade ruff`, `apt-get install --only-upgrade ruff`, `conda update ruff`, etc.
- **Uninstallation**: `brew uninstall ruff`, `apt-get remove ruff`, `pacman -R ruff`, etc.
- **Idempotency**: package manager handles reinstall semantics.

#### Notes and Best Practices

- Distro versions often lag upstream; not recommended when exact version pinning is required.
- Simple fallback when release binaries are inconvenient and approximate versions suffice.

### Cargo Installation

#### Supported Platforms

- Platforms where Rust/Cargo toolchains are supported and meet MSRV **1.94** (0.15.20).[^cargo-toml]

#### Dependencies

##### Common Dependencies

- Rust toolchain with `cargo` (stable recommended).
- C toolchain and build essentials for compiling Rust crates.

##### Platform-Specific Dependencies

- Network access to crates.io (or vendored sources) during build.

#### Installation Steps

```bash
cargo install --locked ruff
cargo install --locked --version 0.15.20 ruff
```

The `ruff` crate is published to crates.io alongside each release.[^crates-io]

#### Installation Verification

- `ruff --version`
- Binary at `$CARGO_HOME/bin/ruff` (default `~/.cargo/bin/ruff`).

#### Configuration Options

- **Version Selection**: `--version <semver>` or `--git` for non-crates.io sources.
- **Installation Path**: Cargo home `bin/` directory (`$CARGO_HOME/bin` or `~/.cargo/bin`).
- **User Targeting**: per-user by default.
- **Required Privileges**: none for user Cargo home.
- **Tool-Specific Configurations**: `--locked` recommended to honor crate lockfile.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: ensure `$CARGO_HOME/bin` is on `PATH`.
- **Configuration Files**: none for Ruff itself.
- **Environment Variables**: standard `CARGO_HOME`, `RUSTUP_HOME` if customized.
- **Activation Scripts**: none beyond Cargo env snippets some installers add.
- **Shell Completions**: generate manually with `ruff generate-shell-completion` after install.
- **Cleanup**: `cargo uninstall ruff`; optional `cargo cache` cleanup.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: `cargo install --force --locked --version <ver> ruff`
- **Uninstallation**: `cargo uninstall ruff`
- **Idempotency**: Cargo overwrites same-name binary on reinstall with `--force`.

#### Notes and Best Practices

- Compiles from source; significantly slower than prebuilt binary methods.
- Fallback for uncommon platforms without published release artifacts or PyPI wheels.

### Docker Image Usage

#### Supported Platforms

- Container runtimes with access to `ghcr.io` (Docker, Podman, etc.).

#### Dependencies

##### Common Dependencies

- Container engine installed and configured.
- Network access to pull `ghcr.io/astral-sh/ruff` images.

##### Platform-Specific Dependencies

- Podman on SELinux hosts may require `:Z` volume flag (documented upstream).[^docs-install]

#### Installation Steps

Ruff publishes `ghcr.io/astral-sh/ruff` with tags `latest`, `{major}.{minor}.{patch}`, `{major}.{minor}`, and base-image variants (`alpine`, `debian-slim`, `bookworm`, etc.).[^docs-install][^docs-integrations]

```bash
docker run -v .:/io --rm ghcr.io/astral-sh/ruff check
docker run -v .:/io --rm ghcr.io/astral-sh/ruff:0.15.20-alpine check
# Podman on SELinux:
docker run -v .:/io:Z --rm ghcr.io/astral-sh/ruff check
```

This provides `ruff` inside the container only; it does not install `ruff` on the host/devcontainer `PATH`.

#### Installation Verification

- `docker run --rm ghcr.io/astral-sh/ruff:0.15.20 --version`

#### Configuration Options

- **Version Selection**: image tag (`0.15.20`, `0.15.20-alpine`, `latest`, etc.).
- **Installation Path**: N/A (container-local `/usr/local/bin` or image-defined path).
- **User Targeting**: N/A.
- **Required Privileges**: container engine permissions (often rootful Docker or rootless Podman setup).
- **Tool-Specific Configurations**: mount workspace at `/io` per upstream examples.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: not applicable on host; invoke via `docker run`.
- **Configuration Files**: mount project config into container workspace.
- **Environment Variables**: pass via `docker run -e` if needed.
- **Activation Scripts**: none.
- **Cleanup**: `docker image rm ghcr.io/astral-sh/ruff:<tag>` to remove pulled images.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: pull/run a different image tag.
- **Uninstallation**: remove local image layers.
- **Idempotency**: pulling same tag is idempotent modulo tag movement for `latest`.

#### Notes and Best Practices

- Complementary to host PATH install; common in GitLab CI per upstream docs.[^docs-integrations]
- Not a substitute for installing `ruff` on the devcontainer `PATH` when editor integration needs `ruff server` locally.

## Dev Container Setup

Ruff works in standard devcontainer environments without special runtime privileges. Key considerations:

- **Recommended devcontainer recipe** (Python-independent, no profile mutation):

```bash
curl -LsSf https://astral.sh/ruff/0.15.20/install.sh | env RUFF_UNMANAGED_INSTALL=/usr/local/bin sh
```

`RUFF_UNMANAGED_INSTALL` forces install to `/usr/local/bin`, disables PATH profile mutation, and skips install receipt/updater side effects. Equivalent: direct GitHub release binary via `install -m 0755` with `RUFF_NO_MODIFY_PATH=1` if using the default installer path logic.

- Alternative when `install-uv` is already present: `uv tool install ruff@0.15.20` (ensure uv tool bin dir is on `PATH`).
- **Platform mapping in containers**:
  - Debian/Ubuntu devcontainers (x86_64): `x86_64-unknown-linux-gnu` tarball or standalone installer.
  - Debian/Ubuntu devcontainers (arm64): `aarch64-unknown-linux-gnu` tarball.
  - Alpine devcontainers (x86_64): `x86_64-unknown-linux-musl` or `apk add ruff`.
  - Alpine devcontainers (arm64): `aarch64-unknown-linux-musl` or `apk add ruff`.
- **Dependencies during build**: ensure `curl`, `ca-certificates`, and `tar` are available before downloading.
- **PATH**: `/usr/local/bin` is standard in devcontainers and avoids installer profile edits when combined with `RUFF_UNMANAGED_INSTALL`.
- **Podman/SELinux**: for containerized CI invoking the Ruff Docker image, use `-v .:/io:Z` per upstream docs.[^docs-install]
- **No entrypoint or lifecycle commands** required for basic CLI usage.
- **Configuration scaffolding**: optionally write a starter `pyproject.toml` `[tool.ruff]` section or `ruff.toml` in the workspace; not required for the binary to function.
- **VS Code integration**: install extension `charliermarsh.ruff` (extension ID used by community feature).[^extra-feature-json] The extension uses `ruff server` from PATH; recommend extension version `2024.32.0` or later per upstream editor docs.[^docs-editors-setup]
- **CI in devcontainers**: `ruff check --output-format=github` for GitHub Actions annotations; `ruff check --output-format=gitlab` for GitLab code quality reports.[^docs-integrations]

**Comparable devcontainer features:**

| Feature | Method | Version pinning | Notes |
|---------|--------|----------------|-------|
| `devcontainers-extra/ruff` | GitHub release via `gh-release` helper | Yes (`version` option, default `latest`) | Adds VS Code extension `charliermarsh.ruff`[^extra-feature] |
| `devcontainers/features` (python) | pip install among alternate tools | Via Python feature version/options | Installs into devcontainer Python env, not standalone binary[^devcontainers-python] |

## Plugins and Extensions

### VS Code Extension (`charliermarsh.ruff`)

- **Marketplace**: https://marketplace.visualstudio.com/items?itemName=charliermarsh.ruff
- **Source Code**: https://github.com/astral-sh/ruff-vscode
- **Architecture**: Editor extension that invokes `ruff server` (native server introduced in Ruff **0.3.5**; VS Code extension auto-selects it when `ruff` ≥ **0.5.3**).[^docs-editors-migration][^docs-editors-setup] Upstream recommends disabling the legacy `ruff-lsp` package to avoid conflicts.[^docs-editors-setup]
- **Versioning**: Extension uses a separate CalVer scheme (even minor = stable, odd minor = preview) distinct from the `ruff` CLI version.[^docs-versioning-vscode]
- **Installation**: via VS Code marketplace or `devcontainer.json` `customizations.vscode.extensions`.

### `ruff-lsp` (legacy)

- **Source Code**: https://github.com/astral-sh/ruff-lsp
- **Notes**: Separate Python-based language server superseded by `ruff server`. Upstream recommends disabling it when using the native server.[^docs-editors-setup]

### `ruff-pre-commit`

- **Source Code**: https://github.com/astral-sh/ruff-pre-commit
- **Installation**: pre-commit hook repo `https://github.com/astral-sh/ruff-pre-commit` with `rev: v<version>` (note `v` prefix on hook repo tags).[^docs-integrations]

### `ruff-action` (GitHub Actions)

- **Source Code**: https://github.com/astral-sh/ruff-action
- **Usage**: `uses: astral-sh/ruff-action@v3` with optional `version`, `args`, `src` inputs.[^docs-integrations]

## References

[^readme]: [Ruff README](https://raw.githubusercontent.com/astral-sh/ruff/main/README.md) — Tool overview, feature list, installation quickstart, Python 3.14 compatibility claim, and links to docs.

[^docs-install]: [Ruff Installation Guide](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/installation.md) — Official installation methods: uv/uvx, pip/pipx, standalone installers, Homebrew, Conda, pkgx, distro packages, Docker.

[^docs-linter]: [The Ruff Linter](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/linter.md) — `ruff check` usage, rule selection, recommended configurations.

[^docs-formatter]: [The Ruff Formatter](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/formatter.md) — `ruff format` usage, Black compatibility, import sorting workflow.

[^docs-config]: [Configuring Ruff](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/configuration.md) — Config file types, precedence, `--config` flag, default settings, discovery rules.

[^docs-config-defaults]: [Configuring Ruff — Default configuration](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/configuration.md) — Built-in defaults for line length, rules, formatter options.

[^docs-config-discovery]: [Configuring Ruff — Config file discovery](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/configuration.md) — Hierarchical config, `extend`, `target-version` inference from `requires-python`.

[^docs-faq-user-config]: [Ruff FAQ — User-level config](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/faq.md) — `~/.config/ruff/ruff.toml` fallback behavior.

[^docs-preview]: [Ruff Preview Mode](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/preview.md) — Enabling preview for lint and format separately.

[^docs-versioning]: [Ruff Versioning](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/versioning.md) — Pre-1.0 minor/patch semantics, rule stabilization, MSRV policy.

[^docs-versioning-vscode]: [Ruff Versioning — VS Code Extension](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/versioning.md) — Extension CalVer stable/preview scheme.

[^docs-integrations]: [Ruff Integrations](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/integrations.md) — GitHub Actions, GitLab CI, pre-commit, Docker image tags.

[^docs-editors-setup]: [Ruff Editor Setup](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/editors/setup.md) — VS Code extension, Neovim `ruff server` configuration, `ruff-lsp` deprecation.

[^docs-formatter-imports]: [Ruff Formatter — Sorting imports](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/formatter.md) — `ruff check --select I --fix` then `ruff format`.

[^release-latest]: [Latest Ruff Release API](https://api.github.com/repos/astral-sh/ruff/releases/latest) — Authoritative tag `0.15.20`, publish timestamp 2026-06-25.

[^release-01520]: [Ruff 0.15.20 Release Assets](https://github.com/astral-sh/ruff/releases/tag/0.15.20) — Per-platform tarballs/zips, `.sha256` sidecars, `sha256.sum`, installer scripts.

[^pypi-json]: [PyPI ruff 0.15.20 JSON](https://pypi.org/pypi/ruff/0.15.20/json) — Wheel platforms, `requires-python >=3.7`.

[^dist-workspace]: [Ruff `dist-workspace.toml`](https://raw.githubusercontent.com/astral-sh/ruff/main/dist-workspace.toml) — cargo-dist targets, `install-updater = false`, install path, hosting URLs.

[^installer-sh]: [Ruff Shell Installer 0.15.20](https://github.com/astral-sh/ruff/releases/download/0.15.20/ruff-installer.sh) — cargo-dist installer (also served via `https://astral.sh/ruff/install.sh` redirect): env vars, arch detection, glibc fallback, `sha256sum`-only checksum verification, PATH mutation, receipt.

[^src-user-config]: [Ruff `find_user_settings_toml()`](https://raw.githubusercontent.com/astral-sh/ruff/main/crates/ruff_workspace/src/pyproject.rs) — Authoritative user-config search order: `.ruff.toml`, `ruff.toml`, `pyproject.toml` under `${config_dir}/ruff/`.

[^crates-io]: [crates.io — `ruff` crate](https://crates.io/crates/ruff) — Published crate for `cargo install`.

[^docs-editors-migration]: [Ruff Editor Migration Guide](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/editors/migration.md) — Native `ruff server` introduced in 0.3.5; VS Code extension uses it for Ruff ≥0.5.3.

[^args-rs]: [Ruff CLI Args (`args.rs`)](https://raw.githubusercontent.com/astral-sh/ruff/main/crates/ruff/src/args.rs) — Subcommands, global flags, completions subcommand.

[^cargo-toml]: [Ruff Workspace `Cargo.toml`](https://raw.githubusercontent.com/astral-sh/ruff/main/Cargo.toml) — MSRV `rust-version = "1.94"`, crate versions.

[^extra-feature]: [devcontainers-extra/ruff `install.sh`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/ruff/install.sh) — Community feature using `gh-release` with `repo=astral-sh/ruff`.

[^extra-feature-json]: [devcontainers-extra/ruff `devcontainer-feature.json`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/ruff/devcontainer-feature.json) — Feature options and VS Code extension customization.

[^devcontainers-python]: [devcontainers/features Python alternate tools test](https://raw.githubusercontent.com/devcontainers/features/main/test/python/install_alternate_tools.sh) — Installs `ruff` via pip among optional Python tools.
