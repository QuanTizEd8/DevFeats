# shellcheck shell=bash
# HTTP fetch helpers with retry support using curl or wget.
#
# Auto-detects `curl` or `wget` (installs via `ospkg` if absent). All fetch
# functions support configurable retries, delay between attempts, and custom
# HTTP headers.

_NET__FETCH_TOOL=
_NET__CA_CERTS_OK=

# @brief _net__hdrs_with_default_ua <hdr_block> — Return `<hdr_block>` unchanged when it already contains a `User-Agent` header; otherwise prepend `User-Agent: devfeats`.
#
# GitHub's raw-content CDN and some other hosts return HTTP 403 for requests
# carrying curl's default `curl/<version>` User-Agent. This helper ensures a
# recognisable User-Agent is always present without overriding a caller-supplied
# one.
#
# Args:
#   <hdr_block>  Newline-separated list of HTTP headers (may be empty).
#
# Stdout: the original block if a User-Agent header is present, or the block
#         with `User-Agent: devfeats` prepended as the first line.
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
#
# Returns: 0 on success, 1 after all retries exhausted.
net__fetch_with_retry() {
  local _max=60 _delay=5 _bail_on="" _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null
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
  local _i=1 _rc=0
  while [ "$_i" -le "$_max" ]; do
    _rc=0
    "$@" || _rc=$?
    [ "$_rc" -eq 0 ] && {
      [[ "$_xt" == true ]] && set -x
      return 0
    }
    [ -n "$_bail_on" ] && [ "$_rc" -eq "$_bail_on" ] && {
      [[ "$_xt" == true ]] && set -x
      return "$_rc"
    }
    if [ "$_i" -lt "$_max" ]; then
      logging__warn "Attempt $_i/$_max failed — retrying in ${_delay}s..."
      sleep "$_delay"
    fi
    _i=$((_i + 1))
  done
  logging__error "Failed after $_max attempt(s)."
  [[ "$_xt" == true ]] && set -x
  return 1
}

# @brief _net__fetch <url> <dest> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Internal: download URL via curl or wget.
#
# <dest> is the output file path, or empty string for stdout output.
# curl uses --retry (transient errors only); wget falls back to net__fetch_with_retry.
_net__fetch() {
  local _url="$1" _dest="$2"
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
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  local _rc=$?
  [[ $_rc == 0 ]] || { logging__error "failed to set up HTTP fetch tool."; return "$_rc"; }
  local _h
  if [ "$_NET__FETCH_TOOL" = "curl" ]; then
    set -- -fsSL --compressed --retry "$_max" --retry-delay "$_delay" --retry-connrefused
    [ -n "$_netrc" ] && set -- "$@" --netrc-file "$_netrc"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" -H "$_h"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    if [ -n "$_dest" ]; then
      curl "$@" -o "$_dest" "$_url"
    else
      curl "$@" "$_url"
    fi
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    if [ -n "$_dest" ]; then
      logging__error "failed to fetch '${_url}' to '${_dest}' with curl (exit ${_rc})."
    else
      logging__error "failed to fetch '${_url}' with curl (exit ${_rc})."
    fi
    return "${_rc}"
  elif [ "$_NET__FETCH_TOOL" = "wget" ] && command -v wget > /dev/null 2>&1; then
    if [ -n "$_dest" ]; then
      set -- -O "$_dest"
    else
      set -- -O-
    fi
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
    if [ -n "$_dest" ]; then
      logging__error "failed to fetch '${_url}' to '${_dest}' with wget (exit ${_rc})."
    else
      logging__error "failed to fetch '${_url}' with wget (exit ${_rc})."
    fi
    return "${_rc}"
  fi
  logging__error "no HTTP fetch tool available (curl/wget missing after bootstrap)."
  return 1
}

# @brief net__fetch_url_stdout <url> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to stdout with retries. Auto-detects curl/wget.
#
# curl uses --retry (transient errors only: 5xx, 408, 429, connection
# failures); wget falls back to net__fetch_with_retry. Calls
# _net__ensure_fetch_tool automatically if not already initialised.
#
# Args:
#   <url>                URL to download.
#   --retries N          Maximum number of attempts (default: 60, ≈5 min at 5s).
#   --delay N            Seconds between failures (default: 5).
#   --header <H>         Request header (e.g. `Authorization: Bearer $TOKEN`); repeatable.
#   --netrc-file <path>  Optional netrc file for HTTP authentication.
#
# Stdout: downloaded content.
#
# Returns: 0 on success, non-zero on HTTP error or timeout.
net__fetch_url_stdout() {
  local _url="$1"
  shift
  logging__download "Fetching '${_url}' to stdout."
  _net__fetch "$_url" "" "$@"
}

# @brief net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to `<dest>` with retries. Auto-detects curl/wget.
#
# curl uses --retry (transient errors only: 5xx, 408, 429, connection
# failures); wget falls back to net__fetch_with_retry. Calls
# _net__ensure_fetch_tool automatically if not already initialised.
#
# Args:
#   <url>                URL to download.
#   <dest>               Destination file path.
#   --retries N          Maximum number of attempts (default: 60, ≈5 min at 5s).
#   --delay N            Seconds between failures (default: 5).
#   --header <H>         Request header (e.g. `Authorization: Bearer $TOKEN`); repeatable.
#   --netrc-file <path>  Optional netrc file for HTTP authentication.
#
# Returns: 0 on success, non-zero on HTTP error or timeout.
net__fetch_url_file() {
  local _url="$1" _dest="$2"
  shift 2
  logging__download "Fetching '${_url}' to '${_dest}'."
  _net__fetch "$_url" "$_dest" "$@"
}

# @brief _net__ensure_fetch_tool — Detect `curl` or `wget` and set `_NET__FETCH_TOOL`; install `curl` via ospkg if neither is found.
#
# Runs `_net__ensure_ca_certs` after detection so every fetch that goes through
# this helper also has a valid CA bundle. Idempotent: does nothing when
# `_NET__FETCH_TOOL` is already set.
#
# Side effects: sets `_NET__FETCH_TOOL` to `curl` or `wget`.
# Returns: 0 on success, 1 if a required tool or CA bundle cannot be ensured.
_net__ensure_fetch_tool() {
  if [ -z "${_NET__FETCH_TOOL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      _NET__FETCH_TOOL=curl
    elif command -v wget > /dev/null 2>&1; then
      _NET__FETCH_TOOL=wget
    else
      logging__info "Neither curl nor wget found — installing curl."
      ospkg__install_tracked "lib-net" curl
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "failed to install curl."
        return "$_rc"
      }
      command -v curl > /dev/null 2>&1 || {
        logging__error "curl could not be installed."
        return 1
      }
      _NET__FETCH_TOOL=curl
    fi
  fi
  _net__ensure_ca_certs
  local _rc=$?
  [[ $_rc == 0 ]] || { logging__error "failed to ensure CA certificates."; return "$_rc"; }
  return 0
}

# @brief _net__ensure_ca_certs — Ensure `/etc/ssl/certs/ca-certificates.crt` is present; install `ca-certificates` via ospkg if missing.
#
# macOS uses the system keychain natively (curl and wget pick it up without a
# `.crt` bundle), so the check is skipped there. On Linux, an absent or empty
# bundle causes TLS errors for all HTTPS fetches. Idempotent: sets
# `_NET__CA_CERTS_OK` after the first successful check and returns immediately
# on subsequent calls.
#
# Side effects: may install `ca-certificates` via the system package manager.
# Returns: 0 on success, 1 if the Linux CA bundle is still missing after install.
_net__ensure_ca_certs() {
  [ -n "${_NET__CA_CERTS_OK:-}" ] && return 0
  # macOS uses its own keychain; curl/wget use it natively without a .crt file.
  [ "$(uname -s)" = "Darwin" ] && {
    _NET__CA_CERTS_OK=true
    return 0
  }
  if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    logging__info "CA certificate bundle missing — installing ca-certificates."
    ospkg__install_tracked "lib-net" ca-certificates
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to install ca-certificates."
      return "$_rc"
    }
    if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
      logging__error "ca-certificates could not be installed."
      return 1
    fi
  fi
  _NET__CA_CERTS_OK=true
  return 0
}
