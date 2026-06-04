#!/bin/sh

# Feature entry point.
#
# Ensure bash >=4 is available, then hand off to the main install script.
#
# Notes
# -----
# This file is the single source of truth for all `install.sh` scripts;
# it is distributed to each feature root.
# Therefore, do not edit copies of this file directly —
# edit this one, and then run `scripts/sync-src.sh` to propagate changes to all features.

set -e

_ensure_bash4() {
  # Case 1: already running in a compatible bash (invoked as 'bash install.sh').
  # $BASH is the path bash used to start itself; resolve it to absolute before
  # any cd can change CWD.  Absolute paths are used directly; relative paths
  # (e.g. ./bash install.sh) are resolved via cd+pwd; bare names should not
  # occur in practice (bash resolves its own argv[0] through PATH), but the
  # -x guard handles the degenerate case safely.
  _BASH_BIN=""
  if [ -n "${BASH_VERSION:-}" ]; then
    _v="${BASH_VERSION%%.*}"
    if [ "${_v:-0}" -ge 4 ]; then
      case "${BASH:-}" in
        /*)
          _BASH_BIN="$BASH"
          ;;
        ?*/*)
          _BASH_BIN="$(cd "$(dirname "$BASH")" 2> /dev/null && pwd)/$(basename "$BASH")"
          [ -x "$_BASH_BIN" ] || _BASH_BIN=""
          ;;
      esac
    fi
  fi

  # Case 2: compatible bash already on the system.
  if [ -z "$_BASH_BIN" ]; then
    _BASH_BIN="$(_find_bash4 2> /dev/null)" || _BASH_BIN=""
  fi

  # Case 3: all compile prerequisites available — build from source.
  if [ -z "$_BASH_BIN" ] && _can_compile; then
    _BASH_BIN="$(_compile_bash)" || _BASH_BIN=""
    [ -n "$_BASH_BIN" ] && export _BASH_INSTALLED_INTERNALLY=1
  fi

  # Case 4: use the OS package manager to install bash directly.
  if [ -z "$_BASH_BIN" ]; then
    _pm="$(_detect_pm 2> /dev/null)" || _pm=""
    if [ -z "$_pm" ]; then
      echo "⛔ bash >=4 unavailable: no compatible bash, build tools, or package manager found." >&2
      exit 1
    fi
    if _pm_needs_root "$_pm" && ! _can_sudo; then
      echo "⛔ bash >=4 unavailable: '${_pm}' requires root or passwordless sudo, neither available." >&2
      exit 1
    fi
    _BASH_BIN="$(_install_bash_pkg "$_pm")" || _BASH_BIN=""
    [ -n "$_BASH_BIN" ] && export _BASH_INSTALLED_BY_PM="$_pm"
  fi

  if [ -z "$_BASH_BIN" ]; then
    echo "⛔ bash >=4 could not be obtained." >&2
    exit 1
  fi

  export _BASH_BIN

  # Scrub every helper function and all intermediate variables from the
  # environment before exec so install.bash inherits a clean namespace.
  # _BASH_BIN, _BASH_INSTALLED_INTERNALLY, and _BASH_INSTALLED_BY_PM are
  # intentionally kept — install.bash reads them in __init__ / __exit__.
  unset -f _have _can_sudo _run_privileged _find_bash4 _ensure_xcode_clt \
    _can_compile _compile_bash _detect_pm _pm_needs_root \
    _install_bash_pkg _ensure_bash4
  unset _v _pm _c _b _ipm _pkg _BASH_VER _BASH_URL _tmpdir _bash_bin _dest_dir
}

_find_bash4() {
  # Print the path to the first bash >=4 found; return 1 if none.
  #
  # Probes $PATH first, then well-known install prefixes so that a just-installed
  # bash (e.g. Homebrew's /opt/homebrew/bin/bash) is discovered even in a shell
  # session whose PATH has not yet been updated.  Also probes the user-local bin
  # where a previously compiled bootstrap bash may have been kept.

  for _c in bash \
    /usr/local/bin/bash \
    /opt/homebrew/bin/bash \
    /opt/local/bin/bash \
    "${HOME:-/root}/.local/bin/bash" \
    "${HOME:-/root}/.nix-profile/bin/bash" \
    /nix/var/nix/profiles/default/bin/bash; do
    command -v "$_c" > /dev/null 2>&1 || continue
    # shellcheck disable=SC2016
    _v=$("$_c" -c 'echo ${BASH_VERSINFO[0]}' 2> /dev/null) || continue
    [ "${_v:-0}" -ge 4 ] && {
      command -v "$_c"
      return 0
    }
  done
  return 1
}

_compile_bash() {
  # Compile bash from GNU source and install to $HOME/.local/bin/bash.
  #
  # Prints the installed binary path to stdout; all status messages go to stderr.
  # The caller exports _BASH_BIN and _BASH_INSTALLED_INTERNALLY so install.bash
  # can register it for cleanup via install__track_internal_path / ospkg__cleanup_resources,
  # respecting KEEP_BUILD_DEPS.

  _BASH_VER="5.3"
  _BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${_BASH_VER}.tar.gz"

  echo "🔍 bash >=4 not found — compiling bash ${_BASH_VER} from source." >&2

  # macOS: Xcode CLT provides make and cc; install it headlessly if absent.
  [ "$(uname -s)" = "Darwin" ] && _ensure_xcode_clt

  _tmpdir="$(mktemp -d /tmp/bash-src.XXXXXX)"

  echo "📦 Downloading bash ${_BASH_VER} source..." >&2
  if _have curl; then
    curl -fsSL --compressed \
      --retry 5 --retry-delay 5 --retry-connrefused \
      -H "User-Agent: devfeats" \
      "$_BASH_URL" | tar xz -C "$_tmpdir"
  else
    wget -qO- "$_BASH_URL" | tar xz -C "$_tmpdir"
  fi || {
    rm -rf "$_tmpdir"
    echo "⛔ Failed to download or extract bash ${_BASH_VER} source." >&2
    return 1
  }

  echo "🔨 Compiling bash ${_BASH_VER} (this may take a minute)..." >&2
  (
    cd "$_tmpdir/bash-${_BASH_VER}" &&
      ./configure --without-bash-malloc --without-readline > /dev/null 2>&1 &&
      make > /dev/null 2>&1
  ) || {
    rm -rf "$_tmpdir"
    echo "⛔ Bash compilation failed." >&2
    return 1
  }

  _bash_bin="$_tmpdir/bash-${_BASH_VER}/bash"
  if [ ! -x "$_bash_bin" ]; then
    rm -rf "$_tmpdir"
    echo "⛔ Compiled bash binary not found after make." >&2
    return 1
  fi

  # Install to a persistent, user-writable location.  Source tree is no longer
  # needed once the binary is copied.
  _dest_dir="${HOME:-/root}/.local/bin"
  mkdir -p "$_dest_dir"
  cp "$_bash_bin" "$_dest_dir/bash"
  chmod a+x "$_dest_dir/bash"
  rm -rf "$_tmpdir"

  echo "✅ bash ${_BASH_VER} compiled and installed to '${_dest_dir}/bash'." >&2
  printf '%s\n' "${_dest_dir}/bash"
}

_install_bash_pkg() {
  _ipm="$1"
  echo "📦 Installing bash via ${_ipm}..." >&2
  case "$_ipm" in
    apk) _run_privileged apk add --no-cache bash || return 1 ;;
    apt-get)
      export DEBIAN_FRONTEND=noninteractive
      _run_privileged apt-get update || return 1
      _run_privileged apt-get install -y --no-install-recommends bash || return 1
      ;;
    dnf) _run_privileged dnf install -y bash || return 1 ;;
    microdnf) _run_privileged microdnf install -y bash || return 1 ;;
    yum) _run_privileged yum install -y bash || return 1 ;;
    zypper) _run_privileged zypper --non-interactive install bash || return 1 ;;
    pacman) _run_privileged pacman -S --noconfirm --needed bash || return 1 ;;
    brew) brew install bash || return 1 ;;
    nix-env) nix-env -iA nixpkgs.bash || return 1 ;;
    port) _run_privileged port install bash || return 1 ;;
    *)
      echo "⛔ Unknown package manager '${_ipm}'." >&2
      return 1
      ;;
  esac
  # Locate the newly installed bash — all destinations are already in _find_bash4's probe list.
  _b="$(_find_bash4 2> /dev/null)" || {
    echo "⛔ bash >=4 not found after installing via ${_ipm}." >&2
    return 1
  }
  echo "$_b"
}

_have() {
  command -v "$1" > /dev/null 2>&1
}

_can_sudo() {
  [ "$(id -u)" = "0" ] && return 0
  _have sudo && sudo -n true > /dev/null 2>&1
}

_run_privileged() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

_ensure_xcode_clt() {
  # Headlessly install Xcode Command Line Tools on macOS.
  #
  # Required before compiling bash from source (provides make and cc).

  if xcode-select -p > /dev/null 2>&1; then
    echo "✅ Xcode Command Line Tools already installed at '$(xcode-select -p)'." >&2
    return 0
  fi
  echo "🔍 Xcode Command Line Tools not found — installing headlessly." >&2
  # Headless CLT install pattern: create sentinel, find the softwareupdate
  # package name, install, remove sentinel.
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  _pkg="$(softwareupdate -l 2>&1 |
    grep -E '\*.*Command Line Tools' |
    tail -1 |
    sed 's/.*\* //')" || true
  if [ -z "$_pkg" ]; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    echo "⛔ No 'Command Line Tools' package found in softwareupdate -l." >&2
    echo "ℹ️ Install manually with: xcode-select --install" >&2
    exit 1
  fi
  echo "📦 Installing via softwareupdate: '${_pkg}'" >&2
  softwareupdate -i "$_pkg" --verbose
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  echo "✅ Xcode Command Line Tools installed." >&2
  return 0
}

_can_compile() {
  # On Darwin: make+cc may need Xcode CLT (installable when _can_sudo).
  # On Linux: all tools must already be present — no PM install of build tools.
  _have tar || return 1
  { _have curl || _have wget; } || return 1
  if [ "$(uname -s)" = "Darwin" ]; then
    { _have make && _have cc; } || _can_sudo || return 1
    return 0
  fi
  _have make || return 1
  { _have cc || _have gcc; } || return 1
  return 0
}

_detect_pm() {
  # Print the name of the first available package manager; return 1 if none.
  if [ "$(uname -s)" = "Darwin" ]; then
    for _pm in brew port nix-env; do
      _have "$_pm" && {
        echo "$_pm"
        return 0
      }
    done
    return 1
  fi
  for _pm in apt-get apk dnf microdnf yum zypper pacman brew nix-env port; do
    _have "$_pm" && {
      echo "$_pm"
      return 0
    }
  done
  return 1
}

_pm_needs_root() {
  case "$1" in
    brew | nix-env) return 1 ;;
    *) return 0 ;;
  esac
}

_ensure_bash4
exec "$_BASH_BIN" "$(dirname "$0")/install.bash" "$@"
