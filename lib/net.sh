#!/usr/bin/env bash
# net.sh — HTTP fetch helpers (curl / wget). Bash >=4.
# _net__ensure_fetch_tool and _net__ensure_ca_certs are internal helpers.
# They auto-install curl or ca-certificates via ospkg when absent.

[ -n "${_NET__LIB_LOADED-}" ] && return 0
_NET__LIB_LOADED=1

_NET__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_NET__LIB_DIR/ospkg.sh"

_NET_FETCH_TOOL=
_NET_CA_CERTS_OK=

# _net__hdrs_with_default_ua <hdr_block> — Echo <hdr_block> unchanged if it
# already contains a User-Agent line; otherwise prepend "User-Agent: devfeats".
# GitHub and some CDNs return 403 for curl's default anonymous User-Agent.
_net__hdrs_with_default_ua() {
  local _net__ua_in="$1"
  if printf '%s\n' "$_net__ua_in" | grep -qi '^user-agent:'; then
    printf '%s' "$_net__ua_in"
  else
    printf '%s%s' "User-Agent: devfeats
" "$_net__ua_in"
  fi
}

# @brief net__fetch_with_retry [--retries N] [--delay N] [--bail-on CODE] <cmd...> — Run `<cmd>` up to N times with a delay between failures (default: 60 retries, 5s delay).
#
# Does NOT require ospkg.sh. Prefer net__fetch_url_stdout / net__fetch_url_file
# for curl/wget downloads; those handle tool detection, --compressed, and
# transient-only retries automatically. Use this function only for commands
# that are not curl/wget.
#
# Args:
#   --retries N      Maximum number of attempts (default: 60).
#   --delay N        Seconds to wait between failures (default: 5).
#   --bail-on CODE   If the command exits with CODE, stop immediately without
#                    retrying (use for non-transient configuration errors).
#   <cmd...>         Command and arguments to run.
net__fetch_with_retry() {
  local _max=60 _delay=5 _bail_on=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --bail-on)
        _bail_on="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  local _i=1 _rc
  while [ "$_i" -le "$_max" ]; do
    "$@"
    _rc=$?
    [ "$_rc" -eq 0 ] && return 0
    [ -n "$_bail_on" ] && [ "$_rc" -eq "$_bail_on" ] && return "$_rc"
    if [ "$_i" -lt "$_max" ]; then
      logging__warn "Attempt $_i/$_max failed — retrying in ${_delay}s..."
      sleep "$_delay"
    fi
    _i=$((_i + 1))
  done
  logging__error "Failed after $_max attempt(s)."
  return 1
}

# @brief net__fetch_url_stdout <url> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to stdout with retries. Auto-detects curl/wget.
#
# curl uses --retry (transient errors only: 5xx, 408, 429, connection
# failures); wget falls back to net__fetch_with_retry. Calls
# _net__ensure_fetch_tool automatically if not already initialised.
#
# Args:
#   <url>          URL to download.
#   --retries N    Maximum number of attempts (default: 60, ≈5 min at 5s).
#   --delay N      Seconds between failures (default: 5).
#   --header <H>   Request header (e.g. "Authorization: Bearer $TOKEN").
#                  May be specified multiple times.
#   --netrc-file <path>  Optional netrc file for HTTP authentication (curl/wget).
net__fetch_url_stdout() {
  local _url="$1"
  shift
  local _max=60 _delay=5 _hdrs='' _netrc=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --header)
        _hdrs="${_hdrs}${2}
"
        shift 2
        ;;
      --netrc-file)
        _netrc="$2"
        shift 2
        ;;
      *)
        logging__error "net__fetch_url_stdout: unknown option: '$1'"
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    set -- -fsSL --compressed --retry "$_max" --retry-delay "$_delay" --retry-connrefused
    [ -n "$_netrc" ] && set -- "$@" --netrc-file "$_netrc"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" -H "$_h"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    curl "$@" "$_url"
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    logging__error "net__fetch_url_stdout: failed to fetch '${_url}' with curl (exit ${_rc})."
    return "${_rc}"
  else
    set -- -O-
    [ -n "$_netrc" ] && set -- "$@" "--netrc-file=${_netrc}"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" "--header=${_h}"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    net__fetch_with_retry --retries "$_max" --delay "$_delay" wget "$@" "$_url"
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    logging__error "net__fetch_url_stdout: failed to fetch '${_url}' with wget (exit ${_rc})."
    return "${_rc}"
  fi
}

# @brief net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to `<dest>` with retries. Auto-detects curl/wget.
#
# curl uses --retry (transient errors only: 5xx, 408, 429, connection
# failures); wget falls back to net__fetch_with_retry. Calls
# _net__ensure_fetch_tool automatically if not already initialised.
#
# Args:
#   <url>          URL to download.
#   <dest>         Destination file path.
#   --retries N    Maximum number of attempts (default: 60, ≈5 min at 5s).
#   --delay N      Seconds between failures (default: 5).
#   --header <H>   Request header (e.g. "Authorization: Bearer $TOKEN").
#                  May be specified multiple times.
#   --netrc-file <path>  Optional netrc file for HTTP authentication (curl/wget).
net__fetch_url_file() {
  local _url="$1"
  local _dest="$2"
  shift 2
  local _max=60 _delay=5 _hdrs='' _netrc=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --header)
        _hdrs="${_hdrs}${2}
"
        shift 2
        ;;
      --netrc-file)
        _netrc="$2"
        shift 2
        ;;
      *)
        logging__error "net__fetch_url_file: unknown option: '$1'"
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    set -- -fsSL --compressed --retry "$_max" --retry-delay "$_delay" --retry-connrefused
    [ -n "$_netrc" ] && set -- "$@" --netrc-file "$_netrc"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" -H "$_h"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    curl "$@" -o "$_dest" "$_url"
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    logging__error "net__fetch_url_file: failed to fetch '${_url}' to '${_dest}' with curl (exit ${_rc})."
    return "${_rc}"
  else
    set -- -O "$_dest"
    [ -n "$_netrc" ] && set -- "$@" "--netrc-file=${_netrc}"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" "--header=${_h}"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    net__fetch_with_retry --retries "$_max" --delay "$_delay" wget "$@" "$_url"
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    logging__error "net__fetch_url_file: failed to fetch '${_url}' to '${_dest}' with wget (exit ${_rc})."
    return "${_rc}"
  fi
}

# _net__ensure_fetch_tool (internal)
# Sets _NET_FETCH_TOOL to "curl" or "wget"; installs curl via ospkg__install
# if neither is found.
_net__ensure_fetch_tool() {
  if [ -z "${_NET_FETCH_TOOL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      _NET_FETCH_TOOL=curl
    elif command -v wget > /dev/null 2>&1; then
      _NET_FETCH_TOOL=wget
    else
      logging__info "Neither curl nor wget found — installing curl."
      ospkg__install_tracked "lib-net" curl
      _NET_FETCH_TOOL=curl
    fi
  fi
  _net__ensure_ca_certs
  return 0
}

# _net__ensure_ca_certs (internal)
# Ensures /etc/ssl/certs/ca-certificates.crt exists; installs ca-certificates
# via ospkg__install if not.
_net__ensure_ca_certs() {
  [ -n "${_NET_CA_CERTS_OK:-}" ] && return 0
  # macOS uses its own keychain; curl/wget use it natively without a .crt file.
  [ "$(uname -s)" = "Darwin" ] && {
    _NET_CA_CERTS_OK=true
    return 0
  }
  if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    logging__info "CA certificate bundle missing — installing ca-certificates."
    ospkg__install_tracked "lib-net" ca-certificates
  fi
  _NET_CA_CERTS_OK=true
  return 0
}
