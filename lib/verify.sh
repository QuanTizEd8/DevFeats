#!/usr/bin/env bash
# verify.sh — Artifact integrity verification: SHA hash checking and GPG signature verification.
# Do not edit _lib/ copies directly — edit lib/ instead.

[ -n "${_VERIFY__LIB_LOADED-}" ] && return 0
_VERIFY__LIB_LOADED=1

_VERIFY__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_VERIFY__LIB_DIR/ospkg.sh"
# shellcheck source=lib/net.sh
[[ -z "${_NET__LIB_LOADED-}" ]] && . "$_VERIFY__LIB_DIR/net.sh"

# ── SHA hash verification ─────────────────────────────────────────────────────

# Try sha<algo>sum then shasum; return 1 if neither is found.
_verify__sha_dispatch() {
  local _file="$1" _algo="$2"
  if command -v "sha${_algo}sum" > /dev/null 2>&1; then
    "sha${_algo}sum" "$_file" | awk '{print $1}'
  elif command -v shasum > /dev/null 2>&1; then
    shasum --algorithm "${_algo}" "$_file" | awk '{print $1}'
  else
    return 1
  fi
}

# @brief verify__hash_file <file> [algo] — Print lowercase hex digest of `<file>` to stdout.
#
# `algo` is `256` (default) or `512`.
# Uses sha<N>sum (Linux/coreutils) or shasum --algorithm <N> (macOS/Perl).
# Falls back to installing coreutils via ospkg when neither tool exists.
#
# Args:
#   <file>   Path to an existing regular file.
#   [algo]   Hash algorithm: 256 (default) or 512.
verify__hash_file() {
  local _file="$1"
  local _algo="${2:-256}"
  [ -f "$_file" ] || return 1
  _verify__sha_dispatch "$_file" "$_algo" && return
  logging__info "sha${_algo}sum/shasum not found — installing coreutils."
  ospkg__install_tracked "lib-verify" coreutils
  _verify__sha_dispatch "$_file" "$_algo" || {
    logging__error "verify__hash_file: no sha${_algo}sum or shasum available after coreutils install."
    return 1
  }
}

# @brief verify__sha <file> <expected_hash> [algo] — Verify the digest of `<file>`. Returns 1 on mismatch.
#
# `algo` is `256` (default) or `512`.
#
# Args:
#   <file>           Path to the file to verify.
#   <expected_hash>  Expected lowercase hex digest.
#   [algo]           Hash algorithm: 256 (default) or 512.
verify__sha() {
  local _file="$1"
  local _expected="$2"
  local _algo="${3:-256}"
  local _actual

  _actual="$(verify__hash_file "$_file" "$_algo")" || return 1

  if [ "$_expected" = "$_actual" ]; then
    logging__success "Checksum verification passed."
  else
    logging__fatal "Checksum verification failed."
    logging__error "   Expected: ${_expected}"
    logging__error "   Actual:   ${_actual}"
    return 1
  fi
  return 0
}

# @brief verify__sha_sidecar <file> <hash_file> [algo] — Read expected hash from first field of `<hash_file>` and delegate to verify__sha.
#
# Suitable for the common `<name>.sha256` / `<name>.sha512` sidecar file pattern.
#
# Args:
#   <file>       Path to the file to verify.
#   <hash_file>  Path to the sidecar file containing the expected hash.
#   [algo]       Hash algorithm: 256 (default) or 512.
verify__sha_sidecar() {
  local _file="$1"
  local _hash_file="$2"
  local _algo="${3:-256}"
  local _expected
  _expected="$(awk '{print $1}' "$_hash_file")"
  [ -z "$_expected" ] && {
    logging__error "verify__sha_sidecar: could not read hash from '${_hash_file}'."
    return 1
  }
  verify__sha "$_file" "$_expected" "$_algo"
  return $?
}

# ── GPG signature verification ────────────────────────────────────────────────

# @brief verify__gpg_ensure [group_id] — Ensure `gpg` is available, auto-installing gnupg if needed.
#
# Installs `gnupg` (or `gnupg2` on dnf/yum) via ospkg tracked under `group_id`.
#
# Args:
#   [group_id]  Tracking group for the auto-installed package (default: lib-verify).
verify__gpg_ensure() {
  local _group="${1:-lib-verify}"
  command -v gpg > /dev/null 2>&1 && return 0
  logging__info "gpg not found — installing gnupg."
  ospkg__detect || return 1
  local _pkg="gnupg"
  case "${_OSPKG_PKG_MNGR:-}" in
    dnf | yum) _pkg="gnupg2" ;;
  esac
  ospkg__install_tracked "$_group" "$_pkg" || return 1
  command -v gpg > /dev/null 2>&1 || {
    logging__error "verify__gpg_ensure: gpg still not found after installing ${_pkg}."
    return 1
  }
}

# @brief verify__gpg_detached <file> <sig_file> <key_file> [group_id] — Verify a file against a detached ASCII-armored signature.
#
# Creates an isolated GNUPGHOME, imports the key, runs `gpg --verify`, then
# removes the temporary keyring. The caller is responsible for downloading
# `sig_file` and `key_file` before calling this function.
#
# Args:
#   <file>      Path to the artifact to verify.
#   <sig_file>  Path to the detached PGP signature file (.asc or .sig).
#   <key_file>  Path to the ASCII-armored or binary public key to verify against.
#   [group_id]  Tracking group used when auto-installing gpg (default: lib-verify).
verify__gpg_detached() {
  local _file="$1" _sig="${2-}" _key="${3-}" _group="${4:-lib-verify}"
  [[ -f "$_file" ]] || { logging__error "verify__gpg_detached: artifact not found: '${_file}'."; return 1; }
  [[ -f "$_sig" ]] || { logging__error "verify__gpg_detached: signature file not found: '${_sig}'."; return 1; }
  [[ -f "$_key" ]] || { logging__error "verify__gpg_detached: key file not found: '${_key}'."; return 1; }

  verify__gpg_ensure "$_group" || return 1

  local _ghome
  _ghome="$(mktemp -d)"
  chmod 0700 "$_ghome"

  if ! gpg --homedir "$_ghome" --import "$_key" > /dev/null 2>&1; then
    logging__error "verify__gpg_detached: failed to import key from '${_key}'."
    rm -rf "$_ghome"
    return 1
  fi

  if ! gpg --homedir "$_ghome" --verify "$_sig" "$_file" > /dev/null 2>&1; then
    logging__error "verify__gpg_detached: signature verification failed for '$(basename "$_file")'."
    rm -rf "$_ghome"
    return 1
  fi

  rm -rf "$_ghome"
  logging__success "Signature verification passed for '$(basename "$_file")'."
  return 0
}

# @brief verify__gpg_dearmor_stream <dest_file> [group_id] — Read ASCII-armored key from stdin and write dearmored binary keyring to `<dest_file>`.
#
# Args:
#   <dest_file>  Destination path for the dearmored binary keyring.
#   [group_id]   Tracking group for auto-installing gpg (default: lib-verify).
verify__gpg_dearmor_stream() {
  local _dest="$1" _group="${2:-lib-verify}"
  verify__gpg_ensure "$_group" || return 1
  gpg --dearmor -o "$_dest"
}

# @brief verify__gpg_fetch_key_by_fingerprint <fingerprint> <dest> [group_id] — Fetch a GPG public key by fingerprint and write a dearmored binary keyring to `<dest>`.
#
# Tries Ubuntu HTTPS keyserver first, then HKP keyserver fallbacks.
# The HKP path uses an isolated GNUPGHOME so the system keyring is not polluted.
#
# Args:
#   <fingerprint>  40-hex-char GPG key fingerprint (with or without leading 0x).
#   <dest>         Destination path for the dearmored binary keyring.
#   [group_id]     Tracking group for auto-installing gpg (default: lib-verify).
verify__gpg_fetch_key_by_fingerprint() {
  local _fingerprint="$1" _dest="$2" _group="${3:-lib-verify}"
  verify__gpg_ensure "$_group" || return 1
  mkdir -p "$(dirname "$_dest")"

  # Primary: HTTPS download from Ubuntu keyserver.
  local _key_data
  _key_data="$(net__fetch_url_stdout \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${_fingerprint#0x}" 2> /dev/null)" || true
  if printf '%s' "${_key_data}" | grep -q 'BEGIN PGP'; then
    if printf '%s' "${_key_data}" | gpg --dearmor -o "${_dest}"; then
      chmod 0644 "${_dest}"
      logging__success "GPG key installed via HTTPS keyserver → ${_dest}"
      return 0
    fi
  fi

  # Fallback: gpg --recv-keys via HKP keyservers (isolated GNUPGHOME).
  local _ghome _ks
  _ghome="$(mktemp -d)"
  chmod 0700 "$_ghome"
  for _ks in "hkp://keyserver.ubuntu.com" "hkp://keyserver.pgp.com"; do
    logging__info "Trying keyserver ${_ks}..."
    if gpg --homedir "$_ghome" --recv-keys --keyserver "${_ks}" "${_fingerprint}" 2> /dev/null; then
      if gpg --homedir "$_ghome" --export "${_fingerprint}" | gpg --dearmor -o "${_dest}"; then
        chmod 0644 "${_dest}"
        rm -rf "$_ghome"
        logging__success "GPG key installed via ${_ks} → ${_dest}"
        return 0
      fi
    fi
  done
  rm -rf "$_ghome"
  logging__error "verify__gpg_fetch_key_by_fingerprint: failed to fetch key ${_fingerprint} from all keyservers."
  return 1
}
