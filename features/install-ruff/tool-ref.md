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

Primary CLI commands: `ruff check` (lint), `ruff format` (format), `ruff server` (language server), `ruff clean` (clear `.ruff_cache`), `ruff version` / `ruff --version`.[^docs-linter][^docs-formatter][^args-rs] Import sorting: `ruff check --select I --fix` then `ruff format`.[^docs-formatter-imports] Preview mode (`--preview` or `preview = true` in config) gates unstable rules and formatter changes.[^docs-preview] Ruff uses a custom pre-1.0 versioning scheme where minor versions may break and patch versions fix bugs.[^docs-versioning]

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
| Linux | x86_64 (glibc ≥2.31) | `x86_64-unknown-linux-gnu` | `ruff-x86_64-unknown-linux-gnu.tar.gz` |
| Linux | x86_64 (musl / old glibc fallback) | `x86_64-unknown-linux-musl` | `ruff-x86_64-unknown-linux-musl.tar.gz` |
| Linux | arm64 (glibc ≥2.31) | `aarch64-unknown-linux-gnu` | `ruff-aarch64-unknown-linux-gnu.tar.gz` |
| Linux | arm64 (musl) | `aarch64-unknown-linux-musl` | `ruff-aarch64-unknown-linux-musl.tar.gz` |
| Linux | armv7 (glibc) | `armv7-unknown-linux-gnueabihf` | `ruff-armv7-unknown-linux-gnueabihf.tar.gz` |
| Linux | armv7 (musl) | `armv7-unknown-linux-musleabihf` | `ruff-armv7-unknown-linux-musleabihf.tar.gz` |
| Linux | armv6 | `arm-unknown-linux-musleabihf` | `ruff-arm-unknown-linux-musleabihf.tar.gz` |
| Linux | i686 (glibc) | `i686-unknown-linux-gnu` | `ruff-i686-unknown-linux-gnu.tar.gz` |
| Linux | i686 (musl) | `i686-unknown-linux-musl` | `ruff-i686-unknown-linux-musl.tar.gz` |
| Linux | ppc64le | `powerpc64le-unknown-linux-gnu` | `ruff-powerpc64le-unknown-linux-gnu.tar.gz` |
| Linux | riscv64 | `riscv64gc-unknown-linux-gnu` | `ruff-riscv64gc-unknown-linux-gnu.tar.gz` |
| Linux | s390x | `s390x-unknown-linux-gnu` | `ruff-s390x-unknown-linux-gnu.tar.gz` |
| macOS | arm64 | `aarch64-apple-darwin` | `ruff-aarch64-apple-darwin.tar.gz` |
| macOS | x86_64 | `x86_64-apple-darwin` | `ruff-x86_64-apple-darwin.tar.gz` |
| Windows | x86_64 (MSVC) | `x86_64-pc-windows-msvc` | `ruff-x86_64-pc-windows-msvc.zip` |
| Windows | arm64 (MSVC) | `aarch64-pc-windows-msvc` | `ruff-aarch64-pc-windows-msvc.zip` |
| Windows | i686 (MSVC) | `i686-pc-windows-msvc` | `ruff-i686-pc-windows-msvc.zip` |

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

Each archive contains a top-level directory `ruff-{target-triple}/` with the `ruff` binary (or `ruff.exe` on Windows). Per-asset `.sha256` sidecar files and a `sha256.sum` manifest are published.[^release-01520]

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
ASSET="ruff-${TARGET}.tar.gz"
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
6. **No receipt by default**: unlike the standalone installer, manual extraction does not write `$XDG_CONFIG_HOME/ruff/ruff-receipt.json`. The DevFeats `install-ruff` feature replicates this receipt on the **`method.binary`** path (via `configure_users: true` and a `__configure_user` hook), matching [`install-uv`](../../install-uv/install.bash).

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
- **Shell Completions**: optional; generate with `ruff generate-shell-completion <shell>` after install.[^args-rs]

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: `uv tool upgrade ruff` / `pipx upgrade ruff` / `pip install --upgrade ruff` (or explicit version pin).
- **Uninstallation**: `uv tool uninstall ruff` / `pipx uninstall ruff` / `pip uninstall ruff`
- **Idempotency**: reinstalling the same version is a no-op or overwrites per package-manager semantics; `uv tool install`/`pipx install` fail if already installed unless upgrade/reinstall flags are used.

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
| Fedora | `ruff` | `dnf install ruff` |
| openSUSE Tumbleweed | `python3-ruff` | `zypper install python3-ruff` |

Broader distro coverage is indexed via Repology (linked from upstream installation docs).[^docs-install] Nix/Nixpkgs packages exist via Repology but are not documented in upstream installation.md; treat as out-of-scope unless explicitly added to the feature's OS package manifest.

`devcontainers/features` Python feature can install `ruff` among alternate Python tools via pip in the devcontainer Python environment.[^devcontainers-python]

**Not recommended for DevFeats `ospkg`**: Conda, pkgx, PyPI/uv/pipx (separate install paths), Nix, MacPorts, Gentoo, BSD pkg systems, Void, Windows package managers, Docker-only images.

#### DevFeats-supported package managers — availability matrix

DevFeats `ospkg` supports **`apt`**, **`apk`**, **`brew`**, **`dnf`/`yum`**, **`pacman`**, and **`zypper`**. The table below states whether `ruff` is installable with a **plain** `method-package` manifest (`packages: [ruff]`) — i.e., without adding extra repositories, keys, or vendor-specific `upstream-package` manifests.

| PM | Distros / images | Package name | In default repos? | Extra repo / key setup | Sample version (2026-06-29) | Primary source | DevFeats `method.package`? |
|----|------------------|--------------|-------------------|------------------------|----------------------------|----------------|----------------------------|
| **brew** | macOS, Linuxbrew | `ruff` | Yes (`homebrew-core`) | No | 0.15.20 | [formulae.brew.sh API](https://formulae.brew.sh/api/formula/ruff.json) | Yes |
| **pacman** | Arch | `ruff` | Yes (`extra`) | No | 0.15.20-1 | [archlinux.org JSON](https://archlinux.org/packages/extra/x86_64/ruff/json/) | Yes |
| **apk** | Alpine | `ruff` | Yes (`community`) | No | lags upstream | [pkgs.alpinelinux.org](https://pkgs.alpinelinux.org/package/edge/community/x86_64/ruff) | Yes |
| **dnf / yum** | Fedora | `ruff` | Yes (base repos) | No | 0.15.16–0.15.20 | [packages.fedoraproject.org](https://packages.fedoraproject.org/pkgs/ruff/ruff/) | Yes — `os.id: fedora` |
| **dnf / yum** | RHEL, Rocky, Alma, CentOS Stream, Oracle Linux | `ruff` | **No** (base) | **Yes — EPEL** (+ CRB on host) | 0.15.16–0.15.20 on EPEL 10 | [packages.fedoraproject.org EPEL 10](https://packages.fedoraproject.org/pkgs/ruff/ruff/epel-10.html) | Yes — EPEL via `_internal.epel_rhel_family` in `method-package` manifest[^devfeats-epel-internal] |
| **zypper** | openSUSE | **`python3-ruff`** | Yes | No | verify at install time | [upstream installation.md](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/installation.md) | Yes — `zypper: python3-ruff` alias |
| **apt** | Debian **sid** only | `ruff` | Yes (unstable) | No | 0.0.291+dfsg1-4 (stale) | [packages.debian.org sid/ruff](https://packages.debian.org/sid/ruff) | Maybe — narrow `when`; not Repology-sourced |
| **apt** | Debian bookworm/trixie | — | **No** | — | — | packages.debian.org | No |
| **apt** | Ubuntu noble–resolute | — | **No** | — | — | packages.ubuntu.com | No |

**Channels documented upstream but out of DevFeats `ospkg` scope** (document in tool-ref, do not implement as `method.package`):

| Channel | Package | Notes |
|---------|---------|-------|
| Conda (conda-forge) | `ruff` | 0.15.20 via anaconda.org; use [`install-miniforge`](../../install-miniforge/metadata.yaml) / conda workflows |
| pkgx | `ruff` | Upstream install.md only |
| PyPI / uv / pipx | `ruff` | Separate install path; not ospkg |
| Nix / Nixpkgs | `ruff` | Repology; tool-ref defers Nix |
| MacPorts | `ruff` | No macports ospkg backend |
| Gentoo | `dev-python/ruff` | Portage category path |
| FreeBSD / OpenBSD / NetBSD | `ruff` / `py*-ruff` | pkg systems not in ospkg |
| Void | `ruff` | xbps not in ospkg |
| Docker | `ghcr.io/astral-sh/ruff` | Container-only (separate section) |

**`upstream-package` vs EPEL**: EPEL on RHEL is **`method.package`**, not `upstream-package`. EPEL is a Fedora community third-party repo — not Astral's vendor repo. DevFeats models RHEL-family support as **EPEL entries in the `method-package` dependency manifest** (shared via `_internal.epel_rhel_family` in [`metadata.shared.yaml`](../../metadata.shared.yaml)), the same pattern as [`install-ripgrep`](../../install-ripgrep/metadata.yaml). Astral publishes no vendor apt/dnf repo for Ruff.

#### Dependencies

##### Common Dependencies

- Working OS package manager and configured repositories (Conda channels, Homebrew taps, etc.).

##### Platform-Specific Dependencies

- Root/sudo for system-wide package installation on most distros.
- **RHEL-family (dnf/yum)**: EPEL GPG key + repo (configured in the feature's `method-package` manifest via shared `_internal.epel_rhel_family`) and **CRB / codeready-builder / PowerTools** enabled on the host per EPEL documentation before `dnf install ruff` succeeds.

#### Installation Steps

```bash
# Homebrew (macOS/Linux)
brew install ruff

# Arch
sudo pacman -S --noconfirm ruff

# Alpine (community repo)
sudo apk add --no-cache ruff

# Fedora (base repos — no EPEL)
sudo dnf install -y ruff

# openSUSE (note package name)
sudo zypper install -y python3-ruff

# Debian sid only (when packaged; version may lag upstream)
sudo apt-get update && sudo apt-get install -y ruff
```

EPEL setup (required on **RHEL-compatible** systems before `dnf install ruff`; **not** required on Fedora):[^fedora-ruff-epel]

```bash
# Pattern for RHEL-compatible clones — replace {N} with 8, 9, or 10:
sudo dnf config-manager --set-enabled crb
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-{N}.noarch.rpm
sudo dnf install -y ruff
```

The DevFeats `install-ruff` feature configures EPEL keys/repos automatically in its `method-package` manifest (via `_internal.epel_rhel_family`); CRB/PowerTools enablement remains a host prerequisite.

#### Installation Verification

```bash
command -v ruff
ruff --version
```

Package-manager level verification:

```bash
brew info ruff          # Homebrew
dnf info ruff           # Fedora / EPEL
apk info ruff           # Alpine
zypper info python3-ruff  # openSUSE
dpkg -s ruff            # Debian sid
```

#### Configuration Options

- **Version Selection**: package-manager version pins only (e.g. `brew install ruff@0.15.20` when supported); often tracks distro/brew latest. Debian sid ships `0.0.291+dfsg1-4`, which does not match upstream semver.
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

- **Upgrading/Downgrading**: `brew upgrade ruff`, `dnf upgrade ruff`, `apk upgrade ruff`, etc.
- **Uninstallation**: `brew uninstall ruff`, `apt-get remove ruff`, `pacman -R ruff`, etc.
- **Idempotency**: package manager handles reinstall semantics.

#### Notes and Best Practices

- Distro versions often lag upstream; not recommended when exact version pinning is required.
- **Do not conflate Fedora and RHEL-family**: `dnf install ruff` succeeds on Fedora without EPEL but **fails** on stock RHEL/Rocky/Alma/CentOS Stream images until EPEL (and typically CRB) is configured.
- **Ubuntu is not packaged** (noble through resolute as of 2026-06-29); use `method=binary` or `method=cargo` on Ubuntu devcontainers.
- **Debian sid** has `ruff` but at a very stale version; cite [packages.debian.org](https://packages.debian.org/sid/ruff) directly (Repology may not list Debian for Ruff).
- **`registers_as: ruff`** should be set so `method=auto` PM version checks query `ruff`.
- **openSUSE** package name is **`python3-ruff`**, not `ruff`; use the `zypper:` alias in the manifest.
- Simple fallback when release binaries are inconvenient and approximate versions suffice.

#### Implementation implication

A DevFeats feature using `method.package` and `_dependencies.run.method-package` works on **apk, brew, Fedora dnf, pacman, and zypper** out of the box. **RHEL-family dnf/yum** requires the shared EPEL manifest entry (`_internal.epel_rhel_family` + pyserials substitution). **Debian sid** may be included with a narrow `when` if desired. **Ubuntu apt** should be excluded. No `upstream-package` method — Astral has no vendor OS repo.

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

- **Recommended DevFeats recipe** (Python-independent, version-pinned, no shell profile mutation):

  Use the [`install-ruff`](../../install-ruff/metadata.yaml) feature with `method=binary` (or `method=auto`, which selects binary on supported platforms). The feature downloads the matching GitHub release tarball with SHA-256 verification, installs `ruff` to the configured prefix (default `/usr/local/bin`), and writes `$XDG_CONFIG_HOME/ruff/ruff-receipt.json` per user via `configure_users: true` — replicating the standalone installer's receipt side effect without `curl | sh`.

  ```json
  {
    "features": {
      "ghcr.io/quantized8/devfeats/install-ruff:0.1.0": {
        "version": "0.15.20",
        "method": "binary"
      }
    }
  }
  ```

- **Manual binary install** (when not using the feature): download the matching GitHub release tarball and `install -m 0755` the `ruff` binary to `/usr/local/bin`. Optionally write the install receipt manually if tooling expects it.
- **Not recommended for DevFeats features**: `curl -LsSf https://astral.sh/ruff/0.15.20/install.sh | env RUFF_UNMANAGED_INSTALL=/usr/local/bin sh` — DevFeats uses `method.binary` (direct tarball + sidecar), not `method.script`, for cargo-dist installers without tool-specific logic.
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
- **Architecture**: Editor extension that invokes `ruff server` (native server introduced in Ruff **0.3.5**; VS Code extension auto-selects it when `ruff` executable ≥ **0.5.3** and `ruff.nativeServer` is `auto`).[^docs-editors-migration][^ruff-vscode-readme] Upstream recommends disabling the legacy `ruff-lsp` package to avoid conflicts.[^docs-editors-setup]
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

[^docs-editors-migration]: [Ruff Editor Migration Guide](https://raw.githubusercontent.com/astral-sh/ruff/main/docs/editors/migration.md) — Native `ruff server` introduced in 0.3.5; stabilized in 0.5.3.

[^ruff-vscode-readme]: [Ruff VS Code Extension README](https://raw.githubusercontent.com/astral-sh/ruff-vscode/main/README.md) — `ruff.nativeServer=auto` selects native server when executable ≥ 0.5.3.

[^args-rs]: [Ruff CLI Args (`args.rs`)](https://raw.githubusercontent.com/astral-sh/ruff/main/crates/ruff/src/args.rs) — Subcommands, global flags, completions subcommand.

[^cargo-toml]: [Ruff Workspace `Cargo.toml`](https://raw.githubusercontent.com/astral-sh/ruff/main/Cargo.toml) — MSRV `rust-version = "1.94"`, crate versions.

[^extra-feature]: [devcontainers-extra/ruff `install.sh`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/ruff/install.sh) — Community feature using `gh-release` with `repo=astral-sh/ruff`.

[^extra-feature-json]: [devcontainers-extra/ruff `devcontainer-feature.json`](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/ruff/devcontainer-feature.json) — Feature options and VS Code extension customization.

[^devcontainers-python]: [devcontainers/features Python alternate tools test](https://raw.githubusercontent.com/devcontainers/features/main/test/python/install_alternate_tools.sh) — Installs `ruff` via pip among optional Python tools.

[^fedora-ruff-epel]: [Fedora Packages — ruff on EPEL 10](https://packages.fedoraproject.org/pkgs/ruff/ruff/epel-10.html) — Confirms `ruff` in EPEL for Enterprise Linux 10; verify EL 8/9 during feature testing.

[^devfeats-epel-internal]: [DevFeats `metadata.shared.yaml`](../../metadata.shared.yaml) — Shared `_internal.epel_rhel_family` fragment referenced via pyserials in feature `_dependencies.run.method-package.packages`.
