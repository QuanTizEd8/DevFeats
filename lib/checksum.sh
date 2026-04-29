#!/usr/bin/env bash
# Do not edit _lib/ copies directly — edit lib/ instead.

[ -n "${_CHECKSUM__LIB_LOADED-}" ] && return 0
_CHECKSUM__LIB_LOADED=1

_CHECKSUM__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_CHECKSUM__LIB_DIR/ospkg.sh"

# Try sha<algo>sum then shasum; return 1 if neither is found.
_checksum__dispatch() {
  local _file="$1" _algo="$2"
  if command -v "sha${_algo}sum" > /dev/null 2>&1; then
    "sha${_algo}sum" "$_file" | awk '{print $1}'
  elif command -v shasum > /dev/null 2>&1; then
    shasum --algorithm "${_algo}" "$_file" | awk '{print $1}'
  else
    return 1
  fi
}

# @brief checksum__hash_file <file> [algo] — Print lowercase hex digest of `<file>` to stdout.
#
# `algo` is `256` (default) or `512`.
# Uses sha<N>sum (Linux/coreutils) or shasum --algorithm <N> (macOS/Perl).
# Falls back to installing coreutils via ospkg when neither tool exists.
#
# Args:
#   <file>   Path to an existing regular file.
#   [algo]   Hash algorithm: 256 (default) or 512.
checksum__hash_file() {
  local _file="$1"
  local _algo="${2:-256}"
  [ -f "$_file" ] || return 1
  _checksum__dispatch "$_file" "$_algo" && return
  logging__info "sha${_algo}sum/shasum not found — installing coreutils."
  ospkg__install_tracked "lib-checksum" coreutils
  _checksum__dispatch "$_file" "$_algo" || {
    logging__error "checksum__hash_file: no sha${_algo}sum or shasum available after coreutils install."
    return 1
  }
}

# @brief checksum__verify <file> <expected_hash> [algo] — Verify the digest of `<file>`. Returns 1 on mismatch.
#
# `algo` is `256` (default) or `512`.
#
# Args:
#   <file>           Path to the file to verify.
#   <expected_hash>  Expected lowercase hex digest.
#   [algo]           Hash algorithm: 256 (default) or 512.
checksum__verify() {
  local _file="$1"
  local _expected="$2"
  local _algo="${3:-256}"
  local _actual

  _actual="$(checksum__hash_file "$_file" "$_algo")" || return 1

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

# @brief checksum__verify_sidecar <file> <hash_file> [algo] — Read expected hash from first field of `<hash_file>` and delegate to checksum__verify.
#
# Suitable for the common `<name>.sha256` / `<name>.sha512` sidecar file pattern.
#
# Args:
#   <file>       Path to the file to verify.
#   <hash_file>  Path to the sidecar file containing the expected hash.
#   [algo]       Hash algorithm: 256 (default) or 512.
checksum__verify_sidecar() {
  local _file="$1"
  local _hash_file="$2"
  local _algo="${3:-256}"
  local _expected
  _expected="$(awk '{print $1}' "$_hash_file")"
  [ -z "$_expected" ] && {
    logging__error "checksum__verify_sidecar: could not read hash from '${_hash_file}'."
    return 1
  }
  checksum__verify "$_file" "$_expected" "$_algo"
  return $?
}
