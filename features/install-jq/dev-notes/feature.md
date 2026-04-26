# Feature Reference

jq is a lightweight command-line JSON processor written in portable C. It is widely used in shell pipelines, CI/CD scripts, data-processing jobs, and configuration tooling to filter, transform, and validate JSON. The jq project publishes multiple installation paths: distro package managers, prebuilt release binaries, source tarballs, and a container image. For a SysSet feature that must work across macOS and Linux (including containers and bare metal), the practical methods are: OS package manager, prebuilt binary download, and source build.

- **Homepage**: https://jqlang.org/
- **Source Code**: https://github.com/jqlang/jq
- **Documentation**: https://jqlang.org/manual/ and https://jqlang.org/download/
- **Latest Release**: 1.8.1 (as of 2026-04-26)

## Available Installation Methods

jq supports multiple official installation channels. For `install-jq`, the implementation-relevant channels are:

1. OS package manager installs for distro-native lifecycle management.
2. Prebuilt release binaries for deterministic version pinning and broad portability.
3. Source builds for maximum control and fallback when package/binary constraints apply.

The official jq container image exists, but it is not typically treated as a host/container provisioning install method for this feature.

### OS Package Manager

#### Supported Platforms

- Debian and Ubuntu via `apt-get`.
- Fedora/RHEL-family systems with `dnf` and available jq package.
- openSUSE via `zypper`.
- Arch Linux via `pacman`.
- macOS and Linux via Homebrew.
- Alpine Linux via `apk` package repositories.

#### Dependencies

- **Common Dependencies**: A working system package manager (`apt-get`, `dnf`, `zypper`, `pacman`, `brew`, `apk`) and configured package repositories.
- **Platform-Specific Dependencies**:
  - Linux package managers generally require root privileges for install/remove/upgrade operations.
  - Homebrew requires a working Homebrew installation and user environment configured for `brew`.

#### Installation Steps

1. Refresh package metadata where appropriate.
2. Install jq using the native package manager command.

Examples:

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y jq

# Fedora/RHEL-family
sudo dnf install -y jq

# openSUSE
sudo zypper install -y jq

# Arch
sudo pacman -S --noconfirm jq

# Alpine
sudo apk add --no-cache jq

# Homebrew (macOS/Linux)
brew install jq
```

#### Installation Verification

- Verify command availability and version:

```bash
command -v jq
jq --version
```

- Package-manager level verification examples:

```bash
# Debian/Ubuntu
apt-cache policy jq

# Fedora/RHEL-family
dnf info jq

# openSUSE
zypper info jq

# Arch
pacman -Qi jq

# Alpine
apk info jq

# Homebrew
brew info jq
```

#### Configuration Options

- **Version Selection**:
  - `apt-get` supports explicit version selection with `package=version` syntax.
  - `dnf` supports version-qualified package specs (for repos that publish those NEVRA versions).
  - `zypper` supports capability/version constraints (e.g., `jq=1.8.1`).
  - `pacman`, `apk`, and default Homebrew workflows are generally latest-available in configured repositories.
  - For strict cross-platform pinning, prefer the Prebuilt Binary method.
- **Installation Path**:
  - Package-manager managed, typically system paths such as `/usr/bin/jq` (Linux) or `$(brew --prefix)/bin/jq` (Homebrew).
- **User Targeting**:
  - Linux package-manager installs are system-wide.
  - Homebrew installs into the Homebrew prefix and symlinks into the user's active brew path.
- **Required Privileges**:
  - Root/sudo required for Linux package-manager installs.
  - Homebrew usually runs as non-root user in its configured prefix.
- **Tool-Specific Configurations**:
  - No jq-specific install-time config is generally required for package-manager installs.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Usually not required for system package managers.
  - For Homebrew, ensure shell environment is initialized (for example via `brew shellenv`) if `jq` is not found.
- **Configuration Files**:
  - No jq configuration files are required for basic operation.
- **Environment Variables**:
  - No required persistent environment variables for default jq operation.
- **Activation Scripts**:
  - None required.
- **Cleanup**:
  - Package caches can be cleaned per platform policy. For Debian/Ubuntu image minimization, a common pattern is:

```bash
apt-get clean
apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*
```

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Debian/Ubuntu: `apt-get install jq=<version>` for version pin/downgrade, or `apt-get install --only-upgrade jq` to upgrade jq without a full system upgrade.
  - Fedora/RHEL-family: `dnf upgrade jq` or version-qualified install where available.
  - openSUSE: `zypper update jq` or version-qualified install.
  - Arch: `pacman -Syu jq`.
  - Alpine: `apk upgrade jq`.
  - Homebrew: `brew upgrade jq`.
- **Uninstallation**:

```bash
# Debian/Ubuntu
sudo apt-get remove -y jq

# Fedora/RHEL-family
sudo dnf remove -y jq

# openSUSE
sudo zypper remove -y jq

# Arch
sudo pacman -R --noconfirm jq

# Alpine
sudo apk del jq

# Homebrew
brew uninstall jq
```

- **Idempotency**:
  - Re-running install is package-manager idempotent: already-installed packages remain installed and may be upgraded if newer versions are selected.

#### Notes and Best Practices

- Package-manager installs are simplest and integrate best with OS lifecycle tooling.
- Repository versions can lag upstream releases; this is especially relevant for strict version requirements.
- Prefer package-manager method for default installs, and switch to binary/source methods when exact-version pinning is required.
- Similar feature implementations in devcontainer ecosystems often use this method for simplicity (`apt`/`apk`) and validate with `jq --version` in tests.

### Prebuilt Binary Download (GitHub Releases)

#### Supported Platforms

- Linux and macOS on architectures for which jq publishes release assets.
- Official 1.8.1 assets documented on the jq download page are Linux `amd64`, `arm64`, `i386`, and macOS `amd64`, `arm64`.
- This method works when a matching official binary exists for the target OS/architecture and executes successfully in the target environment.

#### Dependencies

- **Common Dependencies**: `curl` or `wget`; executable permission tools (`chmod`/`install`); checksum tool (`sha256sum` or `shasum`).
- **Platform-Specific Dependencies**:
  - Optional but recommended: `gpg` for signature verification.
  - Root/sudo only required when writing to system paths such as `/usr/local/bin`.

#### Installation Steps

1. Select version (for example `1.8.1`) and resolve platform/arch asset name.
2. Download the binary and checksum list.
3. Verify checksum.
4. Mark executable and place in target path.

Example (Linux `amd64`, system-wide):

```bash
set -e
ver="1.8.1"
asset="jq-linux-amd64"
base="https://github.com/jqlang/jq/releases/download/jq-${ver}"

curl -fsSLo "${asset}" "${base}/${asset}"
curl -fsSLo sha256sum.txt "${base}/sha256sum.txt"
grep " ${asset}$" sha256sum.txt | sha256sum -c -

chmod +x "${asset}"
sudo install -m 0755 "${asset}" /usr/local/bin/jq
jq --version
```

Example (macOS arm64, user-local):

```bash
set -e
ver="1.8.1"
asset="jq-macos-arm64"
base="https://github.com/jqlang/jq/releases/download/jq-${ver}"

curl -fsSLo "${asset}" "${base}/${asset}"
curl -fsSLo sha256sum.txt "${base}/sha256sum.txt"
grep " ${asset}$" sha256sum.txt | shasum -a 256 -c -

chmod +x "${asset}"
mkdir -p "$HOME/.local/bin"
install -m 0755 "${asset}" "$HOME/.local/bin/jq"
"$HOME/.local/bin/jq" --version
```

#### Installation Verification

- Checksum verification against release `sha256sum.txt`.
- Optional signature verification with jq release keys and `.asc` signature files.

Example signature verification:

```bash
# Use jq-release-new.key for 1.7+ releases, jq-release-old.key for 1.6 and older
curl -fsSLo jq-release-new.key \
  https://raw.githubusercontent.com/jqlang/jq/master/sig/jq-release-new.key

gpg --import jq-release-new.key
# Optional fingerprint check: 93079A9511EFC0B7D6CDBFB5B0DA60FB454BAF18

curl -fsSLo jq-linux-amd64.asc \
  https://raw.githubusercontent.com/jqlang/jq/master/sig/v1.8.1/jq-linux-amd64.asc
gpg --verify jq-linux-amd64.asc jq-linux-amd64
```

#### Configuration Options

- **Version Selection**:
  - Controlled by release tag and asset URL (`jq-${version}`).
  - `latest` can be resolved via GitHub Releases API.
  - Asset naming varies across older releases (for example `jq-linux64` in older lines), so version-specific mapping logic is needed.
- **Installation Path**:
  - System-wide: `/usr/local/bin/jq` (root/sudo needed).
  - User-local: `$HOME/.local/bin/jq` (no sudo), with PATH update as needed.
- **User Targeting**:
  - Supports both system-wide and user-local installs.
- **Required Privileges**:
  - Privileged only when writing to root-owned paths.
- **Tool-Specific Configurations**:
  - Release-asset architecture mapping and legacy asset-name fallback are key implementation details.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - If installed to user-local path, ensure `$HOME/.local/bin` is on PATH.
- **Configuration Files**:
  - None required.
- **Environment Variables**:
  - None required for default jq usage.
- **Activation Scripts**:
  - None required.
- **Cleanup**:

```bash
rm -f jq-linux-* jq-macos-* jq-windows-* sha256sum.txt *.asc jq-release-*.key
```

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Re-run download/install with another release tag; binary replacement is straightforward.
- **Uninstallation**:

```bash
# System-wide
sudo rm -f /usr/local/bin/jq

# User-local
rm -f "$HOME/.local/bin/jq"
```

- **Idempotency**:
  - Re-installing same version to the same path simply overwrites/replaces the binary and remains functionally idempotent.

#### Notes and Best Practices

- This is the preferred method for strict, reproducible version pinning across heterogeneous platforms.
- Always verify checksums; verify signatures for higher assurance.
- Handle legacy asset naming for older jq versions (for example pre-1.7 naming) and architecture availability differences.
- Similar community features demonstrate robust fallback logic for old asset names and optional RC-selection handling.

### Build From Source

#### Supported Platforms

- Linux, macOS, and other POSIX-like systems where build dependencies are available.
- Most portable method when package-manager or binary methods are insufficient.

#### Dependencies

- **Common Dependencies**: `libtool`, `make`, `automake`, `autoconf`, C toolchain.
- **Platform-Specific Dependencies**:
  - `git` and submodules when building from a clone.
  - `flex` and `bison` required when using maintainer mode (`--enable-maintainer-mode`) from source-generation paths.
  - On macOS, Xcode command line tools are required; newer bison may be needed.

#### Installation Steps

From git clone:

```bash
set -e
git clone --recursive https://github.com/jqlang/jq.git
cd jq
git submodule update --init
autoreconf -i
./configure --with-oniguruma=builtin
make clean
make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
make check
sudo make install
jq --version
```

From release tarball:

```bash
set -e
ver="1.8.1"
curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${ver}/jq-${ver}.tar.gz" \
  | tar -xz
cd "jq-${ver}"
./configure --with-oniguruma=builtin
make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
make check
sudo make install
jq --version
```

Optional static build variant:

```bash
make LDFLAGS=-all-static
```

#### Installation Verification

- Build-time verification via `make check`.
- Runtime verification:

```bash
command -v jq
jq --version
```

#### Configuration Options

- **Version Selection**:
  - Choose exact release tarball version, or pin to git commit/tag before build.
- **Installation Path**:
  - Controlled by configure prefix (for example `./configure --prefix=/usr/local` or user-local prefix).
- **User Targeting**:
  - Supports system-wide and user-local install depending on prefix.
- **Required Privileges**:
  - Privileges required only for root-owned prefixes.
- **Tool-Specific Configurations**:
  - `--with-oniguruma=builtin` is the documented build mode from upstream instructions.
  - `--enable-maintainer-mode` enables parser/lexer regeneration path and needs `flex`/`bison`.
  - Static linking can be attempted with `LDFLAGS=-all-static`.

#### Post-Installation Steps and Cleanup

- **PATH Setup**:
  - Add custom prefix bin directory to PATH if not already present.
- **Configuration Files**:
  - None required for jq.
- **Environment Variables**:
  - No required jq-specific environment variables.
- **Activation Scripts**:
  - None required.
- **Cleanup**:

```bash
# Optional cleanup after successful install
make clean || true
cd ..
rm -rf jq jq-1.8.1
```

#### Changing Versions and Uninstallation

- **Upgrading/Downgrading**:
  - Rebuild from target version source and reinstall to the same prefix.
- **Uninstallation**:
  - If uninstall target is available from the same build tree, run `sudo make uninstall`.
  - Otherwise remove installed artifacts manually from the chosen prefix (for example `bin/jq`, manpage entries).
- **Idempotency**:
  - Re-running the same build/install for the same version and prefix is generally safe and results in replacement/overwrite behavior.

#### Notes and Best Practices

- Use source builds when strict control or patching is required, or when package/binary methods do not satisfy constraints.
- Prefer release tarballs for reproducible builds; use git builds only when development snapshots are required.
- Run `make check` in CI and during local validation to catch toolchain/platform issues early.
- Upstream CI and cross-compilation references are useful when extending to uncommon architectures.

## References

- [jq Official Download Page](https://jqlang.org/download/) - Official installation methods, package-manager commands, binary links, checksums/signatures, and source-build guidance.
- [jq Official Manual](https://jqlang.org/manual/) - Core user documentation for runtime validation context.
- [jq GitHub Repository](https://github.com/jqlang/jq) - Canonical source repository and project metadata.
- [jq README (upstream)](https://raw.githubusercontent.com/jqlang/jq/master/README.md) - Build dependencies and exact source-build commands.
- [jq Dockerfile (upstream)](https://raw.githubusercontent.com/jqlang/jq/master/Dockerfile) - Maintainer build pattern including static-build-oriented configure flags.
- [GitHub Releases API - latest jq release](https://api.github.com/repos/jqlang/jq/releases/latest) - Authoritative latest stable release metadata and published assets.
- [jq 1.8.1 checksums file](https://raw.githubusercontent.com/jqlang/jq/master/sig/v1.8.1/sha256sum.txt) - Official SHA-256 digests for release artifacts.
- [jq release key (1.7 and newer)](https://raw.githubusercontent.com/jqlang/jq/master/sig/jq-release-new.key) - Public key used to verify modern release signatures.
- [jq release key (1.6 and older)](https://raw.githubusercontent.com/jqlang/jq/master/sig/jq-release-old.key) - Public key used to verify older release signatures.
- [Homebrew jq formula page](https://formulae.brew.sh/formula/jq) - Homebrew install command, supported bottle platforms, and current formula version.
- [Alpine jq package page](https://pkgs.alpinelinux.org/package/edge/main/x86_64/jq) - Alpine package availability and package metadata.
- [apt-get manpage](https://manpages.debian.org/unstable/apt/apt-get.8.en.html) - apt install/remove/version-selection semantics.
- [DNF command reference](https://dnf.readthedocs.io/en/latest/command_ref.html) - dnf install/upgrade/remove and version-qualified package-spec behavior.
- [zypper manpage](https://manpages.opensuse.org/Tumbleweed/zypper/zypper.8.en.html) - zypper install/update/remove and capability/version syntax.
- [pacman manpage](https://man.archlinux.org/man/pacman.8) - pacman sync/remove/upgrade semantics.
- [Homebrew manpage](https://docs.brew.sh/Manpage) - brew install/upgrade/uninstall command behavior.
- [devcontainer-community jq feature README](https://github.com/devcontainer-community/devcontainer-features/tree/main/src/jq/README.md) - Comparable jq feature using apt-based install approach.
- [devcontainer-community jq feature installer](https://github.com/devcontainer-community/devcontainer-features/tree/main/src/jq/install.sh) - Comparable simple apt installer implementation.
- [devcontainer-community jq feature test](https://github.com/devcontainer-community/devcontainer-features/tree/main/test/jq/test.sh) - Comparable validation pattern via `jq --version`.
- [eitsupi jq-likes feature README](https://github.com/eitsupi/devcontainer-features/tree/main/src/jq-likes/README.md) - Comparable multi-tool feature documenting version options and platform notes.
- [eitsupi jq-likes installer](https://github.com/eitsupi/devcontainer-features/tree/main/src/jq-likes/install.sh) - Comparable robust binary-install and fallback logic for jq versions.
- [cirolosapio alpine-jq installer](https://github.com/cirolosapio/devcontainers-features/tree/main/src/alpine-jq/install.sh) - Comparable Alpine `apk`-based jq feature pattern.
- [devcontainers/features common-utils installer](https://github.com/devcontainers/features/tree/main/src/common-utils/main.sh) - Widely used feature collection showing jq installed through distro package managers (including CentOS/EPEL handling).
