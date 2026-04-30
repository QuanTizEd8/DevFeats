# Feature Reference

uv is a Rust-based Python package and project manager from Astral. It covers package management, lockfiles, tool execution (`uvx`), Python runtime installation, and pip-compatible workflows in a single CLI. Upstream documents multiple install paths (standalone installer, package managers, release binaries, and source-based methods), with the standalone installer as the primary cross-platform path.

- **Homepage**: https://astral.sh/uv
- **Source Code**: https://github.com/astral-sh/uv
- **Documentation**: https://docs.astral.sh/uv/
- **Latest Release**: 0.11.8 (as of 2026-04-30)

## Available Installation Methods

Upstream supports installation via a standalone installer script, direct release artifacts, PyPI (via `pipx` or `pip`), system package managers like Homebrew and MacPorts, and Cargo. For SysSet's macOS/Linux scope, the most implementation-relevant methods are: standalone installer, direct release binary extraction, PyPI, Homebrew/MacPorts, and Cargo.

### Standalone Installer Script

#### Supported Platforms

- macOS and Linux are first-class for the shell installer (`install.sh`).
- Windows uses a PowerShell installer (`install.ps1`) and is documented separately upstream.
- The installer maps host OS/arch to published artifacts and includes Linux libc-aware selection logic (glibc baseline checks with musl fallback where available).

#### Dependencies

- **Common Dependencies**: `curl` or `wget` downloader, plus basic Unix tools used by the script (`uname`, `mktemp`, `chmod`, `mkdir`, `rm`, `tar`, `grep`, `cat`).
- **Platform-Specific Dependencies**: Linux code paths also use utilities like `ldd`, `awk`, `head`, `tail`, and may use `getent` if `$HOME` is missing. Checksum verification uses available tools (`sha256sum`, etc.); if missing, verification is skipped with a message.

#### Installation Steps

1. Install latest on macOS/Linux:
   - `curl -LsSf https://astral.sh/uv/install.sh | sh`
2. Alternative downloader:
   - `wget -qO- https://astral.sh/uv/install.sh | sh`
3. Pin a specific version by URL path:
   - `curl -LsSf https://astral.sh/uv/0.11.8/install.sh | sh`
4. The installer selects an artifact for the detected platform, downloads from mirror-first URLs, verifies embedded checksums when checksum tools exist, extracts binaries, installs to a resolved executable directory, and optionally updates shell PATH config.

#### Installation Verification

- Command checks:
  - `uv --version`
  - `uvx --version`
- Integrity checks:
  - The installer embeds expected SHA256 values per artifact and verifies them when supported checksum tools are present.
  - Release pages also publish `sha256` files and GitHub artifact attestations (`gh attestation verify ... --repo astral-sh/uv`).

#### Configuration Options

- **Version Selection**: pin by using versioned installer URLs (`.../uv/<version>/install.sh`).
- **Installation Path**: set `UV_INSTALL_DIR` to force the install directory.
- **User Targeting**: default behavior is user-local install into executable-directory resolution order (`$XDG_BIN_HOME`, `$XDG_DATA_HOME/../bin`, `$HOME/.local/bin`).
- **Required Privileges**: no root required for user-local install; root/sudo required only if targeting privileged directories.
- **Tool-Specific Configurations**:
  - `UV_NO_MODIFY_PATH=1`: disable shell profile PATH edits.
  - `UV_UNMANAGED_INSTALL=/path`: install to fixed path, disable profile edits and disable self-updates.
  - `UV_DISABLE_UPDATE=1`: skip updater/receipt install behavior.
  - `UV_DOWNLOAD_URL` / `INSTALLER_DOWNLOAD_URL`: override artifact download base URL.
  - `UV_INSTALLER_GITHUB_BASE_URL` / `UV_INSTALLER_GHE_BASE_URL`: alternate GitHub base URL routing.
  - `UV_GITHUB_TOKEN`: auth token for GitHub downloads.
  - `UV_PRINT_VERBOSE` / `UV_PRINT_QUIET`: installer output verbosity controls.
  - Script flags include `--help`, `--verbose`, `--quiet`, and deprecated `--no-modify-path`.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: by default the installer writes profile sourcing lines for sh/bash/zsh/fish targets and adds CI path hints via `GITHUB_PATH`; this can be disabled with `UV_NO_MODIFY_PATH`.
- **Configuration Files**: standalone installs write an install receipt (for updater tracking) under uv config directories.
- **Environment Variables**: no mandatory runtime env vars are required for normal use.
- **Activation Scripts**: profile updates source generated env snippets (`env`/`env.fish`) when PATH modification is enabled.
- **Cleanup**: installer removes temporary download directories; optional user cleanup is covered in uninstallation.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Standalone installs support `uv self update`.
  - Upgrades can also be forced by rerunning installer with a versioned URL.
  - `UV_UNMANAGED_INSTALL` disables self-update behavior.
- **Uninstallation**:
  - Optional data cleanup:
    - `uv cache clean`
    - `rm -r "$(uv python dir)"`
    - `rm -r "$(uv tool dir)"`
  - Remove executables (typical default path):
    - `rm ~/.local/bin/uv ~/.local/bin/uvx`
  - For legacy installs before 0.5.0, old binaries may remain under `~/.cargo/bin`.
- **Idempotency**: rerunning installer is safe; it updates binaries in-place and avoids duplicate PATH entries by checking existing shell config/PATH state.

#### Notes and Best Practices

- In CI/ephemeral environments, prefer `UV_UNMANAGED_INSTALL` to prevent shell profile mutation and disable self-update side effects.
- For reproducibility, pin an explicit versioned installer URL instead of `latest`.
- For higher supply-chain assurance, verify release checksums and GitHub attestations in addition to installer checksum verification.

### Direct GitHub Release Artifact Installation

#### Supported Platforms

- Official release artifacts are published for Tier 1 and Tier 2 uv platforms (macOS, Linux, Windows families documented in platform policy and release assets).

#### Dependencies

- **Common Dependencies**: downloader (`curl`/`wget`) and extraction tooling (`tar` for `.tar.gz`, unzip tooling for `.zip` where applicable).
- **Platform-Specific Dependencies**: optional checksum utilities (`sha256sum`) and optional GitHub CLI for attestation verification.

#### Installation Steps

1. Choose a release and matching artifact from `astral-sh/uv` GitHub Releases.
2. Download artifact and checksum sidecar (`.sha256`) or checksum manifest.
3. Verify checksums.
4. Extract `uv` and `uvx` binaries to desired executable directory.
5. Ensure the target directory is on PATH.

#### Installation Verification

- `uv --version`
- `uvx --version`
- Optional attestation verification with `gh attestation verify` as documented in release notes.

#### Configuration Options

- **Version Selection**: explicit by release tag and asset filename.
- **Installation Path**: fully user-controlled (where extracted/copied).
- **User Targeting**: user-local or system-wide based on destination directory.
- **Required Privileges**: only required when writing privileged paths.
- **Tool-Specific Configurations**: release archives themselves are static artifacts; runtime behavior comes from uv configuration, not installer flags.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: manual profile updates are required unless destination is already on PATH.
- **Configuration Files**: none are auto-created by manual archive extraction.
- **Environment Variables**: none required for baseline operation.
- **Activation Scripts**: none required.
- **Cleanup**: remove downloaded archives/checksum files after extraction.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: replace binaries with another tagged release artifact.
- **Uninstallation**: remove installed binaries and optional uv data directories.
- **Idempotency**: repeated extract/copy steps are deterministic if destination overwrite behavior is controlled.

#### Notes and Best Practices

- This method is often used when avoiding `curl | sh`, when pinning exact release assets, or in controlled offline-ish build pipelines where artifacts are mirrored.
- Unlike standalone installer-managed installs, manual extraction may not set up updater receipt state expected by `uv self update`.

### PyPI Installation (`pipx` or `pip`)

#### Supported Platforms

- uv is published to PyPI with many prebuilt wheels.
- If a wheel is unavailable for a platform, installation falls back to source build, which requires Rust toolchain availability.

#### Dependencies

- **Common Dependencies**: Python environment plus `pip` or `pipx`.
- **Platform-Specific Dependencies**: Rust toolchain if source build is needed.

#### Installation Steps

1. Preferred isolated install:
   - `pipx install uv`
2. Alternative install:
   - `pip install uv`

#### Installation Verification

- `uv --version`
- `uvx --version` (if entry point is exposed in the chosen environment)

#### Configuration Options

- **Version Selection**: standard package-manager pinning (for example, `uv==<version>`).
- **Installation Path**: controlled by `pipx` environment layout or active Python environment for `pip`.
- **User Targeting**: user-local (`pipx`, `pip --user`), virtualenv-local, or system-level depending on command usage.
- **Required Privileges**: not required for user/venv installs; system-wide installs may require elevated privileges.
- **Tool-Specific Configurations**: wheel/source selection is automatic based on platform wheel availability.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: ensure package-manager-managed binary directory is on PATH.
- **Configuration Files**: none required for base install.
- **Environment Variables**: none required for base install.
- **Activation Scripts**: depends on Python environment strategy (venv activation if used).
- **Cleanup**: optional package-manager cache cleanup.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: use package manager (`pipx upgrade uv`, `pip install --upgrade uv`, or explicit version pin).
- **Uninstallation**: `pipx uninstall uv` or `pip uninstall uv`.
- **Idempotency**: managed by package manager semantics.

#### Notes and Best Practices

- Upstream explicitly states self-update is disabled when uv is installed via non-standalone methods; use the package manager to update.
- `pipx` is recommended upstream for isolation.

### System Package Managers (Homebrew and MacPorts)

#### Supported Platforms

- Homebrew: supported where Homebrew is available (macOS and Linuxbrew environments).
- MacPorts: available on macOS.

#### Dependencies

- **Common Dependencies**: package manager bootstrap (`brew` or `port`).
- **Platform-Specific Dependencies**: manager-specific runtime dependencies resolved by the manager.

#### Installation Steps

1. Homebrew:
   - `brew install uv`
2. MacPorts:
   - `sudo port install uv`

#### Installation Verification

- `uv --version`
- `uvx --version` (if packaged/exported by the selected manager package)

#### Configuration Options

- **Version Selection**: follows package manager package/version availability.
- **Installation Path**: package manager controlled.
- **User Targeting**: generally system-managed installs.
- **Required Privileges**: may require elevated privileges depending on manager setup.
- **Tool-Specific Configurations**: no uv-specific installer flags in this method; manager options apply.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: typically handled by manager bootstrap; verify manager binary path is active in shell startup.
- **Configuration Files**: none required for base install.
- **Environment Variables**: none required for base install.
- **Activation Scripts**: none required beyond manager environment initialization.
- **Cleanup**: use manager cleanup commands as needed.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: use manager-native upgrade/version controls.
- **Uninstallation**: `brew uninstall uv` or `sudo port uninstall uv`.
- **Idempotency**: manager-controlled and typically idempotent.

#### Notes and Best Practices

- As with other non-standalone installs, update flow should stay with the package manager rather than `uv self update`.

### Cargo Installation

#### Supported Platforms

- Platforms where Rust/Cargo toolchains are supported and uv can be built.

#### Dependencies

- **Common Dependencies**: Rust toolchain with Cargo.
- **Platform-Specific Dependencies**: build prerequisites implied by Rust target/platform.

#### Installation Steps

1. Install from crates.io:
   - `cargo install --locked uv`

#### Installation Verification

- `uv --version`

#### Configuration Options

- **Version Selection**: Cargo version selection flags (for example, explicit crate version).
- **Installation Path**: Cargo binary path (commonly Cargo home bin directory).
- **User Targeting**: per-user toolchain by default.
- **Required Privileges**: typically none for user toolchain directories.
- **Tool-Specific Configurations**: `--locked` recommended upstream to respect lockfile reproducibility.

#### Post-Installation Steps and Cleanup

- **PATH Setup**: ensure Cargo bin directory is on PATH.
- **Configuration Files**: Cargo-managed; no uv installer config involved.
- **Environment Variables**: standard Cargo toolchain env vars if customized.
- **Activation Scripts**: none beyond shell profile path setup for Cargo.
- **Cleanup**: optional Cargo cache cleanup routines.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**: reinstall with desired version constraints.
- **Uninstallation**: `cargo uninstall uv`.
- **Idempotency**: Cargo-managed install behavior.

#### Notes and Best Practices

- This path compiles from source and is generally slower than prebuilt artifact methods.
- As a non-standalone install, self-update behavior should not be relied on.

## References

- [uv Installation Guide](https://docs.astral.sh/uv/getting-started/installation/) - Official installation methods, upgrade/uninstall steps, and shell-completion commands.
- [uv Installer Reference](https://docs.astral.sh/uv/reference/installer/) - Official installer environment variables and script invocation options.
- [uv Storage Reference](https://docs.astral.sh/uv/reference/storage/) - Executable directory resolution and uv data directory behavior.
- [uv Platform Support Policy](https://docs.astral.sh/uv/reference/policies/platforms/) - Tier support, macOS minimum guidance, and Linux libc target baselines.
- [uv GitHub Repository](https://github.com/astral-sh/uv) - Official source repository and project metadata.
- [Latest uv Release API](https://api.github.com/repos/astral-sh/uv/releases/latest) - Authoritative latest stable tag and publish timestamp.
- [uv 0.11.8 Release Page](https://github.com/astral-sh/uv/releases/tag/0.11.8) - Release artifacts, checksums, and attestation verification instructions.
- [uv Shell Installer (0.11.8)](https://releases.astral.sh/github/uv/releases/download/0.11.8/uv-installer.sh) - Full installer implementation for Unix shells, including path mutation and artifact-selection logic.
- [uv PowerShell Installer (0.11.8)](https://releases.astral.sh/github/uv/releases/download/0.11.8/uv-installer.ps1) - Full installer implementation for Windows PowerShell environments.
- [uv Dist Configuration](https://raw.githubusercontent.com/astral-sh/uv/main/dist-workspace.toml) - Cargo-dist installer generation settings, target matrix, glibc baselines, install paths, and hosting preferences.
- [uv Self-Update Implementation](https://raw.githubusercontent.com/astral-sh/uv/main/crates/uv/src/commands/self_update.rs) - Receipt-based standalone self-update behavior and mirror-first installer download flow.
- [Available Dev Container Features Index](https://containers.dev/features) - Registry list confirming no official `devcontainers/features` uv feature and identifying community uv features.
- [devcontainers/features Repository](https://github.com/devcontainers/features) - Official feature collection context (no dedicated uv feature).
- [devcontainers-extra uv Feature Script](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/uv/install.sh) - Community implementation using GH release assets via `gh-release` helper feature.
- [devcontainers-extra uv Feature Metadata](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/uv/devcontainer-feature.json) - Option schema and defaults for the community uv feature.
- [devcontainer-community astral.sh-uv Script](https://raw.githubusercontent.com/devcontainer-community/devcontainer-features/main/src/astral.sh-uv/install.sh) - Community implementation with direct release download and optional autocompletion generation.
- [devcontainer-community astral.sh-uv Metadata](https://raw.githubusercontent.com/devcontainer-community/devcontainer-features/main/src/astral.sh-uv/devcontainer-feature.json) - Option schema and defaults for community uv feature.
- [va-h uv Feature Script](https://raw.githubusercontent.com/va-h/devcontainers-features/main/src/uv/install.sh) - Community implementation with architecture normalization, release-tag lookup, and optional autocompletion.
- [va-h uv Feature Metadata](https://raw.githubusercontent.com/va-h/devcontainers-features/main/src/uv/devcontainer-feature.json) - Option schema and defaults for this community uv feature.