#!/usr/bin/env bash
# Cross-distro package manager abstraction: install, update, clean, and track dependencies.
#
# Detects the host package manager (`apt`, `apk`, `brew`, `dnf`/`yum`, `zypper`)
# automatically. Supports grouping packages into build-time and run-time
# dependency groups for later cleanup.

[[ -n "${_OSPKG__LIB_LOADED-}" ]] && return 0
_OSPKG__LIB_LOADED=1

_OSPKG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/os.sh
. "$_OSPKG_LIB_DIR/os.sh"
# shellcheck source=lib/net.sh
. "$_OSPKG_LIB_DIR/net.sh"
# shellcheck source=lib/logging.sh
. "$_OSPKG_LIB_DIR/logging.sh"
# shellcheck source=lib/json.sh
. "$_OSPKG_LIB_DIR/json.sh"
# shellcheck source=lib/install/yq.sh
. "$_OSPKG_LIB_DIR/install/yq.sh"
# shellcheck source=lib/verify.sh
[[ -z "${_VERIFY__LIB_LOADED-}" ]] && . "$_OSPKG_LIB_DIR/verify.sh"
# shellcheck source=lib/users.sh
. "$_OSPKG_LIB_DIR/users.sh"
# shellcheck source=lib/file.sh
. "$_OSPKG_LIB_DIR/file.sh"

# ── Internal state ────────────────────────────────────────────────────────────
_OSPKG_DETECTED=false
_OSPKG_UPDATED=false
_OSPKG_PKG_MNGR=
_OSPKG_FAMILY=
_OSPKG_INSTALL=()
_OSPKG_UPDATE=()
_OSPKG_CLEAN=
_OSPKG_LISTS_PATH=
_OSPKG_LISTS_PATTERN=
_OSPKG_PREFER_LINUXBREW=false
_OSPKG_YQ_BIN=
declare -A _OSPKG_OS_RELEASE=()

# ── Private: clean functions ──────────────────────────────────────────────────

# @brief _ospkg_clean_apk — Remove the Alpine APK package cache (`/var/cache/apk/*`).
_ospkg_clean_apk() {
  users__run_privileged rm -rf /var/cache/apk/*
  return 0
}

# @brief _ospkg_clean_apt — Clean the APT package cache and remove downloaded index files.
#
# Runs `apt-get clean` (removes cached `.deb` files) then `apt-get dist-clean`
# (APT 3.x; removes `/var/lib/apt/lists/*` while preserving Release files).
# Falls back to a direct `rm -rf /var/lib/apt/lists/*` on APT 2.x and below
# where `dist-clean` does not exist.
_ospkg_clean_apt() {
  users__run_privileged apt-get clean
  # apt-get dist-clean is an APT 3.x command that removes /var/lib/apt/lists/*
  # while preserving the Release/InRelease files for security.
  # Docs: https://manpages.debian.org/unstable/apt/apt-get.8.en.html#distclean
  # Fall back to rm -rf on older APT (2.x and below) where the command does not exist.
  users__run_privileged apt-get dist-clean 2> /dev/null || users__run_privileged rm -rf /var/lib/apt/lists/*
  return 0
}

# @brief _ospkg_clean_dnf — Clean the dnf/yum package cache and remove cached metadata.
_ospkg_clean_dnf() {
  users__run_privileged "$_OSPKG_PKG_MNGR" clean all 2> /dev/null || true
  users__run_privileged rm -rf /var/cache/dnf/* /var/cache/yum/*
  return 0
}

# @brief _ospkg_clean_pacman — Remove all cached pacman packages and unused sync databases.
_ospkg_clean_pacman() {
  users__run_privileged pacman -Scc --noconfirm
  return 0
}

# @brief _ospkg_clean_zypper — Clean all zypper repository caches.
_ospkg_clean_zypper() {
  users__run_privileged zypper clean --all
  return 0
}

# @brief _ospkg_clean_brew — Run `brew cleanup --prune=all` to remove stale Homebrew downloads.
_ospkg_clean_brew() {
  _ospkg_brew_run cleanup --prune=all 2> /dev/null || true
  return 0
}

# @brief _ospkg_update_cmd — Run the package-manager index update command (`_OSPKG_UPDATE`), normalising non-fatal exit codes to 0.
#
# Wraps `_OSPKG_UPDATE` for use with `net__fetch_with_retry`. Non-fatal PM
# codes normalised to 0:
#   - dnf/yum exit 100  — "updates available" (informational, not a failure).
#   - zypper exit 6     — `ZYPPER_EXIT_INF_REPOS_SKIPPED`: at least one repo
#                         was unreachable but all reachable repos refreshed OK.
# APT index-corruption error strings (Hash Sum mismatch, Failed to fetch, etc.)
# are detected and force-retried even when APT itself exits 0.
#
# Returns: 0 on success; 2 for non-transient configuration errors (malformed
# source lists, parse errors) so `net__fetch_with_retry --bail-on 2` skips
# pointless retries; other non-zero codes pass through unchanged for retry.
_ospkg_update_cmd() {
  [[ ${#_OSPKG_UPDATE[@]} -eq 0 ]] && return 0
  local _rc=0 _err_tmp
  _err_tmp="$(mktemp)"
  # Keep interactive mode possible on TTY, but prevent PMs from draining
  # caller-provided stdin in piped/non-interactive contexts.
  # Use || _rc=$? on each branch so set -e callers do not abort before we can
  # normalise non-fatal exit codes (e.g. dnf check-update exits 100 when
  # updates are available; zypper refresh exits 6 for skipped repos).
  if [[ -t 0 ]]; then
    "${_OSPKG_UPDATE[@]}" 2> "$_err_tmp" || _rc=$?
  elif [[ "$_OSPKG_PKG_MNGR" == "apt-get" && -z "${DEBIAN_FRONTEND-}" ]]; then
    DEBIAN_FRONTEND=noninteractive "${_OSPKG_UPDATE[@]}" < /dev/null 2> "$_err_tmp" || _rc=$?
  else
    "${_OSPKG_UPDATE[@]}" < /dev/null 2> "$_err_tmp" || _rc=$?
  fi
  cat "$_err_tmp" >&2
  # APT can occasionally report index corruption/partial fetch failures while
  # still exiting successfully; force retry when those signatures appear.
  if [[ "$_OSPKG_PKG_MNGR" == "apt-get" ]] && grep -qiE \
    'Hash Sum mismatch|Failed to fetch|Some index files failed to download' \
    "$_err_tmp" 2> /dev/null; then
    _rc=100
    users__run_privileged apt-get clean > /dev/null 2>&1 || true
    users__run_privileged apt-get dist-clean 2> /dev/null || users__run_privileged rm -rf /var/lib/apt/lists/* 2> /dev/null || true
  fi
  [[ "$_OSPKG_PKG_MNGR" == "dnf" || "$_OSPKG_PKG_MNGR" == "yum" ]] &&
    [[ $_rc -eq 100 ]] && rm -f "$_err_tmp" && return 0
  [[ "$_OSPKG_PKG_MNGR" == "zypper" ]] && [[ $_rc -eq 6 ]] && rm -f "$_err_tmp" && return 0
  if [[ $_rc -ne 0 ]]; then
    # Detect non-transient configuration errors — retrying will never fix these.
    if grep -qiE 'Malformed line|source list could not be read|parse error|invalid source' \
      "$_err_tmp" 2> /dev/null; then
      logging__error "Package list update failed due to a configuration error — not retrying."
      rm -f "$_err_tmp"
      return 2
    fi
  fi
  rm -f "$_err_tmp"
  return "$_rc"
}

# @brief _ospkg_dnf_bin — Print the name of a full-featured `dnf`-compatible binary (`dnf` or `yum`), or return 1.
#
# `microdnf` does not implement the `copr` or `module` subcommands. This
# helper resolves a usable binary for those operations using the following
# priority:
#   1. Full `dnf` in PATH — always preferred, even when microdnf is the
#      detected package manager.
#   2. `yum` as the detected PM — supports copr/module via plugins on older
#      RHEL/CentOS.
#   3. Neither available — logs an error and returns 1.
#
# Stdout: `dnf` or `yum`.
# Returns: 0 on success, 1 if no suitable binary is found.
_ospkg_dnf_bin() {
  if command -v dnf > /dev/null 2>&1; then
    echo "dnf"
    return 0
  fi
  if [[ "$_OSPKG_PKG_MNGR" == "yum" ]]; then
    echo "yum"
    return 0
  fi
  logging__error "'${_OSPKG_PKG_MNGR}' does not support copr/module subcommands; install full dnf first."
  return 1
}

# ── Private: key / repo helpers ──────────────────────────────────────────────

# @brief _ospkg_key_effective_path <dest> <dearmor> — Print the filesystem path the key will actually be written to, accounting for dearmor mode.
#
# When `dearmor` is `false` and `<dest>` ends in `.gpg`, the key is stored as
# a raw `.key` file (the `.gpg` extension is reserved for dearmored binaries
# in APT conventions). All other combinations return `<dest>` unchanged.
#
# Args:
#   <dest>     Intended destination path for the key file.
#   <dearmor>  `true`, `false`, or `auto` (empty/`null` treated as `auto`).
#
# Stdout: effective file path.
_ospkg_key_effective_path() {
  local _dest="$1" _dearmor="${2:-auto}"
  [[ -z "${_dearmor}" || "${_dearmor}" == "null" ]] && _dearmor=auto
  if [[ "${_dearmor}" == "false" && "${_dest}" == *.gpg ]]; then
    printf '%s' "${_dest%.gpg}.key"
  else
    printf '%s' "${_dest}"
  fi
}

# @brief _ospkg_install_key_entry <url> <dest> [<dearmor>] [<fingerprint>] — Download and install a GPG signing key for a package repository.
#
# Supports three dearmoring modes:
#   `true`  — always pipe through `gpg --dearmor` regardless of `<dest>` extension.
#   `false` — store the raw file (using `.key` instead of `.gpg` extension when needed).
#   `auto`  — dearmor when `<dest>` ends in `.gpg`; raw otherwise (default).
# When `<url>` is empty/null and `<fingerprint>` is provided, the key is
# fetched from HKP keyservers via `verify__gpg_fetch_key_by_fingerprint`.
#
# Args:
#   <url>          URL to download the key from (may be empty when fingerprint is given).
#   <dest>         Destination path for the installed key file.
#   [dearmor]      Dearmoring mode: `true`, `false`, or `auto` (default).
#   [fingerprint]  40-char hex GPG fingerprint (used when URL is absent).
#
# Returns: 0 on success, 1 on error.
_ospkg_install_key_entry() {
  local _url="$1" _dest="$2" _dearmor="${3:-auto}" _fingerprint="${4:-}"
  [[ -z "${_dearmor}" || "${_dearmor}" == "null" ]] && _dearmor=auto
  [[ -z "${_fingerprint}" || "${_fingerprint}" == "null" ]] && _fingerprint=""
  local _target
  _target="$(_ospkg_key_effective_path "$_dest" "$_dearmor")"
  mkdir -p "$(dirname "$_dest")"

  # Fingerprint-only: no URL, fetch from keyserver.
  if [[ -z "${_url}" || "${_url}" == "null" ]]; then
    if [[ -n "${_fingerprint}" ]]; then
      logging__info "Installing key by fingerprint ${_fingerprint} → ${_target}"
      _ospkg_install_key_by_fingerprint "${_fingerprint}" "${_target}"
      return $?
    fi
    logging__error "_ospkg_install_key_entry: neither url nor fingerprint provided."
    return 1
  fi

  case "${_dearmor}" in
    true)
      logging__info "Fetching and dearmoring key (dearmor: true) → ${_target}"
      net__fetch_url_stdout "$_url" | verify__gpg_dearmor_stream "${_target}" "devfeats-ospkg-internals"
      ;;
    false)
      logging__info "Fetching key (dearmor: false) → ${_target}"
      net__fetch_url_file "$_url" "${_target}"
      ;;
    auto)
      if [[ "${_dest}" == *.gpg ]]; then
        logging__info "Fetching and dearmoring key (dest ends in .gpg) → ${_target}"
        net__fetch_url_stdout "$_url" | verify__gpg_dearmor_stream "${_target}" "devfeats-ospkg-internals"
      else
        logging__info "Fetching key → ${_target}"
        net__fetch_url_file "$_url" "${_target}"
      fi
      ;;
    *)
      logging__error "_ospkg_install_key_entry: invalid dearmor (use true, false, or auto): '${_dearmor}'"
      return 1
      ;;
  esac
  users__run_privileged chmod 0644 "${_target}"
  return 0
}

# @brief _ospkg_install_key_by_fingerprint <fingerprint> <dest> — Fetch a GPG signing key by fingerprint and install it to `<dest>`.
#
# Delegates to `verify__gpg_fetch_key_by_fingerprint` with the
# `devfeats-ospkg-internals` tracking group.
#
# Args:
#   <fingerprint>  40-char hex GPG key fingerprint.
#   <dest>         Destination path for the dearmored binary keyring.
#
# Returns: 0 on success, 1 if the key cannot be fetched from any keyserver.
_ospkg_install_key_by_fingerprint() {
  local _fingerprint="$1" _dest="$2"
  verify__gpg_fetch_key_by_fingerprint "$_fingerprint" "$_dest" "devfeats-ospkg-internals"
}

# @brief _ospkg_expand_content_vars <content> — Substitute `${KEY}` tokens in `<content>` using values from `_OSPKG_OS_RELEASE`.
#
# Iterates over all keys in the `_OSPKG_OS_RELEASE` associative array and
# replaces `${KEY}` occurrences in `<content>`. Unknown tokens (keys not
# present in the array) are left unchanged. Prints the result without a
# trailing newline.
#
# Args:
#   <content>  String containing zero or more `${KEY}` placeholder tokens.
#
# Stdout: expanded string without trailing newline.
_ospkg_expand_content_vars() {
  local _content="$1" _k
  for _k in "${!_OSPKG_OS_RELEASE[@]}"; do
    _content="${_content//\$\{${_k}\}/${_OSPKG_OS_RELEASE[$_k]}}"
  done
  printf '%s' "$_content"
  return 0
}

# @brief _ospkg_install_repo_content <content> — Append expanded repository configuration `<content>` to the appropriate PM config file for the current OS.
#
# Calls `_ospkg_expand_content_vars` to substitute `${KEY}` tokens before
# writing. Routes to the correct file based on `_OSPKG_FAMILY`:
#   apt     → `/etc/apt/sources.list.d/syspkg-installer.list`
#   apk     → `/etc/apk/repositories` (one repo URL per non-blank line)
#   dnf/yum → `/etc/yum.repos.d/syspkg-installer.repo`
#   zypper  → `/etc/zypp/repos.d/syspkg-installer.repo`
#   pacman  → `/etc/pacman.d/syspkg-installer.conf` (with `Include =` wired into `pacman.conf`)
# Uses `file__append_privileged` so writes succeed whether or not the current
# process is root.
#
# Args:
#   <content>  Repository config content, possibly containing `${KEY}` tokens.
#
# Returns: 0 always.
_ospkg_install_repo_content() {
  local _content
  _content="$(_ospkg_expand_content_vars "$1")"
  if [[ "$_OSPKG_FAMILY" = "apt" ]]; then
    printf '%s' "$_content" | file__append_privileged /etc/apt/sources.list.d/syspkg-installer.list
    logging__info "Appended to /etc/apt/sources.list.d/syspkg-installer.list"
  elif [[ "$_OSPKG_FAMILY" = "apk" ]]; then
    local _rline
    while IFS= read -r _rline; do
      [[ -z "${_rline:-}" || "${_rline}" =~ ^[[:space:]]*# ]] && continue
      printf '%s\n' "$_rline" | file__append_privileged /etc/apk/repositories
      _OSPKG_APK_ADDED_REPOS+=("$_rline")
      logging__info "Added APK repo: ${_rline}"
    done <<< "$_content"
  elif [[ "$_OSPKG_FAMILY" = "dnf" ]]; then
    printf '%s' "$_content" | file__append_privileged /etc/yum.repos.d/syspkg-installer.repo
    logging__info "Appended to /etc/yum.repos.d/syspkg-installer.repo"
  elif [[ "$_OSPKG_FAMILY" = "zypper" ]]; then
    printf '%s' "$_content" | file__append_privileged /etc/zypp/repos.d/syspkg-installer.repo
    logging__info "Appended to /etc/zypp/repos.d/syspkg-installer.repo"
  elif [[ "$_OSPKG_FAMILY" = "pacman" ]]; then
    users__run_privileged mkdir -p /etc/pacman.d
    printf '%s' "$_content" | file__append_privileged /etc/pacman.d/syspkg-installer.conf
    grep -qxF 'Include = /etc/pacman.d/syspkg-installer.conf' /etc/pacman.conf ||
      printf 'Include = /etc/pacman.d/syspkg-installer.conf\n' | file__append_privileged /etc/pacman.conf
    logging__info "Written to /etc/pacman.d/syspkg-installer.conf"
  fi
  return 0
}

# ── Private: brew user/root handling ─────────────────────────────────────────

# @brief _ospkg_brew_run <args...> — Run `brew` with the correct user context, working around Homebrew's root restriction.
#
# Homebrew refuses to run as root on bare-metal macOS. Three cases are handled:
#   Non-root           → run `brew` directly.
#   Root in container  → run `brew` directly (Homebrew explicitly allows root
#                        in containers via `HOMEBREW_ALLOW_INSTALL_FROM_API`).
#   Root on bare metal → `su` to the owner of the Homebrew prefix and run
#                        `brew` as that user via `users__run_as`.
#
# Args:
#   <args...>  Arguments forwarded verbatim to `brew`.
#
# Returns: exit code of `brew`.
_ospkg_brew_run() {
  if ! users__is_root; then
    brew "$@"
    return
  fi
  if os__is_container; then
    brew "$@"
    return
  fi
  # Bare-metal root: su to the owner of the Homebrew prefix.
  local _prefix _owner
  _prefix="$(brew --prefix 2> /dev/null)" || {
    logging__error "Could not determine Homebrew prefix."
    return 1
  }
  _owner="$(stat -f '%Su' "$_prefix" 2> /dev/null || stat -c '%U' "$_prefix" 2> /dev/null)"
  if [[ -z "${_owner:-}" || "$_owner" == "root" ]]; then
    brew "$@"
    return
  fi
  logging__info "Running brew as user '${_owner}' (brew prefix owner)."
  users__run_as "$_owner" -- brew "$@"
  return 0
}

# ── Private: yq auto-installer ────────────────────────────────────────────────

# @brief _ospkg_ensure_yq — Ensure `yq` (mikefarah/yq) is available, installing it if needed. Caches the binary path in `_OSPKG_YQ_BIN`.
#
# Fast path: `_OSPKG_YQ_BIN` is already set and the binary passes the
# mikefarah compatibility check (`_install__yq_compatible`). Slow path:
# delegates to `install__yq --context internal` and caches the result.
#
# Side effects: sets `_OSPKG_YQ_BIN` to the absolute path of the installed binary.
# Returns: 0 on success, 1 if yq cannot be installed.
_ospkg_ensure_yq() {
  # Fast path: already cached and still compatible.
  if [[ -n "${_OSPKG_YQ_BIN:-}" ]] && [[ -x "${_OSPKG_YQ_BIN}" ]] && _install__yq_compatible "${_OSPKG_YQ_BIN}"; then
    return 0
  fi
  local _yq_out_dir _yq_out_file
  _OSPKG_YQ_BIN=""
  _yq_out_dir="$(file__tmpdir "ospkg/yq")"
  _yq_out_file="$(mktemp "${_yq_out_dir}/install_yq_XXXXXX")" || {
    logging__error "yq could not be installed."
    return 1
  }
  install__yq \
    --context internal \
    --owner-group devfeats-ospkg-internals \
    --method binary \
    --if-exists skip > "${_yq_out_file}" || {
    logging__error "yq could not be installed."
    return 1
  }
  _OSPKG_YQ_BIN="$(awk 'NF{last=$0} END{print last}' "${_yq_out_file}")"
  [[ -n "${_OSPKG_YQ_BIN}" && -x "${_OSPKG_YQ_BIN}" ]] || {
    logging__error "install__yq did not return a usable yq path."
    return 1
  }
  _install__yq_compatible "${_OSPKG_YQ_BIN}" || {
    logging__error "yq could not be installed (or installed binary is incompatible)."
    return 1
  }
  return 0
}

# ── Private: PM configuration helpers ────────────────────────────────────────
# Each _ospkg_set_* function configures the internal state for one PM family.
# Called only from ospkg__detect().

_ospkg_set_apt() {
  logging__detect "Detected ecosystem: APT (tool: apt-get)"
  _OSPKG_FAMILY="apt"
  _OSPKG_PKG_MNGR="apt-get"
  _OSPKG_UPDATE=(users__run_privileged apt-get update)
  _OSPKG_INSTALL=(users__run_privileged apt-get -y install --no-install-recommends)
  _OSPKG_CLEAN=_ospkg_clean_apt
  _OSPKG_LISTS_PATH="/var/lib/apt/lists"
  _OSPKG_LISTS_PATTERN="*_Packages*"
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[deb_arch]="$(dpkg --print-architecture 2> /dev/null || uname -m)"
  return 0
}

_ospkg_set_apk() {
  logging__detect "Detected ecosystem: APK (tool: apk)"
  _OSPKG_FAMILY="apk"
  _OSPKG_PKG_MNGR="apk"
  _OSPKG_UPDATE=(users__run_privileged apk update)
  _OSPKG_INSTALL=(users__run_privileged apk add --no-cache)
  _OSPKG_CLEAN=_ospkg_clean_apk
  _OSPKG_LISTS_PATH="/var/cache/apk"
  _OSPKG_LISTS_PATTERN="APKINDEX*"
  _OSPKG_OS_RELEASE[pm]="apk"
  return 0
}

_ospkg_set_dnf() {
  logging__detect "Detected ecosystem: DNF (tool: dnf)"
  _OSPKG_FAMILY="dnf"
  _OSPKG_PKG_MNGR="dnf"
  _OSPKG_UPDATE=(users__run_privileged dnf check-update)
  _OSPKG_INSTALL=(users__run_privileged dnf -y install)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH="/var/cache/dnf"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="dnf"
  return 0
}

_ospkg_set_microdnf() {
  logging__detect "Detected ecosystem: DNF (tool: microdnf)"
  _OSPKG_FAMILY="dnf"
  _OSPKG_PKG_MNGR="microdnf"
  _OSPKG_UPDATE=()
  _OSPKG_INSTALL=(users__run_privileged microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH=""
  _OSPKG_LISTS_PATTERN=""
  _OSPKG_OS_RELEASE[pm]="dnf"
  return 0
}

_ospkg_set_yum() {
  logging__detect "Detected ecosystem: YUM (tool: yum)"
  _OSPKG_FAMILY="dnf"
  _OSPKG_PKG_MNGR="yum"
  _OSPKG_UPDATE=(users__run_privileged yum check-update)
  _OSPKG_INSTALL=(users__run_privileged yum -y install)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH="/var/cache/yum"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="yum"
  return 0
}

_ospkg_set_zypper() {
  logging__detect "Detected ecosystem: Zypper (tool: zypper)"
  _OSPKG_FAMILY="zypper"
  _OSPKG_PKG_MNGR="zypper"
  _OSPKG_UPDATE=(users__run_privileged zypper --non-interactive refresh)
  _OSPKG_INSTALL=(users__run_privileged zypper --non-interactive install)
  _OSPKG_CLEAN=_ospkg_clean_zypper
  _OSPKG_LISTS_PATH="/var/cache/zypp/raw"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="zypper"
  return 0
}

_ospkg_set_pacman() {
  logging__detect "Detected ecosystem: Pacman (tool: pacman)"
  _OSPKG_FAMILY="pacman"
  _OSPKG_PKG_MNGR="pacman"
  _OSPKG_UPDATE=(users__run_privileged pacman -Sy --noconfirm)
  _OSPKG_INSTALL=(users__run_privileged pacman -S --noconfirm --needed)
  _OSPKG_CLEAN=_ospkg_clean_pacman
  _OSPKG_LISTS_PATH="/var/lib/pacman/sync"
  _OSPKG_LISTS_PATTERN="*.db"
  _OSPKG_OS_RELEASE[pm]="pacman"
  return 0
}

_ospkg_set_brew() {
  local _label="${1:-Linux}"
  logging__detect "Detected ecosystem: Homebrew (tool: brew) [${_label}]"
  _OSPKG_FAMILY="brew"
  _OSPKG_PKG_MNGR="brew"
  _OSPKG_UPDATE=(_ospkg_brew_run update)
  _OSPKG_INSTALL=(_ospkg_brew_run install)
  _OSPKG_CLEAN=_ospkg_clean_brew
  _OSPKG_LISTS_PATH=""
  _OSPKG_LISTS_PATTERN=""
  _OSPKG_OS_RELEASE[pm]="brew"
  return 0
}

# _ospkg_load_linux_release
# Parses /etc/os-release into _OSPKG_OS_RELEASE (merges; does not overwrite pm).
_ospkg_load_linux_release() {
  if [[ -f /etc/os-release ]]; then
    local _key _val
    while IFS='=' read -r _key _val; do
      [[ -z "${_key-}" || "$_key" =~ ^# ]] && continue
      _val="${_val#\"}"
      _val="${_val%\"}"
      _val="${_val#\'}"
      _val="${_val%\'}"
      [[ "$_key" == "pm" ]] && continue # never overwrite pm
      _OSPKG_OS_RELEASE["${_key,,}"]="$_val"
    done < /etc/os-release
  fi
  _OSPKG_OS_RELEASE[kernel]="linux"
  _OSPKG_OS_RELEASE[arch]="$(uname -m)"
  logging__inspect "OS context: pm=${_OSPKG_OS_RELEASE[pm]-} arch=${_OSPKG_OS_RELEASE[arch]-} id=${_OSPKG_OS_RELEASE[id]-} id_like=${_OSPKG_OS_RELEASE[id_like]-} version_id=${_OSPKG_OS_RELEASE[version_id]-} version_codename=${_OSPKG_OS_RELEASE[version_codename]-}"
  return 0
}

# ── Public: ospkg__detect ────────────────────────────────────────────────────
# @brief ospkg__detect — Detect the package manager and populate internal state. Idempotent; called automatically by all other `ospkg__*` functions.
#
# Respects `_OSPKG_PREFER_LINUXBREW`: when true, brew is checked before the
# native Linux PM chain (no effect on macOS where brew is always used).
#
# Returns: 0 on success, 1 if no supported package manager is found.
ospkg__detect() {
  [[ "$_OSPKG_DETECTED" == true ]] && return 0

  local _kernel
  _kernel="$(uname -s)"

  if [[ "$_kernel" == "Darwin" ]]; then
    # macOS: Homebrew is the only supported package manager.
    if ! type brew > /dev/null 2>&1; then
      logging__error "Homebrew (brew) not found on macOS."
      logging__error "Install Homebrew first: https://brew.sh"
      logging__error "Or add the 'install-homebrew' devcontainer feature."
      return 1
    fi
    _ospkg_set_brew "macOS"
    _OSPKG_OS_RELEASE[kernel]="darwin"
    _OSPKG_OS_RELEASE[id]="macos"
    _OSPKG_OS_RELEASE[id_like]="macos"
    _OSPKG_OS_RELEASE[version_id]="$(sw_vers -productVersion 2> /dev/null || echo "")"
    _OSPKG_OS_RELEASE[arch]="$(uname -m)"
    logging__inspect "OS context: pm=brew arch=${_OSPKG_OS_RELEASE[arch]-} id=macos version_id=${_OSPKG_OS_RELEASE[version_id]-}"
    _OSPKG_DETECTED=true
    return 0
  fi

  # Linux: optionally prefer Linuxbrew before the native PM chain.
  if [[ "${_OSPKG_PREFER_LINUXBREW:-false}" == "true" ]] && type brew > /dev/null 2>&1; then
    _ospkg_set_brew "Linux/Linuxbrew"
    _ospkg_load_linux_release
    _OSPKG_DETECTED=true
    return 0
  fi

  # Linux: standard native PM detection chain.
  if type apt-get > /dev/null 2>&1; then
    _ospkg_set_apt
  elif type apk > /dev/null 2>&1; then
    _ospkg_set_apk
  elif type dnf > /dev/null 2>&1; then
    _ospkg_set_dnf
  elif type microdnf > /dev/null 2>&1; then
    _ospkg_set_microdnf
  elif type yum > /dev/null 2>&1; then
    _ospkg_set_yum
  elif type zypper > /dev/null 2>&1; then
    _ospkg_set_zypper
  elif type pacman > /dev/null 2>&1; then
    _ospkg_set_pacman
  elif type brew > /dev/null 2>&1; then
    _ospkg_set_brew "Linux/Linuxbrew"
  else
    logging__error "No supported package manager found."
    return 1
  fi

  _ospkg_load_linux_release
  _OSPKG_DETECTED=true
  return 0
}

# ── Public: ospkg__update ────────────────────────────────────────────────────
# @brief ospkg__update [--force] [--lists_max_age N] [--repo_added] — Refresh the package index. Skips when lists are fresh (within `--lists_max_age` seconds).
#
# Args:
#   --force             Unconditionally refresh (overrides the age check).
#   --lists_max_age N   Skip if package lists were updated within N seconds (default: 300).
#   --repo_added        A new repo was just added; forces an unconditional refresh.
#
# Returns: 0 on success.
ospkg__update() {
  ospkg__detect
  local _force=false _max_age=3600 _repo_added=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --force)
        shift
        _force=true
        ;;
      --lists_max_age)
        shift
        _max_age="$1"
        shift
        ;;
      --repo_added)
        shift
        _repo_added=true
        ;;
      *)
        logging__error "ospkg__update: unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ ${#_OSPKG_UPDATE[@]} -eq 0 ]]; then
    # microdnf bakes --refresh into every install call; no separate update step is needed.
    logging__info "Package list update handled per-install by '${_OSPKG_PKG_MNGR}' (--refresh) — skipping explicit update."
    return 0
  fi

  local _skip=false
  if [[ "$_force" == true || "$_repo_added" == true ]]; then
    _skip=false
  elif [[ "$_OSPKG_UPDATED" == true ]]; then
    # Already ran an update in this process — skip unless force/repo_added.
    logging__info "Package lists already updated in this process — skipping."
    _skip=true
  elif [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
    # brew: no simple lists age check — always update unless forced off.
    _skip=false
  elif [[ -n "${_OSPKG_LISTS_PATH:-}" && -d "$_OSPKG_LISTS_PATH" ]]; then
    if [[ -n "$(find "$_OSPKG_LISTS_PATH" -mindepth 1 -maxdepth 2 -name "${_OSPKG_LISTS_PATTERN:-*}" 2> /dev/null | head -1)" ]]; then
      local _mtime _age
      # stat -c (Linux) or stat -f (macOS)
      _mtime=$(stat -c %Y "$_OSPKG_LISTS_PATH" 2> /dev/null || stat -f %m "$_OSPKG_LISTS_PATH" 2> /dev/null || echo 0)
      _age=$(($(date +%s) - _mtime))
      if [[ $_age -lt $_max_age ]]; then
        _skip=true
        logging__info "Package lists refreshed ${_age}s ago — skipping update (threshold: ${_max_age}s)."
      fi
    fi
  fi

  if [[ "$_skip" == false ]]; then
    logging__info "Updating package lists."
    net__fetch_with_retry --bail-on 2 --retries 10 _ospkg_update_cmd
    _OSPKG_UPDATED=true
    logging__success "Package lists updated."
  fi
  return 0
}

# ── Public: ospkg__install ───────────────────────────────────────────────────
# @brief ospkg__install <pkg>... — Install one or more packages. Skips if all are already installed (APT, DNF/YUM, Homebrew).
#
# Args:
#   <pkg>...  One or more package names to install.
#
# Returns: 0 on success.
ospkg__install() {
  ospkg__detect || return 1
  if [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
    local _pkg _all_installed=true
    for _pkg in "$@"; do
      brew list --formula "$_pkg" > /dev/null 2>&1 || {
        _all_installed=false
        break
      }
    done
    [[ "$_all_installed" == true ]] && {
      logging__info "Packages already installed: $*"
      return 0
    }
  elif [[ "$_OSPKG_PKG_MNGR" = "apt-get" ]]; then
    if dpkg -s "$@" > /dev/null 2>&1; then
      logging__info "Packages already installed: $*"
      return 0
    fi
  elif [[ "$_OSPKG_PKG_MNGR" = "dnf" || "$_OSPKG_PKG_MNGR" = "yum" ]]; then
    local _num_pkgs=$#
    local _num_installed
    _num_installed=$("$_OSPKG_PKG_MNGR" -C list installed "$@" 2> /dev/null | sed '1,/^Installed/d' | wc -l) || _num_installed=0
    if [[ $_num_pkgs -eq $_num_installed ]]; then
      logging__info "Packages already installed: $*"
      return 0
    fi
  fi
  ospkg__update || true
  logging__info "Installing packages:"
  printf '  - %s\n' "$@" >&2
  # Keep interactive mode possible on TTY, but prevent PMs from draining
  # caller-provided stdin in piped/non-interactive contexts.
  if [[ -t 0 ]]; then
    net__fetch_with_retry "${_OSPKG_INSTALL[@]}" "$@" >&2
  elif [[ "$_OSPKG_PKG_MNGR" == "apt-get" && -z "${DEBIAN_FRONTEND-}" ]]; then
    DEBIAN_FRONTEND=noninteractive net__fetch_with_retry "${_OSPKG_INSTALL[@]}" "$@" < /dev/null >&2
  else
    net__fetch_with_retry "${_OSPKG_INSTALL[@]}" "$@" < /dev/null >&2
  fi
}

# ── Public: ospkg__clean ─────────────────────────────────────────────────────
# @brief ospkg__clean — Remove the package manager cache to reduce image layer size.
#
# Returns: 0 on success.
ospkg__clean() {
  ospkg__detect
  logging__clean "Cleaning package manager cache."
  "$_OSPKG_CLEAN"
  return 0
}

# ── Public: ospkg__parse_manifest_yaml ───────────────────────────────────────
# @brief ospkg__parse_manifest_yaml <json-file> — Parse a YAML manifest (pre-converted to JSON by `yq`) and emit normalised installation records to stdout.
#
# Requires jq in PATH and _OSPKG_OS_RELEASE populated by ospkg__detect.
# Each record is a compact JSON object with a "kind" field.
#
# Output record kinds:
#   prescript   {kind,content}
#   key         {kind,url,dest,dearmor}
#   repo        {kind,content}
#   ppa         {kind,ppa}           — APT only
#   tap         {kind,tap}           — brew (string or {name,url})
#   copr        {kind,copr}          — dnf only
#   module      {kind,module}        — dnf only
#   group       {kind,group}
#   package     {kind,name,flags,version}
#   cask        {kind,cask}          — brew (macOS) only
#   script      {kind,content}
#
# Args:
#   <json-file>  Path to the manifest JSON file (use `yq -o=json` to convert YAML first).
#
# Stdout: one compact JSON record per line.
#
# Returns: 0 on success.
ospkg__parse_manifest_yaml() {
  local _json_file="$1"

  # Build a full JSON context object from _OSPKG_OS_RELEASE so that every
  # /etc/os-release key (including version_codename, pretty_name, etc.) plus
  # the synthetic keys (pm, arch, kernel) is available in `when` clauses.
  local _ctx_json _k
  # shellcheck disable=SC2016
  _ctx_json="$(
    for _k in "${!_OSPKG_OS_RELEASE[@]}"; do
      printf '%s\n' "$_k" "${_OSPKG_OS_RELEASE[$_k]}"
    done | json__query -Rn '[inputs] | [range(0; length; 2) as $i | {key: .[$i], value: .[$i + 1]}] | from_entries'
  )"

  local _pm="${_OSPKG_OS_RELEASE[pm]:-${_OSPKG_FAMILY}}"

  json__query -c \
    --argjson ctx "$_ctx_json" \
    --arg pm "$_pm" \
    -f "${_OSPKG_LIB_DIR}/ospkg-manifest.jq" \
    "$_json_file"
  return 0
}

# ── Private: build-dep tracking ──────────────────────────────────────────────
# _ospkg_build_deps_dir — returns the directory used for build-dep sidecar files.
_ospkg_build_deps_dir() {
  printf '%s' "$(file__tmpdir "ospkg/build-deps")"
  return
}

# _ospkg_protect_user_pkgs <pkg-name>... — mark packages as user-requested so
# build-group cleanup cannot remove them. Accepts bare package names only (no
# version suffixes). Applies PM-native marking for marking-capable PMs and
# evicts each package from every build-group sidecar (covers explicit-list PMs:
# apk, zypper, microdnf, brew). All operations are non-fatal.
_ospkg_protect_user_pkgs() {
  [[ $# -eq 0 ]] && return 0
  ospkg__detect
  # PM-native marking: reverse any auto/asdeps/removable mark on these packages.
  case "$_OSPKG_PKG_MNGR" in
    apt-get) users__run_privileged apt-mark manual "$@" > /dev/null 2>&1 || true ;;
    dnf | yum) users__run_privileged dnf mark install "$@" > /dev/null 2>&1 || true ;;
    pacman) users__run_privileged pacman -D --asexplicit "$@" > /dev/null 2>&1 || true ;;
    *) ;;
  esac
  # Sidecar eviction: remove each package from every build-group sidecar so
  # explicit-list PMs do not delete them during build-group cleanup.
  local _bd_dir _sidecar _sidecar_name _pkg _tmp
  _bd_dir="$(_ospkg_build_deps_dir)"
  [[ -d "$_bd_dir" ]] || return 0
  for _sidecar in "$_bd_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    _sidecar_name="$(basename "$_sidecar")"
    # Skip temporary snapshot files used during build-dep tracking.
    [[ "$_sidecar_name" == *.before || "$_sidecar_name" == *.after ]] && continue
    for _pkg in "$@"; do
      if grep -qxF "$_pkg" "$_sidecar" 2> /dev/null; then
        _tmp="${_sidecar}.protect_tmp"
        grep -Fxv "$_pkg" "$_sidecar" > "$_tmp" 2> /dev/null &&
          mv "$_tmp" "$_sidecar" ||
          rm -f "$_tmp" || true
        logging__info "Evicted '${_pkg}' from build-group sidecar '${_sidecar_name}'."
      fi
    done
  done
  return 0
}

# ── Public: ospkg__take_initial_snapshot ─────────────────────────────────────
# @brief ospkg__take_initial_snapshot <file> — Snapshot the current installed-package list to `<file>` as a session baseline.
#
# Called once by install.bash before any installs in manifest mode. Used by
# `ospkg__install_tracked` to exclude pre-existing packages from session
# co-ownership tracking.
#
# Args:
#   <file>  Destination path for the snapshot (one package name per line).
#
# Returns: 0 on success.
ospkg__take_initial_snapshot() {
  local _dest="$1"
  ospkg__detect
  _ospkg_snapshot_packages "$_dest"
  logging__info "Initial package snapshot written to ${_dest}."
  return 0
}

# _ospkg_snapshot_packages <dest-file> — writes a sorted list of installed
# package names (one per line) to <dest-file>.
_ospkg_snapshot_packages() {
  local _dest="$1"
  case "$_OSPKG_PKG_MNGR" in
    apt-get) dpkg-query -W -f='${Package}\n' 2> /dev/null | sort > "$_dest" ;;
    apk) apk info 2> /dev/null | sort > "$_dest" ;;
    dnf | yum | microdnf) rpm -qa --queryformat='%{NAME}\n' 2> /dev/null | sort > "$_dest" ;;
    zypper) rpm -qa --queryformat='%{NAME}\n' 2> /dev/null | sort > "$_dest" ;;
    pacman) pacman -Qq 2> /dev/null | sort > "$_dest" ;;
    brew) brew list 2> /dev/null | sort > "$_dest" ;;
    *) : > "$_dest" ;;
  esac
  return 0
}

# _ospkg_mark_build_group <group-id> <before-file> — diff current state against
# <before-file>, apply PM-native removable marking to newly-installed packages,
# and write the sidecar tracking file.
_ospkg_mark_build_group() {
  local _group_id="$1" _before_file="$2"
  local _deps_dir _after_file _sidecar
  _deps_dir="$(_ospkg_build_deps_dir)"
  _after_file="${_deps_dir}/${_group_id//\//_}.after"
  _sidecar="${_deps_dir}/${_group_id//\//_}"
  _ospkg_snapshot_packages "$_after_file"
  local -a _new_pkgs=()
  mapfile -t _new_pkgs < <(comm -13 "$_before_file" "$_after_file" 2> /dev/null)
  rm -f "$_after_file"
  if [[ ${#_new_pkgs[@]} -eq 0 ]]; then
    logging__info "Build group '${_group_id}': no new packages installed — nothing to track."
    # Preserve an existing sidecar (may already list packages from a prior call
    # with the same group ID).  Only create an empty sentinel if not yet present.
    [[ ! -f "$_sidecar" ]] && : > "$_sidecar"
    return 0
  fi
  logging__info "Build group '${_group_id}': tracking ${#_new_pkgs[@]} package(s): ${_new_pkgs[*]}"
  # Append to the sidecar so that multiple calls with the same group ID
  # accumulate all tracked packages (idempotent across repeat calls).
  printf '%s\n' "${_new_pkgs[@]}" >> "$_sidecar"
  sort -u "$_sidecar" -o "$_sidecar"
  # Apply PM-native removable marking to newly-installed packages only.
  # Safety: _new_pkgs is derived from a before/after snapshot diff taken in
  # ospkg__install_tracked, so it only contains packages that were absent before
  # this call. Packages already installed (e.g. from run.base in the header)
  # never appear here and their manual marks are therefore never disturbed.
  case "$_OSPKG_PKG_MNGR" in
    apt-get)
      users__run_privileged apt-mark auto "${_new_pkgs[@]}" >&2 || true
      ;;
    dnf | yum)
      users__run_privileged dnf mark remove "${_new_pkgs[@]}" >&2 || true
      ;;
    pacman)
      users__run_privileged pacman -D --asdeps "${_new_pkgs[@]}" >&2 || true
      ;;
    *) ;;
  esac
  return 0
}

# _ospkg_remove_build_group <group-id> — remove previously-installed build-only
# packages using PM-native mechanisms based on the sidecar tracking file.
_ospkg_remove_build_group() {
  local _group_id="$1"
  local _deps_dir _sidecar
  _deps_dir="$(_ospkg_build_deps_dir)"
  _sidecar="${_deps_dir}/${_group_id//\//_}"
  if [[ ! -f "$_sidecar" ]]; then
    logging__info "Build group '${_group_id}': sidecar not found — nothing to remove."
    return 0
  fi
  local -a _pkgs=()
  mapfile -t _pkgs < "$_sidecar"
  if [[ ${#_pkgs[@]} -eq 0 ]]; then
    logging__info "Build group '${_group_id}': sidecar empty — nothing to remove."
    return 0
  fi
  logging__remove "Build group '${_group_id}': removing ${#_pkgs[@]} package(s): ${_pkgs[*]}"
  case "$_OSPKG_PKG_MNGR" in
    apt-get)
      # Remove exactly the tracked packages. The sidecar contains the complete
      # before/after diff (all newly installed packages including transitive deps),
      # so explicit removal is sufficient and precisely scoped. '--auto-remove'
      # is intentionally omitted: it performs a global scan and would remove
      # pre-existing auto-marked orphaned packages unrelated to our install.
      users__run_privileged apt-get -y --purge remove "${_pkgs[@]}" >&2 || true
      ;;
    apk)
      users__run_privileged apk del "${_pkgs[@]}" >&2 || true
      ;;
    dnf | yum)
      # Packages were marked removable at install time; remove explicitly so only
      # tracked packages and their orphaned deps are cleaned — not all dnf orphans.
      users__run_privileged dnf -y remove "${_pkgs[@]}" >&2 || true
      ;;
    microdnf)
      users__run_privileged microdnf remove "${_pkgs[@]}" >&2 || true
      ;;
    zypper)
      users__run_privileged zypper --non-interactive remove --clean-deps "${_pkgs[@]}" >&2 || true
      ;;
    pacman)
      # Remove tracked packages explicitly; let pacman handle deps marked asdeps.
      users__run_privileged pacman -Rs --noconfirm "${_pkgs[@]}" >&2 || true
      ;;
    brew)
      local _pkg
      for _pkg in "${_pkgs[@]}"; do
        if [[ -z "$(brew uses --installed "$_pkg" 2> /dev/null)" ]]; then
          _ospkg_brew_run remove "$_pkg" >&2 || true
        else
          logging__info "brew: keeping '$_pkg' (still in use)."
        fi
      done
      ;;
  esac
  rm -f "$_sidecar"
  return 0
}

# ── Public: ospkg__install_tracked ────────────────────────────────────────────
# @brief ospkg__install_tracked <sub-id> <pkg>... — Install packages and register them as build-only under `<sub-id>` for later cleanup. Idempotent.
#
# The full group-id is `"${_SYSSET_BUILD_CONTEXT:-uncontexted}::<sub-id>"`. When
# `_SYSSET_SESSION_TRACK_DIR` is set, also mirrors tracking to the session dir
# for cross-feature co-ownership.
#
# Args:
#   <sub-id>  Build-group sub-identifier (e.g. `lib-net`); context prefix added automatically.
#   <pkg>...  One or more package names to install.
#
# Returns: 0 on success.
ospkg__install_tracked() {
  local _group_id="${_SYSSET_BUILD_CONTEXT:-uncontexted}::$1"
  shift
  local _bd_dir _before_snapshot
  _bd_dir="$(_ospkg_build_deps_dir)"
  _before_snapshot="${_bd_dir}/${_group_id//\//\_}.before"
  _ospkg_snapshot_packages "$_before_snapshot"
  ospkg__install "$@" || return 1
  _ospkg_mark_build_group "$_group_id" "$_before_snapshot"
  rm -f "$_before_snapshot"
  # Session co-ownership tracking (manifest mode only).
  # Register all requested packages not present in the initial snapshot so that
  # the install.bash coordinator can apply keep-wins policy across all co-owners.
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" && -d "${_SYSSET_SESSION_TRACK_DIR}" ]]; then
    local _session_sidecar _pkg
    _session_sidecar="${_SYSSET_SESSION_TRACK_DIR}/${_group_id//\//_}"
    for _pkg in "$@"; do
      # Skip packages that existed before the session (pre-existing is never cleaned).
      if [[ -n "${_SYSSET_INITIAL_SNAPSHOT:-}" && -f "${_SYSSET_INITIAL_SNAPSHOT}" ]]; then
        grep -qxF "$_pkg" "$_SYSSET_INITIAL_SNAPSHOT" && continue
      fi
      printf '%s\n' "$_pkg" >> "$_session_sidecar"
    done
    [[ -f "$_session_sidecar" ]] && sort -u "$_session_sidecar" -o "$_session_sidecar"
  fi
  return 0
}

# @brief ospkg__cleanup_all_build_groups — Remove every registered build-dep group. Scans the sidecar directory and calls `_ospkg_remove_build_group` for each entry.
#
# Returns: 0 on success.
ospkg__cleanup_all_build_groups() {
  local _deps_dir
  _deps_dir="$(_ospkg_build_deps_dir)"
  [[ -d "$_deps_dir" ]] || return 0
  local _sidecar _group_id
  for _sidecar in "$_deps_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    _group_id="$(basename "$_sidecar")"
    # Skip temporary snapshot files used during the tracking process.
    [[ "$_group_id" == *.before || "$_group_id" == *.after ]] && continue
    _ospkg_remove_build_group "$_group_id"
  done
  return 0
}

# @brief ospkg__cleanup_session_build_groups <install-bash-keep> — Manifest-mode coordinator: apply keep-wins policy across co-owners and remove unneeded build packages.
#
# Reads co-ownership entries from `_SYSSET_SESSION_TRACK_DIR`, applies keep-wins
# (any `true` overrides all `false`), then removes packages not kept by any
# co-owner. Deletes `_SYSSET_SESSION_TRACK_DIR` on completion. No-op when
# `_SYSSET_SESSION_TRACK_DIR` is unset or does not exist.
#
# Args:
#   <install-bash-keep>  `"true"` or `"false"` — keep_build_deps for the install-bash context. Feature keep_build_deps is read from `_OPT_OF`.
#
# Returns: 0 on success.
ospkg__cleanup_session_build_groups() {
  local _getbash_keep="${1:-false}"
  [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" ]] || return 0
  [[ -d "$_SYSSET_SESSION_TRACK_DIR" ]] || return 0

  # Build pkg -> should_keep map (keep wins: any true overrides all false).
  declare -A _session_pkg_keep=()
  local _sidecar _basename _context _feature_id _keep _pkg
  for _sidecar in "$_SYSSET_SESSION_TRACK_DIR"/*; do
    [[ -f "$_sidecar" ]] || continue
    _basename="$(basename "$_sidecar")"
    # Derive keep policy from context prefix in the filename.
    # Filename is the context-qualified group ID, e.g.:
    #   "install-bash::bootstrap", "feature::install-gh::lib-net"
    if [[ "$_basename" == install-bash::* ]]; then
      _keep="$_getbash_keep"
    else
      # Extract feature ID from "feature::<id>::<module>" pattern.
      _feature_id="${_basename#feature::}"
      _feature_id="${_feature_id%%::*}"
      _keep=false
      # Read from _OPT_OF if declared in the caller's scope (install.bash).
      if declare -p _OPT_OF > /dev/null 2>&1 && [[ -n "${_OPT_OF[$_feature_id]+x}" ]]; then
        if [[ "${_OPT_OF[$_feature_id]}" =~ \"keep_build_deps\":[[:space:]]*true ]]; then
          _keep=true
        fi
      fi
    fi
    while IFS= read -r _pkg; do
      [[ -z "$_pkg" ]] && continue
      # Keep wins: once set true, never overridden by false.
      if [[ "${_session_pkg_keep[$_pkg]:-false}" != "true" ]]; then
        _session_pkg_keep["$_pkg"]="$_keep"
      fi
    done < "$_sidecar"
  done

  # Collect packages where all co-owners said keep=false.
  local -a _to_remove=()
  for _pkg in "${!_session_pkg_keep[@]}"; do
    [[ "${_session_pkg_keep[$_pkg]}" != "true" ]] && _to_remove+=("$_pkg")
  done

  if [[ ${#_to_remove[@]} -gt 0 ]]; then
    logging__remove "Session cleanup: removing ${#_to_remove[@]} build-dep package(s): ${_to_remove[*]}"
    local _synth_dir _synth_sidecar
    _synth_dir="$(_ospkg_build_deps_dir)"
    _synth_sidecar="${_synth_dir}/__session_cleanup__"
    printf '%s\n' "${_to_remove[@]}" | sort > "$_synth_sidecar"
    _ospkg_remove_build_group "__session_cleanup__" || true
  else
    logging__info "Session cleanup: no packages to remove (all kept or nothing installed)."
  fi

  rm -rf "$_SYSSET_SESSION_TRACK_DIR"
  return 0
}

# ── Public: resource tracking ─────────────────────────────────────────────────
# @brief ospkg__track_resource <group-id> <path>... — Register filesystem paths for cleanup via `ospkg__cleanup_resources`. Also mirrors to the session dir when `_SYSSET_SESSION_TRACK_DIR` is set.
#
# Args:
#   <group-id>  Cleanup group identifier.
#   <path>...   One or more absolute paths to register.
#
# Returns: 0 on success.
ospkg__track_resource() {
  local _group_id="$1"
  shift
  local _res_dir _sidecar _path
  _res_dir="$(file__tmpdir "ospkg/resources")"
  _sidecar="${_res_dir}/${_group_id//\//_}"
  for _path in "$@"; do
    printf '%s\n' "$_path" >> "$_sidecar"
  done
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" && -d "${_SYSSET_SESSION_TRACK_DIR}" ]]; then
    local _sess_res_dir="${_SYSSET_SESSION_TRACK_DIR}/resources"
    mkdir -p "$_sess_res_dir"
    local _sess_sidecar="${_sess_res_dir}/${_group_id//\//_}"
    for _path in "$@"; do
      printf '%s\n' "$_path" >> "$_sess_sidecar"
    done
  fi
  return 0
}

# @brief ospkg__untrack_resource <group-id> <path>... — Remove resource paths from local and session sidecars registered by `ospkg__track_resource`.
#
# Args:
#   <group-id>  Cleanup group identifier.
#   <path>...   One or more paths to deregister.
#
# Returns: 0 on success, 1 if copying the sidecar fails.
ospkg__untrack_resource() {
  local _group_id="$1"
  shift
  local _res_dir _sidecar _path _tmp
  _res_dir="$(file__tmpdir "ospkg/resources")"
  _sidecar="${_res_dir}/${_group_id//\//_}"
  if [[ -f "$_sidecar" ]]; then
    _tmp="${_sidecar}.tmp.$$"
    cp "$_sidecar" "$_tmp" || {
      logging__error "ospkg__untrack_resource: failed to copy sidecar '${_sidecar}'."
      return 1
    }
    for _path in "$@"; do
      awk -v p="$_path" '$0 != p { print }' "$_tmp" > "${_tmp}.next"
      mv "${_tmp}.next" "$_tmp"
    done
    mv "$_tmp" "$_sidecar"
  fi
  if [[ -n "${_SYSSET_SESSION_TRACK_DIR:-}" && -d "${_SYSSET_SESSION_TRACK_DIR}/resources" ]]; then
    local _sess_sidecar="${_SYSSET_SESSION_TRACK_DIR}/resources/${_group_id//\//_}"
    if [[ -f "$_sess_sidecar" ]]; then
      _tmp="${_sess_sidecar}.tmp.$$"
      cp "$_sess_sidecar" "$_tmp" || {
        logging__error "ospkg__untrack_resource: failed to copy session sidecar '${_sess_sidecar}'."
        return 1
      }
      for _path in "$@"; do
        awk -v p="$_path" '$0 != p { print }' "$_tmp" > "${_tmp}.next"
        mv "${_tmp}.next" "$_tmp"
      done
      mv "$_tmp" "$_sess_sidecar"
    fi
  fi
  return 0
}

# @brief ospkg__cleanup_resources — Remove all files registered via `ospkg__track_resource`. Reads sidecars from `_SYSSET_TMPDIR/ospkg/resources/` and `rm -f`s each listed path.
#
# Returns: 0 (always; removal failures emit a warning and continue).
ospkg__cleanup_resources() {
  local _res_dir
  _res_dir="$(file__tmpdir "ospkg/resources")"
  [[ -d "$_res_dir" ]] || return 0
  local _sidecar _path
  for _sidecar in "$_res_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    while IFS= read -r _path; do
      [[ -z "$_path" ]] && continue
      if [[ -e "$_path" ]]; then
        rm -f "$_path" 2> /dev/null || logging__warn "ospkg__cleanup_resources: could not remove '${_path}'"
      fi
    done < "$_sidecar"
    rm -f "$_sidecar"
  done
  return 0
}

# ── Public: ospkg__install_user ──────────────────────────────────────────────
# @brief ospkg__install_user <pkg>... — Install packages and protect them from build-group cleanup. Prefer over `ospkg__install` for all user-facing installs.
#
# Version suffixes are stripped per PM convention before calling
# `_ospkg_protect_user_pkgs`, so packages will not be removed by
# `ospkg__cleanup_all_build_groups` even if a prior build-group install had
# marked them.
#
# Args:
#   <pkg>...  One or more package specs (versioned forms like `gh=2.40.0` accepted).
#
# Returns: 0 on success.
ospkg__install_user() {
  ospkg__install "$@"
  ospkg__detect
  # Strip PM-native version suffixes to get bare package names for marking.
  local -a _bare_names=()
  local _p
  for _p in "$@"; do
    case "$_OSPKG_PKG_MNGR" in
      apt-get | apk | pacman | zypper) _bare_names+=("${_p%%=*}") ;;
      dnf | yum) _bare_names+=("${_p%%-[0-9]*}") ;;
      brew) _bare_names+=("${_p%%@*}") ;;
      *) _bare_names+=("$_p") ;;
    esac
  done
  _ospkg_protect_user_pkgs "${_bare_names[@]}"
  return 0
}

# ── Public: ospkg__run ───────────────────────────────────────────────────────
# @brief ospkg__run [--manifest <f>] [--fetch-netrc-file <path>] [--fetch-header <H>]... [--update <bool>] [--keep_repos] [--dry_run] [--skip_installed] [--interactive] [--build-group <id>] [--remove-build-group <id>] — Run the full installation pipeline from a manifest.
#
# Full pipeline: detect → root check → parse manifest → prescript → keys →
# repos → PM setup → update → install → casks → script.
#
# Cache cleanup is NOT performed by this function. Call ospkg__clean explicitly
# (e.g. via the _on_exit trap) when you want to purge the package manager cache.
#
# Args:
#   --manifest <f>          Path to the YAML manifest file, inline YAML/JSON (with
#                           embedded newlines), or a URI (http(s)://, file://, oci://, gh://).
#   --fetch-netrc-file <path>  Optional .netrc file passed to URI fetches when
#                           resolving a URI manifest.
#   --fetch-header <H>      Additional HTTP header passed to URI fetches when
#                           resolving a URI manifest. Repeatable.
#   --update <bool>         Run package index update before installing (default: true).
#   --keep_repos            Do not remove added third-party repo files after installation.
#   --dry_run               Print what would be installed without doing it.
#   --skip_installed        Skip packages that are already installed.
#   --interactive           Preserve TTY for interactive package prompts.
#   --build-group <id>      Mark all newly-installed packages as build-only and record
#                           them in a sidecar file for later cleanup. Requires --manifest.
#   --remove-build-group <id>  Remove previously-installed build-only packages using
#                              PM-native mechanisms. Does not require --manifest.
#
# Returns: 0 on success, 1 on invalid arguments or manifest parse failure.
ospkg__run() {
  local _manifest='' _update=true _keep_repos=false
  local _lists_max_age=300 _dry_run=false _skip_installed=false _interactive=false
  local _prefer_linuxbrew=false _build_group='' _remove_build_group=''
  local _fetch_netrc_file=''
  local -a _fetch_headers=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      --manifest)
        shift
        _manifest="$1"
        shift
        ;;
      --fetch-netrc-file)
        shift
        _fetch_netrc_file="$1"
        shift
        ;;
      --fetch-header)
        shift
        _fetch_headers+=("$1")
        shift
        ;;
      --update)
        shift
        _update="$1"
        shift
        ;;
      --keep_repos)
        shift
        _keep_repos=true
        ;;
      --lists_max_age)
        shift
        _lists_max_age="$1"
        shift
        ;;
      --dry_run)
        shift
        _dry_run=true
        ;;
      --skip_installed)
        shift
        _skip_installed=true
        ;;
      --interactive)
        shift
        _interactive=true
        ;;
      --prefer_linuxbrew)
        shift
        _prefer_linuxbrew=true
        ;;
      --build-group)
        shift
        _build_group="$1"
        shift
        ;;
      --remove-build-group)
        shift
        _remove_build_group="$1"
        shift
        ;;
      *)
        logging__error "ospkg__run: unknown option: $1"
        return 1
        ;;
    esac
  done

  if ! [[ "$_lists_max_age" =~ ^[0-9]+$ ]]; then
    logging__error "ospkg__run: invalid lists_max_age value: '$_lists_max_age'."
    return 1
  fi

  if [[ -n "$_build_group" && -z "$_manifest" ]]; then
    logging__error "ospkg__run: --build-group requires --manifest."
    return 1
  fi

  if [[ -n "$_remove_build_group" && (-n "$_build_group" || -n "$_manifest") ]]; then
    logging__error "ospkg__run: --remove-build-group must be used alone (no --manifest or --build-group)."
    return 1
  fi

  [[ "$_dry_run" == true ]] && logging__inspect "Dry-run mode enabled — no changes will be made."

  # Set prefer_linuxbrew early so detect() picks it up.
  _OSPKG_PREFER_LINUXBREW="$_prefer_linuxbrew"

  ospkg__detect || return 1

  # Root check: brew is exempt (it manages its own user/root logic via _ospkg_brew_run).
  if [[ "$_dry_run" == false && "$_OSPKG_PKG_MNGR" != "brew" ]]; then
    os__require_root
  fi

  # --remove-build-group: cleanup build-only packages and return immediately.
  if [[ -n "$_remove_build_group" ]]; then
    if [[ "$_dry_run" == true ]]; then
      logging__inspect "[dry-run] remove-build-group '${_remove_build_group}' — would remove build-only packages."
      return 0
    fi
    _ospkg_remove_build_group "$_remove_build_group"
    return 0
  fi

  if [[ "$_OSPKG_PKG_MNGR" = "apt-get" && "$_interactive" == false ]]; then
    logging__info "Setting APT to non-interactive mode."
    export DEBIAN_FRONTEND=noninteractive
  fi

  # Resolve manifest content.
  local _manifest_content=
  local _hl=''
  local -a _ospkg_uri_args=()
  local _ospkg_uri_tmp=''

  if [[ -n "$_manifest" ]]; then
    if [[ "$_manifest" == *$'\n'* ]]; then
      _manifest_content="$_manifest"
    elif [[ "$_manifest" == http://* || "$_manifest" == https://* || "$_manifest" == file://* || "$_manifest" == oci://* || "$_manifest" == gh://* ]]; then
      # shellcheck source=lib/uri.sh
      # shellcheck disable=SC1094
      . "$_OSPKG_LIB_DIR/uri.sh"
      _ospkg_uri_tmp="$(mktemp "${TMPDIR:-/tmp}/ospkg-manifest-uri.XXXXXX")"
      _ospkg_uri_args=()
      if [[ -n "${_fetch_netrc_file:-}" ]]; then
        _ospkg_uri_args+=(--netrc-file "$_fetch_netrc_file")
      fi
      for _hl in "${_fetch_headers[@]}"; do
        [[ -z "${_hl//[[:space:]]/}" ]] && continue
        _ospkg_uri_args+=(--header "$_hl")
      done
      if ! uri__resolve "$_manifest" "$_ospkg_uri_tmp" "${_ospkg_uri_args[@]}"; then
        rm -f "$_ospkg_uri_tmp"
        return 1
      fi
      if ! _manifest_content="$(< "$_ospkg_uri_tmp")"; then
        rm -f "$_ospkg_uri_tmp"
        return 1
      fi
      rm -f "$_ospkg_uri_tmp"
    elif [[ -f "$_manifest" ]]; then
      _manifest_content="$(< "$_manifest")"
    else
      logging__error "Manifest file not found: '$_manifest'"
      return 1
    fi
  fi

  # Take a package snapshot before installation when build-group tracking is enabled.
  local _before_snapshot_file=''
  if [[ -n "$_build_group" && "$_dry_run" == false ]]; then
    local _bd_dir
    _bd_dir="$(_ospkg_build_deps_dir)"
    _before_snapshot_file="${_bd_dir}/${_build_group//\//_}.before"
    logging__info "Build group '${_build_group}': recording pre-install package snapshot."
    _ospkg_snapshot_packages "$_before_snapshot_file"
  fi

  # ── YAML / JSON manifest path ──────────────────────────────────────────────
  if [[ -n "$_manifest_content" ]]; then

    # yq is required to convert YAML to JSON.
    if ! _ospkg_ensure_yq; then
      logging__error "yq is required for YAML manifests but could not be obtained."
      return 1
    fi

    # Convert YAML (or JSON) to JSON via yq, then parse into phase arrays.
    # Temp files live inside _SYSSET_TMPDIR so logging__cleanup removes them
    # automatically on exit, even on unexpected failure.
    local _ospkg_dir _json_tmp
    _ospkg_dir="$(file__tmpdir "ospkg")"
    _json_tmp="$(mktemp "${_ospkg_dir}/yaml_XXXXXX")"

    local -a _Y_PRESCRIPTS=() _Y_KEYS=() _Y_REPOS=() _Y_PPAS=() _Y_TAPS=() _Y_COPR=()
    local -a _Y_MODULES=() _Y_GROUPS=() _Y_PACKAGES=() _Y_CASKS=() _Y_SCRIPTS=()

    logging__info "Converting manifest to JSON via yq."
    if [[ "$_manifest_content" == *$'\n'* ]]; then
      printf '%s' "$_manifest_content" | "$_OSPKG_YQ_BIN" -o=json '.' - > "$_json_tmp"
    else
      "$_OSPKG_YQ_BIN" -o=json '.' - <<< "$_manifest_content" > "$_json_tmp" 2> /dev/null ||
        echo "$_manifest_content" | "$_OSPKG_YQ_BIN" -o=json '.' - > "$_json_tmp"
    fi

    local _item _kind
    local _parsed_records
    if ! _parsed_records="$(ospkg__parse_manifest_yaml "$_json_tmp")"; then
      local _manifest_origin _manifest_preview
      if [[ "$_manifest" == *$'\n'* ]]; then
        _manifest_origin="<inline>"
      else
        _manifest_origin="$_manifest"
      fi
      _manifest_preview="$(printf '%s' "$_manifest_content" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-220)"
      rm -f "$_json_tmp"
      logging__error "Manifest parse failed for: ${_manifest_origin}"
      [[ -n "${_manifest_preview:-}" ]] && logging__info "Manifest preview: ${_manifest_preview}"
      logging__error "Manifest parse failed — see jq error above."
      return 1
    fi
    while IFS= read -r _item; do
      _kind="$(printf '%s' "$_item" | json__query -r '.kind' 2> /dev/null)" || continue
      case "$_kind" in
        prescript) _Y_PRESCRIPTS+=("$_item") ;;
        key) _Y_KEYS+=("$_item") ;;
        repo) _Y_REPOS+=("$_item") ;;
        ppa) _Y_PPAS+=("$_item") ;;
        tap) _Y_TAPS+=("$_item") ;;
        copr) _Y_COPR+=("$_item") ;;
        module) _Y_MODULES+=("$_item") ;;
        group) _Y_GROUPS+=("$_item") ;;
        package) _Y_PACKAGES+=("$_item") ;;
        cask) _Y_CASKS+=("$_item") ;;
        script) _Y_SCRIPTS+=("$_item") ;;
      esac
    done <<< "$_parsed_records"
    rm -f "$_json_tmp"
    logging__info "YAML manifest parsed: ${#_Y_PRESCRIPTS[@]} prescript(s), ${#_Y_KEYS[@]} key(s), ${#_Y_REPOS[@]} repo(s), ${#_Y_PPAS[@]} ppa(s), ${#_Y_TAPS[@]} tap(s), ${#_Y_COPR[@]} copr(s), ${#_Y_MODULES[@]} module(s), ${#_Y_GROUPS[@]} group(s), ${#_Y_PACKAGES[@]} package(s), ${#_Y_CASKS[@]} cask(s), ${#_Y_SCRIPTS[@]} script(s)."

    # Helper: run a shell script with dry-run support.
    _run_script() {
      local _label="$1" _content="$2"
      local _stmp
      _stmp="$(mktemp "${_ospkg_dir}/script_XXXXXX")"
      printf '%s\n' "$_content" > "$_stmp"
      chmod +x "$_stmp"
      logging__launch "Running ${_label}."
      if [[ "$_dry_run" == true ]]; then
        logging__inspect "[dry-run] ${_label} — would execute:"
        sed 's/^/    /' "$_stmp" >&2
      else
        bash "$_stmp"
      fi
      rm -f "$_stmp"
      return 0
    }

    # Phase: PRESCRIPTS.
    if [[ ${#_Y_PRESCRIPTS[@]} -gt 0 ]]; then
      local _combined_prescript=""
      local _pitem
      for _pitem in "${_Y_PRESCRIPTS[@]}"; do
        _combined_prescript+="$(printf '%s' "$_pitem" | json__query -r '.content')"$'\n'
      done
      _run_script "prescript" "$_combined_prescript"
      logging__success "Prescript(s) completed."
    else
      logging__info "No prescripts found — skipping."
    fi

    local _yaml_key_added=false
    local -a _yaml_keys_written=()

    # Phase: SIGNING KEYS.
    if [[ ${#_Y_KEYS[@]} -gt 0 ]]; then
      logging__info "Installing ${#_Y_KEYS[@]} signing key(s)."
      local _key_gnupghome
      _key_gnupghome="$(file__mktmpdir "ospkg-gnupg")"
      chmod 700 "$_key_gnupghome"
      if [[ "$_dry_run" == false ]]; then
        export GNUPGHOME="$_key_gnupghome"
      fi
      local _kitem _kurl _kdest _kdearmor _kfp _keff
      for _kitem in "${_Y_KEYS[@]}"; do
        _kurl="$(printf '%s' "$_kitem" | json__query -r '.url // empty')"
        _kdest="$(printf '%s' "$_kitem" | json__query -r '.dest')"
        _kdearmor="$(printf '%s' "$_kitem" | json__query -r 'if .dearmor == true then "true" elif .dearmor == false then "false" else "auto" end')"
        _kfp="$(printf '%s' "$_kitem" | json__query -r '.fingerprint // empty')"
        # Expand ${token} substitutions in url and dest.
        _kurl="$(_ospkg_expand_content_vars "${_kurl}")"
        _kdest="$(_ospkg_expand_content_vars "${_kdest}")"
        _keff="$(_ospkg_key_effective_path "$_kdest" "$_kdearmor")"
        if [[ "$_dry_run" == true ]]; then
          if [[ -n "${_kfp:-}" && -z "${_kurl:-}" ]]; then
            logging__inspect "[dry-run] key: fingerprint=${_kfp} → ${_keff}"
          elif [[ "${_keff}" != "${_kdest}" ]]; then
            logging__inspect "[dry-run] key: ${_kurl} → ${_keff} (dearmor=${_kdearmor}; manifest dest=${_kdest})"
          else
            logging__inspect "[dry-run] key: ${_kurl} → ${_keff} (dearmor=${_kdearmor})"
          fi
        else
          _ospkg_install_key_entry "$_kurl" "$_kdest" "$_kdearmor" "$_kfp"
          _yaml_keys_written+=("$_keff")
          _yaml_key_added=true
        fi
      done
      if [[ "$_dry_run" == false ]]; then
        unset GNUPGHOME
      fi
      rm -rf "$_key_gnupghome"
      logging__success "Signing keys installed."
    else
      logging__info "No signing keys found — skipping."
    fi

    # Phase: REPOS.
    local _yaml_repo_added=false
    local _OSPKG_APK_ADDED_REPOS=()
    if [[ ${#_Y_REPOS[@]} -gt 0 ]]; then
      logging__info "Adding ${#_Y_REPOS[@]} repository entry/entries."
      local _ritem _rcontent
      for _ritem in "${_Y_REPOS[@]}"; do
        _rcontent="$(printf '%s' "$_ritem" | json__query -r '.content')"
        if [[ "$_dry_run" == true ]]; then
          logging__inspect "[dry-run] repo: would add: ${_rcontent}"
        else
          _ospkg_install_repo_content "${_rcontent}"$'\n'
          _yaml_repo_added=true
        fi
      done
    else
      logging__info "No repo entries found — skipping."
    fi

    # Phase: PPAs (APT only).
    if [[ ${#_Y_PPAS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_FAMILY" == "apt" ]]; then
        logging__info "Adding ${#_Y_PPAS[@]} PPA(s)."
        if ! command -v add-apt-repository > /dev/null 2>&1; then
          logging__info "add-apt-repository not found — installing software-properties-common."
          [[ "$_dry_run" == false ]] && ospkg__install_tracked "devfeats-ospkg-internals" software-properties-common
        fi
        local _ppitem _ppa
        for _ppitem in "${_Y_PPAS[@]}"; do
          _ppa="$(printf '%s' "$_ppitem" | json__query -r '.ppa')"
          if [[ "$_dry_run" == true ]]; then
            logging__inspect "[dry-run] ppa: would run: add-apt-repository -y '${_ppa}'"
          else
            logging__info "Adding PPA: ${_ppa}"
            users__run_privileged add-apt-repository -y "$_ppa"
            _yaml_repo_added=true
            logging__success "PPA added: ${_ppa}"
          fi
        done
      else
        logging__warn "PPAs are only supported on APT — ignoring (current PM: ${_OSPKG_PKG_MNGR})."
      fi
    fi

    # Phase: TAPS (brew only).
    if [[ ${#_Y_TAPS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
        logging__info "Adding ${#_Y_TAPS[@]} Homebrew tap(s)."
        local _titem _tap_val _tap_name _tap_url
        for _titem in "${_Y_TAPS[@]}"; do
          _tap_val="$(printf '%s' "$_titem" | json__query -r '.tap')"
          if printf '%s' "$_tap_val" | json__query -e 'type == "object"' > /dev/null 2>&1; then
            _tap_name="$(printf '%s' "$_tap_val" | json__query -r '.name')"
            _tap_url="$(printf '%s' "$_tap_val" | json__query -r '.url // empty')"
          else
            # tap is a plain string in the json__query -c output
            _tap_name="$(printf '%s' "$_titem" | json__query -r '.tap | if type == "object" then .name else . end')"
            _tap_url="$(printf '%s' "$_titem" | json__query -r '.tap | if type == "object" then (.url // "") else "" end')"
          fi
          if [[ "$_dry_run" == true ]]; then
            logging__inspect "[dry-run] tap: would run: brew tap ${_tap_name}${_tap_url:+ ${_tap_url}}"
          else
            logging__info "Tapping: ${_tap_name}"
            if [[ -n "${_tap_url:-}" ]]; then
              _ospkg_brew_run tap "$_tap_name" "$_tap_url"
            else
              _ospkg_brew_run tap "$_tap_name"
            fi
            logging__success "Tap added: ${_tap_name}"
          fi
        done
      else
        logging__warn "Homebrew taps are only supported when PM is brew — ignoring."
      fi
    fi

    # Phase: COPR (DNF only).
    if [[ ${#_Y_COPR[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_FAMILY" == "dnf" ]]; then
        local _copr_dnf_bin
        if ! _copr_dnf_bin="$(_ospkg_dnf_bin)"; then
          logging__warn "COPR repos require full dnf — '${_OSPKG_PKG_MNGR}' does not support 'copr enable'; skipping."
        else
          logging__info "Enabling ${#_Y_COPR[@]} COPR repo(s)."
          local _copritem _copr
          for _copritem in "${_Y_COPR[@]}"; do
            _copr="$(printf '%s' "$_copritem" | json__query -r '.copr')"
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] copr: would run: ${_copr_dnf_bin} copr enable -y '${_copr}'"
            else
              logging__info "Enabling COPR: ${_copr}"
              users__run_privileged "$_copr_dnf_bin" copr enable -y "$_copr"
              _yaml_repo_added=true
            fi
          done
        fi
      else
        logging__warn "COPR repos are only supported on DNF — ignoring (current PM: ${_OSPKG_PKG_MNGR})."
      fi
    fi

    # Phase: MODULES (DNF only).
    if [[ ${#_Y_MODULES[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_FAMILY" == "dnf" ]]; then
        local _mod_dnf_bin
        if ! _mod_dnf_bin="$(_ospkg_dnf_bin)"; then
          logging__warn "DNF module streams require full dnf — '${_OSPKG_PKG_MNGR}' does not support 'module enable'; skipping."
        else
          logging__info "Enabling ${#_Y_MODULES[@]} DNF module stream(s)."
          local _moditem _mod
          for _moditem in "${_Y_MODULES[@]}"; do
            _mod="$(printf '%s' "$_moditem" | json__query -r '.module')"
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] module: would run: ${_mod_dnf_bin} module enable -y '${_mod}'"
            else
              logging__info "Enabling module: ${_mod}"
              users__run_privileged "$_mod_dnf_bin" module enable -y "$_mod"
              logging__success "Module enabled: ${_mod}"
            fi
          done
        fi
      else
        logging__warn "DNF modules are only supported on DNF — ignoring (current PM: ${_OSPKG_PKG_MNGR})."
      fi
    fi

    # Phase: GROUPS.
    if [[ ${#_Y_GROUPS[@]} -gt 0 ]]; then
      local _grpitem _grp
      for _grpitem in "${_Y_GROUPS[@]}"; do
        _grp="$(printf '%s' "$_grpitem" | json__query -r '.group')"
        case "$_OSPKG_FAMILY" in
          dnf)
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] group: would run: ${_OSPKG_PKG_MNGR} group install -y '${_grp}'"
            else
              logging__install "Installing group '${_grp}' (dnf)."
              users__run_privileged "$_OSPKG_PKG_MNGR" group install -y "$_grp"
              logging__success "Group '${_grp}' installed."
            fi
            ;;
          zypper)
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] group: would run: zypper --non-interactive install -t pattern '${_grp}'"
            else
              logging__install "Installing pattern '${_grp}' (zypper)."
              users__run_privileged zypper --non-interactive install -t pattern "$_grp"
            fi
            ;;
          pacman)
            if [[ "$_dry_run" == true ]]; then
              logging__inspect "[dry-run] group: would run: ${_OSPKG_INSTALL[*]} '${_grp}'"
            else
              logging__install "Installing group '${_grp}' (pacman)."
              ospkg__install "$_grp"
              if [[ -z "${_build_group:-}" ]]; then
                local -a _grp_members=()
                mapfile -t _grp_members < <(pacman -Sg "$_grp" 2> /dev/null | awk '{print $2}')
                [[ ${#_grp_members[@]} -gt 0 ]] && _ospkg_protect_user_pkgs "${_grp_members[@]}"
              fi
            fi
            ;;
          *)
            logging__warn "Group '${_grp}' — groups not supported on '${_OSPKG_PKG_MNGR}'; skipping."
            ;;
        esac
      done
    fi

    # Phase: PACKAGE LIST UPDATE.
    if [[ (${#_Y_PACKAGES[@]} -gt 0 || "$_yaml_repo_added" == true) && "$_update" == true ]]; then
      local _update_args=(--lists_max_age "$_lists_max_age")
      [[ "$_yaml_repo_added" == true ]] && _update_args+=(--repo_added)
      if [[ "$_dry_run" == true ]]; then
        if [[ ${#_OSPKG_UPDATE[@]} -gt 0 ]]; then
          logging__inspect "[dry-run] update: would run: ${_OSPKG_UPDATE[*]}"
        else
          logging__info "Package list update not supported by '${_OSPKG_PKG_MNGR}' — skipping."
        fi
      else
        ospkg__update "${_update_args[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 && "$_yaml_repo_added" == false ]]; then
      logging__info "Package list update skipped (no packages and no repos in manifest)."
    else
      logging__info "Package list update skipped (update=false)."
      _OSPKG_UPDATED=true
      if [[ "$_yaml_repo_added" == true ]]; then
        logging__warn "A repository was added but update=false — packages may not be found."
      fi
    fi

    # Phase: INSTALL PACKAGES.
    local -a _pkgs_to_install=() _pkg_base_names=()
    local _pkgitem _pkgname _pkgflags _pkgversion _pkginstall
    for _pkgitem in "${_Y_PACKAGES[@]}"; do
      _pkgname="$(printf '%s' "$_pkgitem" | json__query -r '.name')"
      _pkgflags="$(printf '%s' "$_pkgitem" | json__query -r '.flags // empty')"
      _pkgversion="$(printf '%s' "$_pkgitem" | json__query -r '.version // empty')"
      [[ -z "${_pkgname:-}" ]] && continue

      # Apply version constraint (PM-native syntax).
      if [[ -n "${_pkgversion:-}" ]]; then
        case "$_OSPKG_FAMILY" in
          apt | apk | pacman | zypper) _pkginstall="${_pkgname}=${_pkgversion}" ;;
          dnf | yum) _pkginstall="${_pkgname}-${_pkgversion}" ;;
          brew) _pkginstall="${_pkgname}@${_pkgversion}" ;;
          *) _pkginstall="${_pkgname}" ;;
        esac
      else
        _pkginstall="${_pkgname}"
      fi

      if [[ "$_skip_installed" == true ]] && command -v "$_pkgname" > /dev/null 2>&1; then
        logging__info "'${_pkgname}' already available in PATH — skipping."
        [[ -z "${_build_group:-}" ]] && _ospkg_protect_user_pkgs "$_pkgname"
        continue
      fi

      # For PMs that support per-package flags, build the install command.
      if [[ -n "${_pkgflags:-}" ]]; then
        if [[ "$_dry_run" == true ]]; then
          logging__inspect "[dry-run] package: ${_OSPKG_INSTALL[*]} ${_pkgflags} ${_pkginstall}"
        else
          logging__info "Installing: ${_pkginstall} (flags: ${_pkgflags})"
          # shellcheck disable=SC2086
          "${_OSPKG_INSTALL[@]}" $_pkgflags "$_pkginstall"
          [[ -z "${_build_group:-}" ]] && _ospkg_protect_user_pkgs "$_pkgname"
        fi
      else
        _pkgs_to_install+=("$_pkginstall")
        _pkg_base_names+=("$_pkgname")
      fi
    done

    if [[ ${#_pkgs_to_install[@]} -gt 0 ]]; then
      logging__install "Installing ${#_pkgs_to_install[@]} package(s)."
      if [[ "$_dry_run" == true ]]; then
        logging__inspect "[dry-run] packages: ${_pkgs_to_install[*]}"
      else
        ospkg__install "${_pkgs_to_install[@]}"
        [[ -z "${_build_group:-}" ]] && _ospkg_protect_user_pkgs "${_pkg_base_names[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 ]]; then
      logging__info "No packages to install — skipping."
    fi

    # Phase: CASKS (brew/macOS only).
    if [[ ${#_Y_CASKS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PKG_MNGR" == "brew" && "$(uname -s)" == "Darwin" ]]; then
        logging__info "Installing ${#_Y_CASKS[@]} Homebrew cask(s)."
        local _caskitem _cask
        for _caskitem in "${_Y_CASKS[@]}"; do
          _cask="$(printf '%s' "$_caskitem" | json__query -r '.cask')"
          if [[ "$_dry_run" == true ]]; then
            logging__inspect "[dry-run] cask: would run: brew install --cask '${_cask}'"
          else
            logging__info "Installing cask: ${_cask}"
            _ospkg_brew_run install --cask "$_cask"
            logging__success "Cask installed: ${_cask}"
          fi
        done
      else
        logging__warn "Casks are only supported on macOS with Homebrew — ignoring."
      fi
    fi

    # Phase: SCRIPTS.
    if [[ ${#_Y_SCRIPTS[@]} -gt 0 ]]; then
      local _combined_script=""
      local _sitem
      for _sitem in "${_Y_SCRIPTS[@]}"; do
        _combined_script+="$(printf '%s' "$_sitem" | json__query -r '.content')"$'\n'
      done
      _run_script "script" "$_combined_script"
      logging__success "Script(s) completed."
    else
      logging__info "No scripts found — skipping."
    fi

    # Phase: REPO CLEANUP.
    # Taps: always kept (never cleaned up).
    # Other repos: remove unless --keep_repos.
    if [[ "$_yaml_repo_added" == true && "$_keep_repos" == false ]]; then
      logging__remove "Removing added repositories."
      if [[ "$_OSPKG_FAMILY" = "apt" ]]; then
        users__run_privileged rm -f /etc/apt/sources.list.d/syspkg-installer.list
        logging__remove "Removed /etc/apt/sources.list.d/syspkg-installer.list"
      elif [[ "$_OSPKG_FAMILY" = "apk" ]]; then
        local _rl
        for _rl in "${_OSPKG_APK_ADDED_REPOS[@]}"; do
          users__run_privileged sed -i "\\|^${_rl}$|d" /etc/apk/repositories
          logging__remove "Removed APK repo: ${_rl}"
        done
      elif [[ "$_OSPKG_FAMILY" = "dnf" ]]; then
        users__run_privileged rm -f /etc/yum.repos.d/syspkg-installer.repo
        logging__remove "Removed /etc/yum.repos.d/syspkg-installer.repo"
      elif [[ "$_OSPKG_FAMILY" = "zypper" ]]; then
        users__run_privileged rm -f /etc/zypp/repos.d/syspkg-installer.repo
      elif [[ "$_OSPKG_FAMILY" = "pacman" ]]; then
        users__run_privileged rm -f /etc/pacman.d/syspkg-installer.conf
        users__run_privileged sed -i '/^Include = \/etc\/pacman.d\/syspkg-installer.conf$/d' /etc/pacman.conf
      fi
    elif [[ "$_yaml_repo_added" == true ]]; then
      logging__info "Keeping added repositories (--keep_repos)."
    fi

    # Phase: KEY CLEANUP.
    # Signing keys added during this run are removed unless --keep_repos.
    if [[ "$_yaml_key_added" == true && "$_keep_repos" == false ]]; then
      logging__remove "Removing installed signing keys."
      local _kpath
      for _kpath in "${_yaml_keys_written[@]}"; do
        rm -f "$_kpath"
        logging__remove "Removed signing key: ${_kpath}"
      done
    elif [[ "$_yaml_key_added" == true ]]; then
      logging__info "Keeping installed signing keys (--keep_repos)."
    fi

    # Apply build-group tracking: diff against pre-install snapshot, mark new packages.
    if [[ -n "$_build_group" && -n "$_before_snapshot_file" ]]; then
      _ospkg_mark_build_group "$_build_group" "$_before_snapshot_file"
      rm -f "$_before_snapshot_file"
    fi

  fi # end manifest processing

  return 0
}
