# Feature Reference

TeX Live is the upstream TeX distribution maintained by TeX user groups and is the canonical source for LaTeX engines, macro packages, fonts, and tooling across Linux, macOS, and Windows. For SysSet `install-latex`, the practical goal is to provide reliable LaTeX toolchain provisioning (at minimum `latex` and package management via `tlmgr`) across macOS and Linux, including container environments.

For this feature, three installation paths are relevant in practice:

1. Official TeX Live Unix installer (`install-tl`) for consistent cross-distro behavior and predictable feature options.
2. Native macOS installers (MacTeX / BasicTeX) for standard Apple package-install UX.
3. Distro-provided TeX Live packages for environments that require strict OS package-manager governance.

- **Homepage**: https://www.tug.org/texlive/
- **Source Code**: https://github.com/TeX-Live/installer
- **Documentation**: https://www.tug.org/texlive/doc/install-tl.html and https://www.tug.org/texlive/tlmgr.html
- **Latest Release**: 2026 (as of 2026-04-26)

## Available Installation Methods

Upstream explicitly supports multiple acquisition and install approaches (network installer, ISO, DVD, mirrored repositories, and platform-specific packaging). For SysSet implementation on macOS/Linux, the most operationally useful methods are detailed below.

### Official TeX Live Unix Installer (`install-tl`)

#### Supported Platforms

- Linux and other Unix-like systems with supported TeX Live binaries.
- macOS (including older versions via Unix installer flow), with platform-specific binary selection handled by TeX Live.

#### Dependencies

- **Common Dependencies**: A working Perl runtime with core modules, archive utilities (`tar`, `zcat`/`gzip`, `xz`), downloader support (`LWP` Perl module is recommended for performance; `wget`/`curl` are fallback paths), and writable install destination.
- **Platform-Specific Dependencies**:
  - Linux: root/sudo only if installing into system-owned paths such as `/usr/local/texlive`.
  - macOS: same installer flow works; native MacTeX package route is an alternative.
  - Installer checksum backend for integrity checks: at least one of `Digest::SHA`, `openssl`, `sha512sum`, or `shasum` must be available (or checksum warnings/checks can be explicitly disabled).
  - Optional but strongly recommended for verification: `gpg` for signature verification support.

#### Installation Steps

Minimal non-interactive upstream flow:

```bash
cd /tmp
wget https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz
zcat < install-tl-unx.tar.gz | tar xf -
cd install-tl-2*
perl ./install-tl --no-interaction
```

Other upstream-supported source media for the same installer include local hard disk trees, mirrored local repositories, and DVD/ISO-based layouts. Example local-repository invocation:

```bash
perl ./install-tl --no-interaction --repository /path/to/local/tlnet
```

For older/frozen yearly states, TeX Live historical repositories can be used by setting `--repository` to the desired archived tlnet endpoint.

Commonly used explicit options for feature automation:

```bash
perl ./install-tl \
  --no-interaction \
  --repository https://mirror.ctan.org/systems/texlive/tlnet \
  --scheme=small
```

If installation directories should be customized:

```bash
perl ./install-tl \
  --no-interaction \
  --texdir=/opt/texlive/2026 \
  --texuserdir=/opt/texlive-user
```

#### Installation Verification

Baseline command verification:

```bash
latex --version
tlmgr --version
```

Optional package-level check:

```bash
tlmgr info --only-installed latex
```

Upstream quick-install smoke test:

```bash
latex small2e
```

When cryptographic verification is active, installer/tlmgr output indicates repository verification status (`(verified)` vs `(not verified)`).

#### Configuration Options

- **Version Selection**:
  - TeX Live major release tracks yearly releases (for example 2026).
  - Repository selection controls source/version stream (`--repository`), including historic yearly snapshots when needed.
- **Installation Path**:
  - Default system tree is under `/usr/local/texlive/YYYY`.
  - User tree defaults are platform-dependent:
    - `TEXMFHOME`: `~/texmf` on Unix, `~/Library/texmf` on macOS.
    - `TEXMFCONFIG`/`TEXMFVAR`: `~/.texliveYYYY/texmf-{config,var}` on Unix, `~/Library/texlive/YYYY/texmf-{config,var}` on macOS.
  - Note: some embedded installer-manual text still shows older macOS path wording; current installer code paths are the authoritative source for these defaults.
  - Path trees are configurable via `--texdir`, `--texuserdir`, and related `--texmf*` options.
- **User Targeting**:
  - Supported both system-wide and user-scoped installs, depending on destination directories and permissions.
- **Required Privileges**:
  - Not inherently required by TeX Live itself; only filesystem permissions matter.
  - Sudo/root required when writing to root-owned prefixes.
- **Tool-Specific Configurations**:
  - Scheme selection: `--scheme=<full|medium|small|basic|minimal|...>`.
  - Paper default: `--paper=a4|letter`.
  - Doc/src toggles: `--no-doc-install`, `--no-src-install`.
  - Batch profile mode: `--profile <file>` / `--init-from-profile <file>`.
  - Install modes: `--portable` for self-contained portable trees (forces `TEXMFHOME`, `TEXMFCONFIG`, and `TEXMFVAR` to map to system trees; disables path adjustment and, on Windows, desktop integration/file associations), and `--in-place` for using an existing TL checkout as source (quick-and-dirty, manual removal required, and intended for advanced use).
  - Advanced repository and binary controls: `--select-repository` (explicit mirror/local-media selection in interactive modes) and `--custom-bin <path>` (inject custom-built binaries; not compatible with `--in-place`).
  - With `--custom-bin`, supplied binaries are copied to `TLROOT/bin/custom`, that literal path should be used in PATH, and ongoing updates require `wget`, `xz`, and `xzdec` in PATH; platform-script symlinks in `bin/custom` must be maintained manually.
  - Failure-handling controls: `--strict` aborts when post-install commands fail; `--no-continue` aborts after retry failure of non-core package installs.
  - Verification and download behavior from installer/tooling (verification is enabled by default when `gpg` is available and can be disabled with `--no-verify-downloads`; for package operations, `tlmgr --verify-repo=none|main|all` controls repository signature requirements; persistent-download controls are also available).

#### install-tl Configuration Options Reference

A comprehensive reference of all `install-tl` configuration options. Each option may be specified through one or more input mechanisms:

- **Profile** — profile key for use in a `.profile` file passed via `--profile`
- **CLI** — command-line argument(s) passed directly to `install-tl`
- **Env Var** — shell environment variable consumed by the installer
- `–` means the option is not available through that input type

---

##### 1. Installation Mode and Flow

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| – | `--no-interaction` / `-N` | – | Suppress all interactive prompts; run fully non-interactively. Also triggered automatically when stdin is not a terminal. |
| `instopt_portable 0\|1` | `--portable` | – | Install into a fully self-contained portable tree. Forces `TEXMFHOME`, `TEXMFCONFIG`, and `TEXMFVAR` to reside inside `TEXDIR`; disables `instopt_adjustpath`; disables desktop integration and file associations on Windows. Default: `0`. Overrides user-tree directory options if any are also set. |
| – | `--in-place` | – | Use an existing TeX Live VCS checkout in `TEXDIR` directly without copying files. Intended for developers. Incompatible with `--custom-bin`. No uninstall script is generated; manual removal is required. |
| – | `--strict` / `--no-strict` | – | `--strict`: abort the entire installation if any post-install command fails (e.g. `fmtutil`, `updmap`). `--no-strict` (default): log warnings and continue. |
| – | `--no-continue` | – | Abort if any non-core package download or install fails on retry. Default: skip the failed package and continue. |
| – | `--non-admin` | – | **Windows only.** Force a per-user installation even when running as Administrator; skips `HKEY_LOCAL_MACHINE` registry writes. Equivalent to `tlpdbopt_w32_multi_user 0`. |
| – | `--gui [=tcl\|perltk\|text\|wizard\|expert\|extl]` | – | Launch the interactive GUI installer. The optional argument selects the frontend: `tcl` (Tcl/Tk), `perltk` (Perl/Tk), `text` (readline, default on Unix/Linux), `wizard`, `expert`, or `extl`. Default on Windows: `tcl`. Use `--no-gui` to force text mode regardless of environment. |
| – | `--no-gui` | – | Force text-mode installation, overriding any GUI default. Distinct from `--gui=text` in that it prevents any GUI from being attempted. |
| – | `--lang LANG` / `--gui-lang LANG` | – | Set the GUI display language via an ISO 639 code (e.g. `de`, `fr`, `ja`). GUI mode only; ignored in non-interactive mode. |
| – | `--logfile FILE` | – | Write the installation log to `FILE`. Default: `$TEXDIR/install-tl.log` (inside the installation root). |
| – | `--version` | – | Print the installer version and exit. |
| – | `--help` / `-?` | – | Print help text and exit. Output format depends on `NOPERLDOC`. |
| – | `--print-platform` / `--print-arch` | – | Print the detected platform identifier (e.g. `x86_64-linux`) and exit. Useful for debugging binary selection. |
| – | `--all-options` | – | Allow configuring platform-specific options that would normally be hidden for the current platform. For example, on Unix, Windows-specific options (file associations, desktop integration) are normally omitted from the interactive menu; this flag makes them visible and configurable. Does not print-and-exit; takes effect during an interactive session. |

---

##### 2. Profile Loading

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| – | `--profile FILE` | – | Load a profile file and run a non-interactive installation. The file is plain text with `key value` pairs, one per line; blank lines and `#`-prefixed lines are ignored. All profile keys documented in the other sections may appear in this file. |
| – | `--init-from-profile FILE` | – | Read a profile to pre-populate defaults, then continue interactively. Useful for seeding the interactive installer with specific values without fully automating it. |
| – | `--no-installation` | – | Skip the actual installation entirely and exit immediately. Useful as a debugging or dry-run option to verify configuration without writing anything to disk. Note: despite what might be expected, this option does **not** write a profile file. |

---

##### 3. Repository / Source

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| `tlpdbopt_location URL` | `--location URL` / `--repository URL` / `--url URL` / `--repos URL` / `-repo URL` | – | Repository URL or local path to install from. Accepted forms: `http://`, `https://`, `ftp://`, `file:///path`, or a bare local directory path. May include a `texlive/YYYY` subdirectory. Default: CTAN mirror auto-selected at runtime. Legacy profile alias `location` (without the `tlpdbopt_` prefix) is auto-translated to this key. |
| `instopt_adjustrepo 0\|1` | – | – | Adjust the repository URL to use the best-performing CTAN mirror. `1` = adjust (default); `0` = use the configured URL verbatim. Profile-only; there are no `--adjust-repo` or `--no-adjust-repo` CLI flags. |
| – | `--select-repository` | – | **Interactive mode only.** Present a numbered mirror list and prompt the user to choose. Ignored in non-interactive mode. |

---

##### 4. Directory Layout

All seven TEXMF paths can be specified as profile keys, CLI flags, and environment variables. When `instopt_portable 1` is set, `TEXMFHOME`, `TEXMFCONFIG`, and `TEXMFVAR` are redirected inside `TEXDIR` regardless of explicit settings.

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| `TEXDIR PATH` | `--texdir PATH` | – | Root installation directory. Default: `/usr/local/texlive/YYYY` (Unix) or `%SystemDrive%\texlive\YYYY` (Windows). Set indirectly via `TEXLIVE_INSTALL_PREFIX` (see below); there is no `TEXLIVE_INSTALL_TEXDIR` env var. |
| `TEXMFLOCAL PATH` | `--texmflocal PATH` | `TEXLIVE_INSTALL_TEXMFLOCAL` | Version-independent shared tree for local additions (packages, fonts, config). Default: `TEXDIR/../texmf-local` (sibling of the year tree; survives side-by-side version upgrades). |
| `TEXMFSYSVAR PATH` | `--texmfsysvar PATH` | `TEXLIVE_INSTALL_TEXMFSYSVAR` | System-wide generated/variable data: format files, font maps, hyphenation patterns, ls-R databases. Default: `TEXDIR/texmf-var`. |
| `TEXMFSYSCONFIG PATH` | `--texmfsysconfig PATH` | `TEXLIVE_INSTALL_TEXMFSYSCONFIG` | System-wide local configuration overrides (e.g. custom `texmf.cnf` additions). Default: `TEXDIR/texmf-config`. |
| `TEXMFHOME PATH` | `--texmfhome PATH` | `TEXLIVE_INSTALL_TEXMFHOME` | Per-user personal package tree. Expanded at runtime per user, not at install time. Default: `~/texmf` (Linux/other Unix); `~/Library/texmf` (macOS). Redirected inside `TEXDIR` when `instopt_portable 1`. |
| `TEXMFVAR PATH` | `--texmfvar PATH` | `TEXLIVE_INSTALL_TEXMFVAR` | Per-user generated data (format files, font maps). Default: `~/.texlive/YYYY/texmf-var`. Redirected inside `TEXDIR` when `instopt_portable 1`. Also set indirectly by `--texuserdir`. |
| `TEXMFCONFIG PATH` | `--texmfconfig PATH` | `TEXLIVE_INSTALL_TEXMFCONFIG` | Per-user configuration overrides. Default: `~/.texlive/YYYY/texmf-config`. Redirected inside `TEXDIR` when `instopt_portable 1`. Also set indirectly by `--texuserdir`. |
| – | `--texuserdir PATH` | – | Convenience shortcut: sets `TEXMFHOME`, `TEXMFCONFIG`, and `TEXMFVAR` to `PATH/texmf`, `PATH/texmf-config`, and `PATH/texmf-var` respectively. Equivalent to setting all three with their individual flags. No profile key equivalent. |
| – | – | `TEXLIVE_INSTALL_PREFIX` | Sets the installation prefix. Final `TEXDIR` becomes `$PREFIX/texlive/YYYY`. Useful for relocating the tree without specifying the year explicitly. |

---

##### 5. Content Selection

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| `selected_scheme SCHEME` | `--scheme SCHEME` / `-scheme SCHEME` / `-s SCHEME` | – | Metapackage scheme to install. Values: `scheme-full`, `scheme-medium`, `scheme-small`, `scheme-basic`, `scheme-minimal`, `scheme-infraonly`, `scheme-bookpublishing`, `scheme-context`, `scheme-gust`, `scheme-tetex`. Default: `scheme-full`. Each scheme is a predefined collection of collections. `scheme-infraonly` installs only the TeX Live infrastructure; no typesetting packages. |
| `collection-NAME 0\|1` | – | – | Override collection inclusion. `1` = force-include a collection not in the selected scheme; `0` = force-exclude a collection that the scheme would include. `NAME` is the collection identifier (e.g. `collection-latex`, `collection-fontsrecommended`). One entry per line; multiple entries allowed. Run `tlmgr info collections` for the full list of identifiers. |
| `binary_PLATFORM 1` | – | – | Include the binary set for `PLATFORM` (e.g. `binary_x86_64-linux 1`, `binary_universal-darwin 1`). The host platform is always included; add extra platforms only for cross-use. |
| `tlpdbopt_install_docfiles 0\|1` | `--doc-install` / `--no-doc-install` | – | Install documentation files bundled with packages (`.pdf`, HTML docs, man pages). `--doc-install` sets `1` (install); `--no-doc-install` sets `0` (skip). Upstream default: `1`. Feature default: `0` (smaller container images). |
| `tlpdbopt_install_srcfiles 0\|1` | `--src-install` / `--no-src-install` | – | Install source files bundled with packages (`.dtx`, `.ins`, etc.). `--src-install` sets `1` (install); `--no-src-install` sets `0` (skip). Upstream default: `1`. Feature default: `0`. |

---

##### 6. PATH and Symlinks

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| `instopt_adjustpath 0\|1` | – | – | Create symlinks in `tlpdbopt_sys_bin`, `tlpdbopt_sys_man`, and `tlpdbopt_sys_info` pointing to TeX Live executables, man pages, and info pages. `1` = create symlinks; `0` = skip. Upstream default: `0` on Unix/macOS; `1` on Windows. Feature default: `1` (symlinks in `/usr/local/bin` make binaries available on PATH in containers). Automatically forced to `0` when `instopt_portable 1`. |
| `tlpdbopt_sys_bin PATH` | `--sys-bin PATH` | – | Target directory for TeX Live executable symlinks. Default: `/usr/local/bin`. Effective only when `instopt_adjustpath 1`. |
| `tlpdbopt_sys_man PATH` | `--sys-man PATH` | – | Target directory for TeX Live man-page symlinks. Default: `/usr/local/share/man`. Effective only when `instopt_adjustpath 1`. |
| `tlpdbopt_sys_info PATH` | `--sys-info PATH` | – | Target directory for TeX Live info-page symlinks. Default: `/usr/local/share/info`. Effective only when `instopt_adjustpath 1`. |

---

##### 7. TeX Behaviour

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| `instopt_letter 0\|1` | `--paper a4\|letter` | `TEXLIVE_INSTALL_PAPER` | Default paper size for newly generated formats. Profile: `0` = A4 (default), `1` = letter. CLI: `--paper a4` or `--paper letter`. Env var: `a4` or `letter`. For installation methods other than install-tl (OS packages, MacTeX/BasicTeX), this feature applies the setting post-install via `tlmgr option paper`. |
| `instopt_write18_restricted 0\|1` | – | – | Enable restricted `\write18` (shell escape). `1` = restricted mode (default; permits only a known-safe list of commands); `0` = fully disabled. Setting to `0` prevents all shell-escape use. |
| `tlpdbopt_create_formats 0\|1` | – | – | Run `fmtutil-sys --all` to generate format files (`.fmt`) after installation. `1` = generate (default); `0` = skip. Skipping speeds up the install but requires running `fmtutil-sys --all` manually before compiling any document. No CLI flag equivalent; profile-only. |
| `tlpdbopt_post_code 0\|1` | – | – | Execute post-installation Perl code supplied by packages (font map generation, hyphenation compilation, etc.). `1` = run (default); `0` = skip. Setting to `0` leaves the installation incomplete and typically requires manual post-install steps before the tree is usable. |
| `tlpdbopt_generate_updmap 0\|1` | – | – | Automatically call `updmap` after each package with map files is installed. `0` = do not auto-call (default); `1` = auto-call. Enabling during bulk installs causes redundant `updmap` invocations; prefer running `updmap-sys` once manually after all packages are installed. |

---

##### 8. Package Manager Settings

These options are stored in the TeX Live package database (`tlpdb`) and persist to govern ongoing `tlmgr` behaviour as well as install-time defaults.

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| `tlpdbopt_autobackup N` | – | – | Number of backup copies of each package to retain when running `tlmgr update`. `0` = no backups; positive integer = keep that many most-recent backups; `-1` = keep unlimited. Default: `1`. Requires a valid `tlpdbopt_backupdir`. |
| `tlpdbopt_backupdir PATH` | – | – | Directory where `tlmgr` stores per-package backup archives. Default: `TEXDIR/tlpkg/backups`. No effect when `tlpdbopt_autobackup 0`. |
| `tlpdbopt_file_assocs 0\|1\|2` | – | – | **Windows only.** File-type associations for TeX-related files. `0` = set none; `1` = add new associations only, do not overwrite existing ones (default); `2` = overwrite all existing associations. Automatically disabled when `instopt_portable 1`. |
| `tlpdbopt_desktop_integration 0\|1` | – | – | **Windows only.** Create Start-menu entries and desktop icons. `1` = create (default); `0` = skip. Automatically disabled when `instopt_portable 1`. |
| `tlpdbopt_w32_multi_user 0\|1` | – | – | **Windows only.** Install for all users (system-wide) rather than the current user only. `1` = all users (default); `0` = current user. The CLI flag `--non-admin` is equivalent to setting this to `0`. |

---

##### 9. Download and Verification

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| – | `--verify-downloads` / `--no-verify-downloads` | – | Enable or disable GPG signature verification of downloaded packages. Default: enabled when `gpg` is found in PATH; `--no-verify-downloads` disables unconditionally. For post-install `tlmgr` operations, `tlmgr --verify-repo=none\|main\|all` controls verification scope separately. |
| – | `--persistent-downloads` / `--no-persistent-downloads` | – | Keep the download agent (`wget` or `curl`) running between package downloads. Default: persistent (enabled). `--no-persistent-downloads` spawns a fresh process per package; slower but may be required on firewalls that close idle HTTP connections. |
| – | `--warn-checksums` / `--no-warn-checksums` | – | Control whether the installer requires a checksum implementation to be present. Default: `--warn-checksums` (enabled). When enabled, the installer checks for `Digest::SHA`, `openssl`, or `sha512sum`; if none is found, it aborts with an error. Use `--no-warn-checksums` to skip this check and proceed without checksum verification. Independent of GPG signature verification (`--verify-downloads`). |
| – | – | `TEXLIVE_DOWNLOADER` | Force a specific download program. Values: `wget` or `curl`. Default: auto-detected. Takes precedence over `TL_DOWNLOAD_PROGRAM`. |
| – | – | `TL_DOWNLOAD_PROGRAM` | Path or name of the download program. Overridden by `TEXLIVE_DOWNLOADER`. |
| – | – | `TL_DOWNLOAD_ARGS` | Additional arguments appended to every download program invocation. |
| – | – | `TEXLIVE_PREFER_OWN` | Prefer the Perl, `wget`, and `xz` bundled with the installer over system-installed copies. Set to `1` to enable. Useful when the system Perl is too old or missing required modules. |

---

##### 10. Behavior Toggles (Environment-Variable-Only)

These options have no profile key or CLI flag and can only be set as environment variables.

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| – | – | `TEXLIVE_INSTALL_ENV_NOCHECK` | Skip the check that warns when environment variable names contain the string "tex", which the installer uses to detect potentially conflicting TeX-related settings. Set to any non-empty value to suppress that specific check. Does not suppress all sanity checks. |
| – | – | `TEXLIVE_INSTALL_NO_DISKCHECK` | Skip the free-disk-space check before installation. Set to any non-empty value. Useful in container builds where the check may fail due to overlay filesystems or quota limitations. |
| – | – | `TEXLIVE_INSTALL_NO_RESUME` | Disable resume of an interrupted installation; force a clean start. Set to any non-empty value. |
| – | – | `TEXLIVE_INSTALL_NO_WELCOME` | Suppress the post-installation welcome/summary message. Set to any non-empty value. |
| – | – | `TEXLIVE_INSTALL_NO_CONTEXT_CACHE` | Skip generation of the ConTeXt file database and LuaTeX cache. Set to any non-empty value. Speeds up container builds when ConTeXt is not used. |
| – | – | `NOPERLDOC` | Suppress Perl-formatted documentation rendering in `--help` output; fall back to plain text. Set to any non-empty value. |
| – | – | `WISH` | Path or name of the `wish` Tcl/Tk interpreter for the `tcl` GUI frontend. Default: `wish` resolved via PATH. |

---

##### 11. Advanced and Rarely Used

| Profile | CLI | Env Var | Description |
|---------|-----|---------|-------------|
| – | `--custom-bin PATH` | – | Install using custom-built binaries from `PATH` instead of the platform binaries from the repository. Binaries are copied to `TEXDIR/bin/custom`; that exact path must be added to `PATH` manually. Incompatible with `--in-place`. Ongoing updates require `wget`, `xz`, and `xzdec` in `PATH`; platform-script symlinks in `bin/custom` must be maintained manually. |
| – | `--force-platform PLATFORM` / `--force-arch PLATFORM` | – | Override platform autodetection and treat the system as `PLATFORM` (e.g. `x86_64-linux`). Useful on unusual or cross-compile environments. |
| – | – | `TEXMFCNF` | Override the search path for `texmf.cnf` configuration files at runtime. Not an install-tl option per se; setting it before running the installer can influence post-install initialization steps that invoke `kpsewhich`. |

---

##### 12. Legacy Profile Key Aliases

The installer's `read_profile()` automatically translates the following legacy profile keys to their modern equivalents. Old keys remain functional but emit a deprecation warning. Use the modern keys in new profiles.

| Legacy Key | Modern Equivalent |
|------------|-------------------|
| `option_path` | `instopt_adjustpath` |
| `option_adjustpath` | `instopt_adjustpath` |
| `option_symlinks` | `instopt_adjustpath` |
| `option_letter` | `instopt_letter` |
| `option_write18_restricted` | `instopt_write18_restricted` |
| `option_adjustrepo` | `instopt_adjustrepo` |
| `option_portable` | `instopt_portable` |
| `option_sys_bin` | `tlpdbopt_sys_bin` |
| `option_sys_man` | `tlpdbopt_sys_man` |
| `option_sys_info` | `tlpdbopt_sys_info` |
| `option_install_docfiles` | `tlpdbopt_install_docfiles` |
| `option_install_srcfiles` | `tlpdbopt_install_srcfiles` |
| `option_create_formats` | `tlpdbopt_create_formats` |
| `option_generate_updmap` | `tlpdbopt_generate_updmap` |
| `option_post_code` | `tlpdbopt_post_code` |
| `option_autobackup` | `tlpdbopt_autobackup` |
| `option_backupdir` | `tlpdbopt_backupdir` |
| `option_desktop_integration` | `tlpdbopt_desktop_integration` |
| `option_file_assocs` | `tlpdbopt_file_assocs` |
| `option_w32_multi_user` | `tlpdbopt_w32_multi_user` |
| `location` | `tlpdbopt_location` |

---


#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Add the platform binary directory to `PATH`, e.g.:

```bash
export PATH=/usr/local/texlive/2026/bin/x86_64-linux:$PATH
```

  - Installer profile option `instopt_adjustpath` controls installer-side PATH adjustment behavior (default off on Unix, on for Windows).
  - Alternative Unix symlink mode is available via `tlmgr option sys_bin|sys_man|sys_info` plus `tlmgr path add`; rerun `tlmgr path` when future updates add/remove linked executables.

- **Configuration Files**:
  - Installer writes installation profile (`tlpkg/texlive.profile` for normal installs; `TEXDIR/texlive.profile` for `--in-place`) and system config overlays (`texmf.cnf`, `texmfcnf.lua`) in the install tree.
  - Post-install generation refreshes key TeX config artifacts (`fmtutil.cnf`, `updmap.cfg`, `language.dat`, `language.def`, `language.dat.lua`) based on installed package metadata.
  - Legacy single-file overlays (`fmtutil-local.cnf`, `updmap-local.cfg`) are obsolete; local additions should be placed in layered files such as `TEXMFLOCAL/web2c/fmtutil.cnf`, `TEXMFLOCAL/web2c/updmap.cfg`, and `language-local.*` files under TEXMFLOCAL.
- **Environment Variables**:
  - Installer automation controls include:
    - Directory overrides: `TEXLIVE_INSTALL_PREFIX` and `TEXLIVE_INSTALL_TEXMF*` variables.
    - Behavior toggles: `TEXLIVE_INSTALL_PAPER`, `TEXLIVE_INSTALL_ENV_NOCHECK`, and `TEXLIVE_INSTALL_NO_*` controls such as disk-check, resume-check, context-cache, and welcome-message toggles.
    - Downloader/tool selection: `TEXLIVE_DOWNLOADER`, `TL_DOWNLOAD_PROGRAM`, `TL_DOWNLOAD_ARGS`, `TEXLIVE_PREFER_OWN`.
    - Help-output control: `NOPERLDOC`.
- **Activation Scripts**:
  - None required beyond shell PATH initialization for chosen install prefix.
- **Cleanup**:
  - Remove installer tarball/work directory after success.
  - In containers, clean package-manager caches/lists after dependency installation to reduce layer size.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Same-release updates via:

```bash
tlmgr update --self --all
```

  - Year-to-year upgrades are typically side-by-side installs in a new `YYYY` tree, then PATH/default switching.
- **Uninstallation**:
  - Remove target install tree and associated user tree if desired.
  - For interrupted/retry scenarios, upstream quick-install docs explicitly show removing incomplete trees before reattempting.
- **Idempotency**:
  - Re-running installer with same settings is generally repeatable; installer supports profile-based non-interactive flows and has logic for aborted-install resume behavior.
  - If a copied `install-tl` script inside an existing tree starts failing due infrastructure drift, rerun from a fresh installer archive (`install-tl-unx.tar.gz`) instead of the in-tree copy.

#### Notes and Best Practices

- Prefer explicit `--repository` in CI/reproducible environments when mirror auto-selection causes instability.
- Keep `tlmgr`-managed installs separate from distro package-manager TeX installs to avoid ownership conflicts.
- For editor workflows like LaTeX Workshop, ensure `latexmk` is present.
- Container implementations in established projects commonly install additional runtime helpers (fontconfig/perl modules/ghostscript/etc.) and perform aggressive package-cache cleanup.

### Native macOS Installers (MacTeX / BasicTeX)

#### Supported Platforms

- MacTeX-2026 and BasicTeX-2026: macOS 11 (Big Sur) and newer, Intel and Apple Silicon.
- Older macOS versions can use the Unix `install-tl` path instead of MacTeX package installers (documented down to macOS Snow Leopard 10.6).
- Legacy certificate behavior is version-sensitive: El Capitan (10.11) and earlier may require a workaround, Sierra (10.12) is unaffected, High Sierra/Mojave use installer-side workarounds, Catalina is fixed in 10.15.5+, and Big Sur+ is unaffected.

#### Dependencies

- **Common Dependencies**: macOS package installer support (`.pkg`) and downloaded installer package.
- **Platform-Specific Dependencies**:
  - Administrator privileges for default system-wide installation.
  - Full MacTeX installs GUI helper tools (including TeX Live Utility), while BasicTeX installs only the TeX Live distribution components.

#### Installation Steps

MacTeX full install:

1. Download `MacTeX.pkg` from the MacTeX download page.
2. Run installer package and follow install wizard.
3. Use default component set unless you intentionally customize (for example Ghostscript component selection).

BasicTeX install:

1. Download `BasicTeX.pkg`.
2. Install; resulting tree is `/usr/local/texlive/2026basic`.
3. Add missing packages later with `tlmgr` as needed; BasicTeX intentionally omits the GUI application bundle and Ghostscript components included with full MacTeX.

#### Installation Verification

```bash
/Library/TeX/texbin/latex --version
/Library/TeX/texbin/tlmgr --version
```

Recommended smoke test:

```bash
/Library/TeX/texbin/latex small2e
```

Also verify TeX distribution root when needed:

```bash
/Library/TeX/texbin/kpsewhich -var-value=TEXMFROOT
```

#### Configuration Options

- **Version Selection**:
  - Chosen by installer artifact year (MacTeX-YYYY / BasicTeX-YYYY).
  - Older MacTeX versions are published separately for older macOS compatibility windows.
- **Installation Path**:
  - MacTeX default: `/usr/local/texlive/2026`.
  - BasicTeX default: `/usr/local/texlive/2026basic`.
  - `/Library/TeX/texbin` symlink is used as stable frontend path.
- **User Targeting**:
  - Standard package flow is system-wide and shared.
- **Required Privileges**:
  - Administrator privileges required for default package installation path.
- **Tool-Specific Configurations**:
  - MacTeX installer supports component customization.
  - TeX Live Utility supports ongoing updates and switching default active TeX distribution when multiple yearly trees coexist.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Use `/Library/TeX/texbin` in PATH (MacTeX-managed stable indirection); do not edit the link directly.
  - TeX Live Utility switching keeps this stable path while updating active distribution wiring, including command-line path behavior and GUI app discovery.
  - For macOS Unix-script installation workflows (outside `MacTeX.pkg`), `TeXDist-YYYY.pkg` (or documented postinstall helper scripts) create/refresh the internal `/Library/TeX/texdist` support structure; GUI/shell discovery still uses `/Library/TeX/texbin`.
- **Configuration Files**:
  - None required for baseline package-installer workflows.
- **Environment Variables**:
  - None required for baseline usage.
- **Activation Scripts**:
  - None required beyond shell profile PATH setup.
- **Cleanup**:
  - Remove downloaded `.pkg` artifacts if not needed.
  - Run TeX Live Utility updates after install to bring package state current.
  - For MacTeX-2026 users affected by the notarization-driven package refresh, use TeX Live Utility to reinstall forcibly removed ConTeXt packages after updates.
  - If the Apple installer hangs at `Verifying...` or aborts due the 600-second postinstall timeout, follow the official recovery flow (reboot/retry, then run documented postinstall commands or the provided `postinstall2026.sh` helper).

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Install another yearly package; versions can coexist in `/usr/local/texlive`.
  - Switch active default distribution using TeX Live Utility (`Configure -> Change Default TeX Live Version`); `/Library/TeX/texbin` remains the stable path used by GUI and shell workflows.
- **Uninstallation**:
  - Remove the specific TeX Live year directory under `/usr/local/texlive` (administrator credentials required).
  - Remove GUI apps from `/Applications/TeX` if desired.
  - Remove `/Library/TeX` only with care, because other TeX distributions can also place files there.
  - If full MacTeX Ghostscript components were installed, cleanup is typically under `/usr/local/bin` and `/usr/local/share`; in many cases installing a newer Ghostscript is simpler than manually removing old files.
- **Idempotency**:
  - Re-running same installer is generally safe and converges on packaged state.
  - Installing new yearly packages is additive (side-by-side), not destructive to prior yearly trees.

#### Notes and Best Practices

- MacTeX is the easiest native path for full-feature macOS setups.
- BasicTeX is intentionally small and often requires follow-up package installs via `tlmgr` for broader document compatibility.
- In the 2026 cycle, MacTeX package contents changed to satisfy Apple notarization requirements: LuaMetaTeX and dependent ConTeXt files were removed from the installer package and must be restored via TeX Live Utility "Reinstall Selected Packages" if needed.
- macOS-specific release notes can include post-release package content adjustments; running TeX Live Utility after installation is important.

### Distro-Provided TeX Live Packages (System Package Managers)

#### Supported Platforms

- Linux distributions that package TeX Live (for example Debian/Ubuntu, Fedora, Arch, openSUSE, Alpine, and others).
- macOS package-manager ecosystems (for example MacPorts) also package TeX-related distributions/tooling.

#### Dependencies

- **Common Dependencies**: Functional distro package manager and configured repositories.
- **Platform-Specific Dependencies**:
  - Root/sudo for system package installs in most Linux distros.
  - Distro-specific package split/grouping knowledge (package names differ significantly).

#### Installation Steps

1. Use your distro's TeX Live packaging documentation.
2. Install the desired TeX package set (minimal/base/full depending on distro conventions).
3. Verify `latex` and related binaries are present.

Example from Alpine package ecosystem (where available):

```bash
sudo apk add texlive-full
```

#### Installation Verification

```bash
latex --version
kpsewhich --version
```

Check package-manager metadata for installed package set as needed.

#### Configuration Options

- **Version Selection**:
  - Controlled by distro repository versions and package policy.
  - Exact upstream-year parity is not guaranteed.
- **Installation Path**:
  - Distro-managed filesystem layout.
- **User Targeting**:
  - Typically system-wide installs.
- **Required Privileges**:
  - Usually root/sudo for package operations.
- **Tool-Specific Configurations**:
  - In distro-packaged setups, TeX package lifecycle is normally managed by distro package manager rather than native `tlmgr` updates.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Usually automatic from distro package install.
- **Configuration Files**:
  - Distro-specific conventions; managed through package scripts and system config tooling.
- **Environment Variables**:
  - Usually none for baseline operation.
- **Activation Scripts**:
  - None in most distro defaults.
- **Cleanup**:
  - Follow distro package-manager cleanup policy.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Managed via distro package updates and repository pinning/version mechanisms.
- **Uninstallation**:
  - Managed via distro package-manager remove commands.
- **Idempotency**:
  - Standard package-manager idempotency applies for repeated installs of already-installed package sets.

#### Notes and Best Practices

- Do not mix distro package ownership with native `tlmgr` package updates unless you intentionally accept divergence risk.
- Distro packaging is best when system governance/security policies require all software lifecycle to stay in package-manager control.

## References

- [TeX Live Home](https://www.tug.org/texlive/) - Official upstream overview and release status, including current release and release date.
- [TeX Live Acquire](https://www.tug.org/texlive/acquire.html) - Official acquisition/install channel matrix and lifecycle notes.
- [TeX Live Network Install](https://www.tug.org/texlive/acquire-netinstall.html) - Upstream internet install flow, mirror guidance, and recommendation to install Perl LWP for faster downloads.
- [TeX Live Quick Install](https://www.tug.org/texlive/quickinstall.html) - Canonical quick install commands, PATH guidance, and post-install basics.
- [install-tl Manual](https://www.tug.org/texlive/doc/install-tl.html) - Full installer option semantics, profile format, defaults, and environment controls.
- [TeX Live Custom Binaries](https://www.tug.org/texlive/custom-bin.html) - Official operational details for `--custom-bin`, PATH expectations, and update-time maintenance caveats.
- [tlmgr Manual](https://www.tug.org/texlive/doc/tlmgr.html) - Package lifecycle commands (`install`, `update`, `remove`, `option`, `path`, repository, verification, user mode).
- [TeX Live and Distros](https://www.tug.org/texlive/distro.html) - Upstream guidance for distro-packaged TeX Live and package-manager ownership boundaries.
- [TeX Live Installer Repository](https://github.com/TeX-Live/installer) - Upstream mirror containing installer source and release metadata files.
- [install-tl Source](https://raw.githubusercontent.com/TeX-Live/installer/master/install-tl) - Authoritative installer behavior (supported options, profile handling, path actions, post-install flow).
- [TLConfig Source](https://raw.githubusercontent.com/TeX-Live/installer/master/tlpkg/TeXLive/TLConfig.pm) - Authoritative defaults/options (`%TLPDBOptions`, release year, repository defaults, critical packages).
- [MacTeX Main Page](https://www.tug.org/mactex/) - Official MacTeX/BasicTeX positioning, compatibility, and workflow guidance.
- [MacTeX Download](https://www.tug.org/mactex/mactex-download.html) - Current MacTeX package artifact details, install path behavior, and post-install notes.
- [MacTeX More Packages / BasicTeX](https://www.tug.org/mactex/morepackages.html) - BasicTeX package details and scope relative to full MacTeX.
- [MacTeX Multiple Distributions](https://www.tug.org/mactex/multipletexdistributions.html) - Authoritative behavior for switching active TeX distribution and `/Library/TeX/texbin` indirection.
- [MacTeX Uninstalling](https://www.tug.org/mactex/uninstalling.html) - Official uninstallation guidance for TeX trees, GUI applications, and distribution support directories.
- [MacTeX Unix Install Page](https://www.tug.org/mactex/mactex-unix-download.html) - macOS Unix-script installation specifics and legacy-system notes.
- [MacTeX Expired Certificate Notes](https://www.tug.org/mactex/expiredcertificate.html) - Legacy macOS certificate-chain issue details and workaround guidance for affected versions.
- [Alpine texlive-full Package](https://pkgs.alpinelinux.org/package/edge/community/x86_64/texlive-full) - Concrete distro package example for full TeX distribution.
- [prulloac Devcontainer LaTeX Feature README](https://raw.githubusercontent.com/prulloac/devcontainer-features/main/src/latex/README.md) - Similar-feature option design (`scheme`, `packages`, `mirror`) and operational notes.
- [prulloac Devcontainer LaTeX Installer Script](https://raw.githubusercontent.com/prulloac/devcontainer-features/main/src/latex/install.sh) - Similar-feature implementation pattern (`install-tl`, `tlmgr`, symlinking, cleanup).
- [prulloac Devcontainer LaTeX Additional Package Test](https://raw.githubusercontent.com/prulloac/devcontainer-features/main/test/latex/additional_packages.sh) - Practical validation patterns for latex/tlmgr/package checks.
- [Island of TeX Base Dockerfile](https://gitlab.com/islandoftex/images/texlive/-/raw/master/Dockerfile.base) - Production container dependency and cleanup patterns for TeX Live ecosystems.
- [Sphinx latexpdf Dockerfile](https://raw.githubusercontent.com/sphinx-doc/sphinx-docker-images/master/latexpdf/Dockerfile) - Real-world distro-package composition for LaTeX build containers.
