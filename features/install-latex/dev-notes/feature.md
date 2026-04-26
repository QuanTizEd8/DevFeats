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

When cryptographic verification is active, installer/tlmgr output indicates repository verification status (`(verified)` vs `(not verified)`).

#### Configuration Options

- **Version Selection**:
  - TeX Live major release tracks yearly releases (for example 2026).
  - Repository selection controls source/version stream (`--repository`), including historic yearly snapshots when needed.
- **Installation Path**:
  - Default system tree is under `/usr/local/texlive/YYYY`.
  - User tree defaults are platform-dependent:
    - `TEXMFHOME`: `~/texmf` on Unix, `~/Library/texmf` on macOS.
    - `TEXMFCONFIG`/`TEXMFVAR`: `~/.texliveYYYY/texmf-{config,var}` on Unix, `~/texliveYYYY/texmf-{config,var}` on macOS.
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
  - Verification and download behavior from installer/tooling (verification is enabled by default when `gpg` is available and can be disabled with `--no-verify-downloads`; persistent-download controls are also available).

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Add the platform binary directory to `PATH`, e.g.:

```bash
export PATH=/usr/local/texlive/2026/bin/x86_64-linux:$PATH
```

- **Configuration Files**:
  - Installer writes installation profile (`tlpkg/texlive.profile`) and system config overlays (`texmf.cnf`, `texmfcnf.lua`) in the install tree.
- **Environment Variables**:
  - Installer honors several environment variables (`TEXLIVE_INSTALL_*`, `TEXLIVE_INSTALL_PAPER`, and others) for automation/scripting.
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

#### Notes and Best Practices

- Prefer explicit `--repository` in CI/reproducible environments when mirror auto-selection causes instability.
- Keep `tlmgr`-managed installs separate from distro package-manager TeX installs to avoid ownership conflicts.
- For editor workflows like LaTeX Workshop, ensure `latexmk` is present.
- Container implementations in established projects commonly install additional runtime helpers (fontconfig/perl modules/ghostscript/etc.) and perform aggressive package-cache cleanup.

### Native macOS Installers (MacTeX / BasicTeX)

#### Supported Platforms

- MacTeX-2026 and BasicTeX-2026: macOS 11 (Big Sur) and newer, Intel and Apple Silicon.
- Older macOS versions can use the Unix `install-tl` path instead of MacTeX package installers.

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
  - Use `/Library/TeX/texbin` in PATH (MacTeX-managed stable indirection).
- **Configuration Files**:
  - Native MacTeX installs expose a stable `/Library/TeX/texbin` path for GUI and shell discovery.
  - For macOS Unix-script installation workflows (outside `MacTeX.pkg`), `TeXDist-YYYY.pkg` is used to install `/Library/TeX/texdist` switching support.
- **Environment Variables**:
  - None required for baseline usage.
- **Activation Scripts**:
  - None required beyond shell profile PATH setup.
- **Cleanup**:
  - Remove downloaded `.pkg` artifacts if not needed.
  - Run TeX Live Utility updates after install to bring package state current.
  - For MacTeX-2026 users affected by the notarization-driven package refresh, use TeX Live Utility to reinstall forcibly removed ConTeXt packages after updates.

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
- [Alpine texlive-full Package](https://pkgs.alpinelinux.org/package/edge/community/x86_64/texlive-full) - Concrete distro package example for full TeX distribution.
- [prulloac Devcontainer LaTeX Feature README](https://raw.githubusercontent.com/prulloac/devcontainer-features/main/src/latex/README.md) - Similar-feature option design (`scheme`, `packages`, `mirror`) and operational notes.
- [prulloac Devcontainer LaTeX Installer Script](https://raw.githubusercontent.com/prulloac/devcontainer-features/main/src/latex/install.sh) - Similar-feature implementation pattern (`install-tl`, `tlmgr`, symlinking, cleanup).
- [prulloac Devcontainer LaTeX Additional Package Test](https://raw.githubusercontent.com/prulloac/devcontainer-features/main/test/latex/additional_packages.sh) - Practical validation patterns for latex/tlmgr/package checks.
- [Island of TeX Base Dockerfile](https://gitlab.com/islandoftex/images/texlive/-/raw/master/Dockerfile.base) - Production container dependency and cleanup patterns for TeX Live ecosystems.
- [Sphinx latexpdf Dockerfile](https://raw.githubusercontent.com/sphinx-doc/sphinx-docker-images/master/latexpdf/Dockerfile) - Real-world distro-package composition for LaTeX build containers.