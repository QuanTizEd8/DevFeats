#!/usr/bin/env bash
# GitHub Releases API: fetch JSON, resolve versions, select and download release assets.
#
# Fetches release metadata via the GitHub API, resolves version specs, selects
# platform-appropriate assets using arch/platform heuristics, downloads and
# verifies them, extracts archives, and installs binaries.
# Respects `GITHUB_TOKEN` for all API calls.

[ -n "${_GITHUB__LIB_LOADED-}" ] && return 0
_GITHUB__LIB_LOADED=1

_GITHUB__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
. "$_GITHUB__LIB_DIR/logging.sh"
# shellcheck source=lib/json.sh
. "$_GITHUB__LIB_DIR/json.sh"
# shellcheck source=lib/net.sh
. "$_GITHUB__LIB_DIR/net.sh"
# shellcheck source=lib/verify.sh
. "$_GITHUB__LIB_DIR/verify.sh"
# shellcheck source=lib/file.sh
. "$_GITHUB__LIB_DIR/file.sh"
# shellcheck source=lib/install/common.sh
. "$_GITHUB__LIB_DIR/install/common.sh"

# @brief github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>] — Fetch GitHub Releases API JSON for a repository.
#
# Without `--tag`: fetches `/releases/latest`. With `--tag`: fetches
# `/releases/tags/<tag>`. Respects `GITHUB_TOKEN` (sets
# `Authorization: Bearer` automatically).
#
# Args:
#   <owner/repo>   GitHub repository in `owner/repo` format.
#   --tag <tag>    Release tag to fetch (optional; defaults to latest).
#   --dest <file>  Write JSON to this file instead of stdout (optional).
#
# Stdout: release JSON (suppressed when `--dest` is given).
#
# Returns: 0 on success, 1 on HTTP error or missing tool.
github__fetch_release_json() {
  local _repo="$1"
  shift
  local _tag="" _dest=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --dest)
        shift
        _dest="$1"
        shift
        ;;
      *)
        logging__error "github__fetch_release_json: unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _url
  if [ -n "$_tag" ]; then
    _url="https://api.github.com/repos/${_repo}/releases/tags/${_tag}"
  else
    _url="https://api.github.com/repos/${_repo}/releases/latest"
  fi

  _github__api_get "$_url" "$_dest"
  return $?
}

# @brief github__release_json_tag_name <file> — Print `tag_name` from a single-release JSON file (`/releases/latest` or `/releases/tags/...` response written to disk).
#
# Prefers jq (via `json__query`) for correct parsing on minified or pretty JSON.
# Falls back to `grep -o` for `tag_name` only (first root `tag_name` key).
#
# Args:
#   <file>  Path to a GitHub release JSON file.
#
# Stdout: tag name string (e.g. `v1.2.3`).
#
# Returns: 0 on success, 1 if unreadable or tag_name not found.
github__release_json_tag_name() {
  local _f="$1"
  local _line
  [ -r "$_f" ] || return 1
  if json__root_scalar_stdin tag_name < "$_f"; then
    return 0
  fi
  _line="$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$_f" | head -n 1)" || return 1
  [ -n "$_line" ] || return 1
  printf '%s\n' "$_line" | sed 's/^"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)"$/\1/'
}

# @brief github__release_json_id <file> — Print the root release numeric `id` from a single-release JSON file.
#
# Uses jq (via `json__query`). Plain-text grep for the first `"id"` is unsafe on minified
# responses where asset objects include `"id"` before the root release `id`.
#
# Args:
#   <file>  Path to a GitHub release JSON file.
#
# Stdout: numeric release id.
#
# Returns: 0 on success, 1 if unreadable or id not found.
github__release_json_id() {
  local _f="$1"
  [ -r "$_f" ] || return 1
  json__root_scalar_stdin id < "$_f"
}

# @brief github__release_json_digest_for_asset <release.json> <asset_name> — Print lowercase hex SHA-256 from the GitHub Releases API asset `digest` field for the asset whose `name` equals `<asset_name>` exactly.
#
# Newer releases publish `digest` on each asset; older releases omit it — callers
# should fall back to a downloaded `.sha256` sidecar when this returns 1.
#
# Args:
#   <release.json>  Path to a `/releases/latest` or `/releases/tags/…` JSON file.
#   <asset_name>    Exact `name` value of the release asset (e.g. `fzf-0.71.0-linux_amd64.tar.gz`).
#
# Stdout: 64-character lowercase hex digest.
#
# Returns: 0 on success, 1 if unreadable, unparsable, not found, or digest absent.
github__release_json_digest_for_asset() {
  local _f="$1" _name="$2" _out=""
  [ -r "$_f" ] || return 1
  [ -n "$_name" ] || return 1

  _out=""
  _json__ensure_jq || return 1
  # shellcheck disable=SC2016
  _out="$(json__query -r --arg n "$_name" '
      (.assets // [])[]
      | select(.name == $n)
      | .digest // empty
      | if length > 0 then (sub("^sha256:"; "") | ascii_downcase) else empty end
    ' "$_f" 2> /dev/null)" || _out=""

  [ -n "$_out" ] && [ "$_out" != "null" ] || return 1
  printf '%s\n' "$_out"
  return 0
}

# @brief github__fetch_release_asset_tarball <owner/repo> <tag> <asset-name> <dest-file> — Download a release asset and verify its SHA-256 if a digest is available in the API.
#
# The download URL is `${SYSSET_RELEASE_BASE:-https://github.com/<repo>/releases/download}/<tag>/<asset-name>`.
# Respects the same GitHub API auth as `github__fetch_release_json`.
# Note: for new code prefer `github__install_release` which also handles
# archive extraction and binary installation in addition to download+verify.
#
# Args:
#   <owner/repo>   GitHub repository in "owner/repo" format.
#   <tag>          Release tag (e.g. `v1.2.3`).
#   <asset-name>   Exact asset filename (e.g. `fzf-0.71.0-linux_amd64.tar.gz`).
#   <dest-file>    Destination path to write the downloaded file.
#
# Returns: 0 on success, 1 on download failure or SHA-256 mismatch.
github__fetch_release_asset_tarball() {
  local _repo="$1" _tag="$2" _asset="$3" _dest="$4"
  local _rel _digest _url

  if [ -z "$_repo" ] || [ -z "$_tag" ] || [ -z "$_asset" ] || [ -z "$_dest" ]; then
    logging__error "github__fetch_release_asset_tarball: need owner/repo, tag, asset, dest"
    return 1
  fi

  _rel="$(mktemp)"
  if github__fetch_release_json "$_repo" --tag "$_tag" --dest "$_rel" 2> /dev/null; then
    _digest="$(github__release_json_digest_for_asset "$_rel" "$_asset")" || _digest=""
  else
    _digest=""
  fi
  rm -f "$_rel"

  if [ -n "${SYSSET_RELEASE_BASE-}" ]; then
    _url="${SYSSET_RELEASE_BASE}/${_tag}/${_asset}"
  else
    _url="https://github.com/${_repo}/releases/download/${_tag}/${_asset}"
  fi

  if ! command -v net__fetch_url_file > /dev/null 2>&1; then
    logging__error "github__fetch_release_asset_tarball: net.sh must be sourced"
    return 1
  fi
  if ! net__fetch_url_file "$_url" "$_dest"; then
    return 1
  fi

  if [ -n "$_digest" ] && [ "$_digest" != "null" ] && command -v verify__sha > /dev/null 2>&1; then
    if ! verify__sha "$_dest" "$_digest"; then
      return 1
    fi
  else
    logging__warn "No digest in release metadata for '${_asset}' — skipping verification."
  fi
  return 0
}

# @brief github__install_release OPTIONS — Unified download → verify → extract → install helper for GitHub release assets.
#
# Resolves and downloads a release asset from GitHub, verifies its integrity
# (SHA-256 and/or GPG), auto-detects whether it is an archive or direct binary
# via magic bytes, extracts if needed, and installs the binary to a destination
# path using install__copy_bin.
#
# Required:
#   --repo <owner/repo>    GitHub repository (e.g. "oras-project/oras")
#   --tag  <tag>           Full release tag (e.g. "v1.2.3")
#   --dest <path>          Absolute destination path for the installed binary
#
# Asset selection (all optional; when none given, full OS/arch heuristic selection is used):
#   --asset <name>         Exact asset filename; skips API enumeration
#   --asset-regex <ere>    ERE pre-filter, then apply github__pick_release_asset heuristics
#
# Binary extraction (optional):
#   --binary-path <name>   Basename of binary inside archive.
#                          When absent, magic bytes determine archive vs. direct binary;
#                          archives are searched for basename($dest).
#
# SHA-256 verification (default: auto):
#   --sha256 <spec>        Composable with '+'. Base modes:
#                            auto      Try JSON digest; warn+continue if absent (default)
#                            json      Require JSON digest; fail if absent
#                            sidecar   Download --sidecar-url and verify
#                            <64-hex>  Verify against caller-provided hash
#                            none      Skip all SHA-256 (standalone only)
#                          Combinations: auto+sidecar, json+sidecar
#   --sidecar-url <url>    Required when --sha256 includes 'sidecar'
#
# GPG verification (optional, additive):
#   --gpg-key-url <url>    Enables GPG; key downloaded from this URL
#   --gpg-sig-url <url>    Signature URL; default: <asset-url>.asc
#
# Resource tracking (optional):
#   --owner-group <id>     If set, calls install__track_internal_path after install
#
# Stdout: absolute path to installed binary.
# Returns: 0 on success, 1 on any failure.
github__install_release() {
  local _repo="" _tag="" _dest="" _asset="" _asset_regex="" _binary_path=""
  local _sha256_spec="auto" _sidecar_url="" _gpg_key_url="" _gpg_sig_url=""
  local _owner_group=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        shift
        _repo="$1"
        shift
        ;;
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --dest)
        shift
        _dest="$1"
        shift
        ;;
      --asset)
        shift
        _asset="$1"
        shift
        ;;
      --asset-regex)
        shift
        _asset_regex="$1"
        shift
        ;;
      --binary-path)
        shift
        _binary_path="$1"
        shift
        ;;
      --sha256)
        shift
        _sha256_spec="$1"
        shift
        ;;
      --sidecar-url)
        shift
        _sidecar_url="$1"
        shift
        ;;
      --gpg-key-url)
        shift
        _gpg_key_url="$1"
        shift
        ;;
      --gpg-sig-url)
        shift
        _gpg_sig_url="$1"
        shift
        ;;
      --owner-group)
        shift
        _owner_group="$1"
        shift
        ;;
      *)
        logging__error "github__install_release: unknown option: '$1'"
        return 1
        ;;
    esac
  done

  # ── Validate required args ──────────────────────────────────────────────────
  if [ -z "$_repo" ] || [ -z "$_tag" ] || [ -z "$_dest" ]; then
    logging__error "github__install_release: --repo, --tag, and --dest are required."
    return 1
  fi
  if [ -n "$_asset" ] && [ -n "$_asset_regex" ]; then
    logging__error "github__install_release: --asset and --asset-regex are mutually exclusive."
    return 1
  fi

  # ── Parse --sha256 spec (split on '+') ──────────────────────────────────────
  local _sha256_do_json=false _sha256_require_json=false
  local _sha256_do_sidecar=false _sha256_hex="" _sha256_none=false
  local _part
  while IFS= read -r _part; do
    [ -z "$_part" ] && continue
    case "$_part" in
      auto) _sha256_do_json=true ;;
      json)
        _sha256_do_json=true
        _sha256_require_json=true
        ;;
      sidecar) _sha256_do_sidecar=true ;;
      none) _sha256_none=true ;;
      *)
        if [[ "$_part" =~ ^[0-9a-fA-F]+$ ]]; then
          if [ "${#_part}" -ne 64 ]; then
            logging__error "github__install_release: --sha256 hex must be 64 chars, got ${#_part}."
            return 1
          fi
          _sha256_hex="$_part"
        else
          logging__error "github__install_release: invalid --sha256 token '${_part}'."
          return 1
        fi
        ;;
    esac
  done < <(printf '%s\n' "$_sha256_spec" | tr '+' '\n')

  if "$_sha256_none" && { "$_sha256_do_json" || "$_sha256_do_sidecar" || [ -n "$_sha256_hex" ]; }; then
    logging__error "github__install_release: --sha256 none cannot be combined with other modes."
    return 1
  fi
  if "$_sha256_do_sidecar" && [ -z "$_sidecar_url" ]; then
    logging__error "github__install_release: --sidecar-url is required when --sha256 includes 'sidecar'."
    return 1
  fi

  # ── Resolve asset name (exact → regex → full heuristics) ────────────────────
  if [ -z "$_asset" ]; then
    local _picked_url
    if [ -n "$_asset_regex" ]; then
      _picked_url="$(github__pick_release_asset "$_repo" --tag "$_tag" --asset-regex "$_asset_regex")" || return 1
    else
      _picked_url="$(github__pick_release_asset "$_repo" --tag "$_tag")" || return 1
    fi
    _asset="${_picked_url##*/}"
  fi

  # ── Build asset download URL ─────────────────────────────────────────────────
  local _asset_url
  if [ -n "${SYSSET_RELEASE_BASE-}" ]; then
    _asset_url="${SYSSET_RELEASE_BASE}/${_tag}/${_asset}"
  else
    _asset_url="https://github.com/${_repo}/releases/download/${_tag}/${_asset}"
  fi

  # ── Create tmpdir and set archive path ──────────────────────────────────────
  local _tmp _archive
  _tmp="$(file__mktmpdir "github-install-release")"
  _archive="${_tmp}/${_asset}"

  # ── Pre-fetch release JSON for auto/json sha256 modes ───────────────────────
  local _json_digest=""
  if "$_sha256_do_json"; then
    local _reljson="${_tmp}/_release.json"
    if github__fetch_release_json "$_repo" --tag "$_tag" --dest "$_reljson" 2> /dev/null; then
      _json_digest="$(github__release_json_digest_for_asset "$_reljson" "$_asset")" || _json_digest=""
    fi
    if "$_sha256_require_json" && [ -z "$_json_digest" ]; then
      logging__error "github__install_release: --sha256 json: no digest in release JSON for '${_asset}'."
      return 1
    fi
  fi

  # ── Download the asset ───────────────────────────────────────────────────────
  logging__download "Downloading '${_asset}' from '${_asset_url}'"
  net__fetch_url_file "$_asset_url" "$_archive" || {
    logging__error "github__install_release: failed to download '${_asset_url}'."
    return 1
  }

  # ── SHA-256: JSON digest (soft — warn if absent) ─────────────────────────────
  if "$_sha256_do_json" && [ -n "$_json_digest" ]; then
    verify__sha "$_archive" "$_json_digest" || return 1
  elif "$_sha256_do_json"; then
    logging__warn "github__install_release: no JSON digest for '${_asset}' — skipping JSON SHA-256."
  fi

  # ── SHA-256: sidecar file ────────────────────────────────────────────────────
  if "$_sha256_do_sidecar"; then
    local _sidecar_file="${_tmp}/_sidecar"
    logging__download "Downloading checksum sidecar from '${_sidecar_url}'"
    net__fetch_url_file "$_sidecar_url" "$_sidecar_file" || {
      logging__error "github__install_release: failed to download sidecar '${_sidecar_url}'."
      return 1
    }
    # Handles standard sha256sum multi-entry format ("<hash>  <filename>") where $NF
    # is the filename, and raw single-hash sidecar files (NR==1 fallback).
    local _sidecar_hash
    _sidecar_hash="$(awk -v a="${_asset}" '$NF==a{print $1;_f=1;exit} END{if(!_f && NR==1)print $1}' "$_sidecar_file")"
    [ -n "$_sidecar_hash" ] || {
      logging__error "github__install_release: could not extract hash for '${_asset}' from sidecar."
      return 1
    }
    verify__sha "$_archive" "$_sidecar_hash" || return 1
  fi

  # ── SHA-256: explicit hex ────────────────────────────────────────────────────
  if [ -n "$_sha256_hex" ]; then
    verify__sha "$_archive" "$_sha256_hex" || return 1
  fi

  # ── SHA-256: none ────────────────────────────────────────────────────────────
  if "$_sha256_none"; then
    logging__warn "github__install_release: SHA-256 verification skipped (--sha256 none)."
  fi

  # ── GPG verification ─────────────────────────────────────────────────────────
  if [ -n "$_gpg_key_url" ]; then
    local _sig_url="${_gpg_sig_url:-${_asset_url}.asc}"
    local _sig_file="${_tmp}/_asset.asc" _key_file="${_tmp}/_release.key"
    logging__download "Downloading GPG signature from '${_sig_url}'"
    net__fetch_url_file "$_sig_url" "$_sig_file" || {
      logging__error "github__install_release: failed to download GPG sig '${_sig_url}'."
      return 1
    }
    logging__download "Downloading GPG key from '${_gpg_key_url}'"
    net__fetch_url_file "$_gpg_key_url" "$_key_file" || {
      logging__error "github__install_release: failed to download GPG key '${_gpg_key_url}'."
      return 1
    }
    verify__gpg_detached "$_archive" "$_sig_file" "$_key_file" "${_owner_group:-lib-github}" || return 1
  fi

  # ── Detect file type and decide whether to extract ──────────────────────────
  local _bin_src _filetype _filetype_is_archive
  _filetype="$(file__detect_type "$_archive")"

  if [ -n "$_binary_path" ]; then
    # Caller explicitly says this is an archive with a named binary inside.
    _filetype_is_archive=true
  else
    case "$_filetype" in
      gzip | xz | bzip2 | zip) _filetype_is_archive=true ;;
      *) _filetype_is_archive=false ;;
    esac
  fi

  if "$_filetype_is_archive"; then
    local _extract_dir="${_tmp}/_extract"
    mkdir -p "$_extract_dir"
    logging__install "Extracting '${_asset}'..."
    # Map detected type to a synthetic filename so file__extract_archive
    # dispatches by extension correctly (handles extensionless downloaded paths).
    local _extract_name
    case "$_filetype" in
      gzip) _extract_name="asset.tar.gz" ;;
      xz) _extract_name="asset.tar.xz" ;;
      bzip2) _extract_name="asset.tar.bz2" ;;
      zip) _extract_name="asset.zip" ;;
      *) _extract_name="$_asset" ;;
    esac
    file__extract_archive "$_archive" "$_extract_dir" "$_extract_name" || {
      logging__error "github__install_release: extraction of '${_asset}' failed."
      return 1
    }
    # Find binary by basename anywhere in the extracted tree (handles any nesting depth).
    local _bin_name
    if [ -n "$_binary_path" ]; then
      _bin_name="$(basename "$_binary_path")"
    else
      _bin_name="$(basename "$_dest")"
    fi
    _bin_src="$(find "$_extract_dir" -name "$_bin_name" -type f | head -1)"
    [ -n "$_bin_src" ] || {
      logging__error "github__install_release: binary '${_bin_name}' not found in extracted '${_asset}'."
      return 1
    }
  else
    _bin_src="$_archive"
  fi

  chmod +x "$_bin_src" 2> /dev/null || true

  # ── Install binary ───────────────────────────────────────────────────────────
  logging__install "Installing '$(basename "$_dest")' to '${_dest}'"
  install__copy_bin "$_bin_src" "$_dest" || return 1

  # ── Track resource ───────────────────────────────────────────────────────────
  if [ -n "$_owner_group" ]; then
    install__track_internal_path "$_owner_group" "$_dest"
  fi

  logging__success "Installed '$(basename "$_dest")' → '${_dest}'"
  printf '%s\n' "$_dest"
}

# @brief github__latest_tag <owner/repo> — Print the latest release tag name.
#
# Args:
#   <owner/repo>  GitHub repository in "owner/repo" format.
#
# Stdout: the tag name (e.g. `v1.2.3`).
#
# Returns: 0 on success, 1 if the API call fails or the tag cannot be parsed.
github__latest_tag() {
  local _repo="$1"
  local _json _tag
  _json="$(github__fetch_release_json "$_repo")" || true
  _tag="$(printf '%s\n' "$_json" | json__root_scalar_stdin tag_name)" || _tag=""
  if [ -z "$_tag" ]; then
    _tag="$(printf '%s\n' "$_json" |
      grep '"tag_name"' | head -1 |
      sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')" || _tag=""
  fi
  if [ -n "$_tag" ]; then
    echo "$_tag"
    return 0
  fi

  if [ -n "$_json" ]; then
    logging__error "github__latest_tag: could not parse tag_name from API response for '${_repo}'."
  fi

  # Fallback: resolve tag via the /releases/latest redirect on github.com.
  # This avoids unauthenticated GitHub API rate limits / 403 responses.
  #
  # Use the net module for curl/wget abstraction.
  local _fallback_tag=""
  _fallback_tag="$(
    net__fetch_url_stdout "https://github.com/${_repo}/releases/latest" |
      sed -n 's|.*href="/'"${_repo}"'/releases/tag/\([^"?#]*\)".*|\1|p' |
      head -1 || true
  )"

  if [ -n "$_fallback_tag" ]; then
    echo "$_fallback_tag"
    return 0
  fi

  logging__error "github__latest_tag: failed to resolve latest tag for '${_repo}' (GitHub API unreachable and redirect fallback failed)."
  return 1
}

# @brief github__release_tags <owner/repo> [--per_page N] [--all] [--retries N] [--retry-delay SEC>] — Print one release tag per line (newest first) from `/releases?per_page=N` (default 100).
#
# Useful for version-matching against a list (grep/sort/tail in the caller).
# Without --all: fetches only the first page (up to --per_page tags). With
# --all: walks `page=1,2,...` until a page returns fewer than --per_page
# items (short-page termination — simpler than Link-header parsing and
# correct for idempotent helpers).
#
# HTTP fetches already use curl retries (5xx, 429, etc.) via net__fetch_url_stdout;
# --retries/--retry-delay add full end-to-end attempts when parsing fails or the
# API returns an error payload after a successful HTTP status.
#
# Args:
#   <owner/repo>       GitHub repository in "owner/repo" format.
#   --per_page N       Releases per page to request (default: 100).
#   --all              Paginate through every release (default: first page only).
#   --retries N        Maximum attempts for the whole list operation (default: 1).
#   --retry-delay SEC  Seconds to sleep between attempts (default: 4; ignored when N=1).
#
# Stdout: one tag name per line, newest first.
github__release_tags() {
  local _repo="$1"
  shift
  local _per_page=100 _all=false _retries=1 _retry_delay=4
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page)
        shift
        _per_page="$1"
        shift
        ;;
      --all)
        _all=true
        shift
        ;;
      --retries)
        shift
        _retries="$1"
        shift
        ;;
      --retry-delay)
        shift
        _retry_delay="$1"
        shift
        ;;
      *)
        logging__error "github__release_tags: unknown option: '$1'"
        return 1
        ;;
    esac
  done

  case "$_retries" in '' | *[!0-9]*)
    logging__error "github__release_tags: --retries must be a non-negative integer."
    return 1
    ;;
  esac
  [ "$_retries" -lt 1 ] && _retries=1
  case "$_retry_delay" in '' | *[!0-9]*)
    logging__error "github__release_tags: --retry-delay must be a non-negative integer."
    return 1
    ;;
  esac

  local _attempt=1
  while [ "$_attempt" -le "$_retries" ]; do
    if [ "$_all" = "false" ]; then
      local _url="https://api.github.com/repos/${_repo}/releases?per_page=${_per_page}"
      if _github__api_list_field "$_url" "tag_name"; then
        return 0
      fi
    else
      if _github__paginate_list_field \
        "https://api.github.com/repos/${_repo}/releases" \
        "tag_name" "$_per_page"; then
        return 0
      fi
    fi

    if [ "$_attempt" -ge "$_retries" ]; then
      logging__error "github__release_tags: failed to reach GitHub API for '${_repo}' after ${_retries} attempt(s)."
      return 1
    fi
    logging__warn "github__release_tags: GitHub API list failed for '${_repo}' (attempt ${_attempt}/${_retries}); retrying in ${_retry_delay}s."
    sleep "$_retry_delay"
    _attempt=$((_attempt + 1))
  done
}

# @brief github__resolve_version <owner/repo> [<version-spec>] — Resolve a version spec to an exact release, printing the full tag and bare version.
#
# Version specs:
#   "stable" / ""  Latest non-prerelease, non-draft release (/releases/latest fast path).
#   "latest"       Most recently published release, including pre-releases.
#   "X"            Latest stable release whose version starts with X.
#   "X.Y"          Latest stable release whose version starts with X.Y.
#   "X.Y.Z"        Latest stable release whose version starts with X.Y.Z
#                  (resolves to X.Y.Z itself when no build suffix exists, or
#                  the newest build e.g. X.Y.Z-1 when the repo uses them).
#   "X.Y.Z-BUILD"  Prefix-matched: resolves to the newest X.Y.Z-BUILD* release.
#
# Leading non-numeric characters are stripped from both the spec and each tag
# before comparison, so "v1.2", "1.2", and "jq-1.2" are all equivalent specs.
# Stable filtering uses GitHub's authoritative prerelease/draft fields (requires jq).
#
# For partial specs, releases are fetched page by page (newest first) and the
# first matching stable release is returned; pagination stops as soon as a match
# is found, so only as many API calls as necessary are made.
#
# Args:
#   <owner/repo>     GitHub repository in "owner/repo" format.
#   [<version-spec>] Version spec string (default: "stable").
#
# Stdout (two lines):
#   Line 1: full release tag as published on GitHub (e.g. "v1.2.3", "jq-1.7.1").
#   Line 2: bare version with the tag prefix stripped (e.g. "1.2.3", "1.7.1").
#
# Returns: 0 on success, 1 if no matching release is found or an API error occurs.
github__resolve_version() {
  local _repo="$1"
  shift
  local _spec="stable" _spec_set=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --*)
        logging__error "github__resolve_version: unknown option: '$1'"
        return 1
        ;;
      *)
        if [ "$_spec_set" = "false" ]; then
          _spec="$1"
          _spec_set=true
          shift
        else
          logging__error "github__resolve_version: unexpected positional argument: '$1'"
          return 1
        fi
        ;;
    esac
  done

  local _tag=""

  case "$_spec" in
    stable | "")
      # /releases/latest always returns the most recent non-prerelease, non-draft release.
      _tag="$(github__latest_tag "$_repo")" || {
        logging__error "github__resolve_version: could not resolve stable release for '${_repo}'."
        return 1
      }
      ;;
    latest)
      # Most recently published release including pre-releases; per_page=1 avoids
      # fetching unnecessary data since we only need the first result.
      local _releases
      _releases="$(_github__api_list_field \
        "https://api.github.com/repos/${_repo}/releases?per_page=1" \
        "tag_name")" || {
        logging__error "github__resolve_version: could not retrieve releases for '${_repo}'."
        return 1
      }
      _tag="$(printf '%s\n' "$_releases" | head -1)"
      ;;
    *)
      # Numeric spec: strip leading non-numerics, stream releases page by page
      # until the first matching stable release is found.
      local _norm
      _norm="$(_github__strip_tag_prefix "$_spec")"
      [ -n "$_norm" ] || {
        logging__error "github__resolve_version: spec '${_spec}' contains no numeric version content."
        return 1
      }
      _tag="$(_github__first_stable_tag_matching "$_repo" "$_norm")" || {
        logging__error "github__resolve_version: no stable release matching '${_spec}' found for '${_repo}'."
        return 1
      }
      ;;
  esac

  printf '%s\n%s\n' "$_tag" "$(_github__strip_tag_prefix "$_tag")"
  return 0
}

# @brief github__tags <owner/repo> [--per_page N] [--all] — Print one tag per line from `/tags?per_page=N` (default 100). Includes lightweight tags not associated with a release.
#
# Unlike github__release_tags (which uses /releases), this endpoint includes
# all git tags, including lightweight ones not associated with a release.
# See github__release_tags for the --all semantics (page-until-short).
#
# Args:
#   <owner/repo>   GitHub repository in "owner/repo" format.
#   --per_page N   Tags per page to request (default: 100).
#   --all          Paginate through every tag (default: first page only).
#
# Stdout: one tag name per line.
github__tags() {
  local _repo="$1"
  shift
  local _per_page=100 _all=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page)
        shift
        _per_page="$1"
        shift
        ;;
      --all)
        _all=true
        shift
        ;;
      *)
        logging__error "github__tags: unknown option: '$1'"
        return 1
        ;;
    esac
  done

  if [ "$_all" = "false" ]; then
    local _url="https://api.github.com/repos/${_repo}/tags?per_page=${_per_page}"
    _github__api_list_field "$_url" "name" || {
      logging__error "github__tags: failed to reach GitHub API for '${_repo}'."
      return 1
    }
    return 0
  fi

  _github__paginate_list_field \
    "https://api.github.com/repos/${_repo}/tags" \
    "name" "$_per_page" || {
    logging__error "github__tags: failed to reach GitHub API for '${_repo}'."
    return 1
  }
  return 0
}

# @brief github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere>] — Print `browser_download_url` values from a release. `--filter` applies an ERE grep to the URL list.
#
# Without --tag: uses /releases/latest. With --tag: uses
# /releases/tags/<tag>. Exits 1 if the API call fails.
#
# Args:
#   <owner/repo>    GitHub repository in "owner/repo" format.
#   --tag <tag>     Release tag to query (optional; defaults to latest).
#   --filter <ere>  ERE grep pattern applied to the URL list (optional).
#
# Stdout: one `browser_download_url` per line.
github__release_asset_urls() {
  local _repo="$1"
  shift
  local _tag="" _filter=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --filter)
        shift
        _filter="$1"
        shift
        ;;
      *)
        logging__error "github__release_asset_urls: unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _tmpfile
  _tmpfile="$(mktemp)"

  local _fetch_args=""
  [ -n "$_tag" ] && _fetch_args="--tag ${_tag}"

  # shellcheck disable=SC2086
  github__fetch_release_json "$_repo" ${_fetch_args} --dest "$_tmpfile" || {
    rm -f "$_tmpfile"
    return 1
  }

  local _urls
  _urls="$(json__object_array_field_lines_stdin assets browser_download_url < "$_tmpfile")" || _urls=""
  rm -f "$_tmpfile"

  if [ -n "$_filter" ]; then
    printf '%s\n' "$_urls" | grep -E "$_filter"
  else
    printf '%s\n' "$_urls"
  fi
  return 0
}

# @brief github__pick_release_asset <owner/repo> [--tag <tag>] [--asset-regex <ERE>] — Select a single release asset URL using heuristic arch/platform filters.
#
# Designed for tools that do not publish checksums or have irregular naming
# conventions. Prefer explicit URL construction with checksum verification
# when the release naming is known and stable.
#
# Filter cascade (each stage is skipped if it would reduce candidates to zero):
#   1. Negative: eliminate assets for other CPU architectures.
#   2. Negative: eliminate assets for other platforms (Windows, macOS, Android).
#   3. Negative: eliminate non-binary files (checksums, packages, certs, metadata).
#   4. Positive tiebreaker: prefer assets that explicitly name the current arch.
#   5. Positive tiebreaker: prefer statically linked / musl builds.
#
# Args:
#   <owner/repo>         GitHub repository in "owner/repo" format.
#   --tag <tag>          Release tag to use (optional; defaults to /releases/latest).
#   --asset-regex <ERE>  Pre-filter applied before the cascade. Exactly one
#                        match skips the cascade; zero matches returns 1.
#
# Stdout: exactly one URL. Returns 1 if no match or >1 candidates remain.
github__pick_release_asset() {
  local _repo="$1"
  shift
  local _tag="" _asset_regex=""
  local _raw_arch="" _kernel=""
  local _own_arch_re="" _bad_arch_re="" _bad_platform_re="" _bad_misc_re=""
  local _tag_arg="" _urls="" _tmp="" _count=0 _re="" _n=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --asset-regex)
        shift
        _asset_regex="$1"
        shift
        ;;
      *)
        logging__error "github__pick_release_asset: unknown option: '$1'"
        return 1
        ;;
    esac
  done

  # ── Fetch all asset URLs ──────────────────────────────────────────────────
  [ -n "$_tag" ] && _tag_arg="--tag $_tag"
  # shellcheck disable=SC2086
  _urls="$(github__release_asset_urls "$_repo" ${_tag_arg})" || return 1
  if [ -z "$_urls" ]; then
    logging__error "github__pick_release_asset: no assets found for '${_repo}'."
    return 1
  fi

  # ── Apply caller-supplied regex pre-filter ────────────────────────────────
  if [ -n "$_asset_regex" ]; then
    _tmp="$(printf '%s\n' "$_urls" | grep -E "$_asset_regex")" || true
    if [ -z "$_tmp" ]; then
      logging__error "github__pick_release_asset: --asset-regex '${_asset_regex}' matched no assets for '${_repo}'."
      return 1
    fi
    _urls="$_tmp"
    _count="$(printf '%s\n' "$_urls" | grep -c '.')"
    if [ "$_count" -eq 1 ]; then
      printf '%s\n' "$_urls"
      return 0
    fi
  fi

  # ── Build arch regex sets ─────────────────────────────────────────────────
  _raw_arch="$(os__arch)"
  case "$_raw_arch" in
    x86_64)
      _own_arch_re='[Aa]md64|x64|x86[_-]64'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]rm32|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    aarch64 | arm64)
      _own_arch_re='[Aa]arch64|[Aa]rm64'
      _bad_arch_re='[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    armv7l | armv7)
      _own_arch_re='[Aa][Rr][Mm]v7|[Aa][Rr][Mm]hf'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[56]|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    armv6l | armv6)
      _own_arch_re='[Aa][Rr][Mm]v6'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[57]|[Aa][Rr][Mm]hf|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    i386 | i686)
      _own_arch_re='i[36]86|-386|-686'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|ppc64|[Ss]390|riscv'
      ;;
    ppc64 | ppc64le)
      _own_arch_re='ppc64'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|[Ss]390|riscv'
      ;;
    s390 | s390x)
      _own_arch_re='[Ss]390'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|ppc64|riscv'
      ;;
    riscv64)
      _own_arch_re='riscv'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|ppc64|[Ss]390'
      ;;
  esac

  # ── Build platform regex sets ─────────────────────────────────────────────
  _kernel="$(os__kernel)"
  case "$_kernel" in
    Linux)
      _bad_platform_re='[Ww]indows|[Ww]in32|-win-|\.msi$|\.exe$|[Mm]ac[Oo][Ss]|-osx-|_osx_|[Dd]arwin|\.dmg$|[Aa]ndroid'
      ;;
    Darwin)
      _bad_platform_re='[Ww]indows|[Ww]in32|-win-|\.msi$|\.exe$|[Ll]inux|[Aa]ndroid'
      ;;
    *)
      _bad_platform_re='[Ww]indows|[Ww]in32|\.msi$|\.exe$|[Aa]ndroid'
      ;;
  esac

  # Packages, checksums, signatures, certificates, metadata.
  _bad_misc_re='\.deb$|\.rpm$|\.pkg$|\.apk$|\.[Aa]pp[Ii]mage$|\.snap$|[Cc]hecksums|sha256|sha512|\.sha1$|\.md5$|\.sig$|\.txt$|\.pub$|\.pem$|\.crt$|\.asc$|\.json$|\.sbom$'

  # ── Apply negative filters ────────────────────────────────────────────────
  # Each filter is skipped (not applied) when it would empty the candidate list.
  for _re in "$_bad_arch_re" "$_bad_platform_re" "$_bad_misc_re"; do
    [ -z "$_re" ] && continue
    _tmp="$(printf '%s\n' "$_urls" | grep -vE "$_re")" || true
    [ -n "$_tmp" ] && _urls="$_tmp"
  done

  # ── Apply positive tiebreakers ────────────────────────────────────────────
  # Each tiebreaker is skipped when it would empty the candidate list.
  for _re in "$_own_arch_re" 'static|musl'; do
    [ -z "$_re" ] && continue
    _tmp="$(printf '%s\n' "$_urls" | grep -E "$_re")" || true
    [ -n "$_tmp" ] && _urls="$_tmp"
  done

  # ── Count survivors and return ────────────────────────────────────────────
  _count="$(printf '%s\n' "$_urls" | grep -c '.')" || _count=0
  case "$_count" in
    1)
      printf '%s\n' "$_urls"
      return 0
      ;;
    0)
      logging__error "github__pick_release_asset: no matching asset for '${_repo}' (arch=${_raw_arch}, kernel=${_kernel})."
      return 1
      ;;
    *)
      logging__error "github__pick_release_asset: ${_count} ambiguous assets remain for '${_repo}'; pass --asset-regex to disambiguate:"
      printf '%s\n' "$_urls" | sed 's|.*/||' | while IFS= read -r _n; do
        logging__error "   ${_n}"
      done
      return 1
      ;;
  esac
}

# _github__api_list_field <url> <field>  (internal)
#
# Fetches a GitHub API list endpoint and extracts all values of the named JSON
# field from each top-level array element, printing one value per line.
# Returns 1 if the API call fails or the response is empty.
#
# Prefers jq then python3 (correct on minified one-line arrays and avoids nested
# "name"/"tag_name" keys inside objects). Falls back to grep -o when neither is
# available.
_github__api_list_field() {
  local _url="$1"
  local _field="$2"
  local _json _lines _msg
  _json="$(_github__api_get "$_url")" || return 1
  [ -z "$_json" ] && return 1

  if printf '%s\n' "$_json" | json__query -e 'type == "object" and (.message | type == "string")' > /dev/null 2>&1; then
    _msg="$(printf '%s\n' "$_json" | json__query -r '.message // empty' 2> /dev/null)" || _msg=""
    logging__error "_github__api_list_field: GitHub API error for '${_url}': ${_msg}"
    return 1
  fi

  _lines="$(printf '%s\n' "$_json" | json__array_field_lines_stdin "$_field")" || _lines=""
  if [ -n "$_lines" ]; then
    printf '%s\n' "$_lines"
    return 0
  fi

  if printf '%s\n' "$_json" | json__query -e 'type == "array" and length == 0' > /dev/null 2>&1; then
    logging__error "_github__api_list_field: GitHub API returned an empty JSON array for '${_url}'."
    return 1
  fi

  logging__error "_github__api_list_field: no '${_field}' values extracted from GitHub API response for '${_url}' (expected a non-empty JSON array of objects)."
  return 1
}

# _github__paginate_list_field <base_url> <field> <per_page>  (internal)
#
# Walks pages 1..N of a GitHub list endpoint (one that accepts `page=` and
# `per_page=`), extracting <field> from every array element, until a page
# returns fewer than <per_page> items (short-page termination). Prints every
# extracted value on stdout. Returns 0 when at least one value was printed,
# 1 when the first page fails to fetch (same contract as
# _github__api_list_field for the single-page case).
#
# Args:
#   <base_url>  API URL without the page/per_page query string.
#   <field>     JSON field to extract from each array element.
#   <per_page>  Page size; also the short-page threshold.
_github__paginate_list_field() {
  local _base="$1"
  local _field="$2"
  local _per_page="$3"
  local _page=1 _json _count _got_any=false

  while :; do
    local _sep='?'
    case "$_base" in *\?*) _sep='&' ;; esac
    local _url="${_base}${_sep}per_page=${_per_page}&page=${_page}"
    _json="$(_github__api_get "$_url")" || {
      [ "$_got_any" = "true" ] && return 0
      return 1
    }
    if [ -z "$_json" ]; then
      [ "$_got_any" = "true" ] && return 0
      return 1
    fi
    local _values
    _values="$(printf '%s\n' "$_json" | json__array_field_lines_stdin "$_field")" || _values=""
    if [ -n "$_values" ]; then
      printf '%s\n' "$_values"
      _got_any=true
    fi
    # Count items on this page to decide whether to continue. We count the
    # top-level array length (not the extracted field count) so that objects
    # missing the requested field don't trigger false-positive short-page
    # termination.
    _count="$(printf '%s\n' "$_json" | _github__count_top_level_array)" || _count=0
    [ -z "$_count" ] && _count=0
    if [ "$_count" -lt "$_per_page" ]; then
      [ "$_got_any" = "true" ] && return 0
      return 1
    fi
    _page=$((_page + 1))
  done
}

# _github__count_top_level_array  (internal)
#
# Reads a JSON array on stdin and prints its top-level element count.
# Uses jq (via json__query); falls back to a best-effort `grep -c '^{'`-style
# heuristic if jq cannot be installed.
_github__count_top_level_array() {
  local _json
  _json="$(cat)"
  if printf '%s' "$_json" | json__query 'length' 2> /dev/null; then
    return 0
  fi
  # Fallback: count occurrences of top-level object open-brace. This is a
  # best-effort heuristic. Over-counts are harmless — the loop just runs an
  # extra empty page before terminating.
  printf '%s\n' "$_json" | grep -c '^[[:space:]]*{' || true
}

# _github__escape_ere <str>  (internal)
#
# Prints <str> with regex meta-characters escaped so it can be safely used
# as a literal prefix/substring inside `grep` / `grep -E` patterns. Covers
# both BRE and ERE metacharacters.
_github__escape_ere() {
  # Chars escaped: \ . ^ $ * + ? ( ) { } | [ ]
  # ']' must come first inside the bracket expression; '\\' is escaped as
  # '\\\\' in the sed replacement to produce a single backslash.
  printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

# _github__api_get <url> [<dest_file>]  (internal)
#
# Performs a GitHub API GET with standard Accept/version headers and an
# optional Authorization header from GITHUB_TOKEN.
# Suppresses xtrace around the authenticated call to prevent token leaking in
# CI logs.  Passes output to stdout or to <dest_file> when provided.
_github__api_get() {
  local _url="$1"
  local _dest="${2:-}"
  local _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null

  # Use set -- to accumulate --header args (POSIX alternative to arrays).
  set -- \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --header "User-Agent: devfeats"
  [ -n "${GITHUB_TOKEN:-}" ] && set -- "$@" --header "Authorization: Bearer ${GITHUB_TOKEN}"

  local _ec=0
  if [ -n "$_dest" ]; then
    net__fetch_url_file "$_url" "$_dest" "$@" || _ec=$?
  else
    net__fetch_url_stdout "$_url" "$@" || _ec=$?
  fi
  [ "$_xt" = "true" ] && { set -x; } 2> /dev/null
  return "$_ec"
}

# _github__strip_tag_prefix <tag>  (internal)
#
# Strip all leading non-numeric characters from a tag or version string.
# "v1.2.3" → "1.2.3", "jq-1.7.1" → "1.7.1", "1.2.3" → "1.2.3".
_github__strip_tag_prefix() {
  printf '%s' "$1" | sed 's/^[^0-9]*//'
}

# _github__first_stable_tag_matching <repo> <norm_spec>  (internal)
#
# Fetches releases page by page (newest first), returning the full tag of the
# first stable (non-prerelease, non-draft) release whose bare version matches
# <norm_spec> as a prefix followed by ".", "-", or end-of-string.  Pagination
# stops as soon as a match is found, so only as many API requests as necessary
# are made.
#
# Args:
#   <owner/repo>  GitHub repository in "owner/repo" format.
#   <norm_spec>   Normalised (prefix-stripped) version spec to match against.
#
# Stdout: the matched full release tag.
# Returns: 0 on match, 1 if no match found or on API error.
_github__first_stable_tag_matching() {
  local _repo="$1" _norm="$2"
  _json__ensure_jq || return 1
  local _per_page=100 _page=1 _json _tags _tag _count

  while :; do
    local _url="https://api.github.com/repos/${_repo}/releases?per_page=${_per_page}&page=${_page}"
    _json="$(_github__api_get "$_url")" || return 1

    _tags="$(printf '%s\n' "$_json" |
      json__query -r '.[] | select(.prerelease == false and .draft == false) | .tag_name' \
        2> /dev/null)" || _tags=""

    if [ -n "$_tags" ]; then
      _tag="$(printf '%s\n' "$_tags" | awk -v s="$_norm" '
        {
          bare = $0; sub(/^[^0-9]*/, "", bare)
          c = substr(bare, length(s) + 1, 1)
          if (bare == s || (index(bare, s) == 1 && (c == "." || c == "-"))) { print; exit }
        }')"
      if [ -n "$_tag" ]; then
        printf '%s\n' "$_tag"
        return 0
      fi
    fi

    _count="$(printf '%s\n' "$_json" | _github__count_top_level_array)" || _count=0
    [ -z "$_count" ] && _count=0
    [ "$_count" -lt "$_per_page" ] && return 1

    _page=$((_page + 1))
  done
}
