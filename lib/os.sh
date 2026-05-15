#!/usr/bin/env bash
# OS and hardware detection: cached accessors for kernel, arch, distro ID, and platform tag.
#
# Results for `os__kernel` and `os__arch` are cached for the lifetime of the
# script. `os__platform` maps OS IDs to a canonical tag (`debian`, `alpine`,
# `rhel`, `suse`, `macos`).

[ -n "${_OS__LIB_LOADED-}" ] && return 0
_OS__LIB_LOADED=1

_OS__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
. "$_OS__LIB_DIR/logging.sh"
# shellcheck source=lib/users.sh
[[ -z "${_USERS__LIB_LOADED-}" ]] && . "$_OS__LIB_DIR/users.sh"

# ── Cached globals (populated lazily) ────────────────────────────────────────
_OS__KERNEL=""
_OS__ARCH=""
_OS__ID=""
_OS__ID_LIKE=""
_OS__CODENAME=""
_OS__PLATFORM=""
_OS__RELEASE_LOADED=""

# @brief os__kernel — Print the kernel name (`Linux` or `Darwin`). Cached; use instead of `uname -s`.
#
# Stdout: kernel name.
os__kernel() {
  [ -n "${_OS__KERNEL-}" ] || _OS__KERNEL="$(uname -s)"
  echo "$_OS__KERNEL"
  return 0
}

# @brief os__arch — Print the CPU architecture (e.g. `x86_64`, `aarch64`). Cached; use instead of `uname -m`.
#
# Stdout: architecture string.
os__arch() {
  [ -n "${_OS__ARCH-}" ] || _OS__ARCH="$(uname -m)"
  echo "$_OS__ARCH"
  return 0
}

# @brief os__id — Print the `ID` field from `/etc/os-release` (e.g. `ubuntu`, `alpine`).
#
# Stdout: distro ID string, or empty on macOS.
os__id() {
  _os__load_release
  echo "${_OS__ID:-}"
  return 0
}

# @brief os__id_like — Print the `ID_LIKE` field from `/etc/os-release` (space-separated distro family list).
#
# Stdout: distro family string, or empty if absent.
os__id_like() {
  _os__load_release
  echo "${_OS__ID_LIKE:-}"
  return 0
}

# @brief os__platform — Print a canonical platform tag: `debian` | `alpine` | `rhel` | `suse` | `macos`.
#
# Falls back to `debian` for unrecognised Linux distros.
#
# Stdout: one of `debian`, `alpine`, `rhel`, `suse`, `macos`.
os__platform() {
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

# @brief os__release_kernel — Print the kernel identifier used in release asset filenames (`linux` or `darwin`).
#
# Maps the result of `os__kernel` to the lowercase token used by most GitHub
# release naming conventions. Returns 1 with a logged error for unsupported
# kernels so callers can abort cleanly rather than constructing a wrong URL.
#
# Stdout: `linux` or `darwin`.
# Returns: 0 on success, 1 if the kernel is unsupported.
os__release_kernel() {
  case "$(os__kernel)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    *)
      logging__error "os__release_kernel: unsupported kernel '$(os__kernel)'."
      return 1
      ;;
  esac
}

# @brief os__release_arch — Print the CPU architecture token used in release asset filenames.
#
# Maps the result of `os__arch` to the canonical token used by most GitHub
# release naming conventions. Covers all architectures present across the
# install/ modules: amd64, arm64, armv7, i386, ppc64le, s390x, riscv64,
# loong64. Callers that only support a subset should check the result with a
# `case` statement and return an error for unsupported values.
#
# Stdout: one of `amd64`, `arm64`, `armv7`, `i386`, `ppc64le`, `s390x`,
#         `riscv64`, `loong64`.
# Returns: 0 on success, 1 if the architecture is unsupported.
os__release_arch() {
  case "$(os__arch)" in
    x86_64 | amd64 | x64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    armv7l | armv7) printf 'armv7\n' ;;
    i386 | i686) printf 'i386\n' ;;
    ppc64le) printf 'ppc64le\n' ;;
    s390x) printf 's390x\n' ;;
    riscv64) printf 'riscv64\n' ;;
    loong64 | loongarch64) printf 'loong64\n' ;;
    *)
      logging__error "os__release_arch: unsupported architecture '$(os__arch)'."
      return 1
      ;;
  esac
}

# @brief os__require_root — Exit 1 with an error message if the current user is not root.
os__require_root() {
  if ! users__is_root; then
    logging__error 'This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
  fi
  return 0
}

# @brief os__font_dir — Print the platform-appropriate font directory for the current user.
#
# Stdout: `/usr/share/fonts` (root), `~/Library/Fonts` (macOS non-root), or `${XDG_DATA_HOME:-~/.local/share}/fonts` (Linux non-root).
os__font_dir() {
  if users__is_root; then
    echo "/usr/share/fonts"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    echo "${HOME}/Library/Fonts"
  else
    echo "${XDG_DATA_HOME:-${HOME}/.local/share}/fonts"
  fi
  return 0
}

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
os__is_devcontainer_build() {
  [ "${_REMOTE_USER+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER+defined}" = "defined" ] &&
    [ "${_REMOTE_USER_HOME+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER_HOME+defined}" = "defined" ]
}

# @brief os__is_container — Return 0 if running inside a container (Docker, Podman, Kubernetes, CI), 1 otherwise.
#
# Uses the same heuristics as Homebrew's `check-run-command-as-root()` so that
# brew can run as root in devcontainers.
os__is_container() {
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  if [ -f /proc/1/cgroup ] &&
    grep -qE 'azpl_job|actions_job|docker|garden|kubepods' /proc/1/cgroup 2> /dev/null; then
    return 0
  fi
  return 1
}

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
_os__load_release() {
  [ -n "${_OS__RELEASE_LOADED-}" ] && return 0
  if [ -f /etc/os-release ]; then
    _OS__ID="$(grep -m1 '^ID=' /etc/os-release 2> /dev/null |
      sed 's/^ID=//;s/^"//;s/"$//')"
    _OS__ID_LIKE="$(grep -m1 '^ID_LIKE=' /etc/os-release 2> /dev/null |
      sed 's/^ID_LIKE=//;s/^"//;s/"$//')"
    _OS__CODENAME="$(grep -m1 '^VERSION_CODENAME=' /etc/os-release 2> /dev/null |
      sed 's/^VERSION_CODENAME=//;s/^"//;s/"$//')"
    # Fallback: UBUNTU_CODENAME (present on some Ubuntu releases that lack VERSION_CODENAME).
    if [ -z "${_OS__CODENAME-}" ]; then
      _OS__CODENAME="$(grep -m1 '^UBUNTU_CODENAME=' /etc/os-release 2> /dev/null |
        sed 's/^UBUNTU_CODENAME=//;s/^"//;s/"$//')"
    fi
  fi
  _OS__RELEASE_LOADED=1
  return 0
}

# @brief os__codename — Print `VERSION_CODENAME` from `/etc/os-release` (e.g. `jammy`, `bookworm`); empty string if absent or on macOS.
#
# Falls back to `UBUNTU_CODENAME` when `VERSION_CODENAME` is absent.
#
# Stdout: distro codename, or empty string.
os__codename() {
  _os__load_release
  echo "${_OS__CODENAME:-}"
  return 0
}

# @brief os__match_spec <key=value> [...] — Return 0 if the current OS context matches all given key=value conditions.
#
# Reads from _OSPKG_OS_RELEASE (populated by ospkg__detect). Calls ospkg__detect automatically
# if the array is empty. AND logic: all key=value pairs must match. Case-insensitive.
# Supported keys: kernel, arch, id, id_like, pm, version_id, version_codename, and any
# /etc/os-release field.
#
# Returns: 0 if all conditions match, 1 otherwise.
os__match_spec() {
  [ $# -eq 0 ] && return 0
  [ "${#_OSPKG_OS_RELEASE[@]}" -eq 0 ] && ospkg__detect
  local _pair _k _v
  for _pair in "$@"; do
    _k="${_pair%%=*}"
    _v="${_pair#*=}"
    [[ "${_OSPKG_OS_RELEASE[$_k],,}" == "${_v,,}" ]] || return 1
  done
  return 0
}

# @brief os__run_as <user> [--cwd <dir>] -- <command> [args] — Run a command as `<user>`: in-process if already that user, otherwise via `su -l` with bash-quoted argv.
#
# Requires `bash` on PATH for the non-self path.
#
# Args:
#   <user>       Username to run as.
#   --cwd <dir>  Working directory for the command (optional).
#   -- <cmd>...  Command and arguments to execute.
os__run_as() {
  if [ -z "$1" ]; then
    return 1
  fi
  _or_u=$1
  shift
  _or_cd=""
  case $1 in
    --cwd)
      _or_cd=$2
      if [ -z "$_or_cd" ]; then
        return 1
      fi
      shift 2
      ;;
  esac
  case $1 in
    --) shift ;;
  esac
  if [ $# -eq 0 ]; then
    return 1
  fi
  # shellcheck source=lib/users.sh
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/users.sh"
  if [ "$(users__get_current --no-sudo)" = "$_or_u" ]; then
    if [ -n "$_or_cd" ]; then
      (cd "$_or_cd" && "$@")
    else
      "$@"
    fi
    return $?
  fi
  if ! command -v bash > /dev/null 2>&1; then
    logging__error "os__run_as: bash is required to run a command as another user"
    return 1
  fi
  # shellcheck disable=SC2016  # $a is intentionally single-quoted — it is bash's variable, not the current shell's
  _or_c="$(bash -c 'for a; do printf " %q" "$a"; done; echo' sh "$@")"
  _or_c="${_or_c# }" # strip the single leading space; $(...) already strips the trailing newline
  if [ -n "$_or_cd" ]; then
    _or_cd_q="$(bash -c 'printf "%q" "$1"' bash "$_or_cd")"
    su -l "$_or_u" -c "cd ${_or_cd_q} && ${_or_c}"
  else
    su -l "$_or_u" -c "$_or_c"
  fi
  return $?
}
