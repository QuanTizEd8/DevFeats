#!/usr/bin/env bash
# URI resolution: materialize local paths and remote URIs to files for feature installers.
#
# Provides a unified download pipeline via uri__fetch_asset, which handles scheme routing
# (http/https, ftp/ftps/sftp, file://, gh://, oci://, local paths), optional integrity
# verification (sha256 fragment, explicit hex, sidecar checksum file, GPG detached signature),
# archive extraction, and binary installation. uri__resolve and related functions are thin
# backward-compatible wrappers around uri__fetch_asset.

[[ -n "${_URI__LIB_LOADED-}" ]] && return 0
_URI__LIB_LOADED=1

_URI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/net.sh
[[ -z "${_NET__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/net.sh"
# shellcheck source=lib/verify.sh
[[ -z "${_VERIFY__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/verify.sh"
# shellcheck source=lib/oci.sh
[[ -z "${_OCI__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/oci.sh"
# shellcheck source=lib/file.sh
[[ -z "${_FILE__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/file.sh"
# shellcheck source=lib/install/common.sh
[[ -z "${_INSTALL_COMMON__LIB_LOADED-}" ]] && . "$_URI_LIB_DIR/install/common.sh"

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

# @brief uri__classify <input> — Print the URI class: `local` | `file` | `http` | `ftp` | `oci` | `gh`. Returns non-zero for unsupported schemes.
#
# Args:
#   <input>  URI or local path to classify.
#
# Stdout: one of `local`, `file`, `http`, `ftp`, `oci`, `gh`.
uri__classify() {
  local _in="$1"
  local _base
  _base="$(_uri__split_frag "$_in")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  case "$_base" in
    "") return 1 ;;
    http://* | https://*) printf 'http\n' ;;
    ftp://* | ftps://* | sftp://*) printf 'ftp\n' ;;
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

# ── Private helpers shared with github__install_release ──────────────────────

# _uri__sidecar_hash <asset_name> <sidecar_file> — extract the sha256 hex for <asset_name>
# from a sidecar checksum file. Supports sha256sum multi-entry format (<hash>  <filename>
# or <hash> *<filename>) and raw single-hash files (one line, one field).
# Prints the hex string (or empty on no match). Returns 0.
_uri__sidecar_hash() {
  local _name="$1" _file="$2"
  awk -v a="$_name" \
    '{fn=$NF; sub(/^\*/, "", fn)} fn==a{print $1;_f=1;exit} END{if(!_f && NR==1 && NF==1)print $1}' \
    "$_file"
}

# _uri__match_binary_src <spec> <extract_dir> — find file(s) matching suffix-path <spec>
# inside <extract_dir>. Whole-component boundary match (e.g. "bin/gh" matches path ending
# in .../bin/gh but not .../bin/ghx). Prints one path per match line.
_uri__match_binary_src() {
  local _spec="$1" _dir="$2"
  local _ncomp
  _ncomp="$(printf '%s\n' "$_spec" | tr '/' '\n' | wc -l)"
  find "$_dir" -type f | awk -v spec="$_spec" -v n="$_ncomp" '
    BEGIN { split(spec, sp, "/") }
    {
      m = split($0, p, "/")
      if (m < n) next
      match_ok = 1
      for (j = 1; j <= n; j++) {
        if (p[m - n + j] != sp[j]) { match_ok = 0; break }
      }
      if (match_ok) print $0
    }
  '
}

# _uri__download_to <url> <dest> [--header H]... [--netrc-file path]
# Route a URI to a local file using the appropriate transport. Strips the #fragment
# from the URL before the actual request. Does NOT verify the sha256 fragment —
# that is the caller's responsibility. Returns 0 on success, 1 on failure.
_uri__download_to() {
  local _url="$1" _dest="$2"
  shift 2
  local _args=("$@")
  local _cls _base
  _cls="$(uri__classify "$_url")" || {
    logging__error "_uri__download_to: unsupported URI scheme in '${_url}'."
    return 1
  }
  _base="$(_uri__split_frag "$_url")"
  _base="$(printf '%s\n' "$_base" | head -n1)"
  case "$_cls" in
    local)
      [[ -e "$_base" ]] || {
        logging__error "_uri__download_to: local path not found: '${_base}'."
        return 1
      }
      [[ "$_base" -ef "$_dest" ]] || cp -f "$_base" "$_dest" || {
        logging__error "_uri__download_to: failed to copy '${_base}' to '${_dest}'."
        return 1
      }
      ;;
    file)
      local _fp
      _fp="$(_uri__file_url_path "$_base")"
      [[ -f "$_fp" ]] || {
        logging__error "_uri__download_to: file:// target not found: '${_fp}'."
        return 1
      }
      cp -f "$_fp" "$_dest" || {
        logging__error "_uri__download_to: failed to copy '${_fp}' to '${_dest}'."
        return 1
      }
      ;;
    http | ftp)
      _uri__net_fetch "$_base" "$_dest" "${_args[@]}" || return 1
      ;;
    gh)
      local _https
      _https="$(_uri__gh_to_https "$_base")" || {
        logging__error "_uri__download_to: invalid gh:// URI '${_base}'."
        return 1
      }
      _uri__net_fetch "$_https" "$_dest" "${_args[@]}" || return 1
      ;;
    oci)
      # _uri__resolve_oci_to handles its own sha256 fragment verification internally.
      _uri__resolve_oci_to "$_url" "$_dest" || return 1
      ;;
    *)
      logging__error "_uri__download_to: internal error (class=${_cls})."
      return 1
      ;;
  esac
  return 0
}

# @brief uri__fetch_asset OPTIONS — Unified download → verify → extract → install pipeline.
#
# Downloads a file from any supported URI, optionally verifies integrity (sha256 fragment,
# sidecar checksum file, explicit hex, GPG signature), optionally extracts archives, and
# optionally installs binaries to a destination directory.
#
# Source:
#   --url <uri>              Required. Supported schemes:
#                              https://, http://, ftp://, ftps://, sftp://
#                              file://, gh://owner/repo@ref:path, oci://ref[?path=pat]
#                              local paths (absolute or relative)
#                            A #sha256=<hex> URI fragment is verified automatically.
#
# Output destination (at least one required):
#   --dest <file>            Write materialized file to this exact path.
#                            Equivalent to uri__resolve's second positional arg.
#   --installer-dir <dir>    Work dir for download/extraction; caller owns cleanup.
#                            When absent and no --dest, an auto-cleaned tmpdir is used.
#   --binary-dest <dir>      Install binary/binaries here; repeatable. Triggers archive
#                            detection and extraction pipeline.
#
# Authentication:
#   --header <H>             HTTP/FTP request header; repeatable.
#   --netrc-file <path>      netrc file for auth (HTTP Basic, FTP, SFTP via curl).
#
# Integrity verification (all optional; additive; independent):
#   --sha256 <hex|none>      64-hex: verify against this hash. 'none': suppress ALL sha256
#                            checks (fragment, sidecar, hex). GPG is not affected.
#   --sidecar-url <uri>      Checksum file URI (same auth args apply). sha256sum multi-entry
#                            format or raw single-hash. Hard-fail on mismatch or missing entry.
#                            Cannot be combined with --sha256 none.
#   --gpg-key-url <uri>      GPG public key URI; enables GPG verification.
#   --gpg-sig-url <uri>      Detached GPG signature URI (default: <url>.asc).
#
# Binary extraction and installation:
#   --filename <name>        Override URL basename used for sidecar hash matching.
#   --binary-src <spec>      Archive: suffix-path inside extracted tree. Direct binary:
#                            desired install name (enables renaming). Repeatable.
#                            When absent with an archive: auto-discovers all executables.
#   --binary-dest <dir>      Install directory; repeatable. N+N paired or N+1 fan-out.
#   --owner-group <id>       install__track_internal_path for each installed binary.
#   --chmod-exec             chmod +x the downloaded file (for installer scripts).
#
# Stdout: installed binary paths (one per line) when --binary-dest is set;
#         materialized file path otherwise.
# Returns: 0 on success, 1 on any failure.
uri__fetch_asset() {
  local _url="" _dest="" _installer_dir=""
  local _sha256_spec="" _sidecar_url="" _gpg_key_url="" _gpg_sig_url=""
  local _filename="" _owner_group="" _netrc=""
  local _chmod_exec=false _sha256_none=false _sha256_hex=""
  local -a _headers=() _binary_src=() _binary_dest=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)
        _url="$2"
        shift 2
        ;;
      --dest)
        _dest="$2"
        shift 2
        ;;
      --installer-dir)
        _installer_dir="$2"
        shift 2
        ;;
      --header)
        _headers+=("$2")
        shift 2
        ;;
      --netrc-file)
        _netrc="$2"
        shift 2
        ;;
      --sha256)
        _sha256_spec="$2"
        shift 2
        ;;
      --sidecar-url)
        _sidecar_url="$2"
        shift 2
        ;;
      --gpg-key-url)
        _gpg_key_url="$2"
        shift 2
        ;;
      --gpg-sig-url)
        _gpg_sig_url="$2"
        shift 2
        ;;
      --filename)
        _filename="$2"
        shift 2
        ;;
      --binary-src)
        _binary_src+=("$2")
        shift 2
        ;;
      --binary-dest)
        _binary_dest+=("$2")
        shift 2
        ;;
      --owner-group)
        _owner_group="$2"
        shift 2
        ;;
      --chmod-exec)
        _chmod_exec=true
        shift
        ;;
      *)
        logging__error "uri__fetch_asset: unknown option '$1'."
        return 1
        ;;
    esac
  done

  # ── Validate required args ────────────────────────────────────────────────
  [[ -z "$_url" ]] && {
    logging__error "uri__fetch_asset: --url is required."
    return 1
  }
  if [[ ${#_binary_dest[@]} -eq 0 && -z "$_dest" && -z "$_installer_dir" ]]; then
    logging__error "uri__fetch_asset: at least one of --dest, --installer-dir, or --binary-dest is required."
    return 1
  fi

  # ── Parse --sha256 spec ──────────────────────────────────────────────────
  case "$_sha256_spec" in
    "") ;;
    none) _sha256_none=true ;;
    *)
      if [[ "$_sha256_spec" =~ ^[0-9a-fA-F]{64}$ ]]; then
        _sha256_hex="${_sha256_spec,,}"
      else
        logging__error "uri__fetch_asset: --sha256 accepts a 64-char hex or 'none', got '${_sha256_spec}'."
        return 1
      fi
      ;;
  esac
  if "$_sha256_none" && [[ -n "$_sidecar_url" ]]; then
    logging__error "uri__fetch_asset: --sha256 none cannot be combined with --sidecar-url."
    return 1
  fi

  # ── Multi-binary pairing validation ──────────────────────────────────────
  local _nsrc="${#_binary_src[@]}" _ndest="${#_binary_dest[@]}"
  if [[ "$_nsrc" -gt 1 && "$_ndest" -gt 1 && "$_nsrc" -ne "$_ndest" ]]; then
    logging__error "uri__fetch_asset: ${_nsrc} --binary-src but ${_ndest} --binary-dest (must be equal or use 1 --binary-dest for all)."
    return 1
  fi

  # ── Build auth args ───────────────────────────────────────────────────────
  local -a _auth_args=()
  local _h
  for _h in "${_headers[@]}"; do _auth_args+=(--header "$_h"); done
  [[ -n "$_netrc" ]] && _auth_args+=(--netrc-file "$_netrc")

  # ── Determine work dir and download path ──────────────────────────────────
  local _split _base_url
  _split="$(_uri__split_frag "$_url")"
  _base_url="$(printf '%s\n' "$_split" | head -n1)"
  local _asset_name="${_filename:-$(_uri__safe_basename "$_base_url")}"
  local _work_dir _dl_path

  if [[ -n "$_dest" ]]; then
    _work_dir="$(dirname "$_dest")"
    mkdir -p "$_work_dir"
    _dl_path="$_dest"
  elif [[ -n "$_installer_dir" ]]; then
    _work_dir="$_installer_dir"
    mkdir -p "$_work_dir"
    _dl_path="${_work_dir}/${_asset_name}"
  else
    _work_dir="$(file__mktmpdir "uri-fetch-asset")"
    _dl_path="${_work_dir}/${_asset_name}"
  fi

  # ── Download ──────────────────────────────────────────────────────────────
  logging__download "Fetching '${_asset_name}' from '${_base_url}'"
  _uri__download_to "$_url" "$_dl_path" "${_auth_args[@]}" || return 1

  # ── sha256 fragment verification ──────────────────────────────────────────
  # OCI URIs verify their own fragment internally in _uri__resolve_oci_to.
  if ! "$_sha256_none"; then
    local _frag _frag_sha
    _frag="$(printf '%s\n' "$_split" | tail -n1)"
    _frag_sha="$(_uri__frag_sha256 "$_frag")"
    local _cls
    _cls="$(uri__classify "$_url" 2> /dev/null)" || true
    if [[ -n "$_frag_sha" && "$_cls" != "oci" ]]; then
      verify__sha "$_dl_path" "$_frag_sha" || return 1
    fi
  fi

  # ── Sidecar verification ──────────────────────────────────────────────────
  if [[ -n "$_sidecar_url" ]]; then
    local _sc_tmp _sc_base _sc_name _sc_file
    _sc_tmp="$(file__mktmpdir "uri-sidecar")"
    _sc_base="$(_uri__split_frag "$_sidecar_url")"
    _sc_base="$(printf '%s\n' "$_sc_base" | head -n1)"
    _sc_name="$(_uri__safe_basename "$_sc_base")"
    _sc_file="${_sc_tmp}/${_sc_name}"
    logging__download "Fetching checksum sidecar from '${_sc_base}'"
    _uri__download_to "$_sidecar_url" "$_sc_file" "${_auth_args[@]}" || return 1
    local _sc_hash
    _sc_hash="$(_uri__sidecar_hash "$_asset_name" "$_sc_file")"
    [[ -n "$_sc_hash" ]] || {
      logging__error "uri__fetch_asset: could not extract hash for '${_asset_name}' from sidecar '${_sc_base}'."
      return 1
    }
    verify__sha "$_dl_path" "$_sc_hash" || return 1
  fi

  # ── Explicit hex sha256 ───────────────────────────────────────────────────
  [[ -n "$_sha256_hex" ]] && { verify__sha "$_dl_path" "$_sha256_hex" || return 1; }

  # ── No-verification notice ────────────────────────────────────────────────
  if ! "$_sha256_none" && [[ -z "$_sha256_hex" && -z "$_sidecar_url" && -z "$_gpg_key_url" ]]; then
    local _frag _frag_sha
    _frag="$(printf '%s\n' "$_split" | tail -n1)"
    _frag_sha="$(_uri__frag_sha256 "$_frag")"
    [[ -z "$_frag_sha" ]] && logging__debug "uri__fetch_asset: no integrity verification configured for '${_asset_name}'."
  fi

  # ── GPG verification ──────────────────────────────────────────────────────
  if [[ -n "$_gpg_key_url" ]]; then
    local _sig_url="${_gpg_sig_url:-${_base_url}.asc}"
    local _gpg_tmp _sig_file _key_file
    _gpg_tmp="$(file__mktmpdir "uri-gpg")"
    _sig_file="${_gpg_tmp}/_asset.asc"
    _key_file="${_gpg_tmp}/_release.key"
    logging__download "Fetching GPG signature from '${_sig_url}'"
    _uri__download_to "$_sig_url" "$_sig_file" "${_auth_args[@]}" || return 1
    logging__download "Fetching GPG key from '${_gpg_key_url}'"
    _uri__download_to "$_gpg_key_url" "$_key_file" "${_auth_args[@]}" || return 1
    verify__gpg_detached "$_dl_path" "$_sig_file" "$_key_file" || return 1
  fi

  # ── chmod-exec ────────────────────────────────────────────────────────────
  [[ "$_chmod_exec" == true ]] && chmod +x "$_dl_path"

  # ── No binary installation → return file path ─────────────────────────────
  if [[ ${#_binary_dest[@]} -eq 0 ]]; then
    printf '%s\n' "$_dl_path"
    return 0
  fi

  # ── Archive detection and extraction ─────────────────────────────────────
  local _filetype _is_archive=false
  _filetype="$(file__detect_type "$_dl_path")"
  case "$_filetype" in
    gzip | xz | bzip2 | zip) _is_archive=true ;;
  esac

  local _content_dir=""
  if "$_is_archive"; then
    _content_dir="${_work_dir}/_extract"
    mkdir -p "$_content_dir"
    logging__install "Extracting '${_asset_name}'..."
    local _extract_name
    case "$_filetype" in
      gzip) _extract_name="asset.tar.gz" ;;
      xz) _extract_name="asset.tar.xz" ;;
      bzip2) _extract_name="asset.tar.bz2" ;;
      zip) _extract_name="asset.zip" ;;
      *) _extract_name="$_asset_name" ;;
    esac
    file__extract_archive "$_dl_path" "$_content_dir" "$_extract_name" || {
      logging__error "uri__fetch_asset: extraction of '${_asset_name}' failed."
      return 1
    }
  fi

  # ── Collect (src_file, install_name) pairs ───────────────────────────────
  local -a _found_srcs=() _install_names=()
  local _i

  if [[ "$_nsrc" -gt 0 ]]; then
    for _i in "${!_binary_src[@]}"; do
      local _spec="${_binary_src[$_i]}"
      local _found_src=""
      if "$_is_archive"; then
        _found_src="$(_uri__match_binary_src "$_spec" "$_content_dir")"
        local _mc
        _mc="$(printf '%s\n' "$_found_src" | grep -c . || true)"
        if [[ "$_mc" -gt 1 ]]; then
          logging__error "uri__fetch_asset: ambiguous --binary-src '${_spec}': ${_mc} matches in '${_asset_name}'."
          return 1
        fi
        [[ -z "$_found_src" ]] && {
          logging__error "uri__fetch_asset: --binary-src '${_spec}' not found in extracted '${_asset_name}'."
          return 1
        }
      else
        _found_src="$_dl_path"
      fi
      _found_srcs+=("$_found_src")
      _install_names+=("$(basename "$_spec")")
    done
  elif "$_is_archive"; then
    local _discovered
    _discovered="$(find "$_content_dir" -type f -perm -u+x 2> /dev/null || true)"
    if [[ -z "$_discovered" ]]; then
      while IFS= read -r _f; do chmod +x "$_f" 2> /dev/null || true; done \
        < <(find "$_content_dir" -type f)
      _discovered="$(find "$_content_dir" -type f 2> /dev/null || true)"
    fi
    while IFS= read -r _f; do
      [[ -n "$_f" ]] || continue
      _found_srcs+=("$_f")
      _install_names+=("$(basename "$_f")")
    done <<< "$_discovered"
    [[ ${#_found_srcs[@]} -eq 0 ]] && {
      logging__error "uri__fetch_asset: no executables found in extracted '${_asset_name}'."
      return 1
    }
  else
    _found_srcs+=("$_dl_path")
    _install_names+=("$_asset_name")
  fi

  # ── Install each binary ───────────────────────────────────────────────────
  local _j
  for _j in "${!_found_srcs[@]}"; do
    local _src="${_found_srcs[$_j]}"
    local _name="${_install_names[$_j]}"
    local _dest_dir
    if [[ "$_ndest" -gt 1 && "$_j" -lt "$_ndest" ]]; then
      _dest_dir="${_binary_dest[$_j]}"
    else
      _dest_dir="${_binary_dest[0]}"
    fi
    local _dest_path="${_dest_dir%/}/${_name}"
    chmod +x "$_src" 2> /dev/null || true
    logging__install "Installing '${_name}' to '${_dest_path}'"
    install__copy_bin "$_src" "$_dest_path" || return 1
    if [[ -n "$_owner_group" ]]; then
      install__track_internal_path "$_owner_group" "$_dest_path"
    fi
    logging__success "Installed '${_name}' → '${_dest_path}'"
    printf '%s\n' "$_dest_path"
  done
  return 0
}

# @brief uri__resolve <input> <dest-file> [--header <H>]... [--netrc-file <path>] [--chmod-exec] — Materialize `<input>` to `<dest-file>`. Thin wrapper around uri__fetch_asset.
#
# Supports `http(s)://`, `ftp://`, `ftps://`, `sftp://`, `file://`, `gh://`, `oci://`, and
# local paths. An optional `#sha256=<hex>` fragment in `<input>` is verified after fetch.
# `--chmod-exec` runs `chmod +x` on `<dest-file>` after a successful resolve.
#
# Args:
#   <input>              URI, local path, or `gh://owner/repo@ref:path` shorthand.
#   <dest-file>          Destination file path.
#   --header <H>         HTTP request header; repeatable.
#   --netrc-file <path>  Optional netrc file for authentication.
#   --chmod-exec         chmod +x on dest after successful resolve.
#
# Stdout: the resolved `<dest-file>` path.
#
# Returns: 0 on success, 1 on fetch or verification failure.
uri__resolve() {
  local _input="$1" _dest="$2"
  shift 2
  local _chmod_exec=false
  local -a _fa_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --header | --netrc-file)
        _fa_args+=("$1" "$2")
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
  [[ "$_chmod_exec" == true ]] && _fa_args+=(--chmod-exec)
  uri__fetch_asset --url "$_input" --dest "$_dest" "${_fa_args[@]}"
}

# @brief uri__resolve_line <input> <materialize-dir> [--header <H>]... [--netrc-file <path>] — For local inputs, print the original path. For remote inputs, materialize under `<materialize-dir>` and print the resulting path.
#
# Args:
#   <input>              URI or local path.
#   <materialize-dir>    Directory used to store downloaded files for remote URIs.
#   --header <H>         HTTP request header; repeatable.
#   --netrc-file <path>  Optional netrc file for authentication.
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
    http | ftp | gh | oci)
      mkdir -p "$_mdir"
      local _dest
      _dest="$(_uri__dest_for_uri "$_mdir" "$_input")"
      uri__fetch_asset --url "$_input" --dest "$_dest" "$@" || return 1
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
#   --netrc-file <path>       Optional netrc file for authentication.
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
