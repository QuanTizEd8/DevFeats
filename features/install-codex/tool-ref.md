# Feature Reference

Codex CLI is OpenAI's local coding agent for software development workflows in a terminal. It can read and edit files, run commands, and interact with OpenAI-hosted model endpoints while applying configurable sandbox and approval policies.[^openai-overview][^openai-security]

The tool is distributed through multiple channels: npm (global package), Homebrew cask, GitHub release assets (manual binaries), and official standalone installer scripts for Unix-like systems and Windows. It also supports source builds from the Rust workspace for contributors and advanced users.[^openai-readme][^openai-install-doc][^openai-install-sh-src][^openai-install-ps1-src]

- **Homepage**: https://developers.openai.com/codex
- **Source Code**: https://github.com/openai/codex
- **Documentation**: https://developers.openai.com/codex
- **Latest Release**: 0.130.0 (as of 2026-05-17)[^openai-release-latest][^openai-npm-latest]

## Tool Architecture

Codex CLI is a hybrid distribution:

1. A Node.js launcher package (`@openai/codex`) exposes the `codex` command.
2. The launcher resolves a platform-specific payload package and then executes a native `codex` binary.
3. Platform payloads include additional helper binaries. For example:
   - Linux payloads include `codex`, `rg` (ripgrep), and `bwrap`.
   - macOS payloads include `codex` and `rg`.
   - Windows payloads include `codex`, `rg`, `codex-windows-sandbox-setup`, and `codex-command-runner`.[^openai-codex-js][^openai-build-npm][^openai-install-native-deps]

The npm "meta package" uses optional platform-specific dependencies and dispatch logic keyed by OS/CPU target triples, so one package name can install on multiple architectures.[^openai-codex-js][^openai-build-npm]

At runtime, Codex stores local state under `CODEX_HOME` (default `~/.codex`), including configuration, logs, and optionally local history. Authentication can be stored in `~/.codex/auth.json` or in an OS keyring depending on `cli_auth_credentials_store`.[^openai-config-advanced][^openai-config-reference][^openai-auth]

Codex is not a standalone offline binary-only tool in normal use: it typically calls remote model/provider endpoints unless configured for local/alternative providers. Security boundaries are enforced by sandbox mode plus approval policy, with OS-specific sandbox implementations on macOS, Linux, and Windows.[^openai-config-advanced][^openai-security][^openai-windows]

## Installation Methods

Codex supports package-manager installation, direct installer scripts, manual release asset installation, and source builds.[^openai-readme][^openai-install-doc]

### NPM Global Installation

#### Supported Platforms

- Linux (`x64`, `arm64`), macOS (`x64`, `arm64`), and Windows (`x64`, `arm64`) via platform payload mapping in the launcher/package build scripts.[^openai-codex-js][^openai-build-npm]

#### Dependencies

##### Common Dependencies

- Node.js `>=16` (package `engines` requirement).
- npm global install capability.[^openai-npm-0130-metadata][^npm-global-install]

##### Platform-Specific Dependencies

- Unix-like systems: global binaries are linked into `{prefix}/bin`.
- Windows: global binaries are linked into `{prefix}`.[^npm-folders][^npm-install-doc]

#### Installation Steps

1. Install globally:

   ```bash
   npm install -g @openai/codex
   ```

2. Start Codex:

   ```bash
   codex
   ```

3. If you encounter `EACCES` permission errors, use a Node version manager (recommended) or move npm's global `prefix` to a user-local path and update your shell PATH.[^npm-global-install][^npm-eacces]

#### Installation Verification

Use:

```bash
codex --version
```

The launcher delegates to the native binary for the current platform and exits with the native process exit code.[^openai-codex-js]

#### Configuration Options

##### Version Selection

- Install latest explicitly:

  ```bash
  npm install -g @openai/codex@latest
  ```

- Install a pinned version:

  ```bash
  npm install -g @openai/codex@0.130.0
  ```

- `npm update -g @openai/codex` updates globally installed packages but follows npm update semantics; for deterministic latest/pinned outcomes, use `npm install -g @openai/codex@...`.[^npm-install-doc][^npm-update-doc]

##### Installation Path

- npm global installation uses `prefix`:
  - Unix packages in `{prefix}/lib/node_modules`, executables in `{prefix}/bin`.
  - Windows packages in `{prefix}/node_modules`, executables in `{prefix}`.
- Default `prefix` is where Node is installed (commonly `/usr/local` on Unix, `%AppData%\npm` on Windows), unless overridden.[^npm-folders]

##### User Targeting

- User-local and system-level global installs are both possible, depending on npm `prefix` and permissions.
- npm's documented non-root pattern is user-local prefix plus shell PATH update.[^npm-eacces][^npm-folders]

##### Required Privileges

- Root/admin is not intrinsically required by Codex, but may be required by the chosen npm `prefix` location.
- npm guidance recommends avoiding sudo by using a version manager or adjusting prefix to a user-local directory.[^npm-global-install][^npm-eacces]

##### Tool-Specific Configurations

Common Codex runtime settings after install:

- Config locations: `~/.codex/config.toml` plus optional project `.codex/config.toml` layers.
- Precedence: CLI flags/overrides > selected profile > project config layers (trusted projects) > user config > system config > defaults.
- Frequently set keys: `model`, `approval_policy`, `sandbox_mode`, `default_permissions`, `web_search`, `log_dir`, `cli_auth_credentials_store`.[^openai-config-basic][^openai-config-reference]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure the npm global binary directory (`{prefix}/bin` on Unix, `{prefix}` on Windows) is on PATH.
- If using a custom user prefix such as `~/.local`, add `~/.local/bin` to shell startup files.[^npm-folders][^npm-eacces]

##### Configuration Files

- User config: `~/.codex/config.toml`
- Project config: `.codex/config.toml` (trusted projects only)
- Optional system config: `/etc/codex/config.toml` on Unix
- Auth cache (file mode): `~/.codex/auth.json`.[^openai-config-basic][^openai-config-advanced][^openai-auth]

##### Environment Variables

- `CODEX_HOME` changes local state root.
- `CODEX_CA_CERTIFICATE` (fallback `SSL_CERT_FILE`) for custom CA bundles in constrained enterprise networks.[^openai-config-advanced][^openai-auth]

##### Activation Scripts

- None specific to Codex.
- If PATH was changed in profile files, source the profile or open a new shell.[^npm-eacces]

##### Cleanup

- npm manages package files in global npm folders and cache.
- Optional npm cache maintenance follows normal npm workflows.[^npm-folders]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Recommended deterministic approach:

  ```bash
  npm install -g @openai/codex@<version>
  ```

- Optional update command:

  ```bash
  npm update -g @openai/codex
  ```

  (subject to npm update behavior/ranges).[^npm-update-doc]

##### Uninstallation

```bash
npm uninstall -g @openai/codex
```

Global uninstall removes the global package context.[^npm-uninstall-doc]

##### Idempotency

- Re-running `npm install -g @openai/codex` is safe and converges to the requested version/tag.
- If platform optional dependencies are missing, launcher errors explicitly and asks for reinstall.[^npm-install-doc][^openai-codex-js]

#### Notes and Best Practices

- Avoid maintaining multiple active Codex installs from different managers without clear PATH ordering.
- The official installers explicitly warn that PATH ambiguity can occur when multiple managed installs coexist.[^openai-install-sh-src][^openai-install-ps1-src]

### Homebrew Cask Installation

#### Supported Platforms

- Homebrew cask metadata for Codex includes macOS (Intel/Apple Silicon) and Linux (`x86_64`/`arm64`) packages.[^homebrew-cask-codex][^formulae-codex]

#### Dependencies

##### Common Dependencies

- Homebrew installation and PATH setup.
- Codex cask depends on Homebrew formula `ripgrep`.[^homebrew-cask-codex][^brew-manpage]

##### Platform-Specific Dependencies

- Homebrew prefix defaults differ by platform:
  - macOS ARM: `/opt/homebrew`
  - macOS Intel: `/usr/local`
  - Linux: `/home/linuxbrew/.linuxbrew`.[^brew-manpage][^brew-faq]

#### Installation Steps

1. Install with Homebrew:

   ```bash
   brew install --cask codex
   ```

2. Verify command availability:

   ```bash
   codex --version
   ```

3. If Homebrew is newly installed, load shell environment:

   ```bash
   eval "$(brew shellenv)"
   ```

   and reopen shell as needed.[^formulae-codex][^brew-manpage]

#### Installation Verification

- `brew info --cask codex`
- `codex --version`.[^formulae-codex][^brew-manpage]

#### Configuration Options

##### Version Selection

- Standard cask install tracks the cask-defined version (currently 0.130.0).
- Homebrew upgrade flow controls when updates are applied (`brew upgrade --cask codex`).
- Pinning can prevent upgrades (`brew pin codex` / `brew unpin codex`), noting cask app self-updaters may still update independently.[^homebrew-cask-codex][^brew-manpage][^brew-faq]

##### Installation Path

- Homebrew-managed cask artifacts install under Caskroom, with binaries linked into Homebrew prefix/bin conventions.
- Query with `brew --caskroom` and `brew --prefix`.[^brew-manpage]

##### User Targeting

- Homebrew is designed primarily for single-user environments and installs into user-controlled prefixes.[^brew-faq]

##### Required Privileges

- Homebrew documentation explicitly discourages/blocks sudo workflows for regular brew operations.[^brew-faq]

##### Tool-Specific Configurations

- Codex runtime configuration is independent of Homebrew and uses standard `config.toml` and auth settings described in Config/Auth docs.[^openai-config-basic][^openai-auth]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure Homebrew prefix/bin is on PATH (typically via `brew shellenv`).[^brew-manpage]

##### Configuration Files

- Same Codex config/auth files as other methods (`~/.codex/config.toml`, optional `.codex/config.toml`, and auth cache/keyring).[^openai-config-basic][^openai-auth]

##### Environment Variables

- Homebrew environment variables may influence install/upgrade behavior.
- Codex runtime env vars (`CODEX_HOME`, `CODEX_CA_CERTIFICATE`) remain applicable.[^brew-manpage][^openai-auth]

##### Activation Scripts

- No Codex-specific activation script. Use shell profile evaluation for Homebrew PATH if needed.[^brew-manpage]

##### Cleanup

- Use standard Homebrew cleanup lifecycle (`brew cleanup`) as desired.[^brew-manpage]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Upgrade with:

  ```bash
  brew upgrade --cask codex
  ```

- Downgrades are not a first-class simple cask operation in normal workflows and generally require advanced tap/history workflows.[^brew-manpage]

##### Uninstallation

```bash
brew uninstall --cask codex
```

The cask defines `zap` cleanup for `~/.codex` directory removal semantics in Homebrew cask maintenance contexts.[^brew-manpage][^homebrew-cask-codex]

##### Idempotency

- `brew install` is idempotent for already-installed current versions.
- If installed cask is outdated, Homebrew can upgrade during install unless configured otherwise.[^brew-manpage]

#### Notes and Best Practices

- Use default Homebrew prefix to maximize bottle/prebuilt compatibility and avoid unsupported source-build fallbacks.[^brew-faq]

### Official Standalone Installer Scripts (`install.sh` / `install.ps1`)

#### Supported Platforms

- `install.sh`: macOS and Linux, `x86_64`/`aarch64` (with Rosetta-aware handling for Intel-translated Apple Silicon).
- `install.ps1`: Windows `x64`/`arm64`, 64-bit OS required.[^openai-install-sh-src][^openai-install-ps1-src]

#### Dependencies

##### Common Dependencies

- Network access to GitHub release assets and release metadata API.
- Shell/PowerShell runtime appropriate for platform.[^openai-install-sh-src][^openai-install-ps1-src]

##### Platform-Specific Dependencies

- Unix script requires `mktemp`, `tar`, and either `curl` or `wget`; checksum verification requires `sha256sum` or `shasum` or `openssl`.
- Windows script uses PowerShell built-ins (`Invoke-WebRequest`, `Get-FileHash`) and `tar` extraction path in script flow.[^openai-install-sh-src][^openai-install-ps1-src]

#### Installation Steps

1. Download `install.sh` or `install.ps1` from the release assets (or latest-download endpoint).
2. Run installer with optional version selection:
   - Unix: `sh install.sh --release <version|latest>`
   - Windows: `./install.ps1 -Release <version|latest>`
3. Installer resolves release tag, downloads platform npm payload archive (`codex-npm-<platform>-<version>.tgz`), validates SHA-256 against GitHub release asset digest metadata, extracts payload, and installs a standalone layout under `CODEX_HOME`.
4. Installer updates visible command links and verifies with `codex --version`.
5. Installer may prompt to uninstall conflicting npm/bun/brew-managed installs to reduce PATH ambiguity.[^openai-install-sh-src][^openai-install-ps1-src][^openai-release-latest]

#### Installation Verification

- Installers perform internal version-command verification.
- Manual check:

  ```bash
  codex --version
  ```

- Archive digest validation is built in and sourced from release metadata (`digest` field).[^openai-install-sh-src][^openai-install-ps1-src]

#### Configuration Options

##### Version Selection

- Unix flag: `--release` accepts normalized forms (`latest`, `rust-vX.Y.Z`, `vX.Y.Z`, `X.Y.Z`).
- Windows parameter: `-Release` supports equivalent normalization.[^openai-install-sh-src][^openai-install-ps1-src]

##### Installation Path

- Unix defaults:
  - Visible command link: `~/.local/bin/codex` (overridable with `CODEX_INSTALL_DIR`)
  - Standalone root: `~/.codex/packages/standalone` (overridable with `CODEX_HOME`)
- Windows defaults:
  - Visible bin directory: `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin` (overridable with `CODEX_INSTALL_DIR`)
  - Standalone root: `%USERPROFILE%\.codex\packages\standalone` (overridable with `CODEX_HOME`).[^openai-install-sh-src][^openai-install-ps1-src]

##### User Targeting

- Designed as per-user install by default (home/profile-local paths).
- No mandatory system-wide placement path in default flow.[^openai-install-sh-src][^openai-install-ps1-src]

##### Required Privileges

- Unix installer does not require sudo in default path usage.
- Windows installer can run per-user; runtime sandbox mode may still involve elevated setup choices depending on host policy.[^openai-install-sh-src][^openai-install-ps1-src][^openai-windows]

##### Tool-Specific Configurations

- Conflict detection with existing manager installs (`npm`, `bun`, `brew`) and optional uninstall prompt.
- Locking/idempotency controls:
  - Unix uses file/directory locking fallback strategies and stale-lock cleanup.
  - Windows uses file lock guard block.
- Unix profile marker block management for PATH (`# >>> Codex installer >>>` block).
- Windows uses junction-based path management for `current` and visible command directory.[^openai-install-sh-src][^openai-install-ps1-src]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Unix installer auto-adds PATH export block when needed.
- Windows installer updates User PATH and also current session PATH when needed.[^openai-install-sh-src][^openai-install-ps1-src]

##### Configuration Files

- Standard Codex config/auth locations under `CODEX_HOME` still apply (`config.toml`, `auth.json` if file credential mode).[^openai-config-advanced][^openai-auth]

##### Environment Variables

- Installer-specific: `CODEX_INSTALL_DIR`, `CODEX_HOME`.
- Runtime auth/network: `CODEX_CA_CERTIFICATE` and `SSL_CERT_FILE` fallback for TLS roots.[^openai-install-sh-src][^openai-install-ps1-src][^openai-auth]

##### Activation Scripts

- No separate activation script; shell/profile updates are done directly where needed.[^openai-install-sh-src][^openai-install-ps1-src]

##### Cleanup

- Installers clear stale staging artifacts/temporary links but keep installed releases and current pointers.
- Versioned release directories remain under standalone root.[^openai-install-sh-src][^openai-install-ps1-src]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Re-run installer with desired `--release` / `-Release` value. Same script path handles upgrades and downgrades.[^openai-install-sh-src][^openai-install-ps1-src]

##### Uninstallation

- No dedicated uninstall subcommand in scripts.
- Manual uninstall consists of removing:
  - Visible command link/path
  - Standalone release root under `CODEX_HOME/packages/standalone`
  - Installer-inserted PATH/profile entries where applicable.[^openai-install-sh-src][^openai-install-ps1-src]

##### Idempotency

- Scripts detect already-complete release directories and avoid unnecessary reinstallation.
- They still refresh current symlink/junction targets and command verification, making repeated runs safe and convergent.[^openai-install-sh-src][^openai-install-ps1-src]

#### Notes and Best Practices

- Prefer a single active manager/install channel per host to avoid PATH ambiguity.
- Keep `CODEX_HOME` in persistent storage if shell history/auth/config persistence is desired across ephemeral environments.[^openai-install-sh-src][^openai-config-advanced]

### Manual GitHub Release Binary Download

#### Supported Platforms

- README highlights macOS (`arm64`, `x86_64`) and Linux musl (`arm64`, `x86_64`) tarballs for direct binary usage.
- Release assets also include Windows executable artifacts in current releases.[^openai-readme][^openai-release-assets][^openai-release-latest]

#### Dependencies

##### Common Dependencies

- Ability to download release asset and metadata.
- Archive extraction tooling and executable placement on PATH.[^openai-readme][^openai-release-latest]

##### Platform-Specific Dependencies

- Unix: `tar` extraction and executable bit setting.
- Windows: `.exe` placement in PATH-managed directory.[^openai-readme][^openai-release-assets]

#### Installation Steps

1. Choose release tag and platform asset.
2. Download archive.
3. Verify digest using release metadata `digest` field.
4. Extract and rename platform-baked binary to `codex` (or keep `.exe` on Windows).
5. Move binary into PATH directory.[^openai-readme][^openai-release-latest]

#### Installation Verification

```bash
codex --version
```

#### Configuration Options

##### Version Selection

- Fully manual: choose exact GitHub release tag and corresponding asset.[^openai-readme][^openai-release-latest]

##### Installation Path

- Fully manual: any directory on PATH (user-local recommended).[^openai-readme]

##### User Targeting

- User-local or system-wide based on chosen destination path and permissions.

##### Required Privileges

- Depends entirely on destination directory permissions.

##### Tool-Specific Configurations

- Same runtime `config.toml`/auth model as other installation methods.[^openai-config-basic][^openai-auth]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Ensure chosen binary destination is in PATH.

##### Configuration Files

- Standard Codex config/auth files under `CODEX_HOME` defaults.[^openai-config-advanced][^openai-auth]

##### Environment Variables

- `CODEX_HOME`, optional TLS CA env vars as needed.[^openai-config-advanced][^openai-auth]

##### Activation Scripts

- None, except shell profile updates for PATH where needed.

##### Cleanup

- Remove downloaded archives/extraction directory after placement.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Replace binary with another release asset version.

##### Uninstallation

- Remove binary from PATH destination and optional local Codex state directory.

##### Idempotency

- Manual process behavior is operator-defined; no built-in transactional guardrails.

#### Notes and Best Practices

- Prefer installer scripts over manual placement when you need checksum validation, lock protection, and managed link updates.[^openai-install-sh-src][^openai-install-ps1-src]

### Build From Source (Rust Workspace)

#### Supported Platforms

- Documented source-build baseline: macOS 12+, Ubuntu 20.04+/Debian 10+, or Windows 11 via WSL2.[^openai-install-doc]

#### Dependencies

##### Common Dependencies

- Git clone access.
- Rust toolchain via rustup.
- Rust components `rustfmt` and `clippy`.
- `just` helper tool.
- Optional `cargo-nextest`.[^openai-install-doc]

##### Platform-Specific Dependencies

- Windows path for source build is documented via WSL2 in install/build guidance.[^openai-install-doc]

#### Installation Steps

1. Clone repository and enter Rust workspace.
2. Install Rust toolchain/components.
3. Install helper tools (`just`, optional `cargo-nextest`).
4. Build and run with Cargo.
5. Use project helpers for formatting/tests as needed.[^openai-install-doc]

#### Installation Verification

- `cargo run --bin codex -- "..."`
- Relevant crate tests (`cargo test -p ...`) or `just test` when configured.[^openai-install-doc]

#### Configuration Options

##### Version Selection

- Controlled by Git ref checkout and Rust build state.

##### Installation Path

- Build artifacts under workspace target directories unless custom cargo target dirs are configured.

##### User Targeting

- User-local development workflow.

##### Required Privileges

- No root required in normal Rust user setup.

##### Tool-Specific Configurations

- TUI logging defaults and `RUST_LOG` behavior are documented in install/build doc.
- Log directory can be overridden with CLI config key `log_dir` and one-off `-c` override.[^openai-install-doc][^openai-config-basic]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- Source Rust cargo environment as needed (`$HOME/.cargo/env`).[^openai-install-doc]

##### Configuration Files

- Same Codex runtime config files when running built binary (`config.toml` layers).[^openai-config-basic]

##### Environment Variables

- `RUST_LOG` for logging verbosity.
- Optional Codex env vars (`CODEX_HOME`, custom CA variables) remain applicable.[^openai-install-doc][^openai-auth]

##### Activation Scripts

- Rust toolchain activation through cargo env sourcing for fresh shells.[^openai-install-doc]

##### Cleanup

- Standard Rust workspace cleanup (`target` directory management) per project workflow.[^openai-install-doc]

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

- Checkout a different repository tag/commit and rebuild.

##### Uninstallation

- Remove workspace checkout and any manually installed helper binaries if no longer needed.

##### Idempotency

- Re-running `cargo build` is incremental and safe.

#### Notes and Best Practices

- Upstream guidance recommends avoiding routine `--all-features` local test runs due to build time/disk overhead.[^openai-install-doc]

## Dev Container Setup

For devcontainer-based usage, npm global installation is the most straightforward baseline, while standalone script installs are useful when you want Codex-managed per-user standalone roots inside the container filesystem.[^openai-readme][^openai-install-sh-src]

Security and sandboxing considerations in containers:

- Codex Linux sandbox relies on OS primitives (`bwrap` + `seccomp`); some container runtimes/capability sets can block required operations.
- OpenAI documents a secure devcontainer reference and notes that if the container itself is your intended isolation boundary, running with full-access mode inside the container may be appropriate.
- This tradeoff must be treated as elevated risk and used only for trusted codebases.[^openai-security]

Recommended container practices:

1. Persist `CODEX_HOME` (`~/.codex`) on a volume if you want stable auth/config/history between rebuilds.
2. Decide explicitly whether Codex inner sandbox or container boundary is authoritative.
3. Keep approval policies restrictive by default in shared team containers.[^openai-config-advanced][^openai-security]

Comparable devcontainer feature patterns from established projects:

- `devcontainers/features` `github-cli` feature exposes version selection and release-based install controls.
- Anthropic's `claude-code` feature demonstrates npm-global install flows and dependency bootstrap patterns.
- The devcontainers collection index confirms these as recognized ecosystem feature sources.[^devcontainers-ghcli-feature][^devcontainers-ghcli-install][^anthropic-claude-feature][^devcontainers-collection-index]

## Plugins and Extensions

Codex supports multiple extension surfaces beyond the CLI binary itself.

### IDE Extensions

- Official Codex IDE extension is distributed through VS Code Marketplace (`openai.chatgpt`) and supports VS Code, Cursor, Windsurf, and JetBrains integrations.
- It shares sign-in methods (ChatGPT or API key) and follows platform-specific guidance for Windows native vs WSL2 workflows.[^openai-ide][^openai-auth][^openai-windows]

### MCP Servers and Provider Extensions

- Codex supports MCP server integrations and custom model providers through `config.toml` (`mcp_servers.*`, `model_providers.*`).
- This is the primary "plugin-like" extensibility mechanism for tool/action expansion and alternate inference backends in enterprise or local proxy environments.[^openai-config-basic][^openai-config-advanced][^openai-config-reference]

## References

[^openai-overview]: [OpenAI Developers - Codex Overview](https://developers.openai.com/codex) - Product overview, high-level capabilities, and positioning.
[^openai-readme]: [openai/codex README](https://github.com/openai/codex/blob/main/README.md) - Canonical CLI install methods (`npm`, Homebrew, release binary hints) and quickstart context.
[^openai-install-doc]: [openai/codex docs/install.md](https://github.com/openai/codex/blob/main/docs/install.md) - Source build system requirements, build/test workflow, and logging behavior.
[^openai-codex-js]: [openai/codex codex-cli/bin/codex.js](https://github.com/openai/codex/blob/main/codex-cli/bin/codex.js) - Launcher target mapping, platform package resolution, environment setup, and process forwarding.
[^openai-build-npm]: [openai/codex codex-cli/scripts/build_npm_package.py](https://github.com/openai/codex/blob/main/codex-cli/scripts/build_npm_package.py) - npm packaging model, optional dependency aliasing, and per-platform native component composition.
[^openai-install-native-deps]: [openai/codex codex-cli/scripts/install_native_deps.py](https://github.com/openai/codex/blob/main/codex-cli/scripts/install_native_deps.py) - Native component acquisition/install details (`codex`, `rg`, `bwrap`, Windows helpers).
[^openai-install-sh-src]: [openai/codex scripts/install/install.sh](https://github.com/openai/codex/blob/main/scripts/install/install.sh) - Unix standalone installer logic, paths, digest verification, lock/idempotency, PATH/profile management, and conflict handling.
[^openai-install-ps1-src]: [openai/codex scripts/install/install.ps1](https://github.com/openai/codex/blob/main/scripts/install/install.ps1) - Windows standalone installer logic, digest verification, junction handling, PATH updates, and conflict handling.
[^openai-release-latest]: [GitHub Releases API - openai/codex latest](https://api.github.com/repos/openai/codex/releases/latest) - Authoritative latest release version, publish date, and release asset digest metadata.
[^openai-release-assets]: [openai/codex release assets listing (tag rust-v0.130.0)](https://github.com/openai/codex/releases/tag/rust-v0.130.0) - Platform asset matrix including tarballs/zips/executables and installer scripts.
[^openai-npm-latest]: [npm Registry - @openai/codex latest package metadata](https://registry.npmjs.org/@openai/codex/latest) - Latest npm-published version and publish timestamp.
[^openai-npm-0130-metadata]: [npm Registry - @openai/codex version 0.130.0](https://registry.npmjs.org/@openai/codex/0.130.0) - Node engine constraint, binary entry point, and optional platform dependency mapping.
[^npm-global-install]: [npm Docs - Downloading and installing packages globally](https://docs.npmjs.com/downloading-and-installing-packages-globally) - Canonical global install command and EACCES guidance link.
[^npm-eacces]: [npm Docs - Resolving EACCES permissions errors when installing packages globally](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally) - Recommended non-sudo remediation and user-prefix PATH setup.
[^npm-install-doc]: [npm CLI Docs - npm install](https://docs.npmjs.com/cli/v11/commands/npm-install) - Version/tag selection syntax, global mode behavior, and install semantics.
[^npm-update-doc]: [npm CLI Docs - npm update](https://docs.npmjs.com/cli/v11/commands/npm-update) - Global update semantics and range/`latest` caveats.
[^npm-uninstall-doc]: [npm CLI Docs - npm uninstall](https://docs.npmjs.com/cli/v11/commands/npm-uninstall) - Global uninstall behavior and command syntax.
[^npm-folders]: [npm CLI Docs - Folders](https://docs.npmjs.com/cli/v11/configuring-npm/folders) - Global prefix defaults and package/bin directory layouts.
[^brew-manpage]: [Homebrew Manpage](https://docs.brew.sh/Manpage) - Command semantics (`install`, `upgrade`, `uninstall`, `shellenv`, `--prefix`, cask behavior).
[^brew-faq]: [Homebrew FAQ](https://docs.brew.sh/FAQ) - Sudo/permissions model, default prefixes, pinning behavior, and cleanup/uninstall notes.
[^homebrew-cask-codex]: [Homebrew Cask Definition - codex.rb](https://github.com/Homebrew/homebrew-cask/blob/master/Casks/c/codex.rb) - Cask URL template, checksums, dependency on `ripgrep`, completion generation, and zap behavior.
[^formulae-codex]: [Formulae Homebrew - codex cask page](https://formulae.brew.sh/cask/codex) - Installation command and cask metadata surface.
[^openai-auth]: [OpenAI Developers - Codex Authentication](https://developers.openai.com/codex/auth) - ChatGPT/API-key auth modes, credential caching/storage options, enterprise token and CA-bundle settings.
[^openai-config-basic]: [OpenAI Developers - Codex Config Basics](https://developers.openai.com/codex/config-basic) - Config layer locations, precedence, and common key patterns.
[^openai-config-advanced]: [OpenAI Developers - Codex Advanced Config](https://developers.openai.com/codex/config-advanced) - Profiles, one-off overrides, state locations, provider and sandbox/approval advanced controls.
[^openai-config-reference]: [OpenAI Developers - Codex Config Reference](https://developers.openai.com/codex/config-reference) - Complete key-level reference for `config.toml`/`requirements.toml`.
[^openai-security]: [OpenAI Developers - Agent approvals and security](https://developers.openai.com/codex/agent-approvals-security) - Sandbox architecture, network/approval defaults, and container operation guidance.
[^openai-windows]: [OpenAI Developers - Codex on Windows](https://developers.openai.com/codex/windows) - Native Windows sandbox modes, version matrix, and WSL2 guidance.
[^openai-ide]: [OpenAI Developers - Codex IDE extension](https://developers.openai.com/codex/ide) - IDE integration surfaces, marketplace distribution, and supported editors.
[^devcontainers-ghcli-feature]: [devcontainers/features github-cli feature metadata](https://github.com/devcontainers/features/blob/main/src/github-cli/devcontainer-feature.json) - Comparative feature API/options pattern.
[^devcontainers-ghcli-install]: [devcontainers/features github-cli install.sh](https://github.com/devcontainers/features/blob/main/src/github-cli/install.sh) - Comparative installer pattern (version resolution, package manager handling, release fallback).
[^anthropic-claude-feature]: [anthropics/devcontainer-features claude-code install.sh](https://github.com/anthropics/devcontainer-features/blob/main/src/claude-code/install.sh) - Comparative npm-global feature installation and dependency bootstrap pattern.
[^devcontainers-collection-index]: [Dev Container collection index](https://raw.githubusercontent.com/devcontainers/devcontainers.github.io/refs/heads/gh-pages/_data/collection-index.yml) - Registry of well-established devcontainer feature collections.