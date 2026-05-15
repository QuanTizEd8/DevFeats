#!/usr/bin/env bash
# URI resolution: materialize local paths and remote URIs to files for feature installers.
#
# Resolves local paths (with optional verification) and remote URIs (HTTPS,
# GitHub release shortcuts) to a materialized local file. Used by feature
# installers to obtain binaries regardless of source type.

[[ -n "${_URI__LIB_LOADED-}" ]] && return 0
_URI__LIB_LOADED=1

_URI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/net.sh
[[ -z "${_NET__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/net.sh"
# shellcheck source=lib/verify.sh
[[ -z "${_VERIFY__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/verify.sh"
# shellcheck source=lib/oci.sh
[[ -z "${_OCI__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/oci.sh"

# _uri__split_frag <full-uri> — prints base-uri on first line, fragment part on second (may be empty).
_uri__split_frag() {
  local _in="$1"
  local _base="${_in%%#*}"
  local _frag=""
  [[ "$_in" == *"#"* ]] && _frag="${_in#*#}"
  printf '%s\n%s\n' "$_base" "$_frag"
}

# _uri__frag_sha256 <frag> — prints expected sha256 hex if present in fragment (else empty).
_uri__frag_sha256() {
  local _frag="$1" _p _v
  [[ -z "$_frag" ]] && return 0
  local _IFS="$IFS"
  IFS='&'
  # shellcheck disable=SC2086
  set -- ${_frag}
  IFS="$_IFS"
  for _p in "$@"; do
    case "$_p" in
      sha256=*)
        _v="${_p#sha256=}"
        printf '%s\n' "${_v%%&*}"
        return 0
        ;;
    esac
  done
  return 0
}

# _uri__file_url_path <file-uri> — strip file:// and print absolute path.
_uri__file_url_path() {
  local _u="$1"
  _u="${_u#file://}"
  [[ "$_u" == /* ]] || _u="/${_u}"
  printf '%s\n' "$_u"
}

# _uri__gh_to_https <gh-uri> — translate gh://owner/repo@ref:path to raw.githubusercontent URL.
_uri__gh_to_https() {
  local _in="$1" _rest _or _at _ref _path
  _rest="${_in#gh://}"
  [[ -n "$_rest" ]] || return 1
  if [[ "$_rest" == *"@"* ]]; then
    _or="${_rest%%@*}"
    _at="${_rest#*@}"
    _ref="${_at%%:*}"
    _path="${_at#*:}"
  else
    _or="${_rest%%:*}"
    _path="${_rest#*:}"
    _ref="main"
  fi
  [[ -n "$_or" && -n "$_path" ]] || return 1
  printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$_or" "$_ref" "$_path"
}

# _uri__safe_basename <uri-without-frag> — derive a filename for materialized downloads.
_uri__safe_basename() {
  local _u="$1"
  local _b="${_u%%\?*}"
  _b="${_b##*/}"
  [[ -n "$_b" ]] || _b="download"
  printf '%s\n' "$_b"
}

# _uri__dest_for_uri <dest_dir> <full-uri> — unique materialized path under dest_dir.
_uri__dest_for_uri() {
  local _dir="$1" _uri="$2"
  local _id _base
  _id="$(printf '%s' "$_uri" | sha256sum 2> /dev/null | awk '{print $1}' | cut -c1-16)"
  [[ -z "$_id" ]] && _id="$(printf '%s' "$_uri" | cksum | awk '{print $1}')"
  local _base_raw
  _base_raw="$(_uri__split_frag "$_uri")"
  _base_raw="$(printf '%s\n' "$_base_raw" | head -n1)"
  _base="$(_uri__safe_basename "$_base_raw")"
  printf '%s/%s-%s\n' "$_dir" "$_id" "$_base"
}

# @brief uri__classify <input> — Print the URI class: `local` | `file` | `http` | `oci` | `gh`. Returns non-zero for unsupported schemes.
#
# Args:
#   <input>  URI or local path to classify.
#
# Stdout: one of `local`, `file`, `http`, `oci`, `gh`.
uri__classify() {
  local _in="$1"
  local _base
  _base="$(_uri__split_frag "$_in")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  case "$_base" in
    "") return 1 ;;
    http://* | https://*) printf 'http\n' ;;
    file://*) printf 'file\n' ;;
    oci://*) printf 'oci\n' ;;
    gh://*) printf 'gh\n' ;;
    *://*)
      logging__error "uri__classify: unsupported scheme in '${_base}'."
      return 1
      ;;
    *) printf 'local\n' ;;
  esac
  return 0
}

# _uri__net_fetch — Run net__fetch_url_file with optional headers and netrc.
_uri__net_fetch() {
  local _url="$1" _dest="$2"
  shift 2
  net__fetch_url_file "$_url" "$_dest" "$@"
}

# _uri__resolve_oci_to <oci-uri> <dest-file>
_uri__resolve_oci_to() {
  local _uri="$1" _dest="$2"
  local _base _frag _rest _ref_part _query _path_pat _pull_dir
  _base="$(_uri__split_frag "$_uri")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  _frag="$(_uri__split_frag "$_uri")"
  _frag="$(printf '%s\n' "$_frag" | tail -n1)"
  _rest="${_base#oci://}"
  _ref_part="${_rest%%\?*}"
  _query=""
  [[ "$_rest" == *"?"* ]] && _query="${_rest#*\?}"
  _path_pat=""
  if [[ -n "$_query" ]]; then
    local _q
    IFS='&' read -ra _q <<< "$_query" || true
    for _p in "${_q[@]}"; do
      case "$_p" in
        path=*)
          _path_pat="${_p#path=}"
          ;;
      esac
    done
  fi
  oci__ensure_oras || return 1
  _oci__ensure_auth_for "$_ref_part" || return 1
  _pull_dir="$(file__mktmpdir "uri-oci-pull")"
  if ! oras pull "$_ref_part" -o "$_pull_dir" > /dev/null 2>&1; then
    logging__error "uri__resolve: oras pull failed for '${_ref_part}'."
    return 1
  fi
  local _picked=""
  if [[ -n "$_path_pat" ]]; then
    _picked="$(find "$_pull_dir" -type f \( -name "${_path_pat}" -o -path "*/${_path_pat}" \) -print -quit 2> /dev/null)"
    [[ -z "$_picked" ]] && _picked="$(find "$_pull_dir" -type f -path "*${_path_pat}*" -print -quit 2> /dev/null)"
  fi
  if [[ -z "$_picked" ]]; then
    local _n
    _n="$(find "$_pull_dir" -type f | wc -l | tr -d ' ')"
    if [[ "$_n" == "1" ]]; then
      _picked="$(find "$_pull_dir" -type f -print -quit)"
    fi
  fi
  [[ -n "$_picked" && -f "$_picked" ]] || {
    logging__error "uri__resolve: could not pick a single file from OCI artefact '${_ref_part}'."
    return 1
  }
  cp -f "$_picked" "$_dest" || {
    logging__error "uri__resolve: failed to copy OCI artifact '${_picked}' to '${_dest}'."
    return 1
  }
  local _expect
  _expect="$(_uri__frag_sha256 "$_frag")"
  if [[ -n "$_expect" ]]; then
    verify__sha "$_dest" "$_expect" || return 1
  fi
  return 0
}

# @brief uri__resolve <input> <dest-file> [--header <H>]... [--netrc-file <path>] [--chmod-exec] — Materialize `<input>` to `<dest-file>`. For local paths, copies when needed.
#
# Supports `http(s)://`, `file://`, `gh://`, `oci://`, and plain local paths.
# An optional `#sha256=<hex>` fragment in `<input>` is verified after fetch.
# `--chmod-exec` runs `chmod +x` on `<dest-file>` after a successful resolve.
#
# Args:
#   <input>              URI, local path, or `gh://owner/repo@ref:path` shorthand.
#   <dest-file>          Destination file path.
#   --header <H>         HTTP request header; repeatable.
#   --netrc-file <path>  Optional netrc file for HTTP authentication.
#   --chmod-exec         chmod +x on dest after successful resolve.
#
# Stdout: the resolved `<dest-file>` path.
#
# Returns: 0 on success, 1 on fetch or verification failure.
uri__resolve() {
  local _input="$1" _dest="$2"
  shift 2
  local _chmod_exec=false _args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --header)
        _args+=("$1" "$2")
        shift 2
        ;;
      --netrc-file)
        _args+=("$1" "$2")
        shift 2
        ;;
      --chmod-exec)
        _chmod_exec=true
        shift
        ;;
      *)
        logging__error "uri__resolve: unknown option '$1'"
        return 1
        ;;
    esac
  done

  local _cls
  _cls="$(uri__classify "$_input")" || {
    logging__error "uri__resolve: unsupported URI scheme in '${_input}'."
    return 1
  }

  local _base _frag _expect
  _base="$(_uri__split_frag "$_input")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  _frag="$(_uri__split_frag "$_input")"
  _frag="$(printf '%s\n' "$_frag" | tail -n1)"
  _expect="$(_uri__frag_sha256 "$_frag")"

  case "$_cls" in
    local)
      [[ -e "$_base" ]] || {
        logging__error "uri__resolve: local path not found: '${_base}'."
        return 1
      }
      if [[ "$_base" -ef "$_dest" ]]; then
        :
      else
        cp -f "$_base" "$_dest" || {
          logging__error "uri__resolve: failed to copy '${_base}' to '${_dest}'."
          return 1
        }
      fi
      ;;
    file)
      local _fp
      _fp="$(_uri__file_url_path "$_base")"
      [[ -f "$_fp" ]] || {
        logging__error "uri__resolve: file:// target not found: '${_fp}'."
        return 1
      }
      cp -f "$_fp" "$_dest" || {
        logging__error "uri__resolve: failed to copy '${_fp}' to '${_dest}'."
        return 1
      }
      ;;
    http)
      _uri__net_fetch "$_base" "$_dest" "${_args[@]}" || return 1
      if [[ -n "$_expect" ]]; then
        verify__sha "$_dest" "$_expect" || return 1
      fi
      ;;
    gh)
      local _https
      _https="$(_uri__gh_to_https "$_base")" || {
        logging__error "uri__resolve: invalid gh:// URI '${_base}'."
        return 1
      }
      _uri__net_fetch "$_https" "$_dest" "${_args[@]}" || return 1
      if [[ -n "$_expect" ]]; then
        verify__sha "$_dest" "$_expect" || return 1
      fi
      ;;
    oci)
      _uri__resolve_oci_to "$_input" "$_dest" || return 1
      ;;
    *)
      logging__error "uri__resolve: internal error (class=${_cls})."
      return 1
      ;;
  esac

  if [[ "$_cls" == "local" || "$_cls" == "file" ]] && [[ -n "$_expect" ]]; then
    verify__sha "$_dest" "$_expect" || return 1
  fi

  [[ "$_chmod_exec" == true ]] && chmod +x "$_dest"
  printf '%s\n' "$_dest"
  return 0
}

# @brief uri__resolve_line <input> <materialize-dir> [--header <H>]... [--netrc-file <path>] — For local inputs, print the original path. For remote inputs, materialize under `<materialize-dir>` and print the resulting path.
#
# Args:
#   <input>              URI or local path.
#   <materialize-dir>    Directory used to store downloaded files for remote URIs.
#   --header <H>         HTTP request header; repeatable.
#   --netrc-file <path>  Optional netrc file for HTTP authentication.
#
# Stdout: resolved local file path.
uri__resolve_line() {
  local _input="$1" _mdir="$2"
  shift 2
  local _cls
  _cls="$(uri__classify "$_input")" || return 1
  case "$_cls" in
    local)
      [[ -e "$(_uri__split_frag "$_input" | head -n1)" ]] || {
        logging__error "uri__resolve_line: local path not found: '${_input%%#*}'."
        return 1
      }
      printf '%s\n' "${_input%%#*}"
      ;;
    file)
      local _fp _in
      _in="$(_uri__split_frag "$_input" | head -n1)"
      _fp="$(_uri__file_url_path "$_in")"
      printf '%s\n' "$_fp"
      ;;
    http | gh | oci)
      mkdir -p "$_mdir"
      local _dest
      _dest="$(_uri__dest_for_uri "$_mdir" "$_input")"
      uri__resolve "$_input" "$_dest" "$@" || return 1
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# @brief uri__resolve_list <newline-separated-list> <materialize-dir> [--header <H>]... [--netrc-file <path>] — Resolve each non-empty line of `<newline-separated-list>` and print one output path per line.
#
# Args:
#   <newline-separated-list>  Newline-separated list of URIs or local paths.
#   <materialize-dir>         Directory used to store downloaded files for remote URIs.
#   --header <H>              HTTP request header; repeatable.
#   --netrc-file <path>       Optional netrc file for HTTP authentication.
#
# Stdout: one resolved local file path per non-empty input line.
uri__resolve_list() {
  local _list="$1" _mdir="$2"
  shift 2
  local _line _out
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    [[ -z "${_line//[[:space:]]/}" ]] && continue
    _out="$(uri__resolve_line "$_line" "$_mdir" "$@")" || return 1
    printf '%s\n' "$_out"
  done <<< "$(printf '%s\n' "$_list")"
  return 0
}
