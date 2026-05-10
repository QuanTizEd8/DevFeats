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

# @brief os__require_root — Exit 1 with an error message if the current user is not root.
os__require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    logging__error 'This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
  fi
  return 0
}

# @brief os__font_dir — Print the platform-appropriate font directory for the current user.
#
# Stdout: `/usr/share/fonts` (root), `~/Library/Fonts` (macOS non-root), or `${XDG_DATA_HOME:-~/.local/share}/fonts` (Linux non-root).
os__font_dir() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "/usr/share/fonts"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    echo "${HOME}/Library/Fonts"
  else
    echo "${XDG_DATA_HOME:-${HOME}/.local/share}/fonts"
  fi
  return 0
}

# @brief os__is_devcontainer_build — Return 0 when this script is being executed by the devcontainer CLI as a feature installer, 1 otherwise.
#
# Uses three independent signals that must all be true:
#
# 1. We are running inside a container (`os__is_container`).
#    This rules out host-side tools (e.g. SysSet) that may set the vars below
#    but always run on a bare host.
#
# 2. The devcontainer CLI's four built-in env vars are present.
#    The CLI unconditionally writes all of them into
#    `devcontainer-features.builtin.env` and sources it before invoking
#    `install.sh`:
#      _REMOTE_USER, _CONTAINER_USER, _REMOTE_USER_HOME, _CONTAINER_USER_HOME
#    Checking both `_REMOTE_USER` and `_CONTAINER_USER` (a devcontainer-spec
#    concept) prevents a false positive if only `_REMOTE_USER` is set by
#    another tool (e.g. SysSet running inside a container).
#
# 3. The CLI's feature staging directory is present on disk.
#    The devcontainer CLI creates `/tmp/dev-container-features/` during the
#    Docker build step and extracts all feature sources there.  This directory
#    does not exist at container runtime, providing a build-vs-runtime
#    discriminator that no env-var convention can fake.
#
# Returns: 0 in devcontainer feature-install context, 1 otherwise.
os__is_devcontainer_build() {
  os__is_container &&
    [ "${_REMOTE_USER+defined}" = "defined" ] &&
    [ "${_CONTAINER_USER+defined}" = "defined" ] &&
    [ -d /tmp/dev-container-features ]
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

# _os__load_release (private)
# Parses /etc/os-release once and caches ID, ID_LIKE, and VERSION_CODENAME.
# Uses grep/sed rather than sourcing the file to avoid env pollution.
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
