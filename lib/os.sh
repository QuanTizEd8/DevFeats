# shellcheck shell=bash
# OS and hardware detection: cached accessors for kernel, arch, distro ID, and platform tag.
#
# Results for `os__kernel` and `os__arch` are cached for the lifetime of the
# script. `os__platform` maps OS IDs to a canonical tag (`debian`, `alpine`,
# `rhel`, `suse`, `macos`).

# ── Cached globals (populated lazily) ────────────────────────────────────────
_OS__KERNEL=""
_OS__ARCH=""
_OS__ID=""
_OS__ID_LIKE=""
_OS__CODENAME=""
_OS__PLATFORM=""
_OS__RELEASE_LOADED=""
_OS__RELEASE_VARS=()

os__kernel() {
  # @brief os__kernel — Print the kernel name (`Linux` or `Darwin`). Cached; use instead of `uname -s`.
  #
  # Stdout: kernel name.
  [ -n "${_OS__KERNEL-}" ] || _OS__KERNEL="$(uname -s)"
  echo "$_OS__KERNEL"
  return 0
}

os__arch() {
  # @brief os__arch — Print the CPU architecture (e.g. `x86_64`, `aarch64`). Cached; use instead of `uname -m`.
  #
  # Stdout: architecture string.
  [ -n "${_OS__ARCH-}" ] || _OS__ARCH="$(uname -m)"
  echo "$_OS__ARCH"
  return 0
}

os__id() {
  # @brief os__id — Print the `ID` field from `/etc/os-release` (e.g. `ubuntu`, `alpine`).
  #
  # Stdout: distro ID string, or empty on macOS.
  _os__load_release
  echo "${_OS__ID:-}"
  return 0
}

os__id_like() {
  # @brief os__id_like — Print the `ID_LIKE` field from `/etc/os-release` (space-separated distro family list).
  #
  # Stdout: distro family string, or empty if absent.
  _os__load_release
  echo "${_OS__ID_LIKE:-}"
  return 0
}

os__platform() {
  # @brief os__platform — Print a canonical platform tag: `debian` | `alpine` | `rhel` | `suse` | `macos`.
  #
  # Falls back to `debian` for unrecognised Linux distros.
  #
  # Stdout: one of `debian`, `alpine`, `rhel`, `suse`, `macos`.
  if [ -n "${_OS__PLATFORM-}" ]; then
    echo "$_OS__PLATFORM"
    return 0
  fi
  _os__load_release
  case "${_OS__ID:-}" in
    debian | ubuntu) _OS__PLATFORM="debian" ;;
    alpine) _OS__PLATFORM="alpine" ;;
    rhel | centos | fedora | rocky | almalinux) _OS__PLATFORM="rhel" ;;
    opensuse-leap | opensuse-tumbleweed | opensuse | sles | sle-micro) _OS__PLATFORM="suse" ;;
    *)
      case "${_OS__ID_LIKE:-}" in
        *debian* | *ubuntu*) _OS__PLATFORM="debian" ;;
        *alpine*) _OS__PLATFORM="alpine" ;;
        *rhel* | *fedora* | *centos* | *"Red Hat"*) _OS__PLATFORM="rhel" ;;
        *suse*) _OS__PLATFORM="suse" ;;
        *)
          [ "$(uname -s)" = "Darwin" ] && _OS__PLATFORM="macos" || _OS__PLATFORM="debian"
          ;;
      esac
      ;;
  esac
  echo "$_OS__PLATFORM"
  return 0
}

os__release_kernel() {
  # @brief os__release_kernel [<flavor>] — Print the kernel identifier used in release asset filenames.
  #
  # Maps the result of `os__kernel` to the token used by release asset naming
  # conventions. Returns 1 with a logged error for unsupported kernels or flavors.
  #
  # Flavor `github` (default): `linux`, `darwin`, or `freebsd` — standard GitHub releases.
  # Flavor `gh`:               `linux` or `macOS`  — GitHub CLI asset naming.
  # Flavor `macos`:            `linux` or `macos`  — tools that use "macos" for Darwin (e.g. jq ≥1.7).
  # Flavor `osx`:              `linux` or `osx`    — tools that use "osx" for Darwin (e.g. jq <1.7).
  #
  # Stdout: kernel token string.
  # Returns: 0 on success, 1 if the kernel or flavor is unsupported.
  local _flavor="${1:-github}"
  case "$(os__kernel)" in
    Linux) printf 'linux\n' ;;
    Darwin)
      case "$_flavor" in
        github) printf 'darwin\n' ;;
        gh) printf 'macOS\n' ;;
        macos) printf 'macos\n' ;;
        osx) printf 'osx\n' ;;
        *)
          logging__error "unknown flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    FreeBSD) printf 'freebsd\n' ;;
    *)
      logging__error "unsupported kernel '$(os__kernel)'."
      return 1
      ;;
  esac
}

os__release_arch() {
  # @brief os__release_arch [<raw-arch>] [--flavor <token>] — Map a raw architecture string to a release asset token.
  #
  # Accepts raw `uname -m` output or already-normalised values. Defaults to
  # `os__arch` when omitted. Pass an explicit value when a user-supplied arch
  # override is in play (e.g. the $ARCH option in install-node).
  #
  # Flavor `github` (default): amd64, arm64, armv7, i386, ppc64le, s390x, riscv64, loong64.
  # Flavor `node`:             x64,  arm64, armv7l, ppc64le, s390x.
  # Flavor `gh`:               amd64, arm64, armv6, 386.
  # Flavor `bitness`:          64 (64-bit arches) or 32 (32-bit arches).
  #
  # Returns: 0 on success, 1 if the arch/flavor combination is unsupported.
  # shellcheck disable=SC2120
  local _raw="" _flavor="github"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --flavor)
        shift
        _flavor="${1-}"
        ;;
      *) _raw="$1" ;;
    esac
    shift
  done
  [[ -n "$_raw" ]] || _raw="$(os__arch)"
  case "$_raw" in
    x86_64 | amd64 | x64)
      case "$_flavor" in
        github | gh) printf 'amd64\n' ;;
        node) printf 'x64\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "unknown flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    aarch64 | arm64)
      case "$_flavor" in
        bitness) printf '64\n' ;;
        *) printf 'arm64\n' ;;
      esac
      ;;
    armv7l | armv7)
      case "$_flavor" in
        github) printf 'armv7\n' ;;
        node) printf 'armv7l\n' ;;
        gh) printf 'armv6\n' ;;
        bitness) printf '32\n' ;;
        *)
          logging__error "unknown flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    armv6l)
      case "$_flavor" in
        gh) printf 'armv6\n' ;;
        bitness) printf '32\n' ;;
        *)
          logging__error "architecture 'armv6l' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    i386 | i686)
      case "$_flavor" in
        github) printf 'i386\n' ;;
        gh) printf '386\n' ;;
        bitness) printf '32\n' ;;
        *)
          logging__error "architecture '${_raw}' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    ppc64le)
      case "$_flavor" in
        github | node) printf 'ppc64le\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 'ppc64le' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    s390x)
      case "$_flavor" in
        github | node) printf 's390x\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 's390x' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    riscv64)
      case "$_flavor" in
        github) printf 'riscv64\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 'riscv64' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    loong64 | loongarch64)
      case "$_flavor" in
        github) printf 'loong64\n' ;;
        bitness) printf '64\n' ;;
        *)
          logging__error "architecture 'loong64' is not supported for flavor '${_flavor}'."
          return 1
          ;;
      esac
      ;;
    *)
      logging__error "unsupported architecture '${_raw}'."
      return 1
      ;;
  esac
}

os__libc() {
  # @brief os__libc — Print the C library type on Linux: `musl` or `gnu`.
  #
  # Detects musl by checking for the musl dynamic linker, which is present at
  # `/lib/ld-musl-<arch>.so*` on every musl-based Linux system regardless of
  # architecture (verified on x86_64, aarch64, armhf, riscv64, ppc64le, s390x,
  # i386). Falls back to scanning `ldd /bin/ls` output as a secondary check.
  # Returns 1 (with no output) on non-Linux systems.
  #
  # Stdout: `musl` or `gnu`.
  # Returns: 0 on Linux, 1 on other kernels.
  [ "$(os__kernel)" = "Linux" ] || return 1
  if ls /lib/ld-musl-*.so* > /dev/null 2>&1 || ldd /bin/ls 2>&1 | grep -q musl; then
    printf 'musl\n'
  else
    printf 'gnu\n'
  fi
}

os__rust_triple() {
  # @brief os__rust_triple [<raw-arch>] — Print the Rust target triple for the current kernel and architecture.
  #
  # Accepts an optional raw architecture string (uname -m output or a user-supplied
  # override). Defaults to os__arch.
  #
  # Linux suffix selection (musl vs gnu):
  #   - x86_64, aarch64, armv6l, armv7l, loongarch64, i686: always musl (portable static builds).
  #   - ppc64le, s390x: always gnu — no widely-published musl builds exist for either
  #     (`s390x-unknown-linux-musl` was removed as a Rust target in Rust 1.81).
  #   - riscv64: detected at runtime via os__libc() — musl on Alpine, gnu on glibc distros.
  #
  # 32-bit x86 detection: on a 64-bit kernel with a 32-bit userland (or a native
  # 32-bit machine), `uname -m` reports `x86_64`. This function detects the 32-bit
  # case via `getconf LONG_BIT` and corrects the arch to i686 so the correct
  # i686-unknown-linux-musl triple is selected instead of the 64-bit one.
  #
  # Stdout: Rust target triple (e.g. x86_64-unknown-linux-musl, aarch64-apple-darwin).
  # Returns: 0 on success, 1 if the kernel/arch combination is unsupported.
  local _raw="${1:-$(os__arch)}"
  # Detect 32-bit x86 userland on a 64-bit kernel: uname -m reports x86_64 but
  # the running process (and its binaries) are 32-bit. getconf LONG_BIT is POSIX
  # and available on both glibc and musl; it reflects the process word size.
  if [ "$_raw" = "x86_64" ] || [ "$_raw" = "amd64" ]; then
    local _bits
    _bits="$(getconf LONG_BIT 2> /dev/null || true)"
    [ "${_bits}" = "32" ] && _raw="i686"
  fi
  case "$(os__kernel):${_raw}" in
    Linux:x86_64 | Linux:amd64) printf 'x86_64-unknown-linux-musl\n' ;;
    Linux:i386 | Linux:i686) printf 'i686-unknown-linux-musl\n' ;;
    Linux:aarch64 | Linux:arm64) printf 'aarch64-unknown-linux-musl\n' ;;
    Linux:armv6l) printf 'arm-unknown-linux-musleabihf\n' ;;
    Linux:armv7l) printf 'armv7-unknown-linux-musleabihf\n' ;;
    Linux:loongarch64) printf 'loongarch64-unknown-linux-musl\n' ;;
    Linux:ppc64le) printf 'powerpc64le-unknown-linux-gnu\n' ;;
    Linux:s390x) printf 's390x-unknown-linux-gnu\n' ;;
    Linux:riscv64)
      if [ "$(os__libc)" = "musl" ]; then
        printf 'riscv64gc-unknown-linux-musl\n'
      else
        printf 'riscv64gc-unknown-linux-gnu\n'
      fi
      ;;
    Darwin:x86_64 | Darwin:amd64) printf 'x86_64-apple-darwin\n' ;;
    Darwin:aarch64 | Darwin:arm64) printf 'aarch64-apple-darwin\n' ;;
    FreeBSD:x86_64 | FreeBSD:amd64) printf 'x86_64-unknown-freebsd\n' ;;
    *)
      logging__error "unsupported kernel/arch '$(os__kernel)/${_raw}'."
      return 1
      ;;
  esac
}

os__font_dir() {
  # @brief os__font_dir — Print the platform-appropriate font directory for the current installation scope.
  #
  # Stdout: `/usr/share/fonts` (root/system), `~/Library/Fonts` (macOS non-root), or `${XDG_DATA_HOME:-~/.local/share}/fonts` (Linux non-root).
  if users__is_root; then
    echo "/usr/share/fonts"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    echo "${HOME}/Library/Fonts"
  else
    echo "${XDG_DATA_HOME:-${HOME}/.local/share}/fonts"
  fi
  return 0
}

os__is_devcontainer_build() {
  # @brief os__is_devcontainer_build — Return 0 when this script is being executed as a devcontainer feature installer, 1 otherwise.
  #
  # The devcontainer Feature spec mandates that ALL FOUR of the following
  # variables be present in the installer environment, regardless of which
  # spec-compliant tool performs the build:
  #
  #   _REMOTE_USER         remoteUser from devcontainer.json
  #   _CONTAINER_USER      containerUser (or default container user)
  #   _REMOTE_USER_HOME    home directory of _REMOTE_USER
  #   _CONTAINER_USER_HOME home directory of _CONTAINER_USER
  #
  # Requiring all four together is the spec-defined signal:
  # - `_REMOTE_USER` alone may be set by other tools (e.g. SysSet).
  # - `_CONTAINER_USER` is more specific but still not unique in isolation.
  # - All four sharing these exact names have no plausible source other than a
  #   devcontainer-spec-compliant feature installer.
  #
  # Note: `os__is_container()` and filesystem paths are intentionally NOT used
  # here. Features are installed during `docker build` (BuildKit RUN steps),
  # where `/.dockerenv` is absent — `os__is_container()` returns false in that
  # context. The `/tmp/dev-container-features` path is a specific CLI internal
  # that other compliant tools need not replicate.
  #
  # Returns: 0 in devcontainer feature-install context, 1 otherwise.
  [ "${_REMOTE_USER+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER+defined}" = "defined" ] &&
    [ "${_REMOTE_USER_HOME+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER_HOME+defined}" = "defined" ]
}

os__is_container() {
  # @brief os__is_container — Return 0 if running inside a container (Docker, Podman, Kubernetes, CI), 1 otherwise.
  #
  # Uses the same heuristics as Homebrew's `check-run-command-as-root()` so that
  # brew can run as root in devcontainers.
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  if [ -f /proc/1/cgroup ] &&
    grep -qE 'azpl_job|actions_job|docker|garden|kubepods' /proc/1/cgroup 2> /dev/null; then
    return 0
  fi
  return 1
}

_os__load_release() {
  # @brief _os__load_release — Parse `/etc/os-release` once and cache `ID`, `ID_LIKE`, and `VERSION_CODENAME` into module-private globals.
  #
  # Uses `grep`/`sed` rather than `source /etc/os-release` to avoid polluting
  # the environment with the full set of os-release variables. Idempotent: sets
  # `_OS__RELEASE_LOADED` after the first parse and returns immediately on
  # subsequent calls. Falls back to `UBUNTU_CODENAME` when `VERSION_CODENAME`
  # is absent (some Ubuntu 22.04 images omit it).
  #
  # Side effects: sets `_OS__ID`, `_OS__ID_LIKE`, `_OS__CODENAME`,
  #               and `_OS__RELEASE_LOADED`.
  [ -n "${_OS__RELEASE_LOADED-}" ] && return 0
  if [ -f /etc/os-release ]; then
    _OS__ID="$(grep -m1 '^ID=' /etc/os-release 2> /dev/null |
      sed 's/^ID=//;s/^"//;s/"$//' || true)"
    _OS__ID_LIKE="$(grep -m1 '^ID_LIKE=' /etc/os-release 2> /dev/null |
      sed 's/^ID_LIKE=//;s/^"//;s/"$//' || true)"
    _OS__CODENAME="$(grep -m1 '^VERSION_CODENAME=' /etc/os-release 2> /dev/null |
      sed 's/^VERSION_CODENAME=//;s/^"//;s/"$//' || true)"
    # Fallback: UBUNTU_CODENAME (present on some Ubuntu releases that lack VERSION_CODENAME).
    if [ -z "${_OS__CODENAME-}" ]; then
      _OS__CODENAME="$(grep -m1 '^UBUNTU_CODENAME=' /etc/os-release 2> /dev/null |
        sed 's/^UBUNTU_CODENAME=//;s/^"//;s/"$//' || true)"
    fi
  fi
  _OS__RELEASE_LOADED=1
  return 0
}

os__codename() {
  # @brief os__codename — Print `VERSION_CODENAME` from `/etc/os-release` (e.g. `jammy`, `bookworm`); empty string if absent or on macOS.
  #
  # Falls back to `UBUNTU_CODENAME` when `VERSION_CODENAME` is absent.
  #
  # Stdout: distro codename, or empty string.
  _os__load_release
  echo "${_OS__CODENAME:-}"
  return 0
}

os__match_spec() {
  # @brief os__match_spec <key=value> [...] — Return 0 if the current OS context matches all given key=value conditions.
  #
  # Delegates to `ospkg__os_release_match` (which calls `ospkg__detect` idempotently).
  # AND logic: all key=value pairs must match. Case-insensitive.
  # OR within values: a `|`-separated value (e.g. `arch=amd64|arm64`) matches if any alternative matches.
  # Supported keys: kernel, arch, id, id_like, pm, version_id, version_codename, and any
  # /etc/os-release field.
  #
  # Returns: 0 if all conditions match, 1 otherwise.
  [ $# -eq 0 ] && return 0
  local _pair _k _v _alt _matched
  local -a _alts
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    IFS='|' read -ra _alts <<< "${_v}"
    _matched=false
    for _alt in "${_alts[@]}"; do
      ospkg__os_release_match "${_k}" "${_alt}" 2> /dev/null && {
        _matched=true
        break
      }
    done
    [[ "${_matched}" == true ]] || {
      logging__error "platform condition '${_pair}' did not match."
      return 1
    }
  done
  return 0
}

os__match_when() {
  # @brief os__match_when <when-string> — Return 0 if the current OS context matches the given when block.
  #
  # Evaluates a serialized `when` block using the same semantics as the ospkg manifest schema:
  # - AND across space-separated `key=value` atoms within a group.
  # - OR (`|`) across values within a single atom (e.g. `arch=amd64|arm64`).
  # - OR across newline-separated groups (array form: matches if any group matches).
  # An empty string always matches (no constraint).
  # Delegates per-key matching to `os__match_spec`.
  #
  # Serialization format (produced by the build pipeline from metadata.yaml `when` blocks):
  #   Object form  : `{arch: [amd64, arm64]}`   → `"arch=amd64|arm64"`
  #   Array form   : `[{kernel:linux,arch:amd64},{kernel:darwin}]` → `"kernel=linux arch=amd64\nkernel=darwin"`
  #
  # Returns: 0 if the when block matches (or is empty), 1 otherwise.
  local _when="${1:-}"
  [ -z "${_when}" ] && return 0
  local _group
  while IFS= read -r _group; do
    [ -z "${_group}" ] && continue
    # shellcheck disable=SC2086
    os__match_spec ${_group} 2> /dev/null && return 0
  done <<< "${_when}"
  return 1
}

_os__init_release_vars() {
  # _os__init_release_vars — Populate _OS__RELEASE_VARS with all OS/arch KEY=VALUE pairs on first call.
  # Flavour variants that fail on the current system are silently skipped.
  [[ ${#_OS__RELEASE_VARS[@]} -gt 0 ]] && return 0
  local _v
  _OS__RELEASE_VARS=(
    "OS=$(os__release_kernel)"
    "KERNEL=$(os__kernel)"
    "ARCH=$(os__release_arch)"
    "OS_ARCH=$(os__arch)"
    "OS_ID=$(os__id)"
    "PLATFORM=$(os__platform)"
  )
  _v="$(os__release_kernel gh 2> /dev/null)" && _OS__RELEASE_VARS+=("OS:gh=${_v}") || true
  _v="$(os__release_kernel macos 2> /dev/null)" && _OS__RELEASE_VARS+=("OS:macos=${_v}") || true
  _v="$(os__release_kernel osx 2> /dev/null)" && _OS__RELEASE_VARS+=("OS:osx=${_v}") || true
  _v="$(os__release_arch --flavor gh 2> /dev/null)" && _OS__RELEASE_VARS+=("ARCH:gh=${_v}") || true
  _v="$(os__release_arch --flavor node 2> /dev/null)" && _OS__RELEASE_VARS+=("ARCH:node=${_v}") || true
  _v="$(os__release_arch --flavor bitness 2> /dev/null)" && _OS__RELEASE_VARS+=("ARCH:bitness=${_v}") || true
  _v="$(os__rust_triple 2> /dev/null)" && _OS__RELEASE_VARS+=("RUST_TRIPLE=${_v}") || true
  _v="$(os__libc 2> /dev/null)" && _OS__RELEASE_VARS+=("LIBC=${_v}") || true
}

os__expand_release_pattern() {
  # @brief os__expand_release_pattern <pattern> <version> <tag> — Expand a GitHub release
  # asset filename pattern.
  #
  # Plain tokens: {VERSION}, {TAG}, {OS}, {KERNEL}, {ARCH}, {OS_ARCH}, {OS_ID},
  #   {PLATFORM}, {RUST_TRIPLE}, {LIBC} (Linux only: `musl` or `gnu`).
  # Flavor tokens: {OS:<flavor>} → os__release_kernel <flavor>,
  #   {ARCH:<flavor>} → os__release_arch --flavor <flavor>.
  # Conditionals (nestable): {TOKEN==VALUE?TRUE:FALSE},
  #   {TOKEN:FLAVOR==VALUE?TRUE:FALSE}, {VERSION>=X.Y?TRUE:FALSE},
  #   {VERSION<X.Y?TRUE:FALSE}.
  # TRUE and FALSE branches may themselves contain any token form.
  #
  # <version> and <tag> may be empty strings.
  _os__init_release_vars
  str__expand_pattern "${1}" "VERSION=${2:-}" "TAG=${3:-}" "${_OS__RELEASE_VARS[@]}"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to expand release pattern '${1}'."
    return "$_rc"
  }
  printf '\n'
}
