# Feature Reference

fzf is a general-purpose command-line fuzzy finder and an interactive terminal toolkit, written in Go. It reads a list of items from standard input (or a configured source) and presents an interactive, real-time filtering interface in the terminal that allows the user to narrow down items with fuzzy or exact matching. Beyond simple filtering, fzf exposes an event-driven architecture that enables building custom terminal UIs, menus, and workflows. Its primary use cases include interactive file and directory selection, command history search, process management, hostname completion, and integration with other tools like `git`, `kubectl`, `tmux`, and editors.

fzf ships as a single, statically-linked binary with no runtime dependencies, making it straightforward to install and distribute. It also provides first-class shell integration for Bash, Zsh, Fish, and Nushell that wires up three key bindings (`CTRL-T` for file selection, `CTRL-R` for history search, `ALT-C` for directory navigation) and a fuzzy completion trigger (`**<TAB>` by default) for any interactive shell session.[^readme]

- **Homepage**: https://github.com/junegunn/fzf
- **Source Code**: https://github.com/junegunn/fzf
- **Documentation**: https://junegunn.github.io/fzf/
- **Latest Release**: 0.73.1 (as of 2026-06-03)[^release-latest]

## Tool Architecture

fzf is a **single, self-contained binary** written in Go. It has no runtime dependencies beyond the operating system's standard C library, and the official pre-built release binaries are statically linked so they run without any additional shared libraries.[^readme][^install-script]

The binary (`fzf`) is the only required component. It handles input reading, fuzzy matching, terminal UI rendering (via the `tcell/v2` library), preview execution, and output. When shell integration is desired, fzf can generate its own shell integration code directly — running `fzf --bash`, `fzf --zsh`, `fzf --fish`, or `fzf --nushell` outputs the corresponding shell script that sets up key bindings and completion. This design means a plain binary install is sufficient to unlock full shell integration without needing to clone the repository or install separate shell scripts.[^readme]

An optional `fzf-tmux` shell script wrapper (included in the git repository at `bin/fzf-tmux`, not distributed in the pre-built binary tarballs) wraps fzf to open it in a tmux popup or split pane. The shell integration scripts use `fzf-tmux` automatically when a `$TMUX_PANE` is detected and `$FZF_TMUX` is enabled.[^key-bindings-bash]

The project's Go module (`go.mod`) requires **Go 1.23.0** or later and depends on `tcell/v2` for terminal rendering, `fastwalk` for filesystem traversal, `go-shellwords` for shell quoting, `go-isatty`, `rivo/uniseg` (Unicode), and `golang.org/x/{sys,term}`.[^go-mod]

## Installation Methods

fzf offers four principal installation routes:

1. **Prebuilt Binary Download (GitHub Releases)** — direct, deterministic, version-pinnable; the most suitable method for DevFeats/devcontainer features.
2. **Git Clone + Installer Script** — the upstream-recommended interactive method for individual developer workstations.
3. **OS Package Manager** — distro-native lifecycle management; version may lag upstream.
4. **Go Install** — source-level build; the install script uses this as a fallback when no pre-built binary is available for the target platform.

### Prebuilt Binary Download (GitHub Releases)

#### Supported Platforms

All current release assets (v0.73.1):[^release-v0731]

| OS | Architecture | Asset filename |
|----|-------------|---------------|
| Linux | amd64 | `fzf-{version}-linux_amd64.tar.gz` |
| Linux | arm64 | `fzf-{version}-linux_arm64.tar.gz` |
| Linux | armv5 | `fzf-{version}-linux_armv5.tar.gz` |
| Linux | armv6 | `fzf-{version}-linux_armv6.tar.gz` |
| Linux | armv7 | `fzf-{version}-linux_armv7.tar.gz` |
| Linux | loong64 | `fzf-{version}-linux_loong64.tar.gz` |
| Linux | ppc64le | `fzf-{version}-linux_ppc64le.tar.gz` |
| Linux | riscv64 | `fzf-{version}-linux_riscv64.tar.gz` |
| Linux | s390x | `fzf-{version}-linux_s390x.tar.gz` |
| macOS | amd64 (Intel) | `fzf-{version}-darwin_amd64.tar.gz` |
| macOS | arm64 (Apple Silicon) | `fzf-{version}-darwin_arm64.tar.gz` |
| FreeBSD | amd64 | `fzf-{version}-freebsd_amd64.tar.gz` |
| OpenBSD | amd64 | `fzf-{version}-openbsd_amd64.tar.gz` |
| Android | arm64 | `fzf-{version}-android_arm64.tar.gz` |
| Windows | amd64 | `fzf-{version}-windows_amd64.zip` |
| Windows | arm64 | `fzf-{version}-windows_arm64.zip` |

**Note:** There is **no** `linux_386` (32-bit x86) binary. The devcontainer-community feature's architecture map includes an `i386 → 386` entry that will fail at download time.[^community-install]

#### Dependencies

##### Common Dependencies

- `curl` or `wget` to download the asset.
- `tar` (for Linux/macOS/BSD) or `unzip` (for Windows) to extract the archive.
- `sha256sum` or `shasum -a 256` to verify the checksum.

##### Platform-Specific Dependencies

- Linux/macOS/BSD: None beyond `curl`/`wget` and `tar`.
- Root/sudo required only when writing to a system-wide path (e.g., `/usr/local/bin`).

#### Installation Steps

The release tag uses a `v` prefix (`v0.73.1`), but the binary asset filename and checksums filename do **not** — this distinction matters when constructing download URLs.[^install-script][^release-v0731]

URL pattern: `https://github.com/junegunn/fzf/releases/download/v{version}/{filename}`

Example — Linux amd64, system-wide install:

```bash
set -e
VERSION="0.73.1"
OS="linux"         # or: darwin, freebsd, openbsd, android
ARCH="amd64"       # or: arm64, armv5, armv6, armv7, loong64, ppc64le, riscv64, s390x
ASSET="fzf-${VERSION}-${OS}_${ARCH}.tar.gz"
CHECKSUMS="fzf_${VERSION}_checksums.txt"
BASE_URL="https://github.com/junegunn/fzf/releases/download/v${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/${CHECKSUMS}"
grep "${ASSET}" "${CHECKSUMS}" | sha256sum -c -
tar -xzf "${ASSET}" fzf
sudo install -m 0755 fzf /usr/local/bin/fzf
rm -f "${ASSET}" "${CHECKSUMS}" fzf
```

Example — macOS arm64, system-wide install (note: use `shasum -a 256` instead of `sha256sum`):

```bash
set -e
VERSION="0.73.1"
ASSET="fzf-${VERSION}-darwin_arm64.tar.gz"
CHECKSUMS="fzf_${VERSION}_checksums.txt"
BASE_URL="https://github.com/junegunn/fzf/releases/download/v${VERSION}"

curl -fsSLO "${BASE_URL}/${ASSET}"
curl -fsSLO "${BASE_URL}/${CHECKSUMS}"
grep "${ASSET}" "${CHECKSUMS}" | shasum -a 256 -c -
tar -xzf "${ASSET}" fzf
sudo install -m 0755 fzf /usr/local/bin/fzf
rm -f "${ASSET}" "${CHECKSUMS}" fzf
```

#### Installation Verification

Verify with the version flag:

```bash
fzf --version
# Expected output: 0.73.1 (e.g. "0.73.1 (3f4c6fc)")
```

Checksum verification is performed as shown above using the `fzf_{version}_checksums.txt` file from the same release. Each line in that file contains a SHA256 hash and the corresponding asset filename (space-separated). **No GPG/PGP signatures are provided** for fzf releases.[^release-v0731]

#### Configuration Options

##### Version Selection

Pass the desired `VERSION` variable when constructing the download URL. The string `"latest"` is not a valid release tag; resolve the latest version at install time from the GitHub API:

```bash
VERSION=$(curl -fsSL "https://api.github.com/repos/junegunn/fzf/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
```

##### Installation Path

Any writable directory on `PATH`. Common choices:
- System-wide: `/usr/local/bin/fzf` (requires root)
- User-local: `$HOME/.local/bin/fzf` (no sudo; requires `$HOME/.local/bin` on PATH)

##### User Targeting

- **System-wide**: install to `/usr/local/bin` with `sudo install -m 0755 fzf /usr/local/bin/fzf`.
- **User-local**: install to `$HOME/.local/bin/fzf` without sudo.

##### Required Privileges

Root/sudo is required only when the target directory is root-owned (e.g., `/usr/local/bin`). User-local installs require no elevated privileges.

##### Tool-Specific Configurations

No build-time or install-time flags. Runtime configuration is done through environment variables (see the Post-Installation section below) and through `fzf`'s own CLI flags or a config file at the path set in `$FZF_DEFAULT_OPTS_FILE`.[^readme]

#### Post-Installation Steps and Cleanup

##### PATH Setup

- If installing to `/usr/local/bin` (or any other directory already on the system PATH), no additional configuration is needed.
- If installing to a user-local directory, ensure it is on PATH:

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  # Add to ~/.bashrc or ~/.zshrc for persistence.
  ```

##### Configuration Files

No configuration file is required. Optionally, fzf reads default options from the file path set in `$FZF_DEFAULT_OPTS_FILE` (e.g., `~/.fzfrc`), one option per line.[^readme]

##### Environment Variables

The following environment variables configure fzf's default runtime behavior and should be set in the user's shell profile if they differ from the defaults:[^readme]

| Variable | Default | Description |
|----------|---------|-------------|
| `FZF_DEFAULT_COMMAND` | (empty) | Command used to generate the input list when fzf is launched with no piped input |
| `FZF_DEFAULT_OPTS` | (empty) | Default CLI options applied to every fzf invocation |
| `FZF_DEFAULT_OPTS_FILE` | (empty) | Path to a file containing default options (one per line) |
| `FZF_CTRL_T_COMMAND` | `--walker file,dir,follow,hidden` | Command or walker for CTRL-T (file selection); set to `""` to disable |
| `FZF_CTRL_T_OPTS` | (empty) | Additional fzf options for CTRL-T |
| `FZF_CTRL_R_COMMAND` | (empty) | Reserved; custom commands not yet fully supported for CTRL-R |
| `FZF_CTRL_R_OPTS` | (empty) | Additional fzf options for CTRL-R |
| `FZF_ALT_C_COMMAND` | `--walker dir,follow,hidden` | Command or walker for ALT-C (directory navigation); set to `""` to disable |
| `FZF_ALT_C_OPTS` | (empty) | Additional fzf options for ALT-C |
| `FZF_COMPLETION_TRIGGER` | `**` | Shell string that triggers fuzzy completion (bash/zsh) |
| `FZF_COMPLETION_OPTS` | (empty) | Additional fzf options for fuzzy completion |
| `FZF_COMPLETION_PATH_OPTS` | (empty) | Additional fzf options for path completion |
| `FZF_COMPLETION_DIR_OPTS` | (empty) | Additional fzf options for directory completion |
| `FZF_TMUX` | `0` | Set to `1` to use `fzf-tmux` inside tmux sessions |
| `FZF_TMUX_OPTS` | (empty) | Options passed to `fzf-tmux` |
| `FZF_TMUX_HEIGHT` | `40%` | Default height for fzf in tmux height mode |

##### Activation Scripts

Shell integration is activated by generating and evaluating fzf's built-in shell integration code. This sets up the CTRL-T, CTRL-R, and ALT-C key bindings and `**<TAB>` fuzzy completion. The commands below should be added to the user's shell profile:

**Bash** — add to `~/.bashrc`:
```bash
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
```

**Zsh** — add to `~/.zshrc`:
```bash
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)
```

**Fish** — add to `~/.config/fish/config.fish` or inside a `fish_user_key_bindings` function:
```fish
command -v fzf >/dev/null 2>&1 && fzf --fish | source
```

**Nushell** — run once and restart the shell (the file is auto-loaded):
```nushell
mkdir ($nu.default-config-dir | path join "autoload")
fzf --nushell | save -f ($nu.default-config-dir | path join "autoload" "_fzf_integration.nu")
```

The guard `command -v fzf >/dev/null 2>&1 &&` ensures the shell startup does not fail if fzf is absent (e.g., in minimal environments).[^readme][^install-bash-existing]

**What the shell integration enables:**

| Key binding / trigger | Action |
|----------------------|--------|
| `CTRL-T` | Paste selected files/directories onto the command line |
| `CTRL-R` | Search and paste a command from shell history |
| `ALT-C` | `cd` into a selected directory |
| `**<TAB>` (bash/zsh) | Fuzzy-complete paths, hostnames (ssh), PIDs (kill), env vars, aliases |

Individual bindings can be disabled by setting the corresponding `_COMMAND` variable to an empty string before evaluating the integration:

```bash
# Disable ALT-C and CTRL-R, keep CTRL-T
FZF_ALT_C_COMMAND= FZF_CTRL_R_COMMAND= eval "$(fzf --bash)"
```

##### Cleanup

```bash
rm -f "${ASSET}" "${CHECKSUMS}"
```

No package caches or build artifacts to clean up for the binary install method.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run the download and install steps with the desired version; the binary file is simply overwritten.

##### Uninstallation

```bash
# System-wide
sudo rm -f /usr/local/bin/fzf

# User-local
rm -f "$HOME/.local/bin/fzf"
```

Remove the shell integration lines from `~/.bashrc`, `~/.zshrc`, or equivalent files. For fish, remove the `fzf --fish | source` line from `config.fish` or the `fish_user_key_bindings` function. For nushell, delete `$nu.default-config-dir/autoload/_fzf_integration.nu`.

##### Idempotency

Re-running the install with the same version and target path overwrites the binary file in-place. Adding the shell integration lines to profile files is idempotent when guarded with `command -v fzf >/dev/null 2>&1 &&`, and should be protected against duplicate-line insertion (check before appending).

#### Details

The release asset URL format is:
```
https://github.com/junegunn/fzf/releases/download/v{version}/fzf-{version}-{os}_{arch}.tar.gz
```

The tag uses a `v` prefix (`v0.73.1`) but the asset filename and the checksums filename do not include the `v`:
- Asset: `fzf-0.73.1-linux_amd64.tar.gz`
- Checksums: `fzf_0.73.1_checksums.txt` (underscores, not hyphens, around the version in this filename)

Each `.tar.gz` archive contains a single file at the root level named `fzf` (no directory prefix), so it can be extracted directly to a target directory with `tar -xzf archive.tar.gz -C /target/dir fzf`.[^install-script]

#### Notes and Best Practices

- Always verify the SHA256 checksum against `fzf_{version}_checksums.txt` before executing the binary.
- There are no GPG signatures for fzf releases. Checksum verification is the available integrity check.
- There is no `linux_386` binary. Attempting to install on 32-bit x86 Linux requires a source build (see the Go Install method).
- The `fzf-tmux` wrapper script is **not** included in the pre-built binary tarballs; it lives in the git repository at `bin/fzf-tmux`. If tmux integration via `fzf-tmux` is desired, the script must be fetched separately from the repo.
- Starting with recent fzf versions, the built-in `fzf --bash` / `fzf --zsh` / `fzf --fish` / `fzf --nushell` commands are the recommended and simplest way to set up shell integration; the separate `shell/*.bash` / `shell/*.zsh` files in the repo are functionally equivalent but require the full repository to be cloned.

---

### Git Clone + Installer Script

#### Supported Platforms

- Linux (all architectures for which a pre-built binary is published; see the table in the Prebuilt Binary method).
- macOS (Intel and Apple Silicon).
- FreeBSD, OpenBSD.
- Android (arm64).
- Windows via CYGWIN, MINGW, MSYS2 (not relevant for devcontainer use).

Falls back to `go install` when no binary is available for the target platform (requires Go 1.23.0+).

#### Dependencies

##### Common Dependencies

- `git` (for cloning the repository).
- `curl` or `wget` (for downloading the binary).
- `tar` (for extracting the binary).

##### Platform-Specific Dependencies

- **Fallback Go build**: Go 1.23.0+ must be available if no pre-built binary exists for the platform.
- **Nushell integration**: `nu` must be available for nushell configuration setup.

#### Installation Steps

```bash
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

The install script prompts the user about key bindings, completion, and shell RC file updates. Non-interactive options:

```bash
~/.fzf/install --all                # Enable everything, update RC files
~/.fzf/install --all --no-update-rc # Enable everything, do not touch RC files
~/.fzf/install --bin                # Download binary only, no shell integration setup
~/.fzf/install --all --xdg          # Use $XDG_CONFIG_HOME/fzf/ instead of ~/.fzf.{bash,zsh}
~/.fzf/install --no-bash --no-zsh   # Set up only non-bash/zsh shells
```

Full list of installer script flags:[^install-script]

| Flag | Description |
|------|-------------|
| `--help` | Show help |
| `--bin` | Download binary only; do not generate `~/.fzf.{bash,zsh}` |
| `--all` | Download binary and enable key bindings + completion; update RC files |
| `--xdg` | Generate config files under `$XDG_CONFIG_HOME/fzf/` |
| `--[no-]key-bindings` | Enable or disable key bindings (CTRL-T, CTRL-R, ALT-C) |
| `--[no-]completion` | Enable or disable fuzzy completion |
| `--[no-]update-rc` | Update (or skip) shell RC files (`~/.bashrc`, `~/.zshrc`) |
| `--no-bash` | Skip bash configuration |
| `--no-zsh` | Skip zsh configuration |
| `--no-fish` | Skip fish configuration |
| `--no-nushell` | Skip nushell configuration |

#### Installation Verification

```bash
~/.fzf/bin/fzf --version
```

The install script internally checks that the downloaded binary reports the expected version string matching the hardcoded `version` variable in the script.[^install-script]

#### Configuration Options

##### Version Selection

The version is hardcoded in the `install` script (`version=0.73.1` in the current master). To install a specific older version, check out the corresponding git tag before running the installer:

```bash
git clone --depth 1 --branch v0.73.0 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --bin
```

##### Installation Path

The binary is installed to `~/.fzf/bin/fzf`. The install script adds `~/.fzf/bin` to PATH by generating `~/.fzf.bash` and `~/.fzf.zsh` files. There is no option to change the binary installation path without modifying the script.

##### User Targeting

Always user-local (installs to `~/.fzf/`). Not designed for system-wide installs.

##### Required Privileges

No elevated privileges required; installs to user's home directory.

##### Tool-Specific Configurations

- The installer generates `~/.fzf.bash` and `~/.fzf.zsh` (or XDG equivalents) that:
  - Add `~/.fzf/bin` to `PATH`.
  - Source the shell integration (either via `eval "$(fzf --bash)"` / `source <(fzf --zsh)` when both key bindings and completion are enabled, or by sourcing individual `~/.fzf/shell/key-bindings.{bash,zsh}` and `~/.fzf/shell/completion.{bash,zsh}` files when only one is enabled).
- It appends a line to `~/.bashrc` and `~/.zshrc` to source the generated config:
  ```bash
  [ -f ~/.fzf.bash ] && source ~/.fzf.bash
  ```
- Fish: updates `fish_user_paths` to include `~/.fzf/bin` and creates/updates `~/.config/fish/functions/fish_user_key_bindings.fish`.
- Nushell: generates `$nu.user-autoload-dirs/_fzf_integration.nu`.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Handled by the generated `~/.fzf.bash` / `~/.fzf.zsh` files (sourced from RC files). For fish, `fish_user_paths` is updated. For nushell, the autoload file handles it.

##### Configuration Files

`~/.fzf.bash`, `~/.fzf.zsh` (or XDG equivalents). These are sourced from the user's RC files.

##### Environment Variables

Same as the Prebuilt Binary method. See the environment variable table above.

##### Activation Scripts

Handled automatically by the installer. No manual steps after `./install --all`.

##### Cleanup

The entire `~/.fzf/` directory constitutes the installation. It includes the git repository, the binary, and the shell scripts. No separate download artifacts remain after install.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
cd ~/.fzf && git pull && ./install
```

Or, for a specific version:
```bash
cd ~/.fzf && git fetch --tags && git checkout v0.73.0 && ./install --bin
```

##### Uninstallation

```bash
~/.fzf/uninstall   # Interactive: removes config files and RC file entries
rm -rf ~/.fzf
```

The `uninstall` script removes `~/.fzf.bash`, `~/.fzf.zsh`, and the sourcing lines from `~/.bashrc`, `~/.zshrc`, and fish/nushell configs.[^uninstall-script]

##### Idempotency

Re-running `./install` on an existing clone is safe. The installer checks for an existing binary and verifies its version; if the version matches, it skips the download. RC file updates are also idempotent: the `append_line` helper checks for pre-existing lines before appending.[^install-script]

#### Details

The install script:
1. Detects OS and CPU architecture using `uname -smo` (or `uname -sm` as fallback).
2. Maps the detected platform to a GitHub release asset filename.
3. Downloads the asset using `curl` (preferred) or `wget`.
4. Extracts the binary to `$fzf_base/bin/fzf` (where `$fzf_base` is the repo directory).
5. If no pre-built binary is available for the platform and Go is installed, falls back to `go install github.com/junegunn/fzf`.
6. Prompts (or reads flags) for key bindings / completion / RC update preferences.
7. Generates `~/.fzf.bash` and/or `~/.fzf.zsh` shell config files.
8. Optionally appends sourcing lines to `~/.bashrc` / `~/.zshrc` / fish functions / nushell autoload directory.

Before downloading, the script checks if `fzf` is already available in PATH and, if so, creates a symlink at `$fzf_base/bin/fzf` pointing to the existing binary rather than downloading a new one.[^install-script]

#### Notes and Best Practices

- This method is best suited for individual developer workstations; for devcontainer/CI use the Prebuilt Binary method for determinism and speed.
- The `--bin` flag installs only the binary; combined with the `eval "$(fzf --bash)"` one-liner in the shell profile, it provides equivalent functionality to the full install without requiring the entire repo clone to persist at runtime.

---

### OS Package Manager

#### Supported Platforms

- macOS and Linux (Homebrew).
- Alpine Linux (APK).
- Debian/Ubuntu (APT).
- Fedora/RHEL-family (DNF).
- Arch Linux (pacman).
- openSUSE (zypper).
- NixOS / nix-env (Nix).
- FreeBSD (pkg), NetBSD (pkgin/pkg_add), OpenBSD (pkg_add), Gentoo (portage), Spack, Void Linux (XBPS), openSUSE (zypper).[^readme]

#### Dependencies

##### Common Dependencies

A working, configured system package manager.

##### Platform-Specific Dependencies

- Linux package managers require root/sudo for install/remove.
- Homebrew requires a working Homebrew installation.

#### Installation Steps

```bash
# Homebrew (macOS and Linux)
brew install fzf

# Alpine
apk add fzf

# Debian/Ubuntu
apt-get install -y fzf

# Fedora/RHEL
dnf install -y fzf

# Arch Linux
pacman -S --noconfirm fzf

# openSUSE
zypper install -y fzf

# Nix
nix-env -iA nixpkgs.fzf
```

#### Installation Verification

```bash
fzf --version
```

#### Configuration Options

##### Version Selection

Package managers install the version available in their repositories, which may lag the latest upstream release. For strict version pinning, use the Prebuilt Binary method. Some managers allow version-pinning (e.g., `apt-get install fzf=0.73.1-*`), but availability depends on repository contents.

##### Installation Path

Managed by the package manager: typically `/usr/bin/fzf` (Linux package managers) or `$(brew --prefix)/bin/fzf` (Homebrew).

##### User Targeting

- Linux package managers: system-wide.
- Homebrew: user-local within the Homebrew prefix.

##### Required Privileges

Root/sudo required for Linux package managers. Homebrew does not require sudo.

##### Tool-Specific Configurations

Shell integration must be set up separately after installation. Unlike the git clone method, package manager installs do not run the fzf installer script. Use the `eval "$(fzf --bash)"` / `source <(fzf --zsh)` approach documented in the Post-Installation section of the Prebuilt Binary method above.

#### Post-Installation Steps and Cleanup

##### PATH Setup

Not required for system package managers. For Homebrew, ensure the brew shellenv is initialized.

##### Configuration Files

None required.

##### Environment Variables

Same as the Prebuilt Binary method.

##### Activation Scripts

Same as the Prebuilt Binary method — add `eval "$(fzf --bash)"` (bash) or `source <(fzf --zsh)` (zsh) to the shell profile.

##### Cleanup

```bash
# Debian/Ubuntu
apt-get clean && rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```bash
brew upgrade fzf            # Homebrew
apt-get install -y fzf      # Debian/Ubuntu (installs newest in repo)
dnf upgrade fzf             # Fedora/RHEL
apk upgrade fzf             # Alpine
```

##### Uninstallation

```bash
brew uninstall fzf          # Homebrew
apt-get remove -y fzf       # Debian/Ubuntu
dnf remove -y fzf           # Fedora/RHEL
apk del fzf                 # Alpine
pacman -R --noconfirm fzf   # Arch
zypper remove -y fzf        # openSUSE
```

##### Idempotency

Package manager installs are idempotent; re-running install on an already-installed package is a no-op or an upgrade to the newest available version.

#### Notes and Best Practices

- Repository versions may lag upstream by several releases; for example, Debian stable repos often ship older versions.
- After a package manager install, the Homebrew formula page shows the current formula version and supported bottle platforms.[^brew-formula]

---

### Go Install

#### Supported Platforms

Any platform where Go 1.23.0+ is installed and the target architecture has a working Go toolchain.

#### Dependencies

##### Common Dependencies

- Go 1.23.0 or later.
- Network access to `proxy.golang.org` / `sum.golang.org` (or a configured GOPROXY).

#### Installation Steps

```bash
go install github.com/junegunn/fzf@latest
# or pin to a specific version:
go install github.com/junegunn/fzf@v0.73.1
```

The binary is placed in `$(go env GOPATH)/bin/fzf` (typically `~/go/bin/fzf`).

#### Installation Verification

```bash
fzf --version
```

#### Configuration Options

##### Version Selection

Specify the version via the `@version` suffix in the module path.

##### Installation Path

`$(go env GOPATH)/bin/fzf`. Set `GOBIN` to override.

##### User Targeting

Always user-local (within GOPATH/GOBIN). No sudo required.

##### Required Privileges

No elevated privileges required.

##### Tool-Specific Configurations

The installer script uses this method with additional ldflags:
```bash
go install -ldflags "-s -w -X main.version=${version} -X main.revision=go-install" \
  github.com/junegunn/fzf
```
This strips debug symbols (`-s -w`) and embeds version metadata.[^install-script]

#### Post-Installation Steps and Cleanup

##### PATH Setup

Ensure `$(go env GOPATH)/bin` is on PATH:

```bash
export PATH="$(go env GOPATH)/bin:$PATH"
```

##### Cleanup

Build artifacts are cached in the Go module cache (`$(go env GOMODCACHE)`). Clear with `go clean -cache` if needed.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run `go install github.com/junegunn/fzf@{version}`.

##### Uninstallation

```bash
rm -f "$(go env GOPATH)/bin/fzf"
```

##### Idempotency

Re-running with the same version tag overwrites the binary.

#### Notes and Best Practices

- The binary built via `go install` does not embed the same version string as the pre-built releases unless the ldflags shown above are provided.
- Use this method only as a fallback when no pre-built binary is available for the target platform.

---

## Dev Container Setup

fzf works correctly in standard devcontainer environments (Debian/Ubuntu based) without any special container-specific configuration. Key considerations:

- **Binary install**: Install to `/usr/local/bin/fzf` (root, accessible by all users) or a per-user location.
- **Shell integration**: Inject `eval "$(fzf --bash)"` into the user's `~/.bashrc` and `source <(fzf --zsh)` into `~/.zshrc` (guarded with `command -v fzf`). For zsh with Oh My Zsh, inject into the theme or `~/.zshrc.d/` file, not directly into `~/.zshrc` if that file is managed by Oh My Zsh.
- **tmux**: fzf's `--popup` display mode (floating window) requires tmux 3.3+ or Zellij 0.44+. The `fzf-tmux` wrapper script is not included in the binary tarball; if needed, fetch it from the repo separately.
- **No entrypoint or lifecycle commands** are needed; fzf runs purely as a user-space CLI tool.
- **No volume mounts or special privileges** are required.
- **No persistent services or daemons**; fzf starts and exits on each invocation.
- The `--listen` feature (HTTP API for remote control) binds a local socket and is a no-op at container image build time.[^readme]

The existing `install-fzf` feature installs the binary system-wide and injects the `eval "$(fzf --<shell>)"` guarded one-liner into each target user's bash and zsh theme file.[^install-bash-existing]

## Plugins and Extensions

### fzf.vim

fzf.vim is the official Vim/Neovim plugin that provides a rich set of fzf-powered commands within the editor, such as `:Files`, `:Buffers`, `:Rg` (ripgrep integration), `:Colors`, `:History`, `:Commits`, and many others.

- **Homepage**: https://github.com/junegunn/fzf.vim
- **Source Code**: https://github.com/junegunn/fzf.vim
- **Documentation**: https://github.com/junegunn/fzf.vim#readme

**Architecture**: A Vim plugin (VimScript / Vim9 script). It wraps fzf as an external process and communicates via terminal buffers. Depends on the `fzf` binary being available on PATH and the base `junegunn/fzf` Vim plugin (which provides helper functions; this is separate from the fzf binary).

**Installation** (via vim-plug):
```vim
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
```

The `fzf#install()` call downloads the fzf binary during plugin installation if not already present.

**Notes**: fzf.vim is not required for shell key bindings or completion; it only adds Vim/Neovim command integrations. It is not relevant for a devcontainer feature targeting shell environments.

### Integration with fd, bat, and ripgrep

fzf integrates natively with several companion tools:

- **fd** (`fd-find`): a fast `find` replacement. Can be used as `FZF_DEFAULT_COMMAND` or `FZF_CTRL_T_COMMAND` to power file listing while respecting `.gitignore`.
  ```bash
  export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  ```
- **bat**: a `cat` replacement with syntax highlighting. Used as a `--preview` command:
  ```bash
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}'"
  ```
- **ripgrep** (`rg`): used for live interactive grep inside fzf, replacing the input list as the query changes via `--bind 'change:reload:rg ...'`.

These tools are optional enhancements; fzf functions fully without them using its built-in `--walker` filesystem traversal.

## References

[^readme]: [fzf Official README](https://raw.githubusercontent.com/junegunn/fzf/master/README.md) — Primary reference for tool overview, shell integration, environment variables, key bindings, fuzzy completion, display modes, and all CLI options.

[^install-script]: [fzf `install` script](https://raw.githubusercontent.com/junegunn/fzf/master/install) — Official installer script; source of truth for platform detection, binary naming conventions, release tag URL format (`v`-prefixed tag, non-`v` asset filename), fallback Go build logic, shell config file generation, and RC file update logic.

[^uninstall-script]: [fzf `uninstall` script](https://raw.githubusercontent.com/junegunn/fzf/master/uninstall) — Source of truth for uninstallation procedure; removes generated shell config files and sourcing lines from RC files.

[^key-bindings-bash]: [fzf `shell/key-bindings.bash`](https://raw.githubusercontent.com/junegunn/fzf/master/shell/key-bindings.bash) — Shell integration source for bash: CTRL-T, CTRL-R, ALT-C key binding implementations; `__fzfcmd()` function showing tmux detection logic; history deduplication with Perl/awk fallback.

[^completion-bash]: [fzf `shell/completion.bash`](https://raw.githubusercontent.com/junegunn/fzf/master/shell/completion.bash) — Shell integration source for bash: `**<TAB>` fuzzy completion trigger, path/dir/proc/host/var/alias completion implementations.

[^go-mod]: [fzf `go.mod`](https://raw.githubusercontent.com/junegunn/fzf/master/go.mod) — Go module definition; specifies Go 1.23.0 minimum requirement and all runtime dependencies.

[^release-latest]: [GitHub API — latest fzf release](https://api.github.com/repos/junegunn/fzf/releases/latest) — Authoritative latest release metadata, confirming version 0.73.1 released May 25, 2025.

[^release-v0731]: [GitHub — fzf v0.73.1 release page](https://github.com/junegunn/fzf/releases/tag/v0.73.1) — Complete list of downloadable binary assets and the `fzf_0.73.1_checksums.txt` SHA256 checksums file; confirms no GPG signatures are provided.

[^community-install]: [devcontainer-community fzf `install.sh`](https://raw.githubusercontent.com/devcontainer-community/devcontainer-features/main/src/fzf/install.sh) — Community devcontainer feature for fzf; documents a Debian-only binary download approach; architecture mapping reveals the `i386 → 386` mapping which is broken as no `linux_386` binary exists in fzf releases.

[^community-feature-json]: [devcontainer-community fzf `devcontainer-feature.json`](https://raw.githubusercontent.com/devcontainer-community/devcontainer-features/main/src/fzf/devcontainer-feature.json) — Community feature metadata: version 1.0.2, version option (latest or X.Y.Z), `installsAfter` dependency on `ca-certificates`.

[^install-bash-existing]: [DevFeats `features/install-fzf/install.bash`](features/install-fzf/install.bash) — Current DevFeats skeleton; documents per-user shell integration via guarded `eval "$(fzf --bash)"` / `source <(fzf --zsh)` in bash/zsh theme files.

[^brew-formula]: [Homebrew fzf formula](https://formulae.brew.sh/formula/fzf) — Homebrew installation command, current formula version, supported bottle platforms (macOS arm64/x86_64, Linux x86_64/arm64), and installation statistics.
