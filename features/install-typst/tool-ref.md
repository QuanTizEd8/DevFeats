# Feature Reference

Typst is an open-source, markup-based typesetting compiler that converts Typst documents into output formats such as PDF, images, and web pages. It is designed to be used as a fast local CLI compiler and as an embeddable Rust library, while the hosted Typst web app provides an additional closed-source collaborative UI layer on top of the compiler.[^typst-open-source][^typst-readme]

For feature implementation, the important operational context is that Typst is distributed through multiple channels (release archives, package managers, Cargo, Nix, and container images), with one CLI binary (`typst`) exposing subcommands for compile, watch, querying, package/template initialization, self-update (when compiled with that feature), and diagnostics. Runtime behavior is controlled primarily by CLI flags and environment variables rather than mandatory config files.[^typst-readme][^typst-cli-args][^typst-cli-main][^typst-cli-info]

- **Homepage**: https://typst.app/
- **Source Code**: https://github.com/typst/typst
- **Documentation**: https://typst.app/docs/
- **Latest Release**: v0.14.2 (as of 2026-05-17)[^typst-release-latest]

## Tool Architecture

Typst is implemented as a Rust multi-crate project. The CLI itself is provided by `crates/typst-cli` and compiled into a single `typst` executable, while core compiler functionality lives in crates such as `typst`, `typst-eval`, `typst-layout`, `typst-pdf`, and related exporter/runtime crates.[^typst-arch][^typst-cli-cargo]

The end-user interface is command-oriented (`typst <subcommand>`). Core subcommands include `compile`, `watch`, `init`, `query`, `fonts`, `update`, `completions`, and `info`. This is a standalone local CLI architecture (not a persistent client/server daemon), though `watch` can optionally serve HTML via a built-in HTTP server when that compile-time feature is enabled.[^typst-cli-args][^typst-cli-main][^typst-cli-cargo]

Typst is mostly self-contained at runtime for local document compilation, but it can rely on external resources in specific paths:

- Package/template retrieval for the default namespace uses `https://packages.typst.org` (default registry) and stores data in default package/cache paths derived from OS data/cache directories unless overridden.[^typst-kit-package][^typst-cli-args]
- Self-update (when enabled) calls the GitHub Releases API and downloads prebuilt release assets.[^typst-cli-update]
- Font discovery can use system fonts, embedded fonts, and user-specified font paths, controlled by flags and environment variables.[^typst-cli-args][^typst-cli-info]

Compile-time feature flags matter for behavior: `embed-fonts` and `http-server` are default features in `typst-cli`, while `self-update` is optional. Official release workflow builds enable `self-update` for published binaries, while custom builds can omit it.[^typst-cli-cargo][^typst-release-workflow][^typst-cli-main]

## Installation Methods

Typst publishes installation guidance for release binaries, package managers, Cargo, Nix usage, and Docker usage. Method choice affects upgrade path, privilege requirements, binary ownership, and reproducibility controls.[^typst-readme][^typst-open-source]

### Official GitHub Release Archives (tar.xz/zip)

#### Supported Platforms

- macOS: `x86_64-apple-darwin`, `aarch64-apple-darwin`.[^typst-release-workflow][^typst-release-latest]
- Linux: `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl`, `armv7-unknown-linux-musleabi`, `riscv64gc-unknown-linux-gnu`.[^typst-release-workflow][^typst-release-latest]
- Windows: `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`.[^typst-release-workflow][^typst-release-latest]

#### Dependencies

##### Common Dependencies

- Ability to download release assets from GitHub Releases.[^typst-readme][^typst-release-latest]
- Archive extraction tooling (`tar` for `.tar.xz`, ZIP extraction tooling for `.zip`).[^typst-cli-update][^typst-release-workflow]

##### Platform-Specific Dependencies

- Linux/macOS: `tar` with xz support for `.tar.xz` release assets.[^typst-release-workflow][^typst-cli-update]
- Windows: ZIP extraction support for `.zip` assets.[^typst-release-workflow][^typst-cli-update]

#### Installation Steps

1. Pick a release tag and target asset from GitHub Releases.[^typst-readme][^typst-release-latest]
2. Download the matching archive for your platform and architecture.[^typst-readme][^typst-release-latest]
3. Extract the archive.
4. Move the `typst` binary (`typst.exe` on Windows) into a directory on `PATH`.

Example on Linux/macOS:

```bash
# Example for Linux x86_64
curl -LO https://github.com/typst/typst/releases/download/v0.14.2/typst-x86_64-unknown-linux-musl.tar.xz
tar -xf typst-x86_64-unknown-linux-musl.tar.xz
install -m 0755 typst-x86_64-unknown-linux-musl/typst "$HOME/.local/bin/typst"
```

Example on Windows (PowerShell):

```powershell
Invoke-WebRequest -Uri https://github.com/typst/typst/releases/download/v0.14.2/typst-x86_64-pc-windows-msvc.zip -OutFile typst.zip
Expand-Archive -Path typst.zip -DestinationPath .
# Move typst.exe to a PATH directory (user or system)
```

The Typst documentation and README describe this as the canonical archive-based installation path and recommend placing the binary in a `PATH` directory.[^typst-readme][^typst-open-source]

#### Installation Verification

- Check the installed CLI responds and prints version:

```bash
typst --version
```

- Optionally validate downloaded archive checksums against release asset digests exposed by the GitHub Releases API (`digest` field, SHA-256 format).[^typst-release-latest]

#### Configuration Options

##### Version Selection

- Select version by choosing the release tag in the download URL (`vX.Y.Z`).[^typst-release-latest][^typst-readme]
- If installed binary includes self-update feature, `typst update` can fetch latest or a specific version, and supports controlled downgrade via `--force`.[^typst-cli-update][^typst-cli-args]

##### Installation Path

- Binary location is fully user-controlled in this method; recommended practice is placing it in a `PATH` directory.[^typst-readme][^typst-open-source]

##### User Targeting

- User-local install: place binary under a user-owned path (for example `~/.local/bin`).
- System-wide install: place under shared system path (for example `/usr/local/bin`) where policy allows.

##### Required Privileges

- User-local installs require no elevation.
- System path writes require elevated privileges according to OS policy.

##### Tool-Specific Configurations

The `typst` CLI supports tool-specific runtime configuration via flags and environment variables, including:

- Project root: `--root`, `TYPST_ROOT`.[^typst-cli-args][^typst-cli-info]
- Package storage: `--package-path`, `--package-cache-path`, `TYPST_PACKAGE_PATH`, `TYPST_PACKAGE_CACHE_PATH`.[^typst-cli-args][^typst-cli-info][^typst-kit-package]
- Font discovery: `--font-path`, `TYPST_FONT_PATHS`, `TYPST_IGNORE_SYSTEM_FONTS`, `TYPST_IGNORE_EMBEDDED_FONTS`.[^typst-cli-args][^typst-cli-info]
- Custom CA certificate: `--cert`, `TYPST_CERT`.[^typst-cli-args][^typst-cli-info]
- Self-update backup path: `--backup-path`, `TYPST_UPDATE_BACKUP_PATH`.[^typst-cli-args][^typst-cli-info][^typst-cli-update]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure the chosen binary directory is on `PATH` in shell startup files.[^typst-readme][^typst-open-source]

##### Configuration Files

- No mandatory Typst config file is required for basic CLI usage.

##### Environment Variables

- Persist only the variables needed for your environment (`TYPST_ROOT`, package/font path variables, proxies/certs as needed).[^typst-cli-info][^typst-cli-args]

##### Activation Scripts

- None required for base CLI operation.

##### Cleanup

- Remove downloaded archives and temporary extraction directories after binary placement.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Manual method: download another release archive and replace the installed binary.
- CLI self-update method (if available in build): `typst update [version]`, with downgrade requiring `--force` and rollback via `--revert` when backup exists.[^typst-cli-update][^typst-cli-args][^typst-cli-main]

##### Uninstallation

- Remove the installed `typst` executable from its install path.
- If self-update was used, optionally remove backup file (`typst_backup.part`) from default or custom backup location.[^typst-cli-update]

##### Idempotency

- Replacing the binary with the same version is effectively idempotent.
- `typst update` reports `Already up-to-date.` when no newer target is available and `--force` is not used.[^typst-cli-update]

#### Notes and Best Practices

- Prefer this method when you need the newest official release quickly or explicit version pinning independent of OS package lag.[^typst-readme]
- Verify architecture-target alignment before installation to avoid runtime incompatibilities.[^typst-release-latest][^typst-release-workflow]
- Avoid mixing package-manager ownership with manual replacement on the same path.

### OS Package Managers (Homebrew, WinGet, Linux Package Channels)

#### Supported Platforms

- macOS: Homebrew (`brew install typst`).[^typst-readme][^typst-open-source]
- Windows: WinGet (`winget install --id Typst.Typst`).[^typst-readme]
- Linux: distribution channels listed via Repology and Snap listing.[^typst-readme]

#### Dependencies

##### Common Dependencies

- Active package manager installation and repository access.

##### Platform-Specific Dependencies

- macOS/Linux (Homebrew path): Homebrew CLI available and configured.[^brew-man]
- Windows: WinGet client available.[^winget-install]
- Linux distro-specific paths: distro package manager or Snap tooling depending on chosen channel.[^typst-readme]

#### Installation Steps

- Homebrew:

```bash
brew install typst
```

- WinGet:

```powershell
winget install --id Typst.Typst
```

- Linux distro channels:
  - Locate distro package channel via Repology, then use distro-native package commands.
  - Or use the Snap package listing and install through Snap tooling if applicable.[^typst-readme]

#### Installation Verification

```bash
typst --version
```

And optionally inspect package-manager state (`brew list`, `winget list`, distro equivalent).[^brew-man][^winget-install]

#### Configuration Options

##### Version Selection

- Homebrew and distro channels use package-manager version semantics.
- WinGet supports explicit `--version` for install/upgrade flows.[^winget-install][^winget-upgrade]

##### Installation Path

- Package-manager managed; location and links are controlled by manager conventions.[^brew-man][^winget-install]

##### User Targeting

- WinGet supports scope targeting (`--scope user|machine`).[^winget-install][^winget-uninstall]
- Homebrew and Linux package managers follow their own user/system ownership models.[^brew-man]

##### Required Privileges

- Depends on manager and selected scope. Machine/system installs usually require elevated rights.

##### Tool-Specific Configurations

- Typst runtime configuration is unchanged by manager choice (same CLI flags and environment variables described above).[^typst-cli-args][^typst-cli-info]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- PATH updates are typically handled by the package manager installation model; verify shell environment if command is not immediately discoverable.[^brew-man][^winget-install]

##### Configuration Files

- No mandatory Typst config file required for basic usage.

##### Environment Variables

- Persist Typst variables only if needed (`TYPST_ROOT`, package/font path, proxy/cert options).[^typst-cli-info]

##### Activation Scripts

- None required.

##### Cleanup

- Use manager cleanup mechanisms (for example Homebrew cleanup or WinGet logs handling) as needed.[^brew-man][^winget-uninstall]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Homebrew: `brew upgrade typst`.[^brew-man]
- WinGet: `winget upgrade --id Typst.Typst` and optional `--version` selection.[^winget-upgrade]
- Linux distro managers: use distro-native upgrade and version pinning workflows.

##### Uninstallation

- Homebrew:

```bash
brew uninstall typst
```

- WinGet:

```powershell
winget uninstall --id Typst.Typst --source winget
```

- Linux distro channels: use distro-native uninstall command.[^brew-man][^winget-uninstall]

##### Idempotency

- Package-manager installs are idempotent in the manager sense (re-running converges on requested package state/version).[^brew-man][^winget-install]

#### Notes and Best Practices

- The Typst project explicitly notes package-manager versions may lag behind latest release; use release archives when immediate latest is required.[^typst-readme]
- Prefer manager-native upgrade/uninstall over `typst update` for package-manager-owned binaries.

### Cargo Installation (`typst-cli`)

#### Supported Platforms

- Any platform with a compatible Rust/Cargo toolchain and build environment.[^typst-readme][^cargo-install]

#### Dependencies

##### Common Dependencies

- Rust toolchain with Cargo installed.[^typst-readme][^cargo-install]
- Network access to crates.io or git source (depending on install mode).[^cargo-install]

##### Platform-Specific Dependencies

- Platform-specific build toolchain requirements follow Rust crate build requirements.

#### Installation Steps

- Stable release from crates.io:

```bash
cargo install --locked typst-cli
```

- Development version from git:

```bash
cargo install --git https://github.com/typst/typst --locked typst-cli
```

`--locked` is the documented Typst recommendation for Cargo installs and enforces lockfile-based dependency resolution where available.[^typst-readme][^cargo-install]

#### Installation Verification

```bash
typst --version
cargo install --list | grep typst-cli
```

#### Configuration Options

##### Version Selection

- `cargo install typst-cli --version <REQ>` for crates.io versions.
- `cargo install --git ... --tag <TAG>` or `--rev <SHA>` for git-source pinning.[^cargo-install]

##### Installation Path

- Install root precedence includes `--root`, `CARGO_INSTALL_ROOT`, config, `CARGO_HOME`, and default `$HOME/.cargo`.[^cargo-install][^cargo-uninstall]

##### User Targeting

- Default target is user-local Cargo install root (`$HOME/.cargo/bin` in default setup).[^cargo-install]

##### Required Privileges

- No elevation needed for user-local install root.
- Elevated privileges are required only when writing into privileged system paths.

##### Tool-Specific Configurations

- Cargo method controls Typst binary build features. `self-update` is an optional compile feature in `typst-cli`; builds without it will return an error when `typst update` is invoked.[^typst-cli-cargo][^typst-cli-main]
- Standard Typst runtime flags/env vars remain available regardless of install channel.[^typst-cli-args][^typst-cli-info]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure Cargo bin path (typically `$HOME/.cargo/bin`) is in `PATH`.[^cargo-install]

##### Configuration Files

- Cargo config may influence install behavior (`$CARGO_HOME/config.toml` precedence for this command).[^cargo-install]

##### Environment Variables

- Cargo installation path variables (`CARGO_INSTALL_ROOT`, `CARGO_HOME`) and Typst runtime variables can be persisted as needed.[^cargo-install][^typst-cli-info]

##### Activation Scripts

- None required.

##### Cleanup

- Remove intermediate build artifacts/caches per Cargo maintenance policy if needed.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Re-run `cargo install` with desired version/source; Cargo reinstalls when version/source/features/target/profile differ.
- Use `--force` to force rebuild/reinstall when needed.[^cargo-install]

##### Uninstallation

```bash
cargo uninstall typst-cli
```

[^cargo-uninstall]

##### Idempotency

- Cargo tracks installed package metadata and avoids unnecessary reinstalls unless relevant install parameters change (unless `--force` is provided).[^cargo-install]

#### Notes and Best Practices

- Prefer `--locked` for reproducibility and to reduce dependency drift in automation.[^cargo-install]
- Be explicit about desired source (`crates.io` vs git) and revision in CI pipelines.

### Nix Installation and Execution

#### Supported Platforms

- Platforms with Nix package manager support and configured `nix` CLI.[^typst-readme][^nix-run][^nix-profile-install]

#### Dependencies

##### Common Dependencies

- Nix installed and configured.[^nix-run][^nix-profile-install]

##### Platform-Specific Dependencies

- Nix configuration may vary by host OS/distribution and policy.

#### Installation Steps

Typst README documents two common Nix usage paths:

- Shell environment package:

```bash
nix-shell -p typst
```

- Run development version from Typst git flake/ref:

```bash
nix run github:typst/typst -- --version
```

For persistent profile-style installs, use Nix profiles:

```bash
nix profile install nixpkgs#typst
```

[^typst-readme][^nix-run][^nix-profile-install]

#### Installation Verification

```bash
typst --version
# or
nix run nixpkgs#typst -- --version
```

[^nix-run]

#### Configuration Options

##### Version Selection

- Nix installables support channel/branch/revision addressing (`nixpkgs#...`, `nixpkgs/<rev>#...`, flake refs).[^nix-profile-install][^nix-run]

##### Installation Path

- Managed by Nix profile/store semantics (`nix profile install` installs into profile, not arbitrary user-chosen bin directory).[^nix-profile-install]

##### User Targeting

- Default profile operations are user profile scoped unless alternative profile paths are explicitly used.[^nix-profile-install][^nix-profile-remove]

##### Required Privileges

- User-profile operations generally do not require root; system-level Nix setup policy can vary.

##### Tool-Specific Configurations

- Typst runtime flags/env vars are unchanged by Nix channel and remain available at execution time.[^typst-cli-args][^typst-cli-info]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure Nix profile binaries are on `PATH` according to your Nix installation mode.

##### Configuration Files

- No mandatory Typst-specific file required for baseline operation.

##### Environment Variables

- Persist Typst variables only when required by workflow (`TYPST_ROOT`, package/font path vars, etc.).[^typst-cli-info]

##### Activation Scripts

- Depending on Nix setup, shell init/profile scripts may need to source Nix environment hooks.

##### Cleanup

- Use standard Nix garbage collection/profile maintenance as needed.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Change installable reference and re-run `nix profile install`.
- For ad-hoc execution, `nix run` can target a specific flake revision/reference directly.[^nix-profile-install][^nix-run]

##### Uninstallation

```bash
nix profile remove <element>
```

Element can be removed by profile element index, attribute path, or store path.[^nix-profile-remove]

##### Idempotency

- Nix profile operations are declarative/profile-element based and converge on selected installables.[^nix-profile-install][^nix-profile-remove]

#### Notes and Best Practices

- Use explicit flake revisions in CI for deterministic reproducibility.
- Keep in mind the Nix `nix` command family is marked experimental in referenced manual pages.[^nix-run][^nix-profile-install][^nix-profile-remove]

### Docker Image Execution

#### Supported Platforms

- Any platform with a functional Docker runtime that can pull and run `ghcr.io/typst/typst` images.[^typst-readme][^typst-dockerfile]

#### Dependencies

##### Common Dependencies

- Docker CLI/daemon access.[^typst-readme]

##### Platform-Specific Dependencies

- Host filesystem mount and container runtime policies vary by OS/container backend.

#### Installation Steps

The Typst README documents direct container usage:

```bash
docker run ghcr.io/typst/typst:latest --help
```

For real compilation, mount workspace files and call Typst entrypoint command arguments:

```bash
docker run --rm -v "$PWD":/work -w /work ghcr.io/typst/typst:latest compile file.typ
```

[^typst-readme][^typst-dockerfile]

#### Installation Verification

```bash
docker run --rm ghcr.io/typst/typst:latest --version
```

#### Configuration Options

##### Version Selection

- Select image tags explicitly (`:latest` or pinned tags) when pulling/running.[^typst-readme]

##### Installation Path

- No host binary installation path is required; executable lives in image at `/bin/typst` with image `ENTRYPOINT` set accordingly.[^typst-dockerfile]

##### User Targeting

- Image defines a `typst` non-root user and notes it can be used via container runtime `--user` selection.[^typst-dockerfile]

##### Required Privileges

- Requires permission to run Docker containers on the host.

##### Tool-Specific Configurations

- Pass Typst CLI flags and env vars at container run time (`-e TYPST_*`, bind mounts for project, fonts, package cache as needed).[^typst-cli-args][^typst-cli-info][^typst-kit-package]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Not applicable unless a local wrapper/alias is created.

##### Configuration Files

- No mandatory Typst config file required.

##### Environment Variables

- Provide runtime variables through `docker run -e ...` as needed.

##### Activation Scripts

- None required.

##### Cleanup

- Remove unused containers/images with standard Docker cleanup commands.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Pull/run a different image tag.

##### Uninstallation

- Remove local image copies from host image cache when no longer needed.

##### Idempotency

- Re-running containers from same immutable image tag is deterministic for equivalent inputs; image pulls are layer-cached by Docker.

#### Notes and Best Practices

- Pin image tags in CI/build workflows to avoid accidental drift from `latest`.
- Mount explicit working and cache/package directories to control reproducibility and persistence.

## Dev Container Setup

Two practical patterns are available for dev containers:

1. Use the community Typst Dev Container Feature from `devcontainers-extra/features`:
   - Feature ID: `ghcr.io/devcontainers-extra/features/typst:1`
   - Option: `version` (default `latest`)
   - Implementation delegates to a shared `gh-release` feature installer for `typst/typst` release binaries.[^devextra-feature-json][^devextra-feature-install][^devextra-feature-readme]

2. Use the official Typst container image directly as base image:
   - Typst binary is present at `/bin/typst`
   - Image entrypoint is `/bin/typst`
   - Includes OCI metadata and a non-root `typst` user definition.[^typst-dockerfile]

When using the official image in a devcontainer, account for entrypoint behavior (for example by overriding command/entrypoint in devcontainer configuration) if you need a shell-first development workflow instead of Typst-first command execution.

## Plugins and Extensions

Typst itself does not expose a traditional plugin-manager CLI command comparable to package-manager ecosystems, but it has a first-class package/template ecosystem and a strong editor-extension ecosystem.

### Typst Packages and Templates (Universe)

- Community templates and packages are published in Typst Universe and backed by the Typst package repository (`typst/packages`).[^typst-readme][^typst-packages-repo]
- The default registry is `https://packages.typst.org`, with default namespace `preview` and local/cache paths managed by Typst package storage logic.[^typst-kit-package]
- CLI supports initializing projects from templates, including `@preview/...` identifiers and version-qualified template references via `typst init`.[^typst-cli-args]

### Tinymist Language Server and Editor Integrations

- Typst README identifies Tinymist as a community language server integrated into multiple editor extensions.[^typst-readme]
- Tinymist documentation lists integrations for VS Code/VSCodium, Neovim, Emacs, Sublime Text, Helix, and Zed, and describes LSP-centric features such as diagnostics, code actions, formatting, symbol/navigation support, and preview/export tooling.[^tinymist-docs]

For feature implementation in development environments, Tinymist is the most established editor-side integration to pair with the Typst CLI compiler.

## References

[^typst-open-source]: [Typst Open Source Page](https://typst.app/open-source/) - Official overview of the open-source compiler, install options, and context vs the web app.
[^typst-readme]: [typst/typst README (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/README.md) - Canonical installation, usage, and ecosystem links published by the Typst project.
[^typst-release-latest]: [GitHub API - typst/typst latest release](https://api.github.com/repos/typst/typst/releases/latest) - Authoritative latest stable version, publish date, release assets, and checksums/digests.
[^typst-arch]: [Typst Compiler Architecture](https://raw.githubusercontent.com/typst/typst/v0.14.2/docs/dev/architecture.md) - Official architectural overview of Typst compiler crates and compilation phases.
[^typst-cli-args]: [typst-cli args.rs (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/crates/typst-cli/src/args.rs) - Source of CLI subcommands, flags, and environment-variable bindings.
[^typst-cli-main]: [typst-cli main.rs (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/crates/typst-cli/src/main.rs) - Entry-point dispatch and behavior when self-update feature is unavailable.
[^typst-cli-update]: [typst-cli update.rs (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/crates/typst-cli/src/update.rs) - Self-update implementation details, downgrade/revert behavior, backup path handling, and asset resolution.
[^typst-cli-info]: [typst-cli info.rs (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/crates/typst-cli/src/info.rs) - Runtime environment-variable inventory and resolved package/font configuration reporting.
[^typst-cli-cargo]: [typst-cli Cargo.toml (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/crates/typst-cli/Cargo.toml) - CLI packaging metadata, binary definition, and compile-time feature flags.
[^typst-kit-package]: [typst-kit package.rs (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/crates/typst-kit/src/package.rs) - Default package registry, namespace, package path/cache defaults, and package download behavior.
[^typst-release-workflow]: [Release Workflow (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/.github/workflows/release.yml) - Official build target matrix and release artifact packaging process.
[^brew-man]: [Homebrew Manpage](https://docs.brew.sh/Manpage) - Official command semantics for Homebrew install/upgrade/uninstall and path behavior.
[^winget-install]: [WinGet install command](https://learn.microsoft.com/en-us/windows/package-manager/winget/install) - Official install syntax, options, and scope/version controls.
[^winget-upgrade]: [WinGet upgrade command](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade) - Official upgrade syntax and version handling.
[^winget-uninstall]: [WinGet uninstall command](https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall) - Official uninstall syntax, options, and source/scope controls.
[^cargo-install]: [Cargo install command reference](https://doc.rust-lang.org/cargo/commands/cargo-install.html) - Official install semantics, version/source selection, path/root precedence, and idempotency rules.
[^cargo-uninstall]: [Cargo uninstall command reference](https://doc.rust-lang.org/cargo/commands/cargo-uninstall.html) - Official uninstall semantics and root targeting.
[^nix-run]: [nix run command reference](https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-run) - Official execution semantics for flake/installable-based invocation.
[^nix-profile-install]: [nix profile install command reference](https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-profile-install) - Official persistent profile installation semantics.
[^nix-profile-remove]: [nix profile remove command reference](https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-profile-remove) - Official profile removal semantics.
[^typst-dockerfile]: [Typst Dockerfile (v0.14.2)](https://raw.githubusercontent.com/typst/typst/v0.14.2/Dockerfile) - Official container image entrypoint, user, and image construction details.
[^devextra-feature-json]: [devcontainers-extra Typst feature manifest](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/typst/devcontainer-feature.json) - Community feature metadata, version option, and dependency relationship.
[^devextra-feature-install]: [devcontainers-extra Typst feature install.sh](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/typst/install.sh) - Actual installer logic showing release-based install delegation.
[^devextra-feature-readme]: [devcontainers-extra Typst feature README](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/typst/README.md) - Usage example and option summary for the community devcontainer feature.
[^typst-packages-repo]: [Typst Packages Repository](https://github.com/typst/packages/) - Canonical package repository for Typst ecosystem packages/templates.
[^tinymist-docs]: [Tinymist Documentation](https://myriad-dreamin.github.io/tinymist/) - Established third-party LSP/editor integration documentation for Typst.