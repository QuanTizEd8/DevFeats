# Feature Reference

Lefthook is a Git hook manager implemented as a single Go binary. It installs small hook entrypoint scripts into `.git/hooks/` and executes jobs defined in `lefthook.yml`. It is positioned as a fast, polyglot alternative to language-specific hook managers and supports installation via direct binaries, OS package managers, and language ecosystem packages.

- **Homepage**: https://lefthook.dev/
- **Source Code**: https://github.com/evilmartians/lefthook
- **Documentation**: https://lefthook.dev/
- **Latest Release**: 2.1.6 (as of 2026-04-30)

## Available Installation Methods

The upstream project documents many install channels. For DevFeats feature design, the most implementation-relevant methods are: direct GitHub Release binary installation, OS package manager installation, and language-ecosystem package installation.

### GitHub Release Binary (Manual Installation)

#### Supported Platforms

- macOS (x86_64, arm64)
- Linux (x86_64, arm64/aarch64)
- FreeBSD (x86_64, arm64)
- OpenBSD (x86_64, arm64)
- Windows (x86_64, arm64, i386)
- Notes:
  - Asset names are platform-encoded (for example: `lefthook_2.1.6_Linux_x86_64`, `lefthook_2.1.6_MacOS_arm64`, `lefthook_2.1.6_Windows_x86_64.exe`).
  - Lefthook's self-updater currently maps runtime OS to `Windows`, `MacOS`, `Linux`, `Freebsd`, `Openbsd` and runtime arch to `x86_64`, `arm64`, `i386` when selecting assets.

#### Dependencies

- **Common Dependencies**:
  - Network access to GitHub Releases/API
  - A download client (`curl` or `wget`)
  - A SHA-256 verification tool (`sha256sum` or platform equivalent)
  - Permission to write into the chosen binary directory
- **Platform-Specific Dependencies**:
  - On Linux/macOS, `install` or `chmod` + `mv` for executable placement
  - On Windows, executable placement in a PATH directory and `.exe` asset selection

#### Installation Steps

1. Resolve target version:
   - Fixed: use a specific release tag such as `v2.1.6`.
   - Latest: query `https://api.github.com/repos/evilmartians/lefthook/releases/latest`.
2. Resolve platform/arch and compute asset name.
3. Download both the target asset and `lefthook_checksums.txt` from the release.
4. Verify SHA-256 checksum against the exact matching entry.
5. Install binary into a PATH directory (for example `/usr/local/bin/lefthook`) and ensure executable mode.
6. In each repository that should use Lefthook, run `lefthook install`.
  - You can also install specific hooks only: `lefthook install <hook-1> <hook-2> ...`.

#### Installation Verification

- Verify checksum before installation using `lefthook_checksums.txt`.
- Confirm executable availability and version:
  - `lefthook version`
  - Optional detailed output: `lefthook version --full`
- Confirm hook installation state in a repository:
  - `lefthook check-install`

#### Configuration Options

- **Version Selection**:
  - Fixed version by explicit release tag/URL.
  - Latest via GitHub API (same mechanism used by `lefthook self-update`).
- **Installation Path**:
  - Any directory in PATH can be used.
  - System-wide defaults commonly use `/usr/local/bin`.
- **User Targeting**:
  - System-wide installation for all users (privileged paths).
  - User-local installation in a user-owned PATH directory.
- **Required Privileges**:
  - Root/sudo required only when writing to protected directories.
- **Tool-Specific Configurations**:
  - `lefthook install --force` allows installation even if `core.hooksPath` is set.
  - `lefthook install --reset-hooks-path` unsets local/global `core.hooksPath` automatically.
  - `lefthook install <hook-1> <hook-2> ...` installs selected hooks; non-Git hook names are skipped unless `install_non_git_hooks: true` is set.
  - `LEFTHOOK_CONFIG` overrides main config path lookup only; local config, extends, and remotes are still loaded.
  - `lefthook self-update` supports `--yes` and `--force`.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure chosen binary directory is present in PATH.
- **Configuration Files**:
  - `lefthook install` creates `lefthook.yml` if no main config exists.
  - Main config base names: `lefthook`, `.lefthook`, `.config/lefthook` with extensions `.yml`, `.yaml`, `.json`, `.jsonc`, `.toml`.
  - Local config base names: `lefthook-local`, `.lefthook-local`, `.config/lefthook-local`.
- **Environment Variables**:
  - `LEFTHOOK_CONFIG` for config override.
  - `LEFTHOOK_VERBOSE` enables verbose logging.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Remove temporary downloaded files and checksum manifests after successful install.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Replace binary with another release asset, or use `lefthook self-update` for latest.
  - `self-update` is intended for source or GitHub Release-binary installs. For package-manager installs, use package-manager-native upgrades.
  - `self-update` verifies SHA-256 against `lefthook_checksums.txt`, swaps binaries with backup/rollback logic, and sets executable mode.
- **Uninstallation**:
  - Remove binary from PATH.
  - `lefthook uninstall` removes Lefthook-managed hooks and restores `.old` backups when present.
  - `lefthook uninstall --force` removes all Git hooks, not only Lefthook-managed ones.
  - `lefthook uninstall --remove-configs` removes Lefthook main/local config files for extensions `.yml`, `.yaml`, `.toml`, `.json`.
  - Uninstall also removes the remotes folder state under `.git`.
- **Idempotency**:
  - Hook installation tracks config checksum and timestamp in `.git/info/lefthook.checksum`.
  - If hooks are synchronized, repeated install is effectively a no-op.
  - Existing non-Lefthook hook files are renamed to `.old`; if `.old` already exists, install fails unless forced.

#### Notes and Best Practices

- Prefer checksum verification for every downloaded binary.
- Prefer fixed versions in CI/reproducible environments.
- If repository or global `core.hooksPath` is set, decide explicitly between:
  - cleaning it with `--reset-hooks-path`, or
  - forcing installation with `--force`.

### OS Package Managers (Homebrew, Cloudsmith APT/RPM/APK, Arch AUR, Snap, Winget, Scoop)

#### Supported Platforms

- Homebrew: macOS and Linux (`brew install lefthook`)
- Debian/Ubuntu: APT via Cloudsmith setup + `apt install lefthook`
- RPM-based Linux: Cloudsmith setup plus manager-specific install (`yum`/`dnf`/`microdnf`/`zypper` families)
- Alpine Linux: Cloudsmith setup + `apk add lefthook`
- Arch Linux: AUR packages (`lefthook`, `lefthook-bin`)
- Linux (Snap): `snap install --classic lefthook`
- Windows: Winget (`winget install evilmartians.lefthook`) and Scoop (`scoop install lefthook`)

#### Dependencies

- **Common Dependencies**:
  - Platform package manager tooling
  - Network access to package repositories
- **Platform-Specific Dependencies**:
  - For Cloudsmith bootstrap scripts:
    - APT path: `curl`, `gpg`, `apt-get`, and Debian keyring/transport prerequisites
    - RPM path: `rpm` plus `yum`/`dnf`/`microdnf`/`zypper` manager support
    - Alpine path: `curl`, `apk`

#### Installation Steps

- Homebrew:
  - `brew install lefthook`
- Debian/Ubuntu:
  - `curl -1sLf 'https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.deb.sh' | sudo -E bash`
  - `sudo apt install lefthook`
- RPM-based Linux:
  - `curl -1sLf 'https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.rpm.sh' | sudo -E bash`
  - Install with available manager family (for example):
    - `sudo yum install lefthook`
    - `sudo dnf install lefthook`
    - `sudo microdnf install lefthook`
    - `sudo zypper install lefthook`
- Alpine:
  - `sudo apk add --no-cache bash curl`
  - `curl -1sLf 'https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.alpine.sh' | sudo -E bash`
  - `sudo apk add lefthook`
- Arch Linux:
  - `yay -S lefthook` (build from source) or `yay -S lefthook-bin` (prebuilt)
- Snap:
  - `snap install --classic lefthook`
- Windows:
  - `winget install evilmartians.lefthook` or `scoop install lefthook`

#### Installation Verification

- Verify package installation via package manager query commands (manager-specific).
- Verify executable and version:
  - `lefthook version`
- In repositories using hooks, verify hook status:
  - `lefthook check-install`

#### Configuration Options

- **Version Selection**:
  - Depends on package manager capabilities/repository retention.
  - Cloudsmith + distro packages support manager-specific version constraints when versions are available in repo metadata.
- **Installation Path**:
  - Managed by package manager defaults.
- **User Targeting**:
  - Typically system-wide.
- **Required Privileges**:
  - Usually root/sudo (except common Homebrew user-owned prefix scenarios).
- **Tool-Specific Configurations**:
  - After package installation, repository-level hook activation is still done with `lefthook install`.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Typically handled automatically by package manager.
- **Configuration Files**:
  - Lefthook project config is not created until `lefthook install` is run in a repository.
- **Environment Variables**:
  - No persistent variables are required for basic operation.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Cloudsmith setup scripts update package metadata caches as part of repository setup.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Use package-manager-native upgrade/downgrade flows.
- **Uninstallation**:
  - Use package-manager-native uninstall/remove commands.
  - Optionally run `lefthook uninstall` inside repositories to remove hooks/config state.
- **Idempotency**:
  - Re-running package install commands is generally idempotent per package manager semantics.

#### Notes and Best Practices

- Cloudsmith setup scripts are root-privileged repository-bootstrap scripts:
  - APT script imports a GPG key and configures `/etc/apt/sources.list.d/...`.
  - RPM script imports GPG key(s) into RPM and configures manager repo files.
  - Alpine script imports RSA key and appends repository config to `/etc/apk/repositories`.
- Treat repository bootstrap and package install as separate stages for clearer error handling.

### Language-Ecosystem Installers (NPM, RubyGems, PyPI, Go, Swift/Mise/Devbox)

#### Supported Platforms

- NPM `lefthook` package:
  - Uses OS/arch-specific optional dependencies (darwin/linux/freebsd/openbsd/windows for x64/arm64 variants listed in package metadata).
- RubyGems wrapper:
  - Wrapper maps common Linux/macOS/Windows/FreeBSD/OpenBSD platform variants and dispatches to packaged binary.
- PyPI package:
  - Provides `lefthook` entrypoint and packaged binaries (build tooling maps platform/arch tags for wheel publishing).
- Go:
  - Source installation with Go toolchain (minimum Go 1.26).
- Swift/Mise/Devbox methods are documented but include explicit community-maintained support caveats.

#### Dependencies

- **Common Dependencies**:
  - Corresponding ecosystem tooling (npm/yarn/pnpm, gem/bundler, python/pip or pipx, Go toolchain, etc.)
- **Platform-Specific Dependencies**:
  - PATH setup may be required for user-local installs (notably Ruby/Python toolchains).
  - Python package declares `requires-python >=3.6`.

#### Installation Steps

- NPM:
  - `npm install --save-dev lefthook`
  - `yarn add --dev lefthook`
  - `pnpm add -D lefthook`
- Ruby:
  - Add `gem "lefthook", require: false` to development group, or `gem install lefthook`
- Python:
  - `python -m pip install --user lefthook`
  - `uv add --dev lefthook`
  - `pipx install lefthook`
- Go:
  - `go install github.com/evilmartians/lefthook/v2@v2.1.6`
  - or project tool mode `go get -tool github.com/evilmartians/lefthook/v2`
- Additional documented methods:
  - Swift wrapper plugin:
    - Swift Package Manager: `.package(url: "https://github.com/csjones/lefthook-plugin.git", exact: "2.1.6"),`
    - Mint: `mint run csjones/lefthook-plugin`
  - Mise: `mise use lefthook@latest`
  - Devbox: `devbox add lefthook@latest`

#### Installation Verification

- `lefthook version`
- If expecting automatic hook bootstrap in Node projects, verify hook files in `.git/hooks/` or run `lefthook check-install`.

#### Configuration Options

- **Version Selection**:
  - Package-manager-native version constraints (semver/range/pinned versions).
  - Go method supports exact version with `@vX.Y.Z`.
- **Installation Path**:
  - Controlled by ecosystem manager conventions.
- **User Targeting**:
  - Project-local dependency mode (npm, Gemfile, uv project).
  - User/global install mode (gem install, pip user, pipx, Go global install).
- **Required Privileges**:
  - Usually no root for local/project installs; may require elevated permissions for global locations.
- **Tool-Specific Configurations**:
  - NPM `lefthook` postinstall runs `lefthook install -f` unless CI is enabled and `LEFTHOOK` override is not enabled.
  - With pnpm, `onlyBuiltDependencies` must include `lefthook` so postinstall executes.
  - Official docs mark `@evilmartians/lefthook` and `@evilmartians/lefthook-installer` as legacy.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure user-level binary directories are in PATH for gem/pip/pipx/go user installs.
- **Configuration Files**:
  - Same repository config/hook behavior applies once `lefthook install` is executed.
- **Environment Variables**:
  - NPM CI behavior can be affected by `CI` and `LEFTHOOK` env vars.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Managed through package manager uninstall/removal workflows.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Use manager-native update commands or version constraints.
- **Uninstallation**:
  - Remove package via manager and optionally run `lefthook uninstall` in repositories.
- **Idempotency**:
  - Reinstall behavior depends on manager lifecycle hooks.
  - Lefthook's own repository hook install remains checksum/timestamp-aware.

#### Notes and Best Practices

- In CI and reproducible builds, prefer explicit version pinning and explicit `lefthook install` step when needed.
- Avoid relying on legacy NPM distributions marked for future shutdown.
- Community-maintained channels (for example Mise/Devbox wrappers) are documented but not directly supported by Lefthook maintainers.

## References

- [Lefthook Homepage](https://lefthook.dev/) - Official site and top-level install/usage navigation.
- [Lefthook GitHub Repository](https://github.com/evilmartians/lefthook) - Primary source code and release history.
- [Lefthook README](https://raw.githubusercontent.com/evilmartians/lefthook/master/README.md) - Official overview, quick install matrix, and usage quickstart.
- [Install Overview Doc](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/install.md) - States standalone binary model and `self-update` path.
- [Installation: Manual](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/manual.md) - Manual binary install entrypoint.
- [Installation: Node](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/node.md) - NPM/Yarn/pnpm commands, legacy package status, pnpm note.
- [Installation: Ruby](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/ruby.md) - Gemfile/global gem method and PATH troubleshooting note.
- [Installation: Python](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/python.md) - `pip`, `uv`, and `pipx` methods.
- [Installation: Go](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/go.md) - Go minimum version and install/tool commands.
- [Installation: Homebrew](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/homebrew.md) - Homebrew install command.
- [Installation: Debian](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/deb.md) - Cloudsmith APT bootstrap/install commands.
- [Installation: RPM](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/rpm.md) - Cloudsmith RPM bootstrap/install commands.
- [Installation: Alpine](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/alpine.md) - Cloudsmith APK bootstrap/install commands.
- [Installation: Arch](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/arch.md) - AUR source/binary package choices.
- [Installation: Snap](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/snap.md) - Snap install command.
- [Installation: Winget](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/winget.md) - Winget command.
- [Installation: Scoop](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/scoop.md) - Scoop command.
- [Installation: Swift](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/swift.md) - Swift wrapper plugin methods.
- [Installation: Mise](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/mise.md) - Community-maintained mise install method.
- [Installation: Devbox](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/installation/devbox.md) - Community-maintained devbox install method.
- [Usage Command: install](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/usage/commands/install.md) - Install command behavior notes and specific-hook usage.
- [Usage Command: uninstall](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/usage/commands/uninstall.md) - Uninstall command purpose.
- [Usage Command: self-update](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/usage/commands/self-update.md) - Scope and limitations of self-update.
- [Usage Command: check-install](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/usage/commands/check-install.md) - Hook install/sync verification semantics and exit codes.
- [Usage Command: version](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/usage/commands/version.md) - Version verification CLI details.
- [Usage Env: LEFTHOOK_CONFIG](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/usage/envs/LEFTHOOK_CONFIG.md) - Main-config override scope and loading caveats.
- [Configuration: install_non_git_hooks](https://raw.githubusercontent.com/evilmartians/lefthook/master/docs/configuration/install_non_git_hooks.md) - Enables installation of non-Git hook names into `.git/hooks`.
- [Go Module Metadata](https://raw.githubusercontent.com/evilmartians/lefthook/master/go.mod) - Minimum Go version/toolchain requirement.
- [Install Command Source](https://raw.githubusercontent.com/evilmartians/lefthook/master/cmd/install.go) - Install CLI flags (`--force`, `--reset-hooks-path`).
- [check-install Command Source](https://raw.githubusercontent.com/evilmartians/lefthook/master/cmd/check_install.go) - `check-install` command wiring and exit-code intent.
- [Uninstall Command Source](https://raw.githubusercontent.com/evilmartians/lefthook/master/cmd/uninstall.go) - Uninstall CLI flags (`--force`, `--remove-configs`).
- [Self-update Command Source](https://raw.githubusercontent.com/evilmartians/lefthook/master/cmd/self_update.go) - Self-update CLI flags and entrypoint.
- [Install Internals](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/command/install.go) - Config discovery/creation, hooksPath handling, synchronization/checksum behavior.
- [Config Loader Internals](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/config/load.go) - Canonical main/local config base names and supported config extensions.
- [Hook File Internals](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/command/lefthook.go) - `.old` rename strategy and Lefthook file fingerprint logic.
- [Uninstall Internals](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/command/uninstall.go) - Hook/config cleanup behavior.
- [Updater Internals](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/updater/updater.go) - GitHub API release lookup, asset selection, checksum verification, binary replacement rollback.
- [Install Behavior Tests](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/command/install_test.go) - Edge-case coverage (`core.hooksPath`, `.old`, forced behavior).
- [Updater Tests](https://raw.githubusercontent.com/evilmartians/lefthook/master/internal/updater/updater_test.go) - Checksum mismatch and success-path validation.
- [NPM Package Metadata](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/npm/lefthook/package.json) - Optional dependency platform mapping and postinstall hook.
- [NPM postinstall Script](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/npm/lefthook/postinstall.js) - Automatic `lefthook install -f` behavior and CI guard.
- [NPM executable resolver](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/npm/lefthook/get-exe.js) - OS/arch package resolution logic.
- [PyPI Entrypoint Wrapper](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/pypi/lefthook/main.py) - Runtime platform/arch binary dispatch.
- [PyPI Build Config](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/pypi/pyproject.toml) - Project script and wheel build settings.
- [PyPI Build Hook](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/pypi/hatch_build.py) - Platform wheel targeting and binary pruning behavior.
- [RubyGems Wrapper Binary](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/rubygems/bin/lefthook) - Ruby platform mapping and binary dispatch.
- [RubyGems Spec](https://raw.githubusercontent.com/evilmartians/lefthook/master/packaging/registries/rubygems/lefthook.gemspec) - Post-install message and packaged executable metadata.
- [Cloudsmith APT setup script](https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.deb.sh) - Repository bootstrap details (GPG keyring, apt source installation, metadata refresh).
- [Cloudsmith RPM setup script](https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.rpm.sh) - Repository bootstrap details across yum/dnf/microdnf/zypper.
- [Cloudsmith Alpine setup script](https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.alpine.sh) - RSA key import and apk repository update flow.
- [GitHub API Latest Release Endpoint](https://api.github.com/repos/evilmartians/lefthook/releases/latest) - Latest version and asset inventory used for release-based installers.
- [Available Dev Container Features](https://containers.dev/features) - Registry listing used to identify comparable Lefthook feature implementations.
- [devcontainers-extra lefthook-asdf feature](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/lefthook-asdf/install.sh) - Example of delegating Lefthook installation to shared asdf-package feature.
- [devcontainers-extra gh-release feature](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/gh-release/install.sh) - Reusable release-binary installer pattern with configurable repo/version/asset filtering.
- [iyaki Lefthook feature](https://raw.githubusercontent.com/iyaki/devcontainer-features/main/src/lefthook/install.sh) - Example of architecture-aware asset regex + delegation to gh-release feature.
- [NicoVIII Lefthook feature](https://raw.githubusercontent.com/nicoviii/devcontainer-features/main/src/lefthook/install.sh) - Example of direct GitHub Release download with checksum-manifest verification and `/usr/local/bin` placement.
