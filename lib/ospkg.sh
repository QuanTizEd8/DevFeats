#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

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

# ── Internal state ────────────────────────────────────────────────────────────
_OSPKG_DETECTED=false
_OSPKG_UPDATED=false
_OSPKG_PKG_MNGR=
_OSPKG_PREFIX=
_OSPKG_INSTALL=()
_OSPKG_UPDATE=()
_OSPKG_CLEAN=
_OSPKG_LISTS_PATH=
_OSPKG_LISTS_PATTERN=
_OSPKG_PREFER_LINUXBREW=false
_OSPKG_YQ_BIN=
declare -A _OSPKG_OS_RELEASE=()

# ── Private: clean functions ──────────────────────────────────────────────────
_ospkg_clean_apk() {
  rm -rf /var/cache/apk/*
  return 0
}
_ospkg_clean_apt() {
  apt-get clean
  # apt-get dist-clean is an APT 3.x command that removes /var/lib/apt/lists/*
  # while preserving the Release/InRelease files for security.
  # Docs: https://manpages.debian.org/unstable/apt/apt-get.8.en.html#distclean
  # Fall back to rm -rf on older APT (2.x and below) where the command does not exist.
  apt-get dist-clean 2> /dev/null || rm -rf /var/lib/apt/lists/*
  return 0
}
_ospkg_clean_dnf() {
  "${_OSPKG_INSTALL[0]%% *}" clean all 2> /dev/null || "$_OSPKG_PKG_MNGR" clean all
  rm -rf /var/cache/dnf/* /var/cache/yum/*
  return 0
}
_ospkg_clean_pacman() {
  pacman -Scc --noconfirm
  return 0
}
_ospkg_clean_zypper() {
  zypper clean --all
  return 0
}
_ospkg_clean_brew() {
  _ospkg_brew_run cleanup --prune=all 2> /dev/null || true
  return 0
}

# _ospkg_update_cmd: wraps _OSPKG_UPDATE for use with net__fetch_with_retry.
# Normalises non-fatal PM exit codes to 0:
#   dnf/yum exit 100 — "updates available" (informational, not a failure).
#   zypper exit 6    — ZYPPER_EXIT_INF_REPOS_SKIPPED: one or more repos were
#                      unreachable, but all reachable repos were refreshed OK.
#                      Common in containers that inherit subscription-only or
#                      stale mirror repos from the base image.
#
# Returns exit code 2 for non-transient configuration errors (malformed source
# lists, parse errors). net__fetch_with_retry --bail-on 2 will not retry these.
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
  [[ "$_OSPKG_PKG_MNGR" == "dnf" || "$_OSPKG_PKG_MNGR" == "yum" ]] &&
    [[ $_rc -eq 100 ]] && rm -f "$_err_tmp" && return 0
  [[ "$_OSPKG_PKG_MNGR" == "zypper" ]] && [[ $_rc -eq 6 ]] && rm -f "$_err_tmp" && return 0
  if [[ $_rc -ne 0 ]]; then
    # Detect non-transient configuration errors — retrying will never fix these.
    if grep -qiE 'Malformed line|source list could not be read|parse error|invalid source' \
      "$_err_tmp" 2> /dev/null; then
      echo "⛔ Package list update failed due to a configuration error — not retrying." >&2
      rm -f "$_err_tmp"
      return 2
    fi
  fi
  rm -f "$_err_tmp"
  return $_rc
}

# _ospkg_dnf_bin — Prints the name of the full-featured dnf binary, or returns 1.
#
# microdnf does not implement the `copr` or `module` subcommands.  This helper
# resolves a usable binary for those operations:
#   1. Full `dnf` in PATH — always preferred (even when microdnf is the detected PM).
#   2. `yum` as the detected PM — yum supports copr/module via plugins on older RHEL.
#   3. Otherwise — emit a clear error and return 1.
_ospkg_dnf_bin() {
  if command -v dnf > /dev/null 2>&1; then
    echo "dnf"
    return 0
  fi
  if [[ "$_OSPKG_PKG_MNGR" == "yum" ]]; then
    echo "yum"
    return 0
  fi
  echo "⛔ '${_OSPKG_PKG_MNGR}' does not support copr/module subcommands; install full dnf first." >&2
  return 1
}

# ── Private: key / repo helpers ──────────────────────────────────────────────
_ospkg_ensure_gpg() {
  command -v gpg > /dev/null 2>&1 && return 0
  echo "ℹ️  gpg not found — installing gnupg." >&2
  local _gpg_pkg
  case "$_OSPKG_PREFIX" in
    dnf) _gpg_pkg=gnupg2 ;;
    *) _gpg_pkg=gnupg ;;
  esac
  ospkg__install_tracked "sysset-ospkg-internals" "$_gpg_pkg"
  return 0
}

# _ospkg_key_effective_path <dest> <dearmor>
# Prints the filesystem path the key is written to (same rules as
# _ospkg_install_key_entry). dearmor: true | false | auto
_ospkg_key_effective_path() {
  local _dest="$1" _dearmor="${2:-auto}"
  [[ -z "${_dearmor}" || "${_dearmor}" == "null" ]] && _dearmor=auto
  if [[ "${_dearmor}" == "false" && "${_dest}" == *.gpg ]]; then
    printf '%s' "${_dest%.gpg}.key"
  else
    printf '%s' "${_dest}"
  fi
}

# _ospkg_install_key_entry <url> <dest> [dearmor] [fingerprint]
# dearmor: true = always pipe through gpg --dearmor; false = raw file (or .key if dest
#   would end in .gpg); any other value = auto: dearmor when dest ends in .gpg.
# fingerprint: 40-char hex GPG fingerprint. When url is empty, the key is fetched
#   from keyservers by fingerprint instead.
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
      echo "🔑 Installing key by fingerprint ${_fingerprint} → ${_target}" >&2
      _ospkg_install_key_by_fingerprint "${_fingerprint}" "${_target}"
      return $?
    fi
    echo "⛔ _ospkg_install_key_entry: neither url nor fingerprint provided." >&2
    return 1
  fi

  case "${_dearmor}" in
    true)
      _ospkg_ensure_gpg
      echo "🔑 Fetching and dearmoring key (dearmor: true) → ${_target}" >&2
      net__fetch_url_stdout "$_url" | gpg --dearmor -o "${_target}"
      ;;
    false)
      echo "🔑 Fetching key (dearmor: false) → ${_target}" >&2
      net__fetch_url_file "$_url" "${_target}"
      ;;
    auto)
      if [[ "${_dest}" == *.gpg ]]; then
        _ospkg_ensure_gpg
        echo "🔑 Fetching and dearmoring key (dest ends in .gpg) → ${_target}" >&2
        net__fetch_url_stdout "$_url" | gpg --dearmor -o "${_target}"
      else
        echo "🔑 Fetching key → ${_target}" >&2
        net__fetch_url_file "$_url" "${_target}"
      fi
      ;;
    *)
      echo "⛔ _ospkg_install_key_entry: invalid dearmor (use true, false, or auto): '${_dearmor}'" >&2
      return 1
      ;;
  esac
  chmod 0644 "${_target}"
  return 0
}

# _ospkg_install_key_by_fingerprint <fingerprint> <dest>
# Fetches and installs a GPG signing key by its 40-hex-char fingerprint.
# Tries Ubuntu HTTPS keyserver first, then two HKP keyserver fallbacks.
# Always writes a dearmored binary keyring to <dest>.
_ospkg_install_key_by_fingerprint() {
  local _fingerprint="$1" _dest="$2"
  _ospkg_ensure_gpg
  mkdir -p "$(dirname "$_dest")"

  # Primary: HTTPS download from Ubuntu keyserver.
  local _key_data
  _key_data="$(net__fetch_url_stdout \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${_fingerprint}" 2> /dev/null)" || true
  if printf '%s' "${_key_data}" | grep -q 'BEGIN PGP'; then
    if printf '%s' "${_key_data}" | gpg --dearmor -o "${_dest}"; then
      chmod 0644 "${_dest}"
      echo "✅ GPG key installed via HTTPS keyserver → ${_dest}" >&2
      return 0
    fi
  fi

  # Fallback: gpg --recv-keys via HKP keyservers.
  local _ks
  for _ks in "hkp://keyserver.ubuntu.com" "hkp://keyserver.pgp.com"; do
    echo "ℹ️  Trying keyserver ${_ks}..." >&2
    if gpg --recv-keys --keyserver "${_ks}" "${_fingerprint}" 2> /dev/null; then
      if gpg --export "${_fingerprint}" | gpg --dearmor -o "${_dest}"; then
        chmod 0644 "${_dest}"
        echo "✅ GPG key installed via ${_ks} → ${_dest}" >&2
        return 0
      fi
    fi
  done

  echo "⛔ Failed to install GPG key for fingerprint ${_fingerprint} from all keyservers." >&2
  return 1
}

# _ospkg_expand_content_vars <content>
# Substitutes ${key} tokens in <content> using values from _OSPKG_OS_RELEASE.
# Unknown tokens are left unchanged. Prints the expanded string (no trailing newline).
_ospkg_expand_content_vars() {
  local _content="$1" _k
  for _k in "${!_OSPKG_OS_RELEASE[@]}"; do
    _content="${_content//\$\{${_k}\}/${_OSPKG_OS_RELEASE[$_k]}}"
  done
  printf '%s' "$_content"
  return 0
}

# _ospkg_install_repo_content <content>
_ospkg_install_repo_content() {
  local _content
  _content="$(_ospkg_expand_content_vars "$1")"
  if [[ "$_OSPKG_PREFIX" = "apt" ]]; then
    printf '%s' "$_content" >> /etc/apt/sources.list.d/syspkg-installer.list
    echo "📄 Appended to /etc/apt/sources.list.d/syspkg-installer.list" >&2
  elif [[ "$_OSPKG_PREFIX" = "apk" ]]; then
    local _rline
    while IFS= read -r _rline; do
      [[ -z "${_rline:-}" || "${_rline}" =~ ^[[:space:]]*# ]] && continue
      echo "$_rline" >> /etc/apk/repositories
      _OSPKG_APK_ADDED_REPOS+=("$_rline")
      echo "📄 Added APK repo: ${_rline}" >&2
    done <<< "$_content"
  elif [[ "$_OSPKG_PREFIX" = "dnf" ]]; then
    printf '%s' "$_content" >> /etc/yum.repos.d/syspkg-installer.repo
    echo "📄 Appended to /etc/yum.repos.d/syspkg-installer.repo" >&2
  elif [[ "$_OSPKG_PREFIX" = "zypper" ]]; then
    printf '%s' "$_content" >> /etc/zypp/repos.d/syspkg-installer.repo
    echo "📄 Appended to /etc/zypp/repos.d/syspkg-installer.repo" >&2
  elif [[ "$_OSPKG_PREFIX" = "pacman" ]]; then
    mkdir -p /etc/pacman.d
    printf '%s' "$_content" >> /etc/pacman.d/syspkg-installer.conf
    grep -qxF 'Include = /etc/pacman.d/syspkg-installer.conf' /etc/pacman.conf ||
      echo "Include = /etc/pacman.d/syspkg-installer.conf" >> /etc/pacman.conf
    echo "📄 Written to /etc/pacman.d/syspkg-installer.conf" >&2
  fi
  return 0
}

# ── Private: brew user/root handling ─────────────────────────────────────────
# _ospkg_brew_run <args...>
# Runs brew with proper user context, handling the root restriction.
#   Non-root           → run directly
#   Root in container  → run directly (brew explicitly allows this)
#   Root on bare metal → su to brew prefix owner
_ospkg_brew_run() {
  if [[ "$(id -u)" -ne 0 ]]; then
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
    echo "⛔ Could not determine Homebrew prefix." >&2
    return 1
  }
  _owner="$(stat -f '%Su' "$_prefix" 2> /dev/null || stat -c '%U' "$_prefix" 2> /dev/null)"
  if [[ -z "${_owner:-}" || "$_owner" == "root" ]]; then
    brew "$@"
    return
  fi
  echo "ℹ️  Running brew as user '${_owner}' (brew prefix owner)." >&2
  os__run_as "$_owner" -- brew "$@"
  return 0
}

# ── Private: yq auto-installer ────────────────────────────────────────────────
# _ospkg_ensure_yq
# Ensures mikefarah/yq is available.  Sets _OSPKG_YQ_BIN.
# If a compatible yq is already in PATH it is reused; otherwise attempts to
# install from the package manager, then falls back to downloading from GitHub
# Releases if the package manager provides an incompatible or no yq.
# The download is verified against the release checksums file before the binary
# is marked executable.
_ospkg_ensure_yq() {
  [[ -n "${_OSPKG_YQ_BIN:-}" ]] && return 0
  # Accept any yq in PATH that understands the -o=json flag (mikefarah/yq).
  if command -v yq > /dev/null 2>&1 && yq -o=json '.' /dev/null > /dev/null 2>&1; then
    _OSPKG_YQ_BIN="yq"
    echo "ℹ️  yq already available: $(command -v yq)" >&2
    return 0
  fi
  # If yq is not in PATH at all, try installing from the package manager.
  # Modern distros (Ubuntu ≥22.04, Debian ≥12, Alpine ≥3.16) package mikefarah/yq.
  # Older distros package kislyuk/yq (incompatible) or nothing at all.
  if ! command -v yq > /dev/null 2>&1; then
    echo "ℹ️  yq not found — attempting package manager install." >&2
    ospkg__install_tracked "sysset-ospkg-internals" yq >&2 || true
    # Re-test after potential install.
    if command -v yq > /dev/null 2>&1 && yq -o=json '.' /dev/null > /dev/null 2>&1; then
      _OSPKG_YQ_BIN="yq"
      echo "ℹ️  yq installed from package manager: $(command -v yq)" >&2
      return 0
    fi
  fi
  # Package manager provided no yq or an incompatible one; fetch mikefarah/yq
  # from GitHub Releases using the stable /releases/latest/download/ redirect
  # URLs.  These bypass the GitHub API entirely, avoiding rate-limit failures
  # in Docker builds that run without a GITHUB_TOKEN.
  # shellcheck source=lib/checksum.sh
  . "$_OSPKG_LIB_DIR/checksum.sh"
  local _os _arch _yq_base _url _yq_dir _dest _expected_hash
  _os="$(os__kernel | tr '[:upper:]' '[:lower:]')" # linux | darwin
  _arch="$(os__arch)"
  case "$_arch" in
    x86_64) _arch="amd64" ;;
    aarch64 | arm64) _arch="arm64" ;;
    *)
      echo "⛔ yq: unsupported architecture '${_arch}'." >&2
      return 1
      ;;
  esac
  _yq_base="https://github.com/mikefarah/yq/releases/latest/download"
  _url="${_yq_base}/yq_${_os}_${_arch}"
  _yq_dir="$(logging__tmpdir "ospkg/yq")"
  _dest="${_yq_dir}/yq"
  echo "ℹ️  Downloading yq (${_os}/${_arch}) from GitHub Releases." >&2
  net__fetch_url_file "$_url" "$_dest"
  net__fetch_url_file "${_yq_base}/checksums" "${_yq_dir}/checksums"
  net__fetch_url_file "${_yq_base}/checksums_hashes_order" "${_yq_dir}/checksums_hashes_order"
  net__fetch_url_file "${_yq_base}/extract-checksum.sh" "${_yq_dir}/extract-checksum.sh"
  _expected_hash="$(cd "${_yq_dir}" && bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  # Guard against CDN soft errors: a lying CDN may return HTTP 200 with an
  # error-page body, making curl exit 0 but producing garbage content.
  # A valid SHA-256 hash is exactly 64 lowercase hex characters.
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "⛔ yq: extracted checksum is not a valid SHA-256 hash (got: '${_expected_hash:-<empty>}') — a download may have been corrupted by a CDN error page." >&2
    return 1
  fi
  if ! checksum__verify_sha256 "$_dest" "$_expected_hash"; then
    echo "⛔ yq: checksum verification failed — aborting." >&2
    return 1
  fi
  chmod +x "$_dest"
  _OSPKG_YQ_BIN="$_dest"
  echo "✅ yq downloaded to ${_dest}." >&2
  return 0
}

# ── Private: PM configuration helpers ────────────────────────────────────────
# Each _ospkg_set_* function configures the internal state for one PM family.
# Called only from ospkg__detect().

_ospkg_set_apt() {
  echo "🛠️  Detected ecosystem: APT (tool: apt-get)" >&2
  _OSPKG_PREFIX="apt"
  _OSPKG_PKG_MNGR="apt-get"
  _OSPKG_UPDATE=(apt-get update)
  _OSPKG_INSTALL=(apt-get -y install --no-install-recommends)
  _OSPKG_CLEAN=_ospkg_clean_apt
  _OSPKG_LISTS_PATH="/var/lib/apt/lists"
  _OSPKG_LISTS_PATTERN="*_Packages*"
  _OSPKG_OS_RELEASE[pm]="apt"
  _OSPKG_OS_RELEASE[deb_arch]="$(dpkg --print-architecture 2> /dev/null || uname -m)"
  return 0
}

_ospkg_set_apk() {
  echo "🛠️  Detected ecosystem: APK (tool: apk)" >&2
  _OSPKG_PREFIX="apk"
  _OSPKG_PKG_MNGR="apk"
  _OSPKG_UPDATE=(apk update)
  _OSPKG_INSTALL=(apk add --no-cache)
  _OSPKG_CLEAN=_ospkg_clean_apk
  _OSPKG_LISTS_PATH="/var/cache/apk"
  _OSPKG_LISTS_PATTERN="APKINDEX*"
  _OSPKG_OS_RELEASE[pm]="apk"
  return 0
}

_ospkg_set_dnf() {
  echo "🛠️  Detected ecosystem: DNF (tool: dnf)" >&2
  _OSPKG_PREFIX="dnf"
  _OSPKG_PKG_MNGR="dnf"
  _OSPKG_UPDATE=(dnf check-update)
  _OSPKG_INSTALL=(dnf -y install)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH="/var/cache/dnf"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="dnf"
  return 0
}

_ospkg_set_microdnf() {
  echo "🛠️  Detected ecosystem: DNF (tool: microdnf)" >&2
  _OSPKG_PREFIX="dnf"
  _OSPKG_PKG_MNGR="microdnf"
  _OSPKG_UPDATE=()
  _OSPKG_INSTALL=(microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH=""
  _OSPKG_LISTS_PATTERN=""
  _OSPKG_OS_RELEASE[pm]="dnf"
  return 0
}

_ospkg_set_yum() {
  echo "🛠️  Detected ecosystem: YUM (tool: yum)" >&2
  _OSPKG_PREFIX="dnf"
  _OSPKG_PKG_MNGR="yum"
  _OSPKG_UPDATE=(yum check-update)
  _OSPKG_INSTALL=(yum -y install)
  _OSPKG_CLEAN=_ospkg_clean_dnf
  _OSPKG_LISTS_PATH="/var/cache/yum"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="yum"
  return 0
}

_ospkg_set_zypper() {
  echo "🛠️  Detected ecosystem: Zypper (tool: zypper)" >&2
  _OSPKG_PREFIX="zypper"
  _OSPKG_PKG_MNGR="zypper"
  _OSPKG_UPDATE=(zypper --non-interactive refresh)
  _OSPKG_INSTALL=(zypper --non-interactive install)
  _OSPKG_CLEAN=_ospkg_clean_zypper
  _OSPKG_LISTS_PATH="/var/cache/zypp/raw"
  _OSPKG_LISTS_PATTERN="*"
  _OSPKG_OS_RELEASE[pm]="zypper"
  return 0
}

_ospkg_set_pacman() {
  echo "🛠️  Detected ecosystem: Pacman (tool: pacman)" >&2
  _OSPKG_PREFIX="pacman"
  _OSPKG_PKG_MNGR="pacman"
  _OSPKG_UPDATE=(pacman -Sy --noconfirm)
  _OSPKG_INSTALL=(pacman -S --noconfirm --needed)
  _OSPKG_CLEAN=_ospkg_clean_pacman
  _OSPKG_LISTS_PATH="/var/lib/pacman/sync"
  _OSPKG_LISTS_PATTERN="*.db"
  _OSPKG_OS_RELEASE[pm]="pacman"
  return 0
}

_ospkg_set_brew() {
  local _label="${1:-Linux}"
  echo "🛠️  Detected ecosystem: Homebrew (tool: brew) [${_label}]" >&2
  _OSPKG_PREFIX="brew"
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
  echo "🔍 OS context: pm=${_OSPKG_OS_RELEASE[pm]-} arch=${_OSPKG_OS_RELEASE[arch]-} id=${_OSPKG_OS_RELEASE[id]-} id_like=${_OSPKG_OS_RELEASE[id_like]-} version_id=${_OSPKG_OS_RELEASE[version_id]-} version_codename=${_OSPKG_OS_RELEASE[version_codename]-}" >&2
  return 0
}

# ── Public: ospkg__detect ────────────────────────────────────────────────────
# @brief ospkg__detect — Detect the package manager and populate internal state. Idempotent; called automatically by all other `ospkg__*` functions.
#
# Respects _OSPKG_PREFER_LINUXBREW: when true, brew is checked before the
# native Linux PM chain (no effect on macOS where brew is always used).
ospkg__detect() {
  [[ "$_OSPKG_DETECTED" == true ]] && return 0

  local _kernel
  _kernel="$(uname -s)"

  if [[ "$_kernel" == "Darwin" ]]; then
    # macOS: Homebrew is the only supported package manager.
    if ! type brew > /dev/null 2>&1; then
      echo "⛔ Homebrew (brew) not found on macOS." >&2
      echo "⛔ Install Homebrew first: https://brew.sh" >&2
      echo "⛔ Or add the 'install-homebrew' devcontainer feature." >&2
      return 1
    fi
    _ospkg_set_brew "macOS"
    _OSPKG_OS_RELEASE[kernel]="darwin"
    _OSPKG_OS_RELEASE[id]="macos"
    _OSPKG_OS_RELEASE[id_like]="macos"
    _OSPKG_OS_RELEASE[version_id]="$(sw_vers -productVersion 2> /dev/null || echo "")"
    _OSPKG_OS_RELEASE[arch]="$(uname -m)"
    echo "🔍 OS context: pm=brew arch=${_OSPKG_OS_RELEASE[arch]-} id=macos version_id=${_OSPKG_OS_RELEASE[version_id]-}" >&2
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
    echo "⛔ No supported package manager found." >&2
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
        echo "⛔ ospkg__update: unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ ${#_OSPKG_UPDATE[@]} -eq 0 ]]; then
    # microdnf bakes --refresh into every install call; no separate update step is needed.
    echo "ℹ️  Package list update handled per-install by '${_OSPKG_PKG_MNGR}' (--refresh) — skipping explicit update." >&2
    return 0
  fi

  local _skip=false
  if [[ "$_force" == true || "$_repo_added" == true ]]; then
    _skip=false
  elif [[ "$_OSPKG_UPDATED" == true ]]; then
    # Already ran an update in this process — skip unless force/repo_added.
    echo "ℹ️  Package lists already updated in this process — skipping." >&2
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
        echo "ℹ️  Package lists refreshed ${_age}s ago — skipping update (threshold: ${_max_age}s)." >&2
      fi
    fi
  fi

  if [[ "$_skip" == false ]]; then
    echo "🔄 Updating package lists." >&2
    net__fetch_with_retry --bail-on 2 _ospkg_update_cmd
    _OSPKG_UPDATED=true
    echo "✅ Package lists updated." >&2
  fi
  return 0
}

# ── Public: ospkg__install ───────────────────────────────────────────────────
# @brief ospkg__install <pkg>... — Install one or more packages. Skips if all are already installed (APT, DNF/YUM).
#
# Args:
#   <pkg>...  One or more package names to install.
ospkg__install() {
  ospkg__detect
  ospkg__update || true
  if [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
    echo "📲 Installing packages:" >&2
    printf '  - %s\n' "$@" >&2
    net__fetch_with_retry _ospkg_brew_run install "$@" >&2
    return 0
  fi
  if [[ "$_OSPKG_PKG_MNGR" = "apt-get" ]]; then
    if dpkg -s "$@" > /dev/null 2>&1; then
      echo "ℹ️  Packages already installed: $*" >&2
      return 0
    fi
  elif [[ "$_OSPKG_PKG_MNGR" = "dnf" || "$_OSPKG_PKG_MNGR" = "yum" ]]; then
    local _num_pkgs=$#
    local _num_installed
    _num_installed=$("$_OSPKG_PKG_MNGR" -C list installed "$@" 2> /dev/null | sed '1,/^Installed/d' | wc -l) || _num_installed=0
    if [[ $_num_pkgs -eq $_num_installed ]]; then
      echo "ℹ️  Packages already installed: $*" >&2
      return 0
    fi
  fi
  echo "📲 Installing packages:" >&2
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
  return 0
}

# ── Public: ospkg__clean ─────────────────────────────────────────────────────
# @brief ospkg__clean — Remove the package manager cache to reduce image layer size.
ospkg__clean() {
  ospkg__detect
  echo "🧹 Cleaning package manager cache." >&2
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

  local _pm="${_OSPKG_OS_RELEASE[pm]:-${_OSPKG_PREFIX}}"

  # shellcheck disable=SC2016
  json__query -c \
    --argjson ctx "$_ctx_json" \
    --arg pm "$_pm" \
    '
# ── Helper definitions ────────────────────────────────────────────────────────
def ic: ascii_downcase;
def ctx: $ctx;

def cond_matches(c):
  to_entries | all(
    .key as $k | .value as $v |
    (c[$k] // "") | ic as $actual |
    if ($v | type) == "array" then [($v[] | ic)] | any(. == $actual)
    else ($v | ic) == $actual
    end
  );

def when_matches:
  if has("when") | not then true
  elif .when == null then true
  elif (.when | type) == "array" then [.when[] | cond_matches(ctx)] | any
  elif (.when | type) == "object" then .when | cond_matches(ctx)
  else false
  end;

def to_lines: if type == "array" then join("\n") else . end;

def merge_flags(gf; pf):
  if   gf == null and pf == null then null
  elif gf == null then pf
  elif pf == null then gf
  else [(gf | if type == "array" then .[] else . end),
        (pf | if type == "array" then .[] else . end)] | join(" ")
  end;

# visit(k; inherited_flags): traverse packages array, emitting items of kind k.
def visit(k; gf):
  if type == "string" then
    if k == "package" then
      {kind: "package", name: ., flags: gf, version: null}
    else empty end
  elif has("packages") then
    # group object
    if when_matches then
      . as $g |
      merge_flags(gf; ($g.flags // null)) as $mf |
      if k == "prescript" then
        (if $g | has("prescript") then
          {kind: "prescript", content: ($g.prescript | to_lines)} else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "key" then
        (if $g | has("keys") then
          $g.keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
        else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "repo" then
        (if $g | has("repos") then $g.repos[] | {kind: "repo", content: (.content // .)} else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "package" then
        ($g.packages[] | visit(k; $mf))
      elif k == "script" then
        ($g.packages[] | visit(k; $mf)),
        (if $g | has("script") then
          {kind: "script", content: ($g.script | to_lines)} else empty end)
      else
        ($g.packages[] | visit(k; $mf))
      end
    else empty
    end
  else
    # package object
    if when_matches then
      . as $e |
      if k == "prescript" then
        if $e | has("prescript") then
          {kind: "prescript", content: ($e.prescript | to_lines)}
        else empty end
      elif k == "key" then
        if $e | has("keys") then
          $e.keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
        else empty end
      elif k == "repo" then
        if $e | has("repos") then $e.repos[] | {kind: "repo", content: (.content // .)} else empty end
      elif k == "package" then
        {kind: "package",
         name: (
           ($e[$pm] // $e.name) as $n
           | if ($n | type) == "string" and ($n | length) > 0 then $n else null end
         ),
         flags: merge_flags(gf; ($e.flags // null)),
         version: ($e.version // null)}
      elif k == "script" then
        if $e | has("script") then
          {kind: "script", content: ($e.script | to_lines)}
        else empty end
      else empty
      end
    else empty
    end
  end;

# ── Emit items in pipeline phase order ────────────────────────────────────────
. as $doc |

# Top-level when: skip entire manifest if it does not match.
if ($doc | has("when")) and (($doc | when_matches) | not) then
  empty
else

# Phase: PRESCRIPTS — top-level, then inline
(if $doc | has("prescripts") then
  {kind: "prescript", content: ($doc.prescripts | to_lines)} else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("prescript"; null) else empty end),

# Phase: KEYS — top-level, PM block, then inline
(if $doc | has("keys") then
  $doc.keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("keys")) then
  $doc[$pm].keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("key"; null) else empty end),

# Phase: REPOS — top-level, PM block, then inline
(if $doc | has("repos") then
  $doc.repos[] | {kind: "repo", content: (.content // .)}
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("repos")) then
  $doc[$pm].repos[] | {kind: "repo", content: (.content // .)}
else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("repo"; null) else empty end),

# Phase: PM-SPECIFIC SETUP — top-level then PM-block
(if $pm == "apt" then
  (if $doc | has("ppas") then $doc.ppas[] | {kind: "ppa", ppa: .} else empty end),
  (if ($doc | has("apt")) and ($doc.apt | has("ppas")) then
    $doc.apt.ppas[] | {kind: "ppa", ppa: .} else empty end)
else empty end),
(if $pm == "brew" then
  (if $doc | has("taps") then $doc.taps[] | {kind: "tap", tap: .} else empty end),
  (if ($doc | has("brew")) and ($doc.brew | has("taps")) then
    $doc.brew.taps[] | {kind: "tap", tap: .} else empty end)
else empty end),
(if $pm == "dnf" then
  (if $doc | has("copr") then $doc.copr[] | {kind: "copr", copr: .} else empty end),
  (if ($doc | has("dnf")) and ($doc.dnf | has("copr")) then
    $doc.dnf.copr[] | {kind: "copr", copr: .} else empty end)
else empty end),
(if $pm == "dnf" then
  (if $doc | has("modules") then $doc.modules[] | {kind: "module", module: .} else empty end),
  (if ($doc | has("dnf")) and ($doc.dnf | has("modules")) then
    $doc.dnf.modules[] | {kind: "module", module: .} else empty end)
else empty end),
(if $doc | has("groups") then
  $doc.groups[] |
  if type == "string" and (length) > 0 then {kind: "group", group: .}
  elif (type == "object") and when_matches
       and ((.name | type) == "string")
       and ((.name | length) > 0) then
    {kind: "group", group: .name}
  else empty
  end
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("groups")) then
  $doc[$pm].groups[] |
  if type == "string" and (length) > 0 then {kind: "group", group: .}
  elif (type == "object") and when_matches
       and ((.name | type) == "string")
       and ((.name | length) > 0) then
    {kind: "group", group: .name}
  else empty
  end
else empty end),

# Phase: PACKAGES — inline packages array, then PM-specific packages block
(if $doc | has("packages") then
  $doc.packages[] | visit("package"; null)
  | select(
      (.name | type) == "string"
      and ((.name | length) > 0)
    ) else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("packages")) then
  $doc[$pm].packages[] | visit("package"; null)
  | select(
      (.name | type) == "string"
      and ((.name | length) > 0)
    )
else empty end),

# Phase: CASKS (brew/macOS only) — top-level then PM block
(if $pm == "brew" then
  (if $doc | has("casks") then $doc.casks[] | {kind: "cask", cask: .} else empty end),
  (if ($doc | has("brew")) and ($doc.brew | has("casks")) then
    $doc.brew.casks[] | {kind: "cask", cask: .} else empty end)
else empty end),

# Phase: SCRIPTS — PM block, then top-level, then inline
(if ($doc | has($pm)) and ($doc[$pm] | has("scripts")) then
  {kind: "script", content: ($doc[$pm].scripts | to_lines)} else empty end),
(if $doc | has("scripts") then
  {kind: "script", content: ($doc.scripts | to_lines)} else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("script"; null) else empty end)

end
' "$_json_file"
  return 0
}

# ── Private: build-dep tracking ──────────────────────────────────────────────
# _ospkg_build_deps_dir — returns the directory used for build-dep sidecar files.
_ospkg_build_deps_dir() {
  printf '%s' "$(logging__tmpdir "ospkg/build-deps")"
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
    apt-get) apt-mark manual "$@" > /dev/null 2>&1 || true ;;
    dnf | yum) dnf mark user "$@" > /dev/null 2>&1 || true ;;
    pacman) pacman -D --asexplicit "$@" > /dev/null 2>&1 || true ;;
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
        echo "ℹ️  Evicted '${_pkg}' from build-group sidecar '${_sidecar_name}'." >&2
      fi
    done
  done
  return 0
}

# ── Public: ospkg__take_initial_snapshot ─────────────────────────────────────
# @brief ospkg__take_initial_snapshot <file> — Snapshot the current installed-
# package list to <file> for use as a session baseline. Called once by
# get.bash before any installs in manifest mode. Used by ospkg__install_tracked
# to exclude pre-existing packages from session co-ownership tracking.
ospkg__take_initial_snapshot() {
  local _dest="$1"
  ospkg__detect
  _ospkg_snapshot_packages "$_dest"
  echo "ℹ️  Initial package snapshot written to ${_dest}." >&2
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
    echo "ℹ️  Build group '${_group_id}': no new packages installed — nothing to track." >&2
    # Preserve an existing sidecar (may already list packages from a prior call
    # with the same group ID).  Only create an empty sentinel if not yet present.
    [[ ! -f "$_sidecar" ]] && : > "$_sidecar"
    return 0
  fi
  echo "ℹ️  Build group '${_group_id}': tracking ${#_new_pkgs[@]} package(s): ${_new_pkgs[*]}" >&2
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
      apt-mark auto "${_new_pkgs[@]}" >&2 || true
      ;;
    dnf | yum)
      dnf mark remove "${_new_pkgs[@]}" >&2 || true
      ;;
    pacman)
      pacman -D --asdeps "${_new_pkgs[@]}" >&2 || true
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
    echo "ℹ️  Build group '${_group_id}': sidecar not found — nothing to remove." >&2
    return 0
  fi
  local -a _pkgs=()
  mapfile -t _pkgs < "$_sidecar"
  if [[ ${#_pkgs[@]} -eq 0 ]]; then
    echo "ℹ️  Build group '${_group_id}': sidecar empty — nothing to remove." >&2
    return 0
  fi
  echo "🗑️  Build group '${_group_id}': removing ${#_pkgs[@]} package(s): ${_pkgs[*]}" >&2
  case "$_OSPKG_PKG_MNGR" in
    apt-get)
      # Packages were marked 'auto' at install time; autoremove handles transitive removal.
      apt-get -y --purge autoremove >&2 || true
      ;;
    apk)
      apk del "${_pkgs[@]}" >&2 || true
      ;;
    dnf | yum)
      # Packages were marked 'removable' at install time.
      dnf autoremove -y >&2 || true
      ;;
    microdnf)
      microdnf remove "${_pkgs[@]}" >&2 || true
      ;;
    zypper)
      zypper --non-interactive remove --clean-deps "${_pkgs[@]}" >&2 || true
      ;;
    pacman)
      # Packages were marked asdeps at install time; remove orphans.
      local _orphans
      _orphans="$(pacman -Qdtq 2> /dev/null)" || _orphans=""
      if [[ -n "$_orphans" ]]; then
        echo "$_orphans" | xargs pacman -Rs --noconfirm >&2 || true
      fi
      ;;
    brew)
      local _pkg
      for _pkg in "${_pkgs[@]}"; do
        if [[ -z "$(brew uses --installed "$_pkg" 2> /dev/null)" ]]; then
          _ospkg_brew_run remove "$_pkg" >&2 || true
        else
          echo "ℹ️  brew: keeping '$_pkg' (still in use)." >&2
        fi
      done
      ;;
  esac
  rm -f "$_sidecar"
  return 0
}

# ── Public: ospkg__install_tracked ────────────────────────────────────────────
# @brief ospkg__install_tracked <sub-id> <pkg>... — Install packages and register
# them as build-only under <sub-id> for cleanup when keep_build_deps=false.
# Idempotent: if all packages are already installed the sidecar is unchanged.
# Requires ospkg__detect to have been called first.
#
# The full group-id is composed as "${_SYSSET_BUILD_CONTEXT:-uncontexted}::<sub-id>".
# Callers pass only the bare sub-id (e.g. "lib-net", "sysset-ospkg-internals");
# the build-context prefix is added automatically.
#
# Session co-ownership: when _SYSSET_SESSION_TRACK_DIR is set (manifest mode),
# also appends each requested package absent from _SYSSET_INITIAL_SNAPSHOT to
# the session sidecar for _group_id. This registers co-ownership for packages
# already installed by a prior feature in the same session.
ospkg__install_tracked() {
  local _group_id="${_SYSSET_BUILD_CONTEXT:-uncontexted}::$1"
  shift
  local _bd_dir _before_snapshot
  _bd_dir="$(_ospkg_build_deps_dir)"
  _before_snapshot="${_bd_dir}/${_group_id//\//\_}.before"
  _ospkg_snapshot_packages "$_before_snapshot"
  ospkg__install "$@"
  _ospkg_mark_build_group "$_group_id" "$_before_snapshot"
  rm -f "$_before_snapshot"
  # Session co-ownership tracking (manifest mode only).
  # Register all requested packages not present in the initial snapshot so that
  # the get.bash coordinator can apply keep-wins policy across all co-owners.
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

# @brief ospkg__cleanup_all_build_groups — Remove every registered build-dep
# group (both feature-level groups and lib-level groups auto-created by
# ospkg__install_tracked).  Scans the build-deps sidecar directory and calls
# _ospkg_remove_build_group for each file found.
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

# @brief ospkg__cleanup_session_build_groups <get-bash-keep> — Manifest-mode
# coordinator. Reads co-ownership entries from _SYSSET_SESSION_TRACK_DIR,
# applies Rule 1 (keep wins over clean), then removes packages not kept by any
# co-owner. Deletes _SYSSET_SESSION_TRACK_DIR on completion.
#
# <get-bash-keep>: "true"|"false" — keep_build_deps for the get-bash context.
# Feature keep_build_deps is read from the _OPT_OF associative array (must be
# in scope when called from get.bash). Defaults to false when not found.
#
# No-ops when _SYSSET_SESSION_TRACK_DIR is unset or does not exist.
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
    #   "get-bash::bootstrap", "feature::install-gh::lib-net"
    if [[ "$_basename" == get-bash::* ]]; then
      _keep="$_getbash_keep"
    else
      # Extract feature ID from "feature::<id>::<module>" pattern.
      _feature_id="${_basename#feature::}"
      _feature_id="${_feature_id%%::*}"
      _keep=false
      # Read from _OPT_OF if declared in the caller's scope (get.bash).
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
    echo "🗑️  Session cleanup: removing ${#_to_remove[@]} build-dep package(s): ${_to_remove[*]}" >&2
    local _synth_dir _synth_sidecar
    _synth_dir="$(_ospkg_build_deps_dir)"
    _synth_sidecar="${_synth_dir}/__session_cleanup__"
    printf '%s\n' "${_to_remove[@]}" | sort > "$_synth_sidecar"
    _ospkg_remove_build_group "__session_cleanup__" || true
  else
    echo "ℹ️  Session cleanup: no packages to remove (all kept or nothing installed)." >&2
  fi

  rm -rf "$_SYSSET_SESSION_TRACK_DIR"
  return 0
}

# ── Public: resource tracking ─────────────────────────────────────────────────
# @brief ospkg__track_resource <group-id> <path>... — Register filesystem paths
# for cleanup alongside package cleanup. Paths are written to a resource sidecar
# in _SYSSET_TMPDIR/ospkg/resources/ (one path per line). When
# _SYSSET_SESSION_TRACK_DIR is set, also mirrors to the session dir so the
# get.bash coordinator can clean cross-feature resources.
ospkg__track_resource() {
  local _group_id="$1"
  shift
  local _res_dir _sidecar _path
  _res_dir="$(logging__tmpdir "ospkg/resources")"
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

# @brief ospkg__cleanup_resources — Remove all files registered via
# ospkg__track_resource. Reads resource sidecars from
# _SYSSET_TMPDIR/ospkg/resources/ and rm -f's each listed path.
# Non-fatal: removal failures emit a warning and continue.
ospkg__cleanup_resources() {
  local _res_dir
  _res_dir="$(logging__tmpdir "ospkg/resources")"
  [[ -d "$_res_dir" ]] || return 0
  local _sidecar _path
  for _sidecar in "$_res_dir"/*; do
    [[ -f "$_sidecar" ]] || continue
    while IFS= read -r _path; do
      [[ -z "$_path" ]] && continue
      if [[ -e "$_path" ]]; then
        rm -f "$_path" 2> /dev/null || echo "⚠️  ospkg__cleanup_resources: could not remove '${_path}'" >&2
      fi
    done < "$_sidecar"
    rm -f "$_sidecar"
  done
  return 0
}

# ── Public: ospkg__install_user ──────────────────────────────────────────────
# @brief ospkg__install_user <pkg>... — Install packages and protect them from
# build-group cleanup. Use this for all user-facing package installs.
#
# Calls ospkg__install then calls _ospkg_protect_user_pkgs with bare package
# names (version suffixes stripped per PM convention). Packages installed this
# way will not be removed by ospkg__cleanup_all_build_groups even if a prior
# build-group install had marked them as auto/asdeps or added them to a sidecar.
#
# Args:
#   <pkg>...  One or more package specs (versioned forms like gh=2.40.0 accepted).
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
# @brief ospkg__run [--manifest <f>] [--update <bool>] [--keep_repos] [--dry_run] [--skip_installed] [--interactive] [--build-group <id>] [--remove-build-group <id>] — Run the full installation pipeline from a manifest.
#
# Full pipeline: detect → root check → parse manifest → prescript → keys →
# repos → PM setup → update → install → casks → script.
#
# Cache cleanup is NOT performed by this function. Call ospkg__clean explicitly
# (e.g. via the _on_exit trap) when you want to purge the package manager cache.
#
# Args:
#   --manifest <f>          Path to the YAML manifest file.
#   --update <bool>         Run package index update before installing (default: true).
#   --keep_repos            Do not remove added third-party repo files after installation.
#   --dry_run               Print what would be installed without doing it.
#   --skip_installed        Skip packages that are already installed.
#   --interactive           Preserve TTY for interactive package prompts.
#   --build-group <id>      Mark all newly-installed packages as build-only and record
#                           them in a sidecar file for later cleanup. Requires --manifest.
#   --remove-build-group <id>  Remove previously-installed build-only packages using
#                              PM-native mechanisms. Does not require --manifest.
ospkg__run() {
  local _manifest='' _update=true _keep_repos=false
  local _lists_max_age=300 _dry_run=false _skip_installed=false _interactive=false
  local _prefer_linuxbrew=false _build_group='' _remove_build_group=''

  while [[ $# -gt 0 ]]; do
    case $1 in
      --manifest)
        shift
        _manifest="$1"
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
        echo "⛔ ospkg__run: unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if ! [[ "$_lists_max_age" =~ ^[0-9]+$ ]]; then
    echo "⛔ ospkg__run: invalid lists_max_age value: '$_lists_max_age'." >&2
    return 1
  fi

  if [[ -n "$_build_group" && -z "$_manifest" ]]; then
    echo "⛔ ospkg__run: --build-group requires --manifest." >&2
    return 1
  fi

  if [[ -n "$_remove_build_group" && (-n "$_build_group" || -n "$_manifest") ]]; then
    echo "⛔ ospkg__run: --remove-build-group must be used alone (no --manifest or --build-group)." >&2
    return 1
  fi

  [[ "$_dry_run" == true ]] && echo "🔍 Dry-run mode enabled — no changes will be made." >&2

  # Set prefer_linuxbrew early so detect() picks it up.
  _OSPKG_PREFER_LINUXBREW="$_prefer_linuxbrew"

  ospkg__detect

  # Root check: brew is exempt (it manages its own user/root logic via _ospkg_brew_run).
  if [[ "$_dry_run" == false && "$_OSPKG_PKG_MNGR" != "brew" ]]; then
    os__require_root
  fi

  # --remove-build-group: cleanup build-only packages and return immediately.
  if [[ -n "$_remove_build_group" ]]; then
    if [[ "$_dry_run" == true ]]; then
      echo "🔍 [dry-run] remove-build-group '${_remove_build_group}' — would remove build-only packages." >&2
      return 0
    fi
    _ospkg_remove_build_group "$_remove_build_group"
    return 0
  fi

  if [[ "$_OSPKG_PKG_MNGR" = "apt-get" && "$_interactive" == false ]]; then
    echo "🆗 Setting APT to non-interactive mode." >&2
    export DEBIAN_FRONTEND=noninteractive
  fi

  # Resolve manifest content.
  local _manifest_content=
  if [[ -n "$_manifest" ]]; then
    if [[ "$_manifest" == *$'\n'* ]]; then
      _manifest_content="$_manifest"
    elif [[ -f "$_manifest" ]]; then
      _manifest_content="$(< "$_manifest")"
    else
      echo "⛔ Manifest file not found: '$_manifest'" >&2
      return 1
    fi
  fi

  # Take a package snapshot before installation when build-group tracking is enabled.
  local _before_snapshot_file=''
  if [[ -n "$_build_group" && "$_dry_run" == false ]]; then
    local _bd_dir
    _bd_dir="$(_ospkg_build_deps_dir)"
    _before_snapshot_file="${_bd_dir}/${_build_group//\//_}.before"
    echo "ℹ️  Build group '${_build_group}': recording pre-install package snapshot." >&2
    _ospkg_snapshot_packages "$_before_snapshot_file"
  fi

  # ── YAML / JSON manifest path ──────────────────────────────────────────────
  if [[ -n "$_manifest_content" ]]; then

    # yq is required to convert YAML to JSON.
    if ! _ospkg_ensure_yq; then
      echo "⛔ yq is required for YAML manifests but could not be obtained." >&2
      return 1
    fi

    # Convert YAML (or JSON) to JSON via yq, then parse into phase arrays.
    # Temp files live inside _SYSSET_TMPDIR so logging__cleanup removes them
    # automatically on exit, even on unexpected failure.
    local _ospkg_dir _json_tmp
    _ospkg_dir="$(logging__tmpdir "ospkg")"
    _json_tmp="$(mktemp "${_ospkg_dir}/yaml_XXXXXX")"

    local -a _Y_PRESCRIPTS=() _Y_KEYS=() _Y_REPOS=() _Y_PPAS=() _Y_TAPS=() _Y_COPR=()
    local -a _Y_MODULES=() _Y_GROUPS=() _Y_PACKAGES=() _Y_CASKS=() _Y_SCRIPTS=()

    echo "ℹ️  Converting manifest to JSON via yq." >&2
    if [[ "$_manifest_content" == *$'\n'* ]]; then
      printf '%s' "$_manifest_content" | "$_OSPKG_YQ_BIN" -o=json '.' - > "$_json_tmp"
    else
      "$_OSPKG_YQ_BIN" -o=json '.' - <<< "$_manifest_content" > "$_json_tmp" 2> /dev/null ||
        echo "$_manifest_content" | "$_OSPKG_YQ_BIN" -o=json '.' - > "$_json_tmp"
    fi

    local _item _kind
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
    done < <(ospkg__parse_manifest_yaml "$_json_tmp")
    rm -f "$_json_tmp"
    echo "ℹ️  YAML manifest parsed: ${#_Y_PRESCRIPTS[@]} prescript(s), ${#_Y_KEYS[@]} key(s), ${#_Y_REPOS[@]} repo(s), ${#_Y_PPAS[@]} ppa(s), ${#_Y_TAPS[@]} tap(s), ${#_Y_COPR[@]} copr(s), ${#_Y_MODULES[@]} module(s), ${#_Y_GROUPS[@]} group(s), ${#_Y_PACKAGES[@]} package(s), ${#_Y_CASKS[@]} cask(s), ${#_Y_SCRIPTS[@]} script(s)." >&2

    # Helper: run a shell script with dry-run support.
    _run_script() {
      local _label="$1" _content="$2"
      local _stmp
      _stmp="$(mktemp "${_ospkg_dir}/script_XXXXXX")"
      printf '%s\n' "$_content" > "$_stmp"
      chmod +x "$_stmp"
      echo "🚀 Running ${_label}." >&2
      if [[ "$_dry_run" == true ]]; then
        echo "🔍 [dry-run] ${_label} — would execute:" >&2
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
      echo "✅ Prescript(s) completed." >&2
    else
      echo "ℹ️  No prescripts found — skipping." >&2
    fi

    local _yaml_key_added=false
    local -a _yaml_keys_written=()

    # Phase: SIGNING KEYS.
    if [[ ${#_Y_KEYS[@]} -gt 0 ]]; then
      echo "🔑 Installing ${#_Y_KEYS[@]} signing key(s)." >&2
      local _key_gnupghome
      _key_gnupghome="$(mktemp -d "${_SYSSET_TMPDIR:-${TMPDIR:-/tmp}}/ospkg_gnupg_XXXXXX")"
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
            echo "🔍 [dry-run] key: fingerprint=${_kfp} → ${_keff}" >&2
          elif [[ "${_keff}" != "${_kdest}" ]]; then
            echo "🔍 [dry-run] key: ${_kurl} → ${_keff} (dearmor=${_kdearmor}; manifest dest=${_kdest})" >&2
          else
            echo "🔍 [dry-run] key: ${_kurl} → ${_keff} (dearmor=${_kdearmor})" >&2
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
      echo "✅ Signing keys installed." >&2
    else
      echo "ℹ️  No signing keys found — skipping." >&2
    fi

    # Phase: REPOS.
    local _yaml_repo_added=false
    local _OSPKG_APK_ADDED_REPOS=()
    if [[ ${#_Y_REPOS[@]} -gt 0 ]]; then
      echo "🗃  Adding ${#_Y_REPOS[@]} repository entry/entries." >&2
      local _ritem _rcontent
      for _ritem in "${_Y_REPOS[@]}"; do
        _rcontent="$(printf '%s' "$_ritem" | json__query -r '.content')"
        if [[ "$_dry_run" == true ]]; then
          echo "🔍 [dry-run] repo: would add: ${_rcontent}" >&2
        else
          _ospkg_install_repo_content "${_rcontent}"$'\n'
          _yaml_repo_added=true
        fi
      done
    else
      echo "ℹ️  No repo entries found — skipping." >&2
    fi

    # Phase: PPAs (APT only).
    if [[ ${#_Y_PPAS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PREFIX" == "apt" ]]; then
        echo "📎 Adding ${#_Y_PPAS[@]} PPA(s)." >&2
        if ! command -v add-apt-repository > /dev/null 2>&1; then
          echo "ℹ️  add-apt-repository not found — installing software-properties-common." >&2
          [[ "$_dry_run" == false ]] && ospkg__install_tracked "sysset-ospkg-internals" software-properties-common
        fi
        local _ppitem _ppa
        for _ppitem in "${_Y_PPAS[@]}"; do
          _ppa="$(printf '%s' "$_ppitem" | json__query -r '.ppa')"
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] ppa: would run: add-apt-repository -y '${_ppa}'" >&2
          else
            echo "📎 Adding PPA: ${_ppa}" >&2
            add-apt-repository -y "$_ppa"
            _yaml_repo_added=true
            echo "✅ PPA added: ${_ppa}" >&2
          fi
        done
      else
        echo "⚠️  PPAs are only supported on APT — ignoring (current PM: ${_OSPKG_PKG_MNGR})." >&2
      fi
    fi

    # Phase: TAPS (brew only).
    if [[ ${#_Y_TAPS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PKG_MNGR" == "brew" ]]; then
        echo "🍺 Adding ${#_Y_TAPS[@]} Homebrew tap(s)." >&2
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
            echo "🔍 [dry-run] tap: would run: brew tap ${_tap_name}${_tap_url:+ ${_tap_url}}" >&2
          else
            echo "🍺 Tapping: ${_tap_name}" >&2
            if [[ -n "${_tap_url:-}" ]]; then
              _ospkg_brew_run tap "$_tap_name" "$_tap_url"
            else
              _ospkg_brew_run tap "$_tap_name"
            fi
            echo "✅ Tap added: ${_tap_name}" >&2
          fi
        done
      else
        echo "⚠️  Homebrew taps are only supported when PM is brew — ignoring." >&2
      fi
    fi

    # Phase: COPR (DNF only).
    if [[ ${#_Y_COPR[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PREFIX" == "dnf" ]]; then
        local _copr_dnf_bin
        if ! _copr_dnf_bin="$(_ospkg_dnf_bin)"; then
          echo "⚠️  COPR repos require full dnf — '${_OSPKG_PKG_MNGR}' does not support 'copr enable'; skipping." >&2
        else
          echo "🧩 Enabling ${#_Y_COPR[@]} COPR repo(s)." >&2
          local _copritem _copr
          for _copritem in "${_Y_COPR[@]}"; do
            _copr="$(printf '%s' "$_copritem" | json__query -r '.copr')"
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] copr: would run: ${_copr_dnf_bin} copr enable -y '${_copr}'" >&2
            else
              echo "🧩 Enabling COPR: ${_copr}" >&2
              "$_copr_dnf_bin" copr enable -y "$_copr"
              _yaml_repo_added=true
            fi
          done
        fi
      else
        echo "⚠️  COPR repos are only supported on DNF — ignoring (current PM: ${_OSPKG_PKG_MNGR})." >&2
      fi
    fi

    # Phase: MODULES (DNF only).
    if [[ ${#_Y_MODULES[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PREFIX" == "dnf" ]]; then
        local _mod_dnf_bin
        if ! _mod_dnf_bin="$(_ospkg_dnf_bin)"; then
          echo "⚠️  DNF module streams require full dnf — '${_OSPKG_PKG_MNGR}' does not support 'module enable'; skipping." >&2
        else
          echo "🔩 Enabling ${#_Y_MODULES[@]} DNF module stream(s)." >&2
          local _moditem _mod
          for _moditem in "${_Y_MODULES[@]}"; do
            _mod="$(printf '%s' "$_moditem" | json__query -r '.module')"
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] module: would run: ${_mod_dnf_bin} module enable -y '${_mod}'" >&2
            else
              echo "🔩 Enabling module: ${_mod}" >&2
              "$_mod_dnf_bin" module enable -y "$_mod"
              echo "✅ Module enabled: ${_mod}" >&2
            fi
          done
        fi
      else
        echo "⚠️  DNF modules are only supported on DNF — ignoring (current PM: ${_OSPKG_PKG_MNGR})." >&2
      fi
    fi

    # Phase: GROUPS.
    if [[ ${#_Y_GROUPS[@]} -gt 0 ]]; then
      local _grpitem _grp
      for _grpitem in "${_Y_GROUPS[@]}"; do
        _grp="$(printf '%s' "$_grpitem" | json__query -r '.group')"
        case "$_OSPKG_PREFIX" in
          dnf)
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] group: would run: ${_OSPKG_PKG_MNGR} group install -y '${_grp}'" >&2
            else
              echo "📦 Installing group '${_grp}' (dnf)." >&2
              "$_OSPKG_PKG_MNGR" group install -y "$_grp"
              echo "✅ Group '${_grp}' installed." >&2
            fi
            ;;
          zypper)
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] group: would run: zypper --non-interactive install -t pattern '${_grp}'" >&2
            else
              echo "📦 Installing pattern '${_grp}' (zypper)." >&2
              zypper --non-interactive install -t pattern "$_grp"
            fi
            ;;
          pacman)
            if [[ "$_dry_run" == true ]]; then
              echo "🔍 [dry-run] group: would run: ${_OSPKG_INSTALL[*]} '${_grp}'" >&2
            else
              echo "📦 Installing group '${_grp}' (pacman)." >&2
              ospkg__install "$_grp"
              if [[ -z "${_build_group:-}" ]]; then
                local -a _grp_members=()
                mapfile -t _grp_members < <(pacman -Sg "$_grp" 2> /dev/null | awk '{print $2}')
                [[ ${#_grp_members[@]} -gt 0 ]] && _ospkg_protect_user_pkgs "${_grp_members[@]}"
              fi
            fi
            ;;
          *)
            echo "⚠️  Group '${_grp}' — groups not supported on '${_OSPKG_PKG_MNGR}'; skipping." >&2
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
          echo "🔍 [dry-run] update: would run: ${_OSPKG_UPDATE[*]}" >&2
        else
          echo "ℹ️  Package list update not supported by '${_OSPKG_PKG_MNGR}' — skipping." >&2
        fi
      else
        ospkg__update "${_update_args[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 && "$_yaml_repo_added" == false ]]; then
      echo "ℹ️  Package list update skipped (no packages and no repos in manifest)." >&2
    else
      echo "ℹ️  Package list update skipped (update=false)." >&2
      _OSPKG_UPDATED=true
      if [[ "$_yaml_repo_added" == true ]]; then
        echo "⚠️  A repository was added but update=false — packages may not be found." >&2
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
        case "$_OSPKG_PREFIX" in
          apt | apk | pacman | zypper) _pkginstall="${_pkgname}=${_pkgversion}" ;;
          dnf | yum) _pkginstall="${_pkgname}-${_pkgversion}" ;;
          brew) _pkginstall="${_pkgname}@${_pkgversion}" ;;
          *) _pkginstall="${_pkgname}" ;;
        esac
      else
        _pkginstall="${_pkgname}"
      fi

      if [[ "$_skip_installed" == true ]] && command -v "$_pkgname" > /dev/null 2>&1; then
        echo "ℹ️  '${_pkgname}' already available in PATH — skipping." >&2
        [[ -z "${_build_group:-}" ]] && _ospkg_protect_user_pkgs "$_pkgname"
        continue
      fi

      # For PMs that support per-package flags, build the install command.
      if [[ -n "${_pkgflags:-}" ]]; then
        if [[ "$_dry_run" == true ]]; then
          echo "🔍 [dry-run] package: ${_OSPKG_INSTALL[*]} ${_pkgflags} ${_pkginstall}" >&2
        else
          echo "📲 Installing: ${_pkginstall} (flags: ${_pkgflags})" >&2
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
      echo "📦 Installing ${#_pkgs_to_install[@]} package(s)." >&2
      if [[ "$_dry_run" == true ]]; then
        echo "🔍 [dry-run] packages: ${_pkgs_to_install[*]}" >&2
      else
        ospkg__install "${_pkgs_to_install[@]}"
        [[ -z "${_build_group:-}" ]] && _ospkg_protect_user_pkgs "${_pkg_base_names[@]}"
      fi
    elif [[ ${#_Y_PACKAGES[@]} -eq 0 ]]; then
      echo "ℹ️  No packages to install — skipping." >&2
    fi

    # Phase: CASKS (brew/macOS only).
    if [[ ${#_Y_CASKS[@]} -gt 0 ]]; then
      if [[ "$_OSPKG_PKG_MNGR" == "brew" && "$(uname -s)" == "Darwin" ]]; then
        echo "🍺 Installing ${#_Y_CASKS[@]} Homebrew cask(s)." >&2
        local _caskitem _cask
        for _caskitem in "${_Y_CASKS[@]}"; do
          _cask="$(printf '%s' "$_caskitem" | json__query -r '.cask')"
          if [[ "$_dry_run" == true ]]; then
            echo "🔍 [dry-run] cask: would run: brew install --cask '${_cask}'" >&2
          else
            echo "🍺 Installing cask: ${_cask}" >&2
            _ospkg_brew_run install --cask "$_cask"
            echo "✅ Cask installed: ${_cask}" >&2
          fi
        done
      else
        echo "⚠️  Casks are only supported on macOS with Homebrew — ignoring." >&2
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
      echo "✅ Script(s) completed." >&2
    else
      echo "ℹ️  No scripts found — skipping." >&2
    fi

    # Phase: REPO CLEANUP.
    # Taps: always kept (never cleaned up).
    # Other repos: remove unless --keep_repos.
    if [[ "$_yaml_repo_added" == true && "$_keep_repos" == false ]]; then
      echo "🗑️  Removing added repositories." >&2
      if [[ "$_OSPKG_PREFIX" = "apt" ]]; then
        rm -f /etc/apt/sources.list.d/syspkg-installer.list
        echo "🗑️  Removed /etc/apt/sources.list.d/syspkg-installer.list" >&2
      elif [[ "$_OSPKG_PREFIX" = "apk" ]]; then
        local _rl
        for _rl in "${_OSPKG_APK_ADDED_REPOS[@]}"; do
          sed -i "\\|^${_rl}$|d" /etc/apk/repositories
          echo "🗑️  Removed APK repo: ${_rl}" >&2
        done
      elif [[ "$_OSPKG_PREFIX" = "dnf" ]]; then
        rm -f /etc/yum.repos.d/syspkg-installer.repo
        echo "🗑️  Removed /etc/yum.repos.d/syspkg-installer.repo" >&2
      elif [[ "$_OSPKG_PREFIX" = "zypper" ]]; then
        rm -f /etc/zypp/repos.d/syspkg-installer.repo
      elif [[ "$_OSPKG_PREFIX" = "pacman" ]]; then
        rm -f /etc/pacman.d/syspkg-installer.conf
        sed -i '/^Include = \/etc\/pacman.d\/syspkg-installer.conf$/d' /etc/pacman.conf
      fi
    elif [[ "$_yaml_repo_added" == true ]]; then
      echo "ℹ️  Keeping added repositories (--keep_repos)." >&2
    fi

    # Phase: KEY CLEANUP.
    # Signing keys added during this run are removed unless --keep_repos.
    if [[ "$_yaml_key_added" == true && "$_keep_repos" == false ]]; then
      echo "🗑️  Removing installed signing keys." >&2
      local _kpath
      for _kpath in "${_yaml_keys_written[@]}"; do
        rm -f "$_kpath"
        echo "🗑️  Removed signing key: ${_kpath}" >&2
      done
    elif [[ "$_yaml_key_added" == true ]]; then
      echo "ℹ️  Keeping installed signing keys (--keep_repos)." >&2
    fi

    # Apply build-group tracking: diff against pre-install snapshot, mark new packages.
    if [[ -n "$_build_group" && -n "$_before_snapshot_file" ]]; then
      _ospkg_mark_build_group "$_build_group" "$_before_snapshot_file"
      rm -f "$_before_snapshot_file"
    fi

  fi # end manifest processing

  return 0
}
