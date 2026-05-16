# Feature Reference

Pandoc is a universal document converter: a command-line tool and Haskell library for converting between many markup and document formats. It is commonly used in documentation pipelines, publishing toolchains, CI/CD conversion jobs, and static-site/book workflows. Upstream supports many installation routes (OS package managers, official release artifacts, conda-forge, Docker images, and source builds).

For DevFeats implementation planning on macOS and Linux, the primary practical methods are:

1. Official release artifacts from the pandoc GitHub Releases page (best for deterministic pinning).
2. OS package manager installation (best for distro-native lifecycle management).
3. Conda-forge installation (best when pandoc should be scoped to Python/Conda environments).
4. Source build (best for advanced customization or unsupported binary/package scenarios).

- **Homepage**: https://pandoc.org/
- **Source Code**: https://github.com/jgm/pandoc
- **Documentation**: https://pandoc.org/installing.html and https://pandoc.org/MANUAL.html
- **Latest Release**: 3.9.0.2 (as of 2026-04-26)

## Available Installation Methods

Upstream installation docs explicitly describe installers/binaries, package-manager installs, conda-forge, Docker images, and source builds. For DevFeats feature implementation, Docker is usually a runtime execution method rather than host provisioning, but it is included below for completeness because upstream treats it as a first-class usage/install path.

Upstream also documents Chrome OS and BSD package-manager routes. Those paths are intentionally out of scope for this DevFeats feature reference, which targets macOS and Linux host/container setup paths.

### Official Release Artifacts (GitHub Releases)

#### Supported Platforms

- Linux via `.deb` packages and `.tar.gz` archives.
- macOS via `.pkg` installer packages and `.zip` archives.
- Windows via `.msi` installer and `.zip` archives (officially available upstream, though DevFeats feature scope is macOS/Linux).

For macOS/Linux-relevant current latest release assets include:

- `pandoc-<ver>-1-amd64.deb`
- `pandoc-<ver>-1-arm64.deb`
- `pandoc-<ver>-linux-amd64.tar.gz`
- `pandoc-<ver>-linux-arm64.tar.gz`
- `pandoc-<ver>-x86_64-macOS.pkg`
- `pandoc-<ver>-arm64-macOS.pkg`
- `pandoc-<ver>-x86_64-macOS.zip`
- `pandoc-<ver>-arm64-macOS.zip`

The full release also includes additional assets such as Windows installers/archives and `pandoc.wasm.zip`.

#### Dependencies

- **Common Dependencies**: Download tool (`curl`/`wget`) and checksum tooling (`sha256sum`/`shasum`) for integrity checks.
- **Platform-Specific Dependencies**:
  - Linux `.deb`: `dpkg`, sufficient privileges for system-wide install, runtime dependencies declared by upstream package metadata (`libc6 (>= 2.13)`, `libgmp10`, `zlib1g (>= 1:1.1.4)`), and upstream-suggested TeX packages for PDF workflows (`texlive-latex-recommended`, `texlive-xetex`, `texlive-fonts-recommended`).
  - Linux tarball: `tar` and a writable destination path (for example `/usr/local` with sudo or `$HOME/.local` without sudo).
  - macOS `.pkg`: macOS installer subsystem and elevated privileges for system-wide install.
  - macOS `.zip`: `unzip` and writable destination path(s) for binaries/man pages.

#### Installation Steps

1. Resolve target release version and architecture.
2. Download the matching official release asset.
3. Install using package format semantics.

Official Linux `.deb` install command from upstream docs:

```bash
sudo dpkg -i "$DEB"
```

Upstream also notes that RPM-family users may be able to install the official `.deb` via `alien`.

Official Linux tarball install command from upstream docs:

```bash
tar xvzf "$TGZ" --strip-components 1 -C "$DEST"
```

Where `$DEST` is commonly `/usr/local/` (system-wide) or `$HOME/.local` (user-local).

Official macOS `.zip` flow from upstream docs: unzip the archive, then move the binaries and man pages into desired install locations (for example a system prefix or user-local prefix).

Upstream packaging scripts show a platform difference in installed entrypoints: Linux release artifacts include `pandoc-server` and `pandoc-lua` symlinked binaries in addition to `pandoc`, while macOS release packaging installs `pandoc` plus man pages without creating those extra symlink entrypoints.

On macOS, upstream provides `.pkg` installers and `.zip` archives; `.pkg` installation is provided via the package installer on the download page.

#### Installation Verification

- Confirm executable availability and version:

```bash
command -v pandoc
pandoc --version
```

- Validate downloaded asset integrity using the release API `digest` field before installation (for example by comparing local SHA-256 against the API-provided `sha256:<hex>` value).

#### Configuration Options

- **Version Selection**:
  - Controlled by release tag and chosen asset URL.
  - Similar ecosystem features commonly support `latest` plus partial-version matching by querying git tags (for example `2.17` resolving to latest `2.17.x.y`).
- **Installation Path**:
  - Linux `.deb` installs into package-managed system paths.
  - Linux tarball install path is user-selected through `$DEST`.
  - macOS official package build scripts target `/usr/local` layout (`/usr/local/bin`, `/usr/local/share/man/man1`).
- **User Targeting**:
  - Supports both system-wide (package installs) and user-local (tarball into user prefix).
- **Required Privileges**:
  - Required for system-owned install prefixes.
  - Not required for user-local tarball extraction.
- **Tool-Specific Configurations**:
  - Upstream notes a key limitation for statically linked binaries (official binary builds and conda-forge): Lua filters that depend on Lua modules written in C are not usable.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Usually automatic for package installs.
  - For user-local tarball installs, ensure `$DEST/bin` is on `PATH`.
- **Configuration Files**:
  - None required for baseline pandoc usage.
- **Environment Variables**:
  - None required for default operation.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Remove temporary download/install artifacts after successful verification and install.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Reinstall with a different release asset version/tag.
  - Package-manager-level replacements are supported by installer/package semantics.
- **Uninstallation**:
  - macOS upstream provides an uninstall script (`perl uninstall-pandoc.pl`) that enumerates package-installed files via `pkgutil`, deletes them, and forgets package metadata.
  - Linux tarball installs require manual removal of extracted files from the chosen prefix.
  - Linux `.deb` installs can be removed using distro package management/removal commands.
- **Idempotency**:
  - Re-running install with the same version is generally replacement-safe; package systems and explicit file replacement semantics handle repeated runs predictably.
  - Upstream warns that mixing installation methods can leave separate pandoc installations side by side; uninstall the current method before switching to another install method.

#### Notes and Best Practices

- Favor this method for strict version pinning and cross-distro consistency.
- Use API-provided release digests (and/or additional signature workflows where available) before installation.
- Tarball install into user-local prefix is a practical non-root path for containers and multi-user systems.
- In official pandoc release engineering scripts, Linux tarball artifacts are validated as statically linked and include `pandoc`, `pandoc-server`, and `pandoc-lua` symlinked binaries plus manpages.

### OS Package Manager

#### Supported Platforms

Upstream explicitly documents package-manager availability in:

- Debian
- Ubuntu
- Slackware
- Arch
- Fedora
- NixOS
- openSUSE
- Gentoo
- Void
- macOS via Homebrew
- macOS via MacPorts

#### Dependencies

- **Common Dependencies**: Working platform package manager and configured repositories.
- **Platform-Specific Dependencies**:
  - Linux system package managers typically require root privileges.
  - Homebrew and MacPorts require prior installation/configuration of those tools.
  - On unsupported macOS versions (more than three releases old), Homebrew may build pandoc from source, which significantly increases installation time and temporary build dependency footprint.

#### Installation Steps

Representative upstream-documented commands:

```bash
# macOS Homebrew
brew install pandoc

# macOS MacPorts
port install pandoc
```

On Linux, upstream points to distro repositories and recommends checking whether the packaged version is sufficiently current.

#### Installation Verification

- Validate executable and version:

```bash
pandoc --version
```

- Optionally inspect package-manager metadata for installed version/source.

#### Configuration Options

- **Version Selection**:
  - Managed by package manager/repository availability; exact pinning support varies by platform.
- **Installation Path**:
  - Package-manager controlled.
- **User Targeting**:
  - Linux distro package-manager installs and MacPorts installs are typically system-wide.
  - Homebrew installs into its managed prefix and is generally user-managed.
- **Required Privileges**:
  - Usually required on Linux for install/remove/upgrade.
- **Tool-Specific Configurations**:
  - None during installation itself; PDF output tooling is configured separately via additional packages and runtime flags.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Usually automatic for Linux distro package-manager installs.
  - Homebrew may require shell profile initialization (`brew shellenv`) if Homebrew paths are not yet configured.
  - MacPorts environments may require shell-profile updates depending on local shell setup.
- **Configuration Files**:
  - None required.
- **Environment Variables**:
  - None required.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Optional package-cache cleanup by platform policy.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Use package-manager-native upgrade/downgrade flows.
- **Uninstallation**:
  - Use package-manager-native removal commands.
- **Idempotency**:
  - Package managers provide standard idempotent install behavior for already-installed packages.

#### Notes and Best Practices

- This method integrates best with host lifecycle and security update workflows.
- Repository versions may lag upstream releases; if exact version pinning is mandatory, prefer official release artifacts.
- Pandoc uses LaTeX for PDF generation by default.
- Linux guidance from upstream is to install TeX Live via package manager (for example `apt-get install texlive` on Debian/Ubuntu).
- macOS guidance from upstream is to prefer BasicTeX or TinyTeX; if font-related errors occur, install additional fonts with `tlmgr install collection-fontsrecommended`.

### Conda Forge

#### Supported Platforms

- Any platform supported by conda-forge and the chosen tool (`conda`, `micromamba`, or `pixi`).

#### Dependencies

- **Common Dependencies**: Installed conda-compatible package manager and an initialized environment/context.
- **Platform-Specific Dependencies**: None beyond tool-specific setup.

#### Installation Steps

Upstream-documented examples:

```bash
conda install -c conda-forge pandoc
pixi global install pandoc
micromamba install pandoc
```

#### Installation Verification

```bash
pandoc --version
```

If installed into a named environment, verify after activating that environment.

#### Configuration Options

- **Version Selection**:
  - Use conda-compatible version constraints according to conda-forge package availability.
- **Installation Path**:
  - Managed by environment prefix.
- **User Targeting**:
  - Environment-scoped (user-local or shared depending environment location/permissions).
- **Required Privileges**:
  - Usually not required for user-local environments.
- **Tool-Specific Configurations**:
  - Upstream documents that conda-forge installs a statically linked executable with the same Lua C-module limitation as official static binaries.
  - Upstream also notes companion ecosystem packages are available on conda-forge (for example `pandoc-citeproc`, `pandoc-plot`, and `rsvg-convert` via `librsvg`).

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure target environment is activated when invoking pandoc.
- **Configuration Files**:
  - None required for baseline pandoc operation.
- **Environment Variables**:
  - None required by pandoc itself.
- **Activation Scripts**:
  - Standard conda/mamba/pixi environment activation only.
- **Cleanup**:
  - Optional package-cache cleanup via conda tool commands.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Use conda-compatible update/install version pin commands.
- **Uninstallation**:
  - Remove package from environment via conda-compatible remove command.
- **Idempotency**:
  - Environment package managers are idempotent for repeated installs of the same resolved version.

#### Notes and Best Practices

- Strong option when pandoc should remain isolated within project environments.
- For workflows requiring Lua filters with C-based Lua modules, avoid static-build methods (including conda-forge builds).

### Docker Images

#### Supported Platforms

- Any platform with a working Docker runtime that can pull and run official `pandoc/*` images.
- Upstream image variants include `pandoc/minimal`, `pandoc/core`, `pandoc/latex`, and `pandoc/extra`.
- Upstream documentation states all images are available on Alpine stack, and `minimal`, `latex`, and `extra` are also available with an Ubuntu stack.

#### Dependencies

- **Common Dependencies**: Docker Engine/CLI and network access to pull image tags.
- **Platform-Specific Dependencies**:
  - Permission to run Docker commands (root or Docker-group equivalent).
  - Host bind-mount support for source/output files.

#### Installation Steps

This method installs/uses pandoc through container images rather than placing a host binary in system paths.

1. Pull or run an official pandoc image.
2. Bind-mount your working directory into `/data`.
3. Run pandoc command arguments via the image entrypoint.

Upstream example:

```bash
docker run --rm --volume "`pwd`:/data" --user `id -u`:`id -g` pandoc/latex README.md -o README.pdf
```

#### Installation Verification

- Verify image-based pandoc execution:

```bash
docker run --rm pandoc/core --version
```

- Verify a conversion succeeds with mounted test input.

#### Configuration Options

- **Version Selection**:
  - Select explicit image tags (for example `pandoc/latex:3.9.0.2`) for reproducibility.
  - Upstream recommends hardcoding version tags rather than floating tags for stable pipelines.
- **Installation Path**:
  - Not a host install path; pandoc binary lives inside the container image.
- **User Targeting**:
  - Runtime user identity can be set via `--user UID:GID` to control host output file ownership.
- **Required Privileges**:
  - Docker runtime privileges are required.
- **Tool-Specific Configurations**:
  - Choose image variant by required capabilities (`minimal` vs `core` vs `latex` vs `extra`).

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Not applicable on host; invoke through `docker run`.
- **Configuration Files**:
  - None required for baseline container usage.
- **Environment Variables**:
  - Upstream image docs note `XDG_DATA_HOME` is set to `/usr/local/share` in images; extensions are typically placed under `/usr/local/share/pandoc` when building custom images.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Remove unused images/layers according to Docker cleanup policy.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Pull/use a different image tag.
- **Uninstallation**:
  - Remove local image tags/layers with Docker image removal commands.
- **Idempotency**:
  - Re-running with the same image tag is idempotent for tool provisioning; repeated pulls refresh local cache state as needed.

#### Notes and Best Practices

- Containerized pandoc is ideal for CI/CD and hermetic conversion workflows.
- Pin exact image tags to avoid unplanned behavior changes.
- Prefer `--user` to avoid root-owned output files on host bind mounts.

### Compiling From Source

#### Supported Platforms

- Platforms where required Haskell toolchains and build dependencies are available.
- Upstream positions source build for non-binary-supported platforms, development usage, or custom builds.

#### Dependencies

- **Common Dependencies**: Haskell toolchain via `stack` or `ghcup` + `cabal`, plus build dependencies resolved by those tools.
- **Platform-Specific Dependencies**:
  - `stack >= 1.7.0` for the stack path.
  - `cabal >= 2.0` for custom cabal method.

#### Installation Steps

Upstream quick stack method:

```bash
stack setup
stack install pandoc-cli
```

Upstream quick cabal method:

```bash
# Install ghcup first (provides ghc and cabal)
# https://www.haskell.org/ghcup/install/

cabal update
cabal install pandoc-cli
```

Upstream custom cabal method (maximal control, useful for packagers):

```bash
cabal update
cabal build --only-dependencies

cabal configure --prefix=DIR --bindir=DIR --libdir=DIR \
  --datadir=DIR --libsubdir=DIR --datasubdir=DIR --docdir=DIR \
  --htmldir=DIR --program-prefix=PREFIX --program-suffix=SUFFIX \
  --mandir=DIR --flags=FLAGSPEC --enable-tests

cabal build
cabal test
cabal haddock --html-location=URL --hyperlink-source
cabal install pandoc-cli
```

Upstream source acquisition options:

```bash
# Source tarball from Hackage
wget https://hackage.haskell.org/package/pandoc-<version>/pandoc-<version>.tar.gz
tar xvzf pandoc-<version>.tar.gz
cd pandoc-<version>

# Or development source
git clone https://github.com/jgm/pandoc
cd pandoc
```

Upstream cautions that development source may sometimes be broken or require additional libraries; unless development snapshots are specifically required, released versions are recommended.

#### Installation Verification

```bash
pandoc --help
pandoc --version
```

Upstream also recommends running tests (`cabal test` / `stack test`) for source-build validation.

#### Configuration Options

- **Version Selection**:
  - Controlled by source tarball version, selected git revision, or package resolver behavior.
- **Installation Path**:
  - Stack default install location: `~/.local/bin`.
  - Cabal quick method symlink location: `$HOME/.cabal/bin` (Linux/unix/macOS) and `%APPDATA%\cabal\bin` on Windows.
  - Custom install directories can be set with cabal options such as `--installdir` and broader `cabal configure` directory flags.
  - Cabal can copy binaries instead of symlinking with `--install-method=copy`.
- **User Targeting**:
  - Typically user-local unless explicitly installing to system directories.
- **Required Privileges**:
  - Not required for user-local prefixes; required only for system-owned prefixes.
- **Tool-Specific Configurations**:
  - `pandoc` flag: `embed_data_files` for relocatable/self-contained binaries.
  - Additional `pandoc` build flag: `http` (enabled in upstream macOS release build script).
  - `pandoc-cli` flags include `lua`, `server`, `repl`, and `nightly`.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Ensure `~/.local/bin` or `$HOME/.cabal/bin` is in `PATH` for quick methods.
- **Configuration Files**:
  - None required for basic operation.
  - For cabal quick installs, upstream notes that `pandoc.1` is not installed automatically; copy it manually from `man/` to your manpage directory if manpage availability is required.
- **Environment Variables**:
  - None required by default.
- **Activation Scripts**:
  - None specific to pandoc; toolchain environment initialization may apply.
- **Cleanup**:
  - Optional cleanup of build directories/artifacts after successful install.

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Rebuild/install from desired source version or change resolver inputs.
- **Uninstallation**:
  - Remove installed binaries from selected install directories (`~/.local/bin`, `$HOME/.cabal/bin`, or custom install targets).
- **Idempotency**:
  - Re-running same build/install target generally replaces binaries for that target path.

#### Notes and Best Practices

- Prefer source builds for custom feature support, local patches, or unsupported binary/package combinations.
- For feature implementation simplicity and reproducibility in DevFeats, source builds are usually fallback rather than default method.

## References

- [Pandoc Installing Guide](https://pandoc.org/installing.html) - Official installation methods, platform notes, commands, and caveats.
- [Pandoc INSTALL.md (upstream source)](https://raw.githubusercontent.com/jgm/pandoc/main/INSTALL.md) - Canonical source for install instructions, caveats, and source-build procedures.
- [Pandoc Repository](https://github.com/jgm/pandoc) - Official source repository and project metadata.
- [Pandoc cabal file](https://raw.githubusercontent.com/jgm/pandoc/main/pandoc.cabal) - Upstream package definition including cabal flags such as `embed_data_files`.
- [Pandoc CLI cabal file](https://raw.githubusercontent.com/jgm/pandoc/main/pandoc-cli/pandoc-cli.cabal) - Upstream CLI package definition including CLI-level flags.
- [Pandoc Latest Release Page](https://github.com/jgm/pandoc/releases/latest) - Official current release and downloadable assets.
- [Pandoc Releases API (latest)](https://api.github.com/repos/jgm/pandoc/releases/latest) - Machine-readable latest version/date/assets and per-asset digests.
- [Homebrew Installation](https://docs.brew.sh/Installation) - Official Homebrew shell environment setup guidance (`brew shellenv`) and install behavior.
- [Pandoc Linux package control template](https://raw.githubusercontent.com/jgm/pandoc/main/linux/control.in) - Debian package metadata/dependency declarations used in release packaging.
- [Pandoc Linux artifact builder](https://raw.githubusercontent.com/jgm/pandoc/main/linux/make_artifacts.sh) - Official Linux release packaging script (binary checks, symlinks, tar/deb assembly).
- [Pandoc macOS package distribution template](https://raw.githubusercontent.com/jgm/pandoc/main/macos/distribution.xml.in) - macOS package ID, architecture gating, and installer metadata.
- [Pandoc macOS release packaging script](https://raw.githubusercontent.com/jgm/pandoc/main/macos/make_macos_release.sh) - Official macOS build/package path layout and packaging behavior.
- [Pandoc macOS uninstaller script](https://raw.githubusercontent.com/jgm/pandoc/main/macos/uninstall-pandoc.pl) - Official uninstallation logic for pkg-based installs.
- [Pandoc Windows MSI source](https://raw.githubusercontent.com/jgm/pandoc/main/windows/pandoc.wxs) - Windows installer behavior, upgrade/replacement policy, and PATH update details.
- [Pandoc Dockerfiles README](https://raw.githubusercontent.com/pandoc/dockerfiles/master/README.md) - Official Docker image variants and usage guidance.
- [Pandoc Dockerfiles core image example](https://raw.githubusercontent.com/pandoc/dockerfiles/master/3.9.0.2/alpine/core/Dockerfile) - Concrete upstream image composition for pandoc/core.
- [Pandoc Dockerfiles latex image example](https://raw.githubusercontent.com/pandoc/dockerfiles/master/3.9.0.2/ubuntu/latex/Dockerfile) - Concrete upstream image composition for pandoc/latex.
- [Available Dev Container Features](https://containers.dev/features) - Registry listing showing existing community pandoc features for comparison.
- [rocker-org pandoc feature installer](https://raw.githubusercontent.com/rocker-org/devcontainer-features/main/src/pandoc/install.sh) - Comparable implementation using architecture checks, tag resolution, and `.deb` install.
- [rocker-org pandoc feature README](https://raw.githubusercontent.com/rocker-org/devcontainer-features/main/src/pandoc/README.md) - Comparable platform/version behavior documentation.
- [devcontainers-extra pandoc feature installer](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/pandoc/install.sh) - Comparable implementation delegating GitHub release installation.
- [devcontainers-extra pandoc feature README](https://raw.githubusercontent.com/devcontainers-extra/features/main/src/pandoc/README.md) - Comparable feature API surface and install-channel framing.
