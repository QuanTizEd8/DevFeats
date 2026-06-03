# Feature Reference

Starship is a minimal, blazing-fast, and infinitely customizable cross-shell prompt.[^docs-guide] It inspects the current environment and displays contextually relevant information — such as the active git branch, current language/tool versions, cloud provider context, and last command exit status — directly in the shell prompt. Because it evaluates all modules in parallel and enforces per-module timeouts, prompt latency stays consistently low even in complex environments.[^docs-config]

Starship is designed to be shell-agnostic and works with bash, zsh, fish, PowerShell, nushell, ion, elvish, tcsh, xonsh, cmd, and ble.sh, among others.[^docs-guide] It is configured entirely through a single TOML file (`~/.config/starship.toml`), with over 60 built-in modules covering version control, programming languages, container/cloud tooling, and system information.[^docs-config]

- **Homepage**: https://starship.rs
- **Source Code**: https://github.com/starship/starship
- **Documentation**: https://starship.rs/guide/
- **Latest Release**: 1.25.1 (as of 2026-06-03)[^repo-releases]

## Tool Architecture

Starship is a single, self-contained compiled binary written in Rust (edition 2024, MSRV 1.90).[^src-cargo] It has no runtime dependency on Rust or any other language runtime; all functionality is embedded in the binary. There is no client–server architecture; the binary is invoked directly by the shell on every prompt render.

Performance is achieved through parallel module evaluation using `rayon`[^src-cargo] and strict scan/command timeouts configurable in the TOML config. Git operations are handled via the `gix` library (a pure-Rust Git implementation), avoiding subprocess spawning for repository inspection.[^src-cargo]

Key compile-time dependencies include:[^src-cargo]
- `clap` — CLI argument parsing
- `gix` — Git repository operations
- `rayon` — Parallel module evaluation
- `toml` / `toml_edit` — TOML configuration file parsing
- `serde` / `serde_json` — Serialization/deserialization
- `chrono` — Date/time formatting
- `regex` — Pattern matching for module detection

Optional features compiled into the default binary include `battery` (power status via `starship-battery`) and `notify` (desktop notifications via `notify-rust`).[^src-cargo] Platform-specific code is gated behind the `nix` crate (Unix/macOS) and the `windows` crate (Windows).[^src-cargo]

Pre-built release binaries are distributed as compressed archives (`.tar.gz` on Unix, `.zip` on Windows) containing only the single `starship` executable. Binary size is approximately 15–20 MB depending on the target platform.[^repo-releases]

## Installation Methods

Starship can be installed via an official shell installer script, OS package managers, the Rust package manager (Cargo), or by downloading pre-built release archives directly. For automated and container-based environments, the official installer script is the recommended approach due to its broad platform support, non-interactive mode, and no dependency on pre-installed package managers.

### Official Installer Script

#### Supported Platforms

The installer script supports the following 12 target triples:[^src-installer]

| Target Triple | Platform |
|---|---|
| `x86_64-unknown-linux-gnu` | Linux x86-64 with glibc |
| `x86_64-unknown-linux-musl` | Linux x86-64 with musl libc |
| `i686-unknown-linux-musl` | Linux x86 (32-bit) with musl libc |
| `aarch64-unknown-linux-musl` | Linux ARM64 with musl libc |
| `arm-unknown-linux-musleabihf` | Linux ARMv7 (hard-float) with musl libc |
| `x86_64-apple-darwin` | macOS Intel |
| `aarch64-apple-darwin` | macOS Apple Silicon |
| `x86_64-pc-windows-msvc` | Windows x86-64 |
| `i686-pc-windows-msvc` | Windows x86 (32-bit) |
| `aarch64-pc-windows-msvc` | Windows ARM64 |
| `x86_64-unknown-freebsd` | FreeBSD x86-64 |
| `riscv64gc-unknown-linux-musl` | Linux RISC-V 64 with musl libc |

The auto-detected Linux target is always `unknown-linux-musl`, which works on both glibc and musl Linux systems. The `x86_64-unknown-linux-gnu` target requires glibc and must be selected explicitly via `--platform`.[^src-installer]

#### Dependencies

##### Common Dependencies

- `sh` (POSIX-compliant shell) to run the script itself
- One of: `curl` (preferred, must not be the snap-packaged version), `wget`, or `fetch` for downloading the release archive[^src-installer]
- `tar` (for `.tar.gz` extraction on Unix) or `unzip` (for `.zip` on Windows)[^src-installer]

##### Platform-Specific Dependencies

- **Linux**: None beyond common dependencies; musl builds are fully static and require no system libraries.
- **macOS**: None beyond common dependencies.
- **Windows**: `unzip` must be available; alternatively, use an MSI installer or a Windows package manager (see [OS Package Managers](#os-package-managers)).

#### Installation Steps

The script is fetched from `https://starship.rs/install.sh` (which is an alias to the canonical source at `https://github.com/starship/starship/blob/master/install/install.sh`) and piped to `sh`:[^src-installer][^docs-guide]

```sh
curl -sS https://starship.rs/install.sh | sh
```

For non-interactive use (required in scripts and containers), pass `--yes` to suppress the confirmation prompt:

```sh
curl -sS https://starship.rs/install.sh | sh -s -- --yes
```

To install to a custom directory and/or a specific version:

```sh
curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin --version v1.25.1
```

The script must be run with `sh`, not `bash` or `zsh`. It performs a shell verification at startup and exits with an error if invoked under non-POSIX bash or zsh.[^src-installer]

The download step attempts download tools in this priority order: `curl` (unless snap-packaged, due to a known issue[^src-installer]), `wget`, then `fetch`.[^src-installer]

#### Installation Verification

After installation, verify by running:

```sh
starship --version
# Output: starship 1.25.1
```

The binary is a single executable file at the installation path (default `/usr/local/bin/starship`). No other files are created by the installer.[^src-installer]

The installer performs no checksum or cryptographic signature verification on the downloaded archive.[^src-installer]

#### Configuration Options

##### Version Selection

Pass `--version` (or `-v`) with the desired tag, e.g. `--version v1.25.1`. Accepts the string `latest` (the default) to install the most recent stable release. The version tag must include the `v` prefix.[^src-installer]

```sh
curl -sS https://starship.rs/install.sh | sh -s -- --yes --version v1.25.1
```

##### Installation Path

The default installation directory is `/usr/local/bin`. Override with `--bin-dir` (or `-b`):[^src-installer]

```sh
curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir ~/.local/bin
```

The script installs only the `starship` binary to `BIN_DIR/starship`.

##### User Targeting

System-wide installation is the default (to `/usr/local/bin`). For user-local installation, specify a user-writable directory via `--bin-dir`:

```sh
curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir ~/.local/bin
```

No `--user` flag exists; user targeting is achieved entirely by choosing a user-writable `--bin-dir`.

##### Required Privileges

If the target `--bin-dir` is not writable by the current user, the script automatically escalates via `sudo`. It errors if `sudo` is not available.[^src-installer] To avoid privilege escalation entirely, use a user-writable `--bin-dir` (e.g. `~/.local/bin`).

In a container running as root, no privilege escalation is needed for the default `/usr/local/bin` path.

##### Tool-Specific Configurations

The installer script exposes one additional flag:[^src-installer]

- `--base-url` / `-B`: Override the GitHub Releases base URL used to construct the download URL (default: `https://github.com/starship/starship/releases`). Useful for air-gapped or mirrored environments.
- `--platform` / `-p`: Override the OS/platform string detected by `uname -s`. Accepted values are the platform component of any supported target triple (e.g. `unknown-linux-musl`, `apple-darwin`).
- `--arch` / `-a`: Override the CPU architecture detected by `uname -m`. Accepted values are the arch component of any supported target triple (e.g. `x86_64`, `aarch64`, `arm`).
- `--verbose` / `-V`: Enable verbose output from the script.

#### Post-Installation Steps and Cleanup

##### PATH Setup

If installed to `/usr/local/bin` (the default), no PATH change is needed on most systems. For custom installation directories, add the directory to `PATH` in the appropriate shell profile file:[^docs-guide]

- **bash**: add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` (and `~/.bash_profile` or `~/.profile` for login shells)
- **zsh**: add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`
- **fish**: run `fish_add_path ~/.local/bin`

##### Configuration Files

The installer does **not** create any configuration files. Starship uses the file `~/.config/starship.toml` if it exists, and falls back to built-in defaults if it does not.[^docs-config] Create it manually when needed:

```sh
mkdir -p ~/.config
touch ~/.config/starship.toml
```

The configuration file location can be overridden via the `STARSHIP_CONFIG` environment variable (see [Environment Variables](#environment-variables) below).

##### Environment Variables

The following environment variables affect Starship's runtime behavior and can be set persistently in shell profile files:[^docs-config]

| Variable | Purpose | Default |
|---|---|---|
| `STARSHIP_CONFIG` | Path to the TOML configuration file | `~/.config/starship.toml` |
| `STARSHIP_CACHE` | Directory for Starship's cache and session log files | `~/.cache/starship/` |
| `STARSHIP_SHELL` | Explicitly declare the current shell type (overrides auto-detection) | Auto-detected |
| `STARSHIP_SESSION_KEY` | Unique key for the current shell session (auto-generated UUID) | Auto-generated |

##### Activation Scripts

Starship must be initialized in each interactive shell session by adding an eval call to the shell's RC file. This is **required** for the prompt to activate; installing the binary alone is not sufficient.[^docs-guide]

**bash** — add to `~/.bashrc`:[^docs-guide]
```bash
eval "$(starship init bash)"
```

**zsh** — add to `~/.zshrc`:[^docs-guide]
```bash
eval "$(starship init zsh)"
```

**fish** — add to `~/.config/fish/config.fish`:[^docs-guide]
```fish
starship init fish | source
```

**PowerShell** — add to `$PROFILE`:[^docs-guide]
```powershell
Invoke-Expression (&starship init powershell)
```

**nushell** — add to the Nushell env file (`$nu.env-path`) and config file (`$nu.config-path`):[^docs-guide]
```nu
# env file
$env.STARSHIP_SHELL = "nu"
$env.STARSHIP_SESSION_KEY = (random chars --length 16)
$env.PROMPT_COMMAND = { || starship prompt --cmd-duration $env.CMD_DURATION_MS $'--status=($env.LAST_EXIT_CODE)' }
$env.PROMPT_COMMAND_RIGHT = { || starship prompt --right $'--cmd-duration=($env.CMD_DURATION_MS)' $'--status=($env.LAST_EXIT_CODE)' }
$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ": "
$env.PROMPT_INDICATOR_VI_NORMAL = "〉"
$env.PROMPT_MULTILINE_INDICATOR = "::: "
# config file
use ~/.cache/starship/init.nu
```

**ion** — add to `~/.config/ion/initrc`:[^docs-guide]
```ion
eval $(starship init ion)
```

**tcsh** — add to `~/.tcshrc`:[^docs-guide]
```tcsh
eval `starship init tcsh`
```

**xonsh** — add to `~/.xonshrc`:[^docs-guide]
```python
execx($(starship init xonsh))
```

**ble.sh** (Bash Line Editor) — add to `~/.blerc` or `~/.config/blesh/init.sh`, **after** sourcing ble.sh:[^docs-advanced]
```bash
eval "$(starship init bash)"
```

##### Cleanup

The installer downloads the release archive to a temporary directory (using `mktemp -d`) and removes it after extraction.[^src-installer] No manual cleanup is required after installation.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run the installer with the desired `--version`. The script is idempotent: it unconditionally overwrites the existing binary with the newly downloaded one.[^src-installer]

```sh
# Upgrade to latest
curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Pin to a specific version
curl -sS https://starship.rs/install.sh | sh -s -- --yes --version v1.24.0
```

The `~/.config/starship.toml` configuration file is never touched by the installer; it is preserved across upgrades.

##### Uninstallation

Remove the binary from the installation directory:

```sh
rm /usr/local/bin/starship
# or for a user-local install:
rm ~/.local/bin/starship
```

Remove shell initialization lines from the relevant RC files (`.bashrc`, `.zshrc`, etc.) manually. Optionally remove the configuration and cache:

```sh
rm -f ~/.config/starship.toml
rm -rf ~/.cache/starship/
```

##### Idempotency

The installer is fully idempotent. Running it multiple times against the same `--bin-dir` unconditionally overwrites the existing binary with the requested version. No state from a previous installation is checked or preserved.[^src-installer]

#### Details

The install script performs these steps in order:[^src-installer]

1. **POSIX shell verification**: exits with an error if run under `zsh` or non-POSIX `bash`, since these are known to cause failures.
2. **Argument parsing**: processes all flags from `$@`; defaults `BIN_DIR=/usr/local/bin` and `VERSION=latest`.
3. **Platform detection** (`detect_platform`): runs `uname -s | tr '[:upper:]' '[:lower:]'` and maps the result — `linux`→`unknown-linux-musl`, `darwin`→`apple-darwin`, `freebsd`→`unknown-freebsd`, `msys_nt*`/`cygwin_nt*`/`mingw*`→`pc-windows-msvc`.
4. **Architecture detection** (`detect_arch`): runs `uname -m | tr '[:upper:]' '[:lower:]'` and maps — `amd64`→`x86_64`, `armv*`→`arm`, `arm64`→`aarch64`, `riscv64`→`riscv64gc`. Also runs `getconf LONG_BIT` to downgrade `x86_64`→`i686` or `aarch64`→`arm` on 32-bit kernel userland.
5. **Target validation**: confirms the detected `${ARCH}-${PLATFORM}` triple is in the `SUPPORTED_TARGETS` list; exits with an error if not.
6. **Version resolution**: if `VERSION=latest`, fetches `https://github.com/starship/starship/releases/latest` with a HEAD redirect to determine the current latest version tag.
7. **Download URL construction**: `${BASE_URL}/download/${VERSION}/starship-${ARCH}-${PLATFORM}.tar.gz` (or `.zip` for Windows).
8. **Confirmation prompt**: unless `FORCE` is set (via `-y`/`-f`/`--yes`/`--force`), displays an interactive `[y/N]` prompt before proceeding.
9. **Directory writability check**: tests whether `BIN_DIR` is writable; if not, runs `sudo -v` to cache credentials and prefixes the install command with `sudo`.
10. **Download**: downloads the archive to a `mktemp -d` temporary directory.
11. **Extraction**: runs `tar -xzof` (`.tar.gz`) or `unzip` (`.zip`) to extract `starship` into `BIN_DIR`.
12. **Temp directory cleanup**: removes the temporary directory.

No checksums or signatures are verified at any point.

#### Notes and Best Practices

- **POSIX shell requirement**: Always pipe the script to `sh`, not `bash` or `zsh`. The script enforces this and will exit immediately if run under either.[^src-installer]
- **snap curl incompatibility**: If `curl` is installed via snap, the script skips it and falls back to `wget` or `fetch`. This is a known issue documented upstream.[^src-installer]
- **No checksum verification**: The installer does not verify the integrity of the downloaded archive. For security-sensitive environments, use [Manual Binary Download](#manual-binary-download) and verify checksums manually.
- **Non-interactive use**: Always pass `--yes` (or `-y`) when running in scripts, CI, or container builds to suppress the confirmation prompt. Without it, the script will error when stdin is not a terminal.
- **Linux default is musl**: The auto-detected Linux target is `unknown-linux-musl`, which produces a fully static binary compatible with any Linux distribution regardless of libc version. The `unknown-linux-gnu` build requires a matching glibc version and must be explicitly selected.
- **Shell init is not automatic**: Installing the binary does not activate Starship. The appropriate `eval "$(starship init <shell>)"` (or equivalent) line must be added to the shell's RC file separately.

---

### OS Package Managers

#### Supported Platforms

Package manager availability varies by distribution and platform. Versions in distro repositories may lag behind the latest upstream release.[^docs-guide]

| Package Manager | Platform | Notes |
|---|---|---|
| `apt` | Debian, Ubuntu | Available in apt repositories |
| `pacman` | Arch Linux | Available in official repos |
| `dnf` (Copr) | Fedora, RHEL | Requires enabling the `atim/starship` Copr repo |
| `apk` | Alpine Linux | Available in community repo |
| `brew` | macOS, Linux | Always up-to-date via formula |
| `nix-env` / NixOS | NixOS, any Nix | Available in `nixpkgs` as `starship` |
| `xbps-install` | Void Linux | Available in official repo |
| `emerge` | Gentoo | Available in portage |
| `pkg` | Android/Termux | Available in Termux repo |

#### Dependencies

##### Common Dependencies

None beyond the package manager itself.

##### Platform-Specific Dependencies

None; package managers handle all dependencies automatically.

#### Installation Steps

**APT (Debian/Ubuntu)**:[^docs-guide]
```sh
sudo apt update
sudo apt install -y starship
```

**pacman (Arch Linux)**:[^docs-guide]
```sh
sudo pacman -S starship
```

**Homebrew (macOS/Linux)**:[^docs-guide]
```sh
brew install starship
```

**Fedora via Copr**:[^docs-guide]
```sh
sudo dnf copr enable atim/starship
sudo dnf install starship
```

**Alpine Linux**:[^docs-guide]
```sh
apk add starship
```

**Nix**:[^docs-guide]
```sh
nix-env -iA nixpkgs.starship
```

#### Installation Verification

```sh
starship --version
```

#### Configuration Options

##### Version Selection

Version selection depends on what the package manager offers. Most OS package managers install the version pinned in their repository, which may not be the latest upstream release. Homebrew and the Arch `pacman` repo tend to track upstream closely. To install a specific version, use the [Official Installer Script](#official-installer-script) or [Manual Binary Download](#manual-binary-download) instead.

##### Installation Path

Package managers install `starship` to their standard binary locations (e.g. `/usr/bin/starship` for APT/pacman, `/usr/local/bin/starship` or `$(brew --prefix)/bin/starship` for Homebrew). These paths are managed by the package manager and should not be changed manually.

##### User Targeting

Package manager installations are system-wide and require elevated privileges (`sudo` or root). User-local installation is not supported through package managers; use the installer script with a custom `--bin-dir` instead.

##### Required Privileges

Root or sudo is required for all distro package managers. Homebrew does not require sudo.

##### Tool-Specific Configurations

None specific to this installation method; the binary behavior and configuration file location are identical regardless of installation method.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Package managers place `starship` in a directory that is already on `PATH`. No additional PATH configuration is required.

##### Configuration Files

Same as [Official Installer Script — Configuration Files](#configuration-files): no config file is created automatically; create `~/.config/starship.toml` manually if needed.

##### Environment Variables

Same as [Official Installer Script — Environment Variables](#environment-variables).

##### Activation Scripts

Same as [Official Installer Script — Activation Scripts](#activation-scripts): add the appropriate `eval "$(starship init <shell>)"` line to the shell's RC file.

##### Cleanup

No post-installation cleanup is required.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Upgrade via the package manager's standard upgrade command:
```sh
brew upgrade starship     # Homebrew
sudo apt upgrade starship # APT
sudo pacman -Syu starship # pacman
```

Downgrading depends on the package manager's support for version pinning; most do not support it easily.

##### Uninstallation

```sh
brew uninstall starship         # Homebrew
sudo apt remove starship        # APT
sudo pacman -R starship         # pacman
sudo dnf remove starship        # Fedora
sudo apk del starship           # Alpine
nix-env --uninstall starship    # Nix
```

##### Idempotency

Running the install command when Starship is already installed is safe; most package managers skip reinstallation if the same version is already present, or upgrade if a newer version is available.

#### Notes and Best Practices

- APT and many distro package managers may ship an older version. Verify with `starship --version` after installation and cross-reference with the [latest upstream release][^repo-releases] if a specific version is required.
- Homebrew is generally the most up-to-date option on macOS.

---

### Cargo (Rust Package Manager)

#### Supported Platforms

Any platform with a stable Rust toolchain, including all Linux distros, macOS, Windows, FreeBSD, and others supported by the Rust compiler.[^docs-guide]

#### Dependencies

##### Common Dependencies

- Rust toolchain (`rustup` recommended), version 1.90 or newer (MSRV)[^src-cargo]
- C compiler toolchain (required by Rust; `gcc`/`clang` on Linux/macOS, MSVC build tools on Windows)
- Internet access to download the crate from crates.io

##### Platform-Specific Dependencies

- **Linux**: `pkg-config`, and development headers for OpenSSL if building with TLS features
- **macOS**: Xcode Command Line Tools

#### Installation Steps

```sh
cargo install starship --locked
```

The `--locked` flag uses the exact dependency versions from the upstream `Cargo.lock`, ensuring a reproducible build.[^docs-guide]

#### Installation Verification

```sh
starship --version
```

The binary is installed to `$CARGO_HOME/bin/starship` (default `~/.cargo/bin/starship`).

#### Configuration Options

##### Version Selection

Install a specific version from crates.io:
```sh
cargo install starship --locked --version 1.25.1
```

##### Installation Path

Cargo installs to `$CARGO_HOME/bin/`. This can be overridden with:
```sh
cargo install starship --locked --root /usr/local
```

##### User Targeting

Cargo installs to the current user's `$CARGO_HOME` by default (user-local). Use `--root /usr/local` for system-wide installation (requires write access).

##### Required Privileges

No privileges required for user-local installation. Root/sudo required for system-wide installation paths.

##### Tool-Specific Configurations

`cargo install` builds from source with all default features. Optional features can be disabled, e.g.:

```sh
cargo install starship --locked --no-default-features
```

Disabling the `battery` feature removes the battery status module; disabling `notify` removes desktop notification support.[^src-cargo]

#### Post-Installation Steps and Cleanup

##### PATH Setup

`~/.cargo/bin` must be on `PATH`. The `rustup` installer adds this automatically. If using a custom `--root`, add `<root>/bin` to `PATH` manually.

##### Configuration Files, Environment Variables, Activation Scripts

Same as [Official Installer Script](#post-installation-steps-and-cleanup).

##### Cleanup

Cargo caches downloaded source code in `$CARGO_HOME/registry/`. To clear the cache after installation:
```sh
cargo cache --autoclean   # requires cargo-cache crate
```
Or remove `~/.cargo/registry/` and `~/.cargo/git/` manually.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```sh
cargo install starship --locked --force           # Reinstall/upgrade to latest
cargo install starship --locked --force --version 1.24.0  # Pin to specific version
```

##### Uninstallation

```sh
cargo uninstall starship
```

##### Idempotency

Without `--force`, Cargo skips reinstallation if the same version is already installed. With `--force`, it always reinstalls.

#### Notes and Best Practices

- Cargo builds take 1–5 minutes depending on hardware and whether the Rust compiler cache is warm.
- Not recommended for container builds where build time matters. Use the installer script or binary download instead.
- Always use `--locked` to ensure a reproducible build matching the upstream `Cargo.lock`.

---

### Manual Binary Download

#### Supported Platforms

All 34 pre-built release assets published on the GitHub releases page.[^repo-releases] This is a superset of the platforms supported by the installer script and includes `*-gnu` Linux variants, BSD variants, and ARM targets.

#### Dependencies

##### Common Dependencies

- `curl` or `wget` for downloading
- `tar` (Unix) or `unzip` (Windows) for extraction

##### Platform-Specific Dependencies

None beyond extraction tools.

#### Installation Steps

1. Browse to https://github.com/starship/starship/releases and find the desired release.
2. Download the archive for your platform, e.g. for Linux x86-64 (musl):
   ```sh
   curl -LO https://github.com/starship/starship/releases/download/v1.25.1/starship-x86_64-unknown-linux-musl.tar.gz
   ```
3. Extract the archive:
   ```sh
   tar -xzf starship-x86_64-unknown-linux-musl.tar.gz
   ```
4. Move the binary to the desired location:
   ```sh
   sudo mv starship /usr/local/bin/starship
   chmod +x /usr/local/bin/starship
   ```

Release asset naming convention: `starship-{arch}-{platform}.tar.gz` (Unix) or `starship-{arch}-{platform}.zip` (Windows).

#### Installation Verification

Each release page provides SHA256 checksums in a `checksums.sha256` file. Verify the download:[^repo-releases]

```sh
curl -LO https://github.com/starship/starship/releases/download/v1.25.1/checksums.sha256
sha256sum --check --ignore-missing checksums.sha256
```

Then verify the binary runs:
```sh
starship --version
```

#### Configuration Options

##### Version Selection

Choose any tag from https://github.com/starship/starship/releases and substitute into the download URL.

##### Installation Path

Move the extracted binary to any directory on `PATH`. Common choices:
- `/usr/local/bin/starship` (system-wide)
- `~/.local/bin/starship` (user-local)

##### User Targeting

System-wide vs. user-local is determined by the target path, not by any installer flag.

##### Required Privileges

Root/sudo required only if writing to a root-owned directory such as `/usr/local/bin`.

##### Tool-Specific Configurations

None; binary behavior is identical regardless of download method.

#### Post-Installation Steps and Cleanup

Same as [Official Installer Script](#post-installation-steps-and-cleanup-1) (PATH setup if needed, shell activation script, optional config file).

After installation, remove the downloaded archive:
```sh
rm starship-x86_64-unknown-linux-musl.tar.gz
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Download the desired version and overwrite the existing binary:
```sh
sudo mv starship /usr/local/bin/starship
```

##### Uninstallation

```sh
sudo rm /usr/local/bin/starship
```

##### Idempotency

Fully idempotent; the binary is unconditionally overwritten.

#### Notes and Best Practices

- This is the only method that provides SHA256 checksum verification. Prefer it over the installer script in security-sensitive or air-gapped environments.
- Use the musl Linux builds (`unknown-linux-musl`) for maximum portability across Linux distributions; the glibc builds (`unknown-linux-gnu`) require a minimum glibc version that must match the target system.

---

## Dev Container Setup

Starship is well-suited for dev container environments. The key considerations are:

**Installation**: Use the official installer script with `--yes` and a system-accessible `--bin-dir`. In containers typically running as root during build, the default `/usr/local/bin` is writable without sudo:[^src-installer]

```sh
curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin
```

**Shell initialization**: The container build creates RC files for the target user. The `eval "$(starship init bash)"` (or equivalent) line must be appended to the correct RC file for the user who will use the container. For the default `vscode` user in VS Code dev containers, this is `/home/vscode/.bashrc`.[^feat-tobias]

For bash, the RC file must exist before appending:
```sh
touch /home/vscode/.bashrc
echo 'eval "$(starship init bash)"' >> /home/vscode/.bashrc
```

**User targeting**: When the build runs as root but the runtime user is non-root, ensure the RC file and config file are owned by the correct user. The `$_REMOTE_USER` variable (set by the dev container spec) can be used to identify the target user in a feature install script.[^feat-tobias]

**Configuration file**: Starship works out of the box with its defaults; no `~/.config/starship.toml` is required. To provide a custom config, either:
- Write it directly during the image build: `mkdir -p /home/vscode/.config && cp starship.toml /home/vscode/.config/starship.toml`
- Mount a local file and copy it via `postCreateCommand` in `devcontainer.json`[^feat-tobias]

**Nerd Fonts**: Starship's default configuration uses Nerd Font symbols. In a dev container, the fonts are rendered by the host terminal, not inside the container, so no font installation inside the container is needed. If using the no-nerd-fonts preset or plain ASCII config, this is moot. Load a Nerd Font–free preset by running `starship preset no-nerd-font -o ~/.config/starship.toml` in the container's `postCreateCommand` if the host terminal lacks a Nerd Font.[^docs-presets]

**Non-interactive sessions**: Starship should be initialized only in interactive shells. The `starship init` eval block in `.bashrc` is automatically skipped in non-interactive bash sessions (bash does not source `.bashrc` non-interactively), so no additional guard is needed for most use cases.

**Existing devcontainer feature references**:

- `ghcr.io/devcontainers-extra/features/starship:1` — installs the binary from GitHub Releases via the `gh-release` wrapper feature; does not handle shell initialization.[^feat-extra-starship]
- `ghcr.io/devcontainers-extra/features/starship-homebrew:1` — installs via Homebrew; does not handle shell initialization.[^feat-extra-homebrew]
- `ghcr.io/tobiaschc/devcontainer-features/starship:1` — full integration: installs via `https://starship.rs/install.sh`, adds shell init to `.bashrc`/`.zshrc`, optionally installs Nerd Fonts, supports custom config from a URL.[^feat-tobias]

## Plugins and Extensions

Starship does not have a plugin system in the traditional sense. Customization is done entirely through the `~/.config/starship.toml` configuration file. The tool ships with 60+ built-in modules covering all common development contexts; custom behavior beyond the built-in modules can be achieved through the `custom` module (runs arbitrary shell commands) and `env_var` module (displays environment variables).[^docs-config]

**Presets**: Starship ships 12+ curated configuration presets that can be applied with a single command:[^docs-presets]

```sh
starship preset <preset-name> -o ~/.config/starship.toml
```

Available presets include `nerd-font-symbols`, `no-nerd-font`, `bracketed-segments`, `plain-text-symbols`, `no-runtime-versions`, `no-empty-icons`, `pure-preset`, `pastel-powerline`, `tokyo-night`, `gruvbox-rainbow`, `jetpack`, and `catppuccin-powerline`.[^docs-presets]

List all available presets:
```sh
starship preset --list
```

## References

[^docs-guide]: [Official Starship Guide – Installation](https://starship.rs/guide/)
[^docs-config]: [Official Starship Configuration Documentation](https://starship.rs/config/)
[^docs-advanced]: [Official Starship Advanced Configuration](https://starship.rs/advanced-config/)
[^docs-presets]: [Official Starship Presets](https://starship.rs/presets/)
[^repo-main]: [Official GitHub Repository – starship/starship](https://github.com/starship/starship)
[^repo-releases]: [GitHub Releases – starship/starship](https://github.com/starship/starship/releases)
[^src-installer]: [Official Installer Script Source – install/install.sh](https://github.com/starship/starship/blob/master/install/install.sh)
[^src-cargo]: [Official Cargo.toml – Architecture & Dependencies](https://github.com/starship/starship/blob/master/Cargo.toml)
[^feat-extra-starship]: [devcontainers-extra/features – starship (GitHub Releases)](https://github.com/devcontainers-extra/features/tree/main/src/starship)
[^feat-extra-homebrew]: [devcontainers-extra/features – starship-homebrew](https://github.com/devcontainers-extra/features/tree/main/src/starship-homebrew)
[^feat-tobias]: [tobiaschc/devcontainer-features – starship (Full Integration)](https://github.com/tobiaschc/devcontainer-features/tree/main/src/starship)
