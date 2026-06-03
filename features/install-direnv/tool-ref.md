# Feature Reference

direnv is an environment variable manager for the shell. It augments the shell with a feature that can load and unload environment variables depending on the current directory. When a directory is entered, direnv checks for an `.envrc` file (and optionally an `.env` file) in the current and parent directories; if the file is found and has been permitted by the user, direnv evaluates it in a bash sub-process, captures the resulting exported variables, and injects the diff into the parent shell. When the directory is left, those variables are automatically unloaded. This enables per-project environment configuration — activating virtual environments, setting API keys, configuring build tools — without polluting global shell configuration or requiring wrapper scripts.[^repo]

direnv is widely used for managing project-specific environments in workflows involving Nix, Python virtualenvs, Node.js version managers, and other language-specific tooling. It integrates natively with many version managers and build tools via its standard library of bash helper functions. A mandatory security step requires users to explicitly run `direnv allow` before any `.envrc` is evaluated, preventing automatic execution of code from cloned repositories.[^man-direnv]

- **Homepage**: https://direnv.net/
- **Source Code**: https://github.com/direnv/direnv
- **Documentation**: https://direnv.net/docs/installation.html
- **Latest Release**: v2.37.1 (as of 2025-07-20)[^gh-api-latest]

## Tool Architecture

direnv is a **single static binary** compiled from Go.[^repo] It has no runtime dependencies — no JVM, no Node.js, no Python interpreter is required. It is entirely self-contained and executes fast enough to run on every shell prompt without noticeable latency.[^repo]

direnv operates through a **shell hook** registered in the shell's prompt mechanism.[^docs-hook] The hook must be set up after binary installation (see the Activation Scripts subsections below). On each prompt, the hook calls `direnv export <shell>`, which performs the following steps:[^man-direnv]

1. Searches for `.envrc` (and optionally `.env`) files starting from the current directory and walking up through parent directories.
2. If a `.envrc` is found and has been explicitly allowed by the user (via `direnv allow`), evaluates it inside a **new bash sub-process** — regardless of the user's active shell — with the direnv standard library pre-loaded and optionally the user's `direnvrc` extension file.
3. Captures all variables exported by the sub-process, computes the diff relative to the previously loaded environment, and outputs a set of `export` / `unset` statements in the syntax of the calling shell.
4. The hook evaluates those statements in the parent shell, updating its environment.
5. When the user changes out of the directory, the variables loaded from that `.envrc` are automatically unloaded.

direnv has **no client-server architecture** — it is a standalone binary invoked inline on each prompt. It requires no external services at runtime. The only external network call happens during installation via the official installer script, which queries the GitHub Releases API to resolve the latest version.[^src-install-sh]

**Supported shells**: bash, zsh (including via Oh My Zsh), tcsh, fish, Elvish (0.12+), Nushell, PowerShell (pwsh), Murex.[^docs-hook]

**Key runtime files and directories**:[^man-direnv][^man-direnv-toml]

| Path | Purpose |
|---|---|
| `$XDG_CONFIG_HOME/direnv/direnv.toml` (default: `~/.config/direnv/direnv.toml`) | Main configuration file (see [direnv.toml](#tool-specific-configurations) below) |
| `$XDG_CONFIG_HOME/direnv/direnvrc` | User-defined bash extensions sourced before every `.envrc` |
| `$XDG_CONFIG_HOME/direnv/lib/*.sh` | Third-party bash extension scripts auto-sourced before every `.envrc` |
| `$XDG_DATA_HOME/direnv/allow/` (default: `~/.local/share/direnv/allow/`) | Hashed records of allowed `.envrc` files |

**Security model**: Before direnv evaluates any `.envrc`, the user must run `direnv allow [path]` to grant explicit permission. The allow record is stored as a hash of the file content; if the file is modified, permission must be re-granted. This prevents `.envrc` files in cloned repositories from running arbitrary code automatically.[^man-direnv]

**Programming language**: Go (>= 1.24 required to build from source).[^docs-development]

## Installation Methods

The installation of direnv consists of two mandatory parts: (1) installing the binary, and (2) hooking into the shell.[^docs-install] The shell hook must be set up after the binary is installed; its configuration is described under the Activation Scripts subsection for each installation method. Full per-shell hook commands are documented in full detail under the [OS Package Manager](#os-package-manager) method and are identical for all installation methods.

### OS Package Manager

#### Supported Platforms

Package manager availability by platform[^docs-install]:

| Platform | Package Manager |
|---|---|
| Debian | apt |
| Ubuntu | apt |
| Fedora | dnf |
| Arch Linux | pacman |
| openSUSE | zypper |
| Gentoo | emerge (via Guru overlay) |
| NixOS | nix (`programs.direnv` NixOS module) |
| GNU Guix | guix |
| macOS | Homebrew |
| macOS | MacPorts |
| NetBSD | pkgsrc-wip |
| Windows | winget |

#### Dependencies

##### Common Dependencies

None beyond the respective package manager.

##### Platform-Specific Dependencies

- **Gentoo**: Requires the [Guru overlay](https://wiki.gentoo.org/wiki/Project:GURU/Information_for_End_Users) to be enabled before installation.[^docs-install]
- **NixOS**: Uses the `programs.direnv.enable = true;` NixOS module option rather than a direct package install; the module handles both installation and shell hook setup automatically.[^docs-install]

#### Installation Steps

**Debian / Ubuntu:**[^docs-install]
```sh
sudo apt-get install direnv
```

**Fedora:**[^docs-install]
```sh
sudo dnf install direnv
```

**Arch Linux:**[^docs-install]
```sh
sudo pacman -S direnv
```

**openSUSE:**[^docs-install]
```sh
sudo zypper install direnv
```

**macOS (Homebrew):**[^docs-install]
```sh
brew install direnv
```

**macOS (MacPorts):**[^docs-install]
```sh
sudo port install direnv
```

**NixOS** — add to `configuration.nix`:[^docs-install]
```nix
programs.direnv.enable = true;
```

**GNU Guix:**[^docs-install]
```sh
guix install direnv
```

**Windows (winget):**[^docs-install]
```sh
winget install direnv
```

#### Installation Verification

```sh
direnv version
```

Prints the installed version number (e.g. `2.37.1`). Also confirms the binary is in `$PATH`.

#### Configuration Options

##### Version Selection

Determined by the package repository. There is no built-in mechanism to select an arbitrary version via these package managers. To install a specific version, use the package manager's pinning mechanisms (e.g. `apt-get install direnv=<version>` on Debian/Ubuntu) or use the [Binary Installer Script](#official-bash-installer-script) or [Manual Binary Download](#manual-binary-download) methods instead.[^docs-install]

##### Installation Path

Determined by the package manager; not user-configurable. Typical locations:
- Debian/Ubuntu/Fedora/Arch: `/usr/bin/direnv`
- Homebrew (Intel Mac): `/usr/local/bin/direnv`
- Homebrew (Apple Silicon): `/opt/homebrew/bin/direnv`
- MacPorts: `/opt/local/bin/direnv`

##### User Targeting

System-wide installation only. The binary is installed globally and accessible to all users.

##### Required Privileges

`sudo` is required on Linux distributions (apt, dnf, pacman, zypper, port). Homebrew on macOS installs to a user-owned prefix and does not require sudo. NixOS and Guix are declarative.

##### Tool-Specific Configurations

All runtime configuration of direnv itself is done through `direnv.toml` and is independent of the installation method. The configuration file is located at `$XDG_CONFIG_HOME/direnv/direnv.toml` (default: `~/.config/direnv/direnv.toml`).[^man-direnv-toml]

> For direnv v2.21.0 and below, the file is named `config.toml` instead of `direnv.toml`.[^man-direnv-toml]

The file uses [TOML](https://toml.io/) syntax and supports the following sections and keys:[^man-direnv-toml]

**[global] section:**

| Key | Type | Default | Description |
|---|---|---|---|
| `bash_path` | string | system bash | Hard-codes the path to bash; useful when `PATH` is mutated during `.envrc` evaluation |
| `disable_stdin` | bool | `false` | Redirects stdin to `/dev/null` during `.envrc` evaluation |
| `load_dotenv` | bool | `false` | Also load `.env` files on top of `.envrc`. `.envrc` takes priority if both exist. Requires direnv >= 2.31.0 |
| `strict_env` | bool | `false` | Load `.envrc` with `set -euo pipefail`; planned to become the default in a future version |
| `warn_timeout` | duration string | `"5s"` | How long before warning about slow `.envrc` execution. Valid units: `ns`, `us`, `ms`, `s`, `m`, `h`. Disable with `"0"` or a negative value. Overridden by the `DIRENV_WARN_TIMEOUT` environment variable |
| `hide_env_diff` | bool | `false` | Hides the env-var diff output when loading `.envrc` |
| `log_format` | string | (default) | Sets the log format. Set to `"-"` to disable normal logging. Requires direnv >= 2.36.0 |
| `log_filter` | regexp | (none) | Regexp to filter log output. Requires direnv >= 2.36.0 |

**[whitelist] section:**

Marks directory hierarchies or specific files as trusted so direnv evaluates matching `.envrc` files without requiring explicit `direnv allow`. **Use with great care** — anyone who can write to a whitelisted directory can execute arbitrary code.[^man-direnv-toml]

| Key | Type | Description |
|---|---|---|
| `prefix` | array of strings | If any entry is a path prefix of an `.envrc` file's absolute path, that file is implicitly allowed |
| `exact` | array of strings | Each entry is either a full path to an `.envrc` file or a directory (implicitly appended with `/.envrc`); requires an exact match |

Example `direnv.toml`:[^man-direnv-toml]
```toml
[global]
warn_timeout = "10s"
load_dotenv = true
hide_env_diff = false

[whitelist]
prefix = [ "/home/user/trusted-projects" ]
exact = [ "/home/user/special/.envrc" ]
```

**Runtime environment variables** that affect direnv behavior (set in the shell environment, not in `direnv.toml`):[^man-direnv-toml][^man-direnv]

| Variable | Effect |
|---|---|
| `XDG_CONFIG_HOME` | Base directory for config files; defaults to `$HOME/.config` |
| `XDG_DATA_HOME` | Base directory for allow records; defaults to `$HOME/.local/share` |
| `DIRENV_WARN_TIMEOUT` | Overrides the `warn_timeout` setting in `direnv.toml` at runtime |

#### Post-Installation Steps and Cleanup

##### PATH Setup

Not required. Package managers install to a directory already in the system `$PATH`.

##### Configuration Files

`~/.config/direnv/direnv.toml` is optional and created by the user when needed. No changes to system-wide configuration files are required for basic operation.

##### Environment Variables

None required.

##### Activation Scripts

The shell hook is mandatory. After installing the binary, add the hook for the appropriate shell to the corresponding configuration file. After editing, restart the shell (or source the config file) for the hook to take effect.[^docs-hook]

**bash** — add to end of `~/.bashrc`:[^docs-hook]
```sh
eval "$(direnv hook bash)"
```
> The hook line must appear **after** any other shell extensions that manipulate the prompt, such as `rvm` or `git-prompt`.[^docs-hook]

**zsh** — add to end of `~/.zshrc`:[^docs-hook]
```sh
eval "$(direnv hook zsh)"
```

**zsh via Oh My Zsh** — add `direnv` to the `plugins` array in `~/.zshrc`:[^docs-hook]
```sh
plugins=(... direnv)
```
The Oh My Zsh direnv plugin registers a `_direnv_hook` function that runs `eval "$(direnv export zsh)"` in both `precmd_functions` (before each prompt) and `chpwd_functions` (on directory change), with SIGINT suppressed during evaluation. It prints a warning and exits without registering the hook if `direnv` is not found in `$PATH`.[^ohmyzsh-plugin]

**fish** — add to end of `~/.config/fish/config.fish`:[^docs-hook]
```fish
direnv hook fish | source
```
Three optional modes are configurable via the global `direnv_fish_mode` variable:[^docs-hook]
```fish
set -g direnv_fish_mode eval_on_arrow    # default: trigger at prompt and on every arrow-based dir change
set -g direnv_fish_mode eval_after_arrow # trigger at prompt and after arrow-based dir changes, before execution
set -g direnv_fish_mode disable_arrow    # trigger at prompt only (classic behavior)
```

**tcsh** — add to end of `~/.cshrc`:[^docs-hook]
```sh
eval `direnv hook tcsh`
```

**Elvish (0.12+)** — one-time setup, then add to `~/.config/elvish/rc.elv`:[^docs-hook]
```sh
mkdir -p ~/.config/elvish/lib
direnv hook elvish > ~/.config/elvish/lib/direnv.elv
```
```
# in ~/.config/elvish/rc.elv:
use direnv
```

**Nushell** — add the following block to the `$env.config.hooks.env_change.PWD` list in `config.nu`:[^docs-hook]
```nushell
{ ||
    if (which direnv | is-empty) {
        return
    }
    direnv export json | from json | default {} | load-env
}
```

**PowerShell** — add to `$PROFILE`:[^docs-hook]
```powershell
Invoke-Expression "$(direnv hook pwsh)"
```

**Murex** — add to `~/.murex_profile`:[^docs-hook]
```sh
direnv hook murex -> source
```

##### Cleanup

None required.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Use the package manager's standard upgrade command:
- Debian/Ubuntu: `sudo apt-get upgrade direnv`
- Fedora: `sudo dnf upgrade direnv`
- Arch: `sudo pacman -Syu direnv`
- Homebrew: `brew upgrade direnv`

Downgrading requires package manager-specific pinning or switching to the [Binary Installer Script](#official-bash-installer-script) / [Manual Binary Download](#manual-binary-download) methods.

##### Uninstallation

Use the package manager's standard remove command:
- Debian/Ubuntu: `sudo apt-get remove direnv`
- Fedora: `sudo dnf remove direnv`
- Arch: `sudo pacman -R direnv`
- Homebrew: `brew uninstall direnv`

The shell hook line added to the shell config file must be removed manually. The `~/.config/direnv/` and `~/.local/share/direnv/` directories are left intact.

##### Idempotency

Standard package manager behavior: re-running the install command is idempotent (a no-op if the package is already at the target version).

---

### Official Bash Installer Script

This is the officially recommended installation method for environments without a supported package manager.[^docs-install]

#### Supported Platforms

Linux and macOS with a `bash` shell and `curl`.[^src-install-sh] Supported operating systems and architectures as detected by `uname`:[^src-install-sh]

| `uname -s` (lowercased) | Mapped OS |
|---|---|
| `linux` | `linux` |
| `darwin` | `darwin` |
| `mingw*` | `windows` |

| `uname -m` | Mapped Architecture |
|---|---|
| `x86_64` | `amd64` |
| `i686` or `i386` | `386` |
| `armv7l` | `arm` |
| `aarch64` or `arm64` | `arm64` |
| any other | fatal error |

All other architectures cause the installer to exit with an error message directing the user to alternate methods.[^src-install-sh]

Note: Pre-built binaries for FreeBSD, NetBSD, and OpenBSD are available on the GitHub Releases page[^gh-api-latest] but the installer script's `uname -s` detection only explicitly handles `linux`, `darwin`, and `mingw*`; the raw lowercased kernel name (e.g. `freebsd`) would be passed through as-is to construct the download URL.

#### Dependencies

##### Common Dependencies

- `bash` (to execute the installer script)[^src-install-sh]
- `curl` (to query the GitHub Releases API and download the binary)[^src-install-sh]
- Network access to `api.github.com` and `github.com`[^src-install-sh]

##### Platform-Specific Dependencies

None.

#### Installation Steps

Basic installation (latest version, auto-detected install path):[^docs-install]
```sh
curl -sfL https://direnv.net/install.sh | bash
```

Install a specific version:
```sh
version=v2.37.1 curl -sfL https://direnv.net/install.sh | bash
```

Install to a custom path:
```sh
bin_path=/usr/local/bin curl -sfL https://direnv.net/install.sh | bash
```

Install a specific version to a custom path:
```sh
version=v2.37.1 bin_path=~/.local/bin curl -sfL https://direnv.net/install.sh | bash
```

#### Installation Verification

```sh
direnv version
```

Prints the installed version number.

#### Configuration Options

##### Version Selection

Set the `version` environment variable before invoking the script.[^src-install-sh] The value must be a full release tag as it appears on the GitHub Releases page (e.g. `v2.37.1`):
```sh
version=v2.37.1 curl -sfL https://direnv.net/install.sh | bash
```

If not set, the script queries `https://api.github.com/repos/direnv/direnv/releases/latest` to determine the latest release.[^src-install-sh]

##### Installation Path

Set the `bin_path` environment variable to a specific directory:[^src-install-sh]
```sh
bin_path=~/.local/bin curl -sfL https://direnv.net/install.sh | bash
```

If `bin_path` is not set, the script iterates over the entries in `$PATH` (split on `:`) and selects the **first directory that is writable** by the current user.[^src-install-sh] If no writable directory is found in `$PATH`, the script exits with an error.

##### User Targeting

Determined by the `bin_path` setting and directory permissions. A user-local install uses a user-writable directory such as `~/.local/bin`; a system-wide install uses a root-owned directory such as `/usr/local/bin` (requires sudo or root). There is no explicit `--user` flag.[^src-install-sh]

##### Required Privileges

Required only if the target installation directory (resolved via `bin_path` or PATH scan) is not writable by the current user. For system-wide directories such as `/usr/local/bin`, run the installer as root or with `sudo bash -c '...'`.[^src-install-sh]

##### Tool-Specific Configurations

Set `DIRENV_GITHUB_API_TOKEN` to a GitHub personal access token to avoid GitHub API rate limits when resolving the latest release:[^src-install-sh]
```sh
DIRENV_GITHUB_API_TOKEN=ghp_... curl -sfL https://direnv.net/install.sh | bash
```

This variable is consumed only by the installer script; it has no effect on direnv at runtime.

Runtime configuration of direnv itself uses `direnv.toml`; see [Tool-Specific Configurations](#tool-specific-configurations) under OS Package Manager.

#### Post-Installation Steps and Cleanup

##### PATH Setup

If `bin_path` was set to a directory not already in `$PATH`, add that directory to `$PATH` in the shell configuration file:
```sh
export PATH="$HOME/.local/bin:$PATH"
```

When using the default behavior (first writable directory found in the current `$PATH`), no PATH modification is needed.

##### Configuration Files

`~/.config/direnv/direnv.toml` is optional; see [Tool-Specific Configurations](#tool-specific-configurations) under OS Package Manager.

##### Environment Variables

None required at runtime.

##### Activation Scripts

The shell hook setup is identical to the OS Package Manager method. See [Activation Scripts](#activation-scripts) under OS Package Manager for the full per-shell instructions.[^docs-hook]

##### Cleanup

The installer creates no temporary files.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Re-run the installer with the desired `version` env var. The script unconditionally overwrites the existing binary:[^src-install-sh]
```sh
version=v2.37.1 bin_path=/path/to/existing/install curl -sfL https://direnv.net/install.sh | bash
```

##### Uninstallation

Delete the binary from its installation path:
```sh
rm "$(which direnv)"
```

The shell hook line in the shell config file must be removed manually.

##### Idempotency

Yes — re-running the installer downloads and replaces the existing binary at the same path. Safe to run multiple times.[^src-install-sh]

#### Details

The script (`https://direnv.net/install.sh`) performs the following steps in order:[^src-install-sh]

1. Detects the kernel type: `uname -s | tr "[:upper:]" "[:lower:]"`. Maps `mingw*` to `windows`.
2. Detects the machine architecture: `uname -m`. Maps to Go-style arch names (`amd64`, `arm64`, `arm`, `386`). Unrecognized architectures exit with an error.
3. Determines the installation directory from `$bin_path` env var; if unset, iterates `$PATH` entries (split on `:`) and picks the first writable one. Exits if none found.
4. Determines the release ref: `tags/${version}` if `$version` is set, otherwise `latest`.
5. Queries `https://api.github.com/repos/direnv/direnv/releases/${release}` via `curl -fL`, optionally with an `Authorization: Bearer ${DIRENV_GITHUB_API_TOKEN}` header.
6. Parses the JSON response by grepping for `browser_download_url`, cutting the quoted URL value, then filtering for lines ending with `direnv.$kernel.$machine` (exact suffix match). This relies on the format of GitHub's release asset JSON, not a hardcoded URL template.
7. Downloads the binary to `$bin_path/direnv` via `curl -o ... -fL`.
8. Sets the binary executable: `chmod a+x "$bin_path/direnv"`.
9. Prints instructions for completing shell hook setup.

**Binary filename format on GitHub Releases**: `direnv.<os>-<arch>` (no file extension, even on Windows).[^gh-api-latest] Examples from v2.37.1:
- `direnv.linux-amd64`, `direnv.linux-arm64`, `direnv.linux-arm`, `direnv.linux-386`
- `direnv.linux-mips`, `direnv.linux-mips64`, `direnv.linux-mips64le`, `direnv.linux-mipsle`
- `direnv.linux-ppc64`, `direnv.linux-ppc64le`, `direnv.linux-s390x`
- `direnv.darwin-amd64`, `direnv.darwin-arm64`
- `direnv.windows-amd64`, `direnv.windows-386`, `direnv.windows-arm64`
- `direnv.freebsd-amd64`, `direnv.freebsd-arm`, `direnv.freebsd-386`
- `direnv.netbsd-amd64`, `direnv.netbsd-arm`, `direnv.netbsd-386`
- `direnv.openbsd-amd64`, `direnv.openbsd-386`

The GitHub Releases API response includes a `digest` field (SHA-256) for each asset (e.g. `sha256:1f1b93dd...`). **The installer script does not verify the checksum.**[^src-install-sh]

#### Notes and Best Practices

- The installer performs no checksum or signature verification. For security-sensitive environments, use [Manual Binary Download](#manual-binary-download) and verify the SHA-256 digest from the GitHub API response.
- The `curl -sfL https://direnv.net/install.sh | bash` pattern executes the installer in a sub-shell, which means environment variable assignments like `version=v2.37.1` must precede the `curl` command in the same shell statement (not exported separately to the sub-shell via `export`), as shown in the installation steps above.[^src-install-sh]

---

### Manual Binary Download

#### Supported Platforms

All platforms for which pre-built binaries are available on the GitHub Releases page.[^gh-api-latest] As of v2.37.1, this includes:
- **Linux**: amd64, arm64, arm, 386, mips, mips64, mips64le, mipsle, ppc64, ppc64le, s390x
- **macOS (darwin)**: amd64, arm64
- **Windows**: amd64, 386, arm64
- **FreeBSD**: amd64, arm, 386
- **NetBSD**: amd64, arm, 386
- **OpenBSD**: amd64, 386

#### Dependencies

##### Common Dependencies

A download tool (`curl`, `wget`, or a web browser) is needed to retrieve the binary. No runtime dependencies.

##### Platform-Specific Dependencies

None.

#### Installation Steps

1. Browse to https://github.com/direnv/direnv/releases and identify the binary for the target platform. The filename format is `direnv.<os>-<arch>` (e.g. `direnv.linux-amd64`).[^gh-api-latest]

2. Download the binary. Example for Linux amd64:[^docs-install]
   ```sh
   curl -Lo direnv https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.linux-amd64
   ```

3. Make it executable:[^docs-install]
   ```sh
   chmod +x direnv
   ```

4. Move it to a directory in `$PATH`:[^docs-install]
   ```sh
   mv direnv ~/.local/bin/
   # or system-wide:
   sudo mv direnv /usr/local/bin/
   ```

#### Installation Verification

```sh
direnv version
```

#### Configuration Options

##### Version Selection

Download any release tag from https://github.com/direnv/direnv/releases and substitute it in the download URL.

##### Installation Path

User-chosen. Recommended:
- User-local (no sudo): `~/.local/bin/direnv`
- System-wide (sudo required): `/usr/local/bin/direnv`

##### User Targeting

User-local or system-wide, depending on the chosen target directory.

##### Required Privileges

Required only if installing to a system-owned directory (e.g. `/usr/local/bin`).

##### Tool-Specific Configurations

Runtime configuration uses `direnv.toml`; see [Tool-Specific Configurations](#tool-specific-configurations) under OS Package Manager.

#### Post-Installation Steps and Cleanup

##### PATH Setup

If the chosen installation directory is not already in `$PATH`, add it:
```sh
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.bashrc or ~/.zshrc
```

##### Configuration Files

`~/.config/direnv/direnv.toml` is optional; see [Tool-Specific Configurations](#tool-specific-configurations) under OS Package Manager.

##### Environment Variables

None required at runtime.

##### Activation Scripts

The shell hook setup is identical to the OS Package Manager method. See [Activation Scripts](#activation-scripts) under OS Package Manager for the full per-shell instructions.[^docs-hook]

##### Cleanup

None.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

Download the desired version's binary and overwrite the existing file:
```sh
curl -Lo "$(which direnv)" https://github.com/direnv/direnv/releases/download/<tag>/direnv.<os>-<arch>
chmod +x "$(which direnv)"
```

##### Uninstallation

```sh
rm "$(which direnv)"
```

##### Idempotency

Manual — overwriting the binary is always safe.

#### Notes and Best Practices

The SHA-256 digest for each release binary is available in the GitHub API response at `https://api.github.com/repos/direnv/direnv/releases/latest` under the `digest` field of each asset.[^gh-api-latest] Verify after download:
```sh
# Example — substitute the actual hash from the API response for the asset you downloaded:
echo "<sha256-hash>  direnv" | sha256sum -c
```

---

### Build from Source

#### Supported Platforms

Any platform with a supported Go toolchain (Linux, macOS, Windows, etc.).[^docs-development]

#### Dependencies

##### Common Dependencies

- Go >= 1.24[^docs-development]
- `make`[^docs-development]
- `git`[^docs-development]

##### Platform-Specific Dependencies

None.

#### Installation Steps

```sh
git clone https://github.com/direnv/direnv.git
cd direnv
make
```

Install system-wide (requires sudo or root):[^docs-development]
```sh
sudo make install
```

Install user-local:[^docs-development]
```sh
make install PREFIX=~/.local
```

To build a specific version:[^docs-development]
```sh
git checkout v2.37.1
make
make install PREFIX=~/.local
```

Run the test suite:[^docs-development]
```sh
make test
```

#### Installation Verification

```sh
direnv version
```

#### Configuration Options

##### Version Selection

Check out the desired git tag before building:[^docs-development]
```sh
git checkout v2.37.1
```

##### Installation Path

Controlled via the `PREFIX` make variable. The binary is installed to `$PREFIX/bin/direnv`. Default `PREFIX` is `/usr/local`.[^docs-development]

```sh
make install PREFIX=~/.local    # installs to ~/.local/bin/direnv
```

##### User Targeting

User-local via `PREFIX=~/.local` (no sudo required). System-wide via default `PREFIX=/usr/local` (sudo required).[^docs-development]

##### Required Privileges

Required only for system-wide install (`make install` without `PREFIX`).[^docs-development]

##### Tool-Specific Configurations

Runtime configuration uses `direnv.toml`; see [Tool-Specific Configurations](#tool-specific-configurations) under OS Package Manager.

#### Post-Installation Steps and Cleanup

##### PATH Setup

If `PREFIX=~/.local` was used and `~/.local/bin` is not already in `$PATH`, add it.

##### Configuration Files

`~/.config/direnv/direnv.toml` is optional.

##### Environment Variables

None required at runtime.

##### Activation Scripts

The shell hook setup is identical to the OS Package Manager method. See [Activation Scripts](#activation-scripts) under OS Package Manager for the full per-shell instructions.[^docs-hook]

##### Cleanup

The cloned repository directory can be removed after installation.

#### Changing Versions and Uninstallation

##### Upgrading/Downgrading

```sh
cd direnv
git fetch --tags
git checkout <new-tag>
make
make install [PREFIX=~/.local]
```

##### Uninstallation

```sh
rm $PREFIX/bin/direnv
```

##### Idempotency

`make install` overwrites the existing binary unconditionally.

---

## Dev Container Setup

When deploying direnv in a devcontainer environment, the following considerations apply:

1. **Binary installation**: Use either `apt-get install direnv` (for Debian/Ubuntu-based containers) or the official installer script. The installer script is preferred when version pinning is required.

2. **Shell hook setup**: In a devcontainer, the shell hook must be injected into the appropriate system-wide or per-user shell initialization files during the feature's `install.sh`. For containers using bash and zsh as the default shells, append the hooks to the system-wide configuration files:
   ```sh
   # bash
   echo 'eval "$(direnv hook bash)"' >> /etc/bash.bashrc
   # zsh (path varies by distribution)
   echo 'eval "$(direnv hook zsh)"' >> /etc/zsh/zshrc   # Debian/Ubuntu
   # or:
   echo 'eval "$(direnv hook zsh)"' >> /etc/zshrc        # other distros
   ```
   For per-user hook injection (if targeting a specific non-root user), append to the user's `~/.bashrc` or `~/.zshrc` instead.

3. **`direnv allow` for workspace**: The `.envrc` in the workspace root will not be automatically loaded on first entry due to direnv's security model. To auto-allow the workspace `.envrc` in a devcontainer, add a `postCreateCommand` in `devcontainer.json`:[^man-direnv]
   ```json
   "postCreateCommand": "direnv allow ${containerWorkspaceFolder}"
   ```
   Alternatively, configure the `[whitelist]` in `direnv.toml` to trust the workspace directory.[^man-direnv-toml]

4. **VS Code integration**: The [mkhl.direnv VS Code extension](#vs-code-extension-mkhldirenv) handles `direnv allow` interactively and makes the direnv environment available in integrated terminals and tasks. Without the extension, the `postCreateCommand` approach is required for automatic loading.

5. **The `devcontainers-extra` feature** (`ghcr.io/devcontainers-extra/features/direnv:1`) installs only the binary via GitHub Releases and does **not** configure the shell hook.[^ext-devcontainers-extra] Shell hook setup must be added separately when using this feature.

6. **The `devcontainers-community` feature** (`ghcr.io/devcontainer-community/devcontainer-features/direnv.net:1`) installs via `apt-get install direnv` and targets Debian-based containers only.[^ext-devcontainer-net] Shell hook setup details are not documented in its source.

7. **No daemon or service**: direnv has zero runtime overhead between prompts and requires no persistent process, service, or volume mount in the container.

## Plugins and Extensions

### VS Code Extension: mkhl.direnv

**Source:** https://github.com/direnv/direnv-vscode[^vscode-ext]

| Detail | Value |
|---|---|
| Extension ID | `mkhl.direnv` |
| Publisher | Martin Kühl (mkhl) |
| Latest version | v0.17.0 (2024-03-12) |
| License | 0BSD |
| Implementation language | TypeScript (96.3%), Shell (3.7%) |

**Architecture**: A VS Code extension that loads the direnv environment for the VS Code workspace root and makes it available within VS Code. It calls `direnv export json` to obtain the environment diff, then injects the resulting variables into VS Code's integrated terminals, shell-type custom tasks, and variable substitutions. It does not use the shell hook mechanism; it interacts with the direnv binary directly.[^vscode-ext]

**Functionality**:[^vscode-ext]
- Automatically loads the direnv environment when opening a workspace containing an `.envrc` file
- Prompts the user to allow or view the `.envrc` before executing (respecting the security model)
- Automatically reloads the environment when files watched by direnv are modified (`direnv.watchForChanges` setting, added in v0.17.0)
- Provides commands: open/create `.envrc`, allow/block `.envrc`, reload environment, reset-and-reload, load from a specified path
- Displays a status indicator (working/succeeded/failed) in the VS Code status bar; clicking it triggers a reload

**Requirements**:[^vscode-ext]
- The `direnv` binary must be installed separately and available in `$PATH`
- Trusted workspaces are required (the extension executes shell scripts)

**Known limitations**:[^vscode-ext]
- **Process-type custom tasks** do NOT inherit the modified environment; only shell-type tasks do (VS Code API limitation)
- **Unset variables** appear as empty strings in terminals (VS Code API limitation, not a direnv limitation)

**Installation via command line:**
```sh
code --install-extension mkhl.direnv
```

Or search for `direnv` in the VS Code Extensions marketplace.

**Version history highlights:**[^vscode-ext]
- v0.17.0 (2024-03-12): added `direnv.watchForChanges` setting
- v0.16.0 (2024-01-18): added Windows support

### Oh My Zsh direnv Plugin

**Source:** https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/direnv[^ohmyzsh-plugin]

A built-in plugin in Oh My Zsh that sets up the direnv zsh hook.

**Activation**: Add `direnv` to the `plugins` array in `~/.zshrc`:[^docs-hook]
```sh
plugins=(... direnv)
```

**How it works**: The plugin registers a `_direnv_hook` function into both `precmd_functions` (runs before each prompt) and `chpwd_functions` (runs on directory change).[^ohmyzsh-plugin] On each invocation, it runs `eval "$(direnv export zsh)"` with SIGINT suppressed during evaluation. If `direnv` is not found in `$PATH`, the plugin prints a warning and exits without registering the hook.[^ohmyzsh-plugin]

This is functionally equivalent to adding `eval "$(direnv hook zsh)"` to `~/.zshrc` but integrates with Oh My Zsh's plugin loading system.

## References

[^repo]: [direnv — Official GitHub Repository](https://github.com/direnv/direnv)
[^docs-install]: [direnv — Official Installation Documentation](https://github.com/direnv/direnv/blob/master/docs/installation.md)
[^docs-hook]: [direnv — Official Shell Hook Documentation](https://github.com/direnv/direnv/blob/master/docs/hook.md)
[^man-direnv-toml]: [direnv — direnv.toml(1) Man Page Source](https://github.com/direnv/direnv/blob/master/man/direnv.toml.1.md)
[^man-direnv-stdlib]: [direnv — direnv-stdlib(1) Man Page](https://direnv.net/man/direnv-stdlib.1.html)
[^man-direnv]: [direnv — direnv(1) Man Page](https://direnv.net/man/direnv.1.html)
[^docs-development]: [direnv — Development Documentation](https://github.com/direnv/direnv/blob/master/docs/development.md)
[^src-install-sh]: [direnv — Official Installer Script Source Code](https://direnv.net/install.sh) — authoritative source for install.sh logic, environment variable handling, platform detection, bin_path resolution, and download URL construction
[^gh-api-latest]: [direnv — GitHub Releases API (latest)](https://api.github.com/repos/direnv/direnv/releases/latest) — authoritative source for release version (v2.37.1 as of 2025-07-20), complete binary asset list with filenames and SHA-256 digests
[^ext-devcontainers-extra]: [devcontainers-extra/features — direnv Feature](https://github.com/devcontainers-extra/features/tree/main/src/direnv) — installs binary via `gh-release` nanolayer helper, no shell hook setup; `devcontainer-feature.json` and `install.sh` reviewed
[^ext-devcontainer-net]: [devcontainer-community/devcontainer-features — direnv.net Feature](https://github.com/devcontainer-community/devcontainer-features/tree/main/src/direnv.net) — Debian-only apt-based installation
[^ext-devcontainers-community]: [devcontainers-community/features — direnv Feature](https://github.com/devcontainers-community/features-direnv) — community feature supporting `latest`, `system`, and versioned installs
[^vscode-ext]: [mkhl.direnv — VS Code Extension Repository](https://github.com/direnv/direnv-vscode) — official VS Code extension; architecture, functionality, limitations, and version history reviewed
[^ohmyzsh-plugin]: [Oh My Zsh — direnv Plugin Source Code](https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/direnv/direnv.plugin.zsh) — full plugin source reviewed; registers `_direnv_hook` into `precmd_functions` and `chpwd_functions`
