# shellcheck shell=bash
# URI resolution: materialize local paths and remote URIs to files for feature installers.
#
# Provides a unified download pipeline via uri__fetch_asset, which handles scheme routing
# (http/https, ftp/ftps/sftp, file://, gh://, oci://, local paths), optional integrity
# verification (sha256 fragment, explicit hex, sidecar checksum file, GPG detached signature),
# archive extraction, and binary installation. uri__resolve and related functions are thin
# backward-compatible wrappers around uri__fetch_asset.

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
    '{fn=$NF; sub(/^\*/, "", fn); sub(/.*\//, "", fn)} fn==a{print $1;_f=1;exit} END{if(!_f && NR==1 && NF==1)print $1}' \
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

# @brief uri__fetch_asset <uri> [OPTIONS] — Download, verify, extract, and optionally install one or more files from a single asset.
#
# Downloads a file from any supported URI, verifies integrity, extracts archives,
# and installs files. Regardless of which flags are provided, the same layout is
# always built inside a work directory:
#
# ```
# work_dir/
#   archive/<basename>      Raw downloaded file (archives only); <basename> is
#                           the basename of <uri>, or --filename if set.
#   asset/                  Archive extracted verbatim (no path stripping): the
#                           archive's internal tree is reproduced exactly under
#                           asset/. For non-archives: the downloaded file as
#                           <basename>.
#   sidecar/<basename>      Basename of --sidecar URI (only when --sidecar given).
#   gpg-sig/<basename>      Basename of --gpg-sig URI (only when --gpg-key given).
#   gpg-key/<basename>      Basename of --gpg-key URI (only when --gpg-key given).
# ```
#
# `work_dir` is `--installer-dir` when provided, otherwise an auto-cleaned tmpdir
# (removed on script exit). When `--installer-dir` is provided, the five managed
# subdirectories are removed and recreated on each invocation (idempotency).
#
# Pairing rules apply independently to the binary pair (`--binary-src` /
# `--binary-dest`) and the file pair (`--file-src` / `--file-dest`). Within each
# pair, a trailing `/` on the dest treats it as a directory (installed file keeps
# its basename); without a trailing `/` the dest is the exact output path,
# enabling renaming. For N src and M dest values within one pair:
#
# - N=M → 1-to-1 paired in order.
# - N>1, M=1-dir → all matched files fan out into the directory.
# - Otherwise → error.
#
# When N=0 (no `--binary-src` or `--file-src` given):
#
# - Binary, archive: auto-discover all executables in `asset/`. With M=1-file
#   dest, error if not exactly one executable found.
# - Binary, non-archive: install `asset/<basename>` directly.
# - File, archive: error — no auto-discovery for non-binary files.
# - File, non-archive: install `asset/<basename>` directly.
#
# Args:
#   <uri>                   Asset URI. Supported schemes: `https://`, `http://`,
#                           `ftp://`, `ftps://`, `sftp://`, `file://<abs-path>`,
#                           `gh://owner/repo@ref:path`, `oci://ref[?path=glob]`,
#                           and bare local paths. A `#sha256=<hex>` fragment is
#                           verified automatically after download (unless
#                           `--sha256 none`).
#   --installer-dir <dir>   Use `<dir>` as `work_dir` (persistent; caller owns
#                           cleanup). Orthogonal to all output flags.
#   --binary-src <spec>     Suffix-path match inside `asset/` (whole-component
#                           boundary; ambiguous match → error). Repeatable. For
#                           non-archives, `asset/` contains one file (`<basename>`);
#                           omit to install it directly, or give a matching spec.
#                           Requires `--binary-dest`.
#   --binary-dest <path>    Install matched or auto-discovered binary/binaries via
#                           `install__copy_bin` (sets executable bit). Repeatable.
#   --file-src <spec>       Suffix-path match inside `asset/` (whole-component
#                           boundary; ambiguous match → error). Repeatable. Required
#                           for archives (no auto-discovery). For non-archives,
#                           omit to install `asset/<basename>` directly.
#                           Requires `--file-dest`.
#   --file-dest <path>      Install matched file(s) via plain copy. Repeatable.
#   --chmod-exec <spec>     Suffix-path match inside `asset/`; sets exec bit in
#                           place without copying. Repeatable. Useful for running
#                           a tool from `work_dir` during installation (tmpdir
#                           persists until script exit).
#   --header <H>            HTTP/FTP request header; repeatable.
#   --netrc-file <path>     netrc file for HTTP Basic / FTP / SFTP auth.
#   --sha256 <hex|none>     64-char hex: verify the downloaded asset against this
#                           hash. `none`: suppress all sha256 checks (URI fragment,
#                           sidecar, and explicit hex). GPG is unaffected.
#   --sidecar <uri>         URI of a checksum file containing the asset's sha256.
#                           Same `--header` and `--netrc` args apply. Formats:
#                           `sha256sum` multi-entry (`<hex>  <filename>` or
#                           `<hex> *<filename>`) matched by asset name, or raw
#                           single-hash (one line, one field). Hard-fails on
#                           mismatch or missing entry. Cannot be combined with
#                           `--sha256 none`.
#   --gpg-key <uri>         URI of the GPG public key; enables GPG verification.
#   --gpg-sig <uri>         URI of the detached GPG signature.
#                           Default: the asset `<uri>` with `.asc` appended.
#   --filename <name>       Override the URI basename for `archive/` placement
#                           and sidecar hash lookup. Does not affect the extracted
#                           tree layout under `asset/`.
#   --owner-group <id>      Call `install__track_internal_path` for each installed
#                           path (binary and file installs only).
#   --retry <n>             Re-download and re-verify up to `<n>` times on any
#                           sha256 mismatch (URI fragment, `--sha256`, or
#                           `--sidecar`). Does not retry GPG failures. Default: `3`.
#
# `--binary-src` requires `--binary-dest`; `--file-src` requires `--file-dest`.
#
# Stdout:
#   - `--binary-dest` given: one absolute installed binary path per line, in
#     `--binary-src` order (or auto-discovery order when N=0).
#   - `--file-dest` given: one absolute installed file path per line, in
#     `--file-src` order.
#   - Both given: binary paths first, then file paths.
#   - Neither given: the `work_dir/asset` directory path (one line).
#
# Returns: 0 on success, 1 on any failure (bad args, download, hash mismatch, GPG, extract, install).
uri__fetch_asset() {
  local _uri=""
  local _installer_dir="" _filename="" _owner_group="" _netrc_file=""
  local _sha256_spec="" _sidecar_uri="" _gpg_key_uri="" _gpg_sig_uri=""
  local _retry=3
  local -a _headers=() _binary_src=() _binary_dest=() _file_src=() _file_dest=() _chmod_exec_specs=()

  if [[ $# -gt 0 && "$1" != --* ]]; then
    _uri="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --installer-dir)
        _installer_dir="$2"
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
      --file-src)
        _file_src+=("$2")
        shift 2
        ;;
      --file-dest)
        _file_dest+=("$2")
        shift 2
        ;;
      --chmod-exec)
        _chmod_exec_specs+=("$2")
        shift 2
        ;;
      --header)
        _headers+=("$2")
        shift 2
        ;;
      --netrc-file)
        _netrc_file="$2"
        shift 2
        ;;
      --sha256)
        _sha256_spec="$2"
        shift 2
        ;;
      --sidecar)
        _sidecar_uri="$2"
        shift 2
        ;;
      --gpg-key)
        _gpg_key_uri="$2"
        shift 2
        ;;
      --gpg-sig)
        _gpg_sig_uri="$2"
        shift 2
        ;;
      --filename)
        _filename="$2"
        shift 2
        ;;
      --owner-group)
        _owner_group="$2"
        shift 2
        ;;
      --retry)
        _retry="$2"
        shift 2
        ;;
      *)
        logging__error "uri__fetch_asset: unknown option '$1'."
        return 1
        ;;
    esac
  done

  # ── Validate ──────────────────────────────────────────────────────────────
  [[ -n "$_uri" ]] || {
    logging__error "uri__fetch_asset: URI is required."
    return 1
  }

  local _sha256_none=false _sha256_hex=""
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
  "$_sha256_none" && [[ -n "$_sidecar_uri" ]] && {
    logging__error "uri__fetch_asset: --sha256 none cannot be combined with --sidecar."
    return 1
  }

  local _nbsrc="${#_binary_src[@]}" _nbdest="${#_binary_dest[@]}"
  local _nfsrc="${#_file_src[@]}" _nfdest="${#_file_dest[@]}"
  [[ "$_nbsrc" -gt 0 && "$_nbdest" -gt 1 && "$_nbsrc" -ne "$_nbdest" ]] && {
    logging__error "uri__fetch_asset: ${_nbsrc} --binary-src but ${_nbdest} --binary-dest (must be equal or use 1 --binary-dest for all)."
    return 1
  }
  [[ "$_nfsrc" -gt 0 && "$_nfdest" -gt 1 && "$_nfsrc" -ne "$_nfdest" ]] && {
    logging__error "uri__fetch_asset: ${_nfsrc} --file-src but ${_nfdest} --file-dest (must be equal or use 1 --file-dest for all)."
    return 1
  }
  [[ "$_nbsrc" -gt 0 && "$_nbdest" -eq 0 ]] && {
    logging__error "uri__fetch_asset: --binary-src requires --binary-dest."
    return 1
  }
  [[ "$_nfsrc" -gt 0 && "$_nfdest" -eq 0 ]] && {
    logging__error "uri__fetch_asset: --file-src requires --file-dest."
    return 1
  }

  # ── Auth args ─────────────────────────────────────────────────────────────
  local -a _auth_args=()
  local _h
  for _h in "${_headers[@]}"; do _auth_args+=(--header "$_h"); done
  [[ -n "$_netrc_file" ]] && _auth_args+=(--netrc-file "$_netrc_file")

  # ── Work dir and asset name ───────────────────────────────────────────────
  local _split _base_uri _frag
  _split="$(_uri__split_frag "$_uri")"
  _base_uri="$(printf '%s\n' "$_split" | head -n1)"
  _frag="$(printf '%s\n' "$_split" | tail -n1)"
  local _asset_name="${_filename:-$(_uri__safe_basename "$_base_uri")}"

  local _work_dir
  if [[ -n "$_installer_dir" ]]; then
    _work_dir="$_installer_dir"
    mkdir -p "$_work_dir"
    local _sd
    for _sd in archive asset sidecar gpg-sig gpg-key; do
      rm -rf "${_work_dir:?}/${_sd}"
    done
  else
    _work_dir="$(file__mktmpdir "uri-fetch-asset")"
  fi

  local _archive_dir="${_work_dir}/archive"
  local _asset_dir="${_work_dir}/asset"
  mkdir -p "$_archive_dir" "$_asset_dir"
  local _dl_path="${_archive_dir}/${_asset_name}"

  # ── Download sidecar once before retry loop ───────────────────────────────
  local _sidecar_hash=""
  if [[ -n "$_sidecar_uri" ]] && ! "$_sha256_none"; then
    local _sidecar_dir="${_work_dir}/sidecar"
    mkdir -p "$_sidecar_dir"
    local _sc_base _sc_name _sidecar_file
    _sc_base="$(printf '%s\n' "$(_uri__split_frag "$_sidecar_uri")" | head -n1)"
    _sc_name="$(_uri__safe_basename "$_sc_base")"
    _sidecar_file="${_sidecar_dir}/${_sc_name}"
    logging__download "Fetching checksum sidecar from '${_sc_base}'"
    _uri__download_to "$_sidecar_uri" "$_sidecar_file" "${_auth_args[@]}" || {
      logging__error "uri__fetch_asset: failed to download sidecar from '${_sc_base}'."
      return 1
    }
    _sidecar_hash="$(_uri__sidecar_hash "$_asset_name" "$_sidecar_file")"
    [[ -n "$_sidecar_hash" ]] || {
      logging__error "uri__fetch_asset: could not extract hash for '${_asset_name}' from sidecar '${_sc_base}'."
      return 1
    }
  fi

  local _frag_sha=""
  ! "$_sha256_none" && _frag_sha="$(_uri__frag_sha256 "$_frag")"
  local _cls
  _cls="$(uri__classify "$_uri" 2> /dev/null)" || true

  # ── Retry loop: re-download on sha256 mismatch ────────────────────────────
  if "$_sha256_none"; then
    logging__warn "uri__fetch_asset: sha256 verification skipped for '${_asset_name}'."
  elif [[ -z "$_frag_sha" && -z "$_sha256_hex" && -z "$_sidecar_hash" && -z "$_gpg_key_uri" ]]; then
    logging__debug "uri__fetch_asset: no integrity verification configured for '${_asset_name}'."
  fi

  local _attempt=0
  while true; do
    _attempt=$((_attempt + 1))
    logging__download "Fetching '${_asset_name}' from '${_base_uri}'"
    _uri__download_to "$_uri" "$_dl_path" "${_auth_args[@]}" || return 1

    if "$_sha256_none"; then break; fi

    local _mismatch=false
    if [[ -n "$_frag_sha" && "$_cls" != "oci" ]]; then
      verify__sha "$_dl_path" "$_frag_sha" 2> /dev/null || _mismatch=true
    fi
    if ! "$_mismatch" && [[ -n "$_sha256_hex" ]]; then
      verify__sha "$_dl_path" "$_sha256_hex" 2> /dev/null || _mismatch=true
    fi
    if ! "$_mismatch" && [[ -n "$_sidecar_hash" ]]; then
      verify__sha "$_dl_path" "$_sidecar_hash" 2> /dev/null || _mismatch=true
    fi
    if ! "$_mismatch"; then break; fi

    if [[ "$_attempt" -ge "$_retry" ]]; then
      # Emit full verify output for the final failure to surface the mismatch details.
      [[ -n "$_frag_sha" && "$_cls" != "oci" ]] && verify__sha "$_dl_path" "$_frag_sha" 2>&1 || true
      [[ -n "$_sha256_hex" ]] && verify__sha "$_dl_path" "$_sha256_hex" 2>&1 || true
      [[ -n "$_sidecar_hash" ]] && verify__sha "$_dl_path" "$_sidecar_hash" 2>&1 || true
      logging__error "uri__fetch_asset: sha256 mismatch for '${_asset_name}' after ${_retry} attempt(s)."
      return 1
    fi
    logging__warn "uri__fetch_asset: sha256 mismatch on attempt ${_attempt}/${_retry} — re-downloading '${_asset_name}'..."
    rm -f "$_dl_path"
  done

  # ── GPG verification ──────────────────────────────────────────────────────
  if [[ -n "$_gpg_key_uri" ]]; then
    local _gpg_sig_dir="${_work_dir}/gpg-sig"
    local _gpg_key_dir="${_work_dir}/gpg-key"
    mkdir -p "$_gpg_sig_dir" "$_gpg_key_dir"
    local _sig_uri="${_gpg_sig_uri:-${_base_uri}.asc}"
    local _sig_base _sig_file
    _sig_base="$(printf '%s\n' "$(_uri__split_frag "$_sig_uri")" | head -n1)"
    _sig_file="${_gpg_sig_dir}/$(_uri__safe_basename "$_sig_base")"
    local _key_base _key_file
    _key_base="$(printf '%s\n' "$(_uri__split_frag "$_gpg_key_uri")" | head -n1)"
    _key_file="${_gpg_key_dir}/$(_uri__safe_basename "$_key_base")"
    logging__download "Fetching GPG signature from '${_sig_base}'"
    _uri__download_to "$_sig_uri" "$_sig_file" "${_auth_args[@]}" || return 1
    logging__download "Fetching GPG key from '${_key_base}'"
    _uri__download_to "$_gpg_key_uri" "$_key_file" "${_auth_args[@]}" || return 1
    verify__gpg_detached "$_dl_path" "$_sig_file" "$_key_file" || return 1
  fi

  # ── Archive detection and extraction ──────────────────────────────────────
  local _filetype _is_archive=false
  _filetype="$(file__detect_type "$_dl_path")"
  case "$_filetype" in
    gzip | xz | bzip2 | zip) _is_archive=true ;;
  esac

  if "$_is_archive"; then
    logging__install "Extracting '${_asset_name}'..."
    local _extract_name
    case "$_filetype" in
      gzip) _extract_name="asset.tar.gz" ;;
      xz) _extract_name="asset.tar.xz" ;;
      bzip2) _extract_name="asset.tar.bz2" ;;
      zip) _extract_name="asset.zip" ;;
      *) _extract_name="$_asset_name" ;;
    esac
    file__extract_archive "$_dl_path" "$_asset_dir" "$_extract_name" || {
      logging__error "uri__fetch_asset: extraction of '${_asset_name}' failed."
      return 1
    }
  else
    mv -f "$_dl_path" "${_asset_dir}/${_asset_name}" || return 1
  fi

  # ── chmod-exec specs ──────────────────────────────────────────────────────
  if [[ "${#_chmod_exec_specs[@]}" -gt 0 ]]; then
    local _cspec _cmatches _cm
    for _cspec in "${_chmod_exec_specs[@]}"; do
      _cmatches="$(_uri__match_binary_src "$_cspec" "$_asset_dir")"
      [[ -n "$_cmatches" ]] || {
        logging__error "uri__fetch_asset: --chmod-exec '${_cspec}': no match in asset directory."
        return 1
      }
      while IFS= read -r _cm; do
        [[ -n "$_cm" ]] && chmod +x "$_cm"
      done <<< "$_cmatches"
    done
  fi

  # ── Binary installation ───────────────────────────────────────────────────
  if [[ "$_nbdest" -gt 0 ]]; then
    local -a _found_srcs=() _install_names=()
    if [[ "$_nbsrc" -gt 0 ]]; then
      local _i
      for _i in "${!_binary_src[@]}"; do
        local _spec="${_binary_src[$_i]}" _found_src _mc
        _found_src="$(_uri__match_binary_src "$_spec" "$_asset_dir")"
        _mc="$(printf '%s\n' "$_found_src" | grep -c . || true)"
        [[ "$_mc" -gt 1 ]] && {
          logging__error "uri__fetch_asset: ambiguous --binary-src '${_spec}': ${_mc} matches in '${_asset_name}'."
          return 1
        }
        [[ -z "$_found_src" ]] && {
          logging__error "uri__fetch_asset: --binary-src '${_spec}' not found in '${_asset_name}'."
          return 1
        }
        _found_srcs+=("$_found_src")
        _install_names+=("$(basename "$_spec")")
      done
    elif "$_is_archive"; then
      local _discovered
      _discovered="$(find "$_asset_dir" -type f -perm -u+x 2> /dev/null || true)"
      if [[ -z "$_discovered" ]]; then
        while IFS= read -r _f; do chmod +x "$_f" 2> /dev/null || true; done \
          < <(find "$_asset_dir" -type f)
        _discovered="$(find "$_asset_dir" -type f 2> /dev/null || true)"
      fi
      if [[ "$_nbdest" -eq 1 && "${_binary_dest[0]}" != */ ]]; then
        local _disc_count
        _disc_count="$(printf '%s\n' "$_discovered" | grep -c . || true)"
        [[ "$_disc_count" -ne 1 ]] && {
          logging__error "uri__fetch_asset: auto-discovery found ${_disc_count} executables but --binary-dest is an exact path (not a directory)."
          return 1
        }
      fi
      while IFS= read -r _f; do
        [[ -n "$_f" ]] || continue
        _found_srcs+=("$_f")
        _install_names+=("$(basename "$_f")")
      done <<< "$_discovered"
      [[ "${#_found_srcs[@]}" -eq 0 ]] && {
        logging__error "uri__fetch_asset: no executables found in extracted '${_asset_name}'."
        return 1
      }
    else
      _found_srcs+=("${_asset_dir}/${_asset_name}")
      _install_names+=("$_asset_name")
    fi

    local _j
    for _j in "${!_found_srcs[@]}"; do
      local _src="${_found_srcs[$_j]}" _name="${_install_names[$_j]}" _dest_spec _dest_path
      if [[ "$_nbdest" -gt 1 && "$_j" -lt "$_nbdest" ]]; then
        _dest_spec="${_binary_dest[$_j]}"
      else
        _dest_spec="${_binary_dest[0]}"
      fi
      if [[ "$_dest_spec" == */ ]]; then
        _dest_path="${_dest_spec%/}/${_name}"
      else
        _dest_path="$_dest_spec"
      fi
      mkdir -p "$(dirname "$_dest_path")"
      chmod +x "$_src" 2> /dev/null || true
      logging__install "Installing '${_name}' to '${_dest_path}'"
      install__copy_bin "$_src" "$_dest_path" || return 1
      [[ -n "$_owner_group" ]] && install__track_internal_path "$_owner_group" "$_dest_path"
      logging__success "Installed '${_name}' → '${_dest_path}'"
      printf '%s\n' "$_dest_path"
    done
  fi

  # ── File installation ─────────────────────────────────────────────────────
  if [[ "$_nfdest" -gt 0 ]]; then
    local -a _fnd_srcs=() _fnd_names=()
    if [[ "$_nfsrc" -gt 0 ]]; then
      local _i
      for _i in "${!_file_src[@]}"; do
        local _spec="${_file_src[$_i]}" _found_src _mc
        _found_src="$(_uri__match_binary_src "$_spec" "$_asset_dir")"
        _mc="$(printf '%s\n' "$_found_src" | grep -c . || true)"
        [[ "$_mc" -gt 1 ]] && {
          logging__error "uri__fetch_asset: ambiguous --file-src '${_spec}': ${_mc} matches in '${_asset_name}'."
          return 1
        }
        [[ -z "$_found_src" ]] && {
          logging__error "uri__fetch_asset: --file-src '${_spec}' not found in '${_asset_name}'."
          return 1
        }
        _fnd_srcs+=("$_found_src")
        _fnd_names+=("$(basename "$_spec")")
      done
    elif "$_is_archive"; then
      logging__error "uri__fetch_asset: --file-dest requires --file-src for archive assets."
      return 1
    else
      _fnd_srcs+=("${_asset_dir}/${_asset_name}")
      _fnd_names+=("$_asset_name")
    fi

    local _k
    for _k in "${!_fnd_srcs[@]}"; do
      local _src="${_fnd_srcs[$_k]}" _name="${_fnd_names[$_k]}" _dest_spec _dest_path
      if [[ "$_nfdest" -gt 1 && "$_k" -lt "$_nfdest" ]]; then
        _dest_spec="${_file_dest[$_k]}"
      else
        _dest_spec="${_file_dest[0]}"
      fi
      if [[ "$_dest_spec" == */ ]]; then
        _dest_path="${_dest_spec%/}/${_name}"
      else
        _dest_path="$_dest_spec"
      fi
      mkdir -p "$(dirname "$_dest_path")"
      logging__install "Installing '${_name}' to '${_dest_path}'"
      cp -f "$_src" "$_dest_path" || return 1
      [[ -n "$_owner_group" ]] && install__track_internal_path "$_owner_group" "$_dest_path"
      logging__success "Installed '${_name}' → '${_dest_path}'"
      printf '%s\n' "$_dest_path"
    done
  fi

  # ── No install flags: print asset dir ────────────────────────────────────
  if [[ "$_nbdest" -eq 0 && "$_nfdest" -eq 0 ]]; then
    printf '%s\n' "$_asset_dir"
  fi
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
  if [[ "$_chmod_exec" == true ]]; then
    uri__fetch_asset "$_input" --binary-dest "$_dest" "${_fa_args[@]}"
  else
    uri__fetch_asset "$_input" --file-dest "$_dest" "${_fa_args[@]}"
  fi
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
      uri__fetch_asset "$_input" --file-dest "$_dest" "$@" > /dev/null || return 1
      printf '%s\n' "$_dest"
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
