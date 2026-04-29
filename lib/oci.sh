#!/usr/bin/env bash
# oci.sh — Container registry reference helpers (bash ≥4).
# Do not edit _lib/ copies directly — edit lib/ instead.
[[ -n "${_OCI__LIB_LOADED-}" ]] && return 0
_OCI__LIB_LOADED=1

_OCI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ospkg.sh
. "$_OCI_LIB_DIR/ospkg.sh"
# shellcheck source=lib/install/oras.sh
. "$_OCI_LIB_DIR/install/oras.sh"
# shellcheck source=lib/logging.sh
. "$_OCI_LIB_DIR/logging.sh"
# shellcheck source=lib/checksum.sh
. "$_OCI_LIB_DIR/checksum.sh"
# shellcheck source=lib/json.sh
. "$_OCI_LIB_DIR/json.sh"

_OCI__ORAS_MIN_VERSION="${_OCI__ORAS_MIN_VERSION:-1.2.0}"
_OCI__AUTH_LOADED=0
declare -gA _OCI__AUTH_USER=()
declare -gA _OCI__AUTH_TOKEN=()
declare -gA _OCI__AUTH_DONE=()

_oci__is_registry_host_like() {
  local _host="${1-}"
  [[ -n "$_host" ]] || return 1
  [[ "$_host" == "localhost" || "$_host" =~ ^localhost:[0-9]+$ ]] && return 0
  [[ "$_host" == *.* ]] && return 0
  [[ "$_host" =~ ^\[[0-9A-Fa-f:.]+\](:[0-9]+)?$ ]] && return 0
  return 1
}

_oci__registry_from_ref_or_repo() {
  local _v="${1-}"
  case "$_v" in
    http://*) _v="${_v#http://}" ;;
    https://*) _v="${_v#https://}" ;;
  esac
  [[ "$_v" == */* ]] || return 1
  printf '%s\n' "${_v%%/*}"
}

_oci__normalize_target() {
  local _in="${1-}" _plain=0
  case "$_in" in
    http://*)
      _in="${_in#http://}"
      _plain=1
      ;;
    https://*) _in="${_in#https://}" ;;
  esac
  printf '%s\t%s\n' "$_in" "$_plain"
}

_oci__load_auth_map() {
  [[ "$_OCI__AUTH_LOADED" -eq 1 ]] && return 0
  _OCI__AUTH_LOADED=1
  local _src="${SYSSET_OCI_AUTH-}" _entry _reg _usr _tok
  if [[ -z "$_src" && -n "${SYSSET_OCI_AUTH_FILE-}" && -f "${SYSSET_OCI_AUTH_FILE}" ]]; then
    _src="$(tr -d '\n' < "${SYSSET_OCI_AUTH_FILE}" 2> /dev/null || true)"
  fi
  [[ -n "$_src" ]] || return 0
  for _entry in ${_src//,/ }; do
    _reg="${_entry%%|*}"
    [[ "$_entry" == *"|"* ]] || continue
    _usr="${_entry#*|}"
    [[ "$_usr" == *"|"* ]] || continue
    _tok="${_usr#*|}"
    _usr="${_usr%%|*}"
    [[ -n "$_reg" && -n "$_usr" && -n "$_tok" ]] || continue
    _OCI__AUTH_USER["$_reg"]="$_usr"
    _OCI__AUTH_TOKEN["$_reg"]="$_tok"
  done
  return 0
}

_oci__ensure_auth_for() {
  local _target="${1-}" _reg _usr _tok _tmp
  _reg="$(_oci__registry_from_ref_or_repo "$_target" 2> /dev/null || true)"
  [[ -n "$_reg" ]] || return 0
  [[ -n "${_OCI__AUTH_DONE[$_reg]+x}" ]] && return 0
  _oci__load_auth_map
  _usr="${_OCI__AUTH_USER[$_reg]-}"
  _tok="${_OCI__AUTH_TOKEN[$_reg]-}"
  if [[ -z "$_usr" || -z "$_tok" ]]; then
    _OCI__AUTH_DONE["$_reg"]=1
    return 0
  fi
  _tmp="$(mktemp)"
  printf '%s' "$_tok" > "$_tmp"
  if oras login "$_reg" -u "$_usr" --password-stdin < "$_tmp" > /dev/null 2>&1; then
    _OCI__AUTH_DONE["$_reg"]=1
  else
    rm -f "$_tmp"
    logging__error "oci.sh: failed to authenticate to '${_reg}'."
    return 1
  fi
  rm -f "$_tmp"
  return 0
}

# @brief oci__ghcr_image_ref <namespace/path> <image-name> <tag> — Print ghcr.io/<namespace>/<image>:<tag>
#
# Example: oci__ghcr_image_ref quantized8/sysset install-pixi 1.0.0
#   → ghcr.io/quantized8/sysset/install-pixi:1.0.0
oci__ghcr_image_ref() {
  local _ns="${1-}" _name="${2-}" _tag="${3-}"
  printf 'ghcr.io/%s/%s:%s\n' "$_ns" "$_name" "$_tag"
}

_oci__version_ge() {
  local _a="${1#v}" _b="${2#v}"
  [[ "$_a" == "$_b" ]] && return 0
  [[ "$(printf '%s\n' "$_a" "$_b" | sort -V | tail -n1)" == "$_a" ]]
}

# @brief oci__ensure_oras — Ensure `oras` exists and meets minimum version.
oci__ensure_oras() {
  local _bin=""
  _bin="$(command -v oras 2> /dev/null || true)"
  if [[ -z "$_bin" ]]; then
    logging__info "oras not found — installing."
    _bin="$(install__oras \
      --context internal \
      --owner-group "lib-oci-oras" \
      --version "${SYSSET_ORAS_VERSION:-latest}" \
      --method auto \
      --if-exists skip 2> /dev/null || true)"
    [[ -n "$_bin" ]] || _bin="$(command -v oras 2> /dev/null || true)"
  fi
  if [[ -z "$_bin" ]]; then
    ospkg__install_tracked "lib-oci" oras >&2 || true
    _bin="$(command -v oras 2> /dev/null || true)"
  fi
  [[ -n "$_bin" ]] || {
    logging__error "oci.sh: oras could not be installed."
    return 1
  }

  local _ver
  _ver="$("$_bin" version 2> /dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n1)"
  [[ -z "$_ver" ]] && _ver="$("$_bin" version 2> /dev/null | head -n1 | sed 's/.*version[[:space:]]\+//I')"
  [[ -n "$_ver" ]] || {
    logging__warn "oci.sh: could not determine oras version; continuing."
    return 0
  }
  _oci__version_ge "$_ver" "$_OCI__ORAS_MIN_VERSION" || {
    logging__error "oci.sh: oras version ${_ver} is below required ${_OCI__ORAS_MIN_VERSION}."
    return 1
  }
  return 0
}

# @brief oci__is_feature_ref_key <key> — Return 0 for OCI-style feature refs.
oci__is_feature_ref_key() {
  local _k="${1-}" _host _rest
  [[ "$_k" == *"/"* ]] || return 1
  _host="${_k%%/*}"
  _rest="${_k#*/}"
  [[ -n "$_host" && -n "$_rest" ]] || return 1
  _oci__is_registry_host_like "$_host" || return 1
  [[ "$_k" == *@sha256:* || "$_k" == *:* ]] || return 1
  return 0
}

_oci__repo_from_ref() {
  local _ref="${1,,}"
  if [[ "$_ref" == *@sha256:* ]]; then
    printf '%s\n' "${_ref%@sha256:*}"
    return 0
  fi
  local _tail="${_ref##*/}"
  if [[ "$_tail" == *:* ]]; then
    printf '%s\n' "${_ref%:*}"
  else
    printf '%s\n' "$_ref"
  fi
}

_oci__tag_from_ref() {
  local _ref="${1-}" _tail
  [[ "$_ref" == *@sha256:* ]] && return 1
  _tail="${_ref##*/}"
  [[ "$_tail" == *:* ]] || return 1
  printf '%s\n' "${_tail#*:}"
}

# @brief oci__list_tags <repo> — Print one tag per line from `oras repo tags`.
oci__list_tags() {
  local _repo="${1-}"
  local _target _plain
  [[ -n "$_repo" ]] || return 1
  oci__ensure_oras || return 1
  _oci__ensure_auth_for "$_repo" || return 1
  IFS=$'\t' read -r _target _plain <<< "$(_oci__normalize_target "$_repo")"
  local _raw
  if [[ "$_plain" == "1" ]]; then
    _raw="$(oras repo tags --plain-http "$_target" 2> /dev/null)" || {
      logging__error "oci.sh: failed to list tags for ${_repo}."
      return 1
    }
  else
    _raw="$(oras repo tags "$_target" 2> /dev/null)" || {
      logging__error "oci.sh: failed to list tags for ${_repo}."
      return 1
    }
  fi
  if [[ -z "${_raw:-}" ]]; then
    logging__error "oci.sh: failed to list tags for ${_repo}."
    return 1
  fi
  printf '%s\n' "$_raw" | tr -d '\r' | sed '/^[[:space:]]*$/d'
}

_oci__semver_from_tag() {
  local _t="${1-}" _s="${1#v}"
  [[ "$_s" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || return 1
  printf '%s\n' "$_s"
}

_oci__semver_is_prerelease() {
  [[ "${1-}" == *-* ]]
}

_oci__highest_semver() {
  local _tags="${1-}" _allow_pre="${2-false}" _t _sv _list=""
  while IFS= read -r _t; do
    [[ -z "$_t" ]] && continue
    _sv="$(_oci__semver_from_tag "$_t" 2> /dev/null || true)"
    [[ -n "$_sv" ]] || continue
    if [[ "$_allow_pre" != true ]] && _oci__semver_is_prerelease "$_sv"; then
      continue
    fi
    _list="${_list}${_sv}"$'\n'
  done <<< "$_tags"
  [[ -n "$_list" ]] || return 1
  printf '%s' "$_list" | sed '/^$/d' | sort -V | tail -n1
}

# @brief oci__resolve_version <repo> [<spec>] — Resolve version spec from OCI tags.
oci__resolve_version() {
  local _repo="${1-}" _spec="${2-}"
  [[ -n "$_repo" ]] || return 1
  local _tags
  _tags="$(oci__list_tags "$_repo")" || return 1

  case "${_spec}" in
    "" | latest)
      if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "latest"; then
        printf 'latest\n'
        return 0
      fi
      _hi="$(_oci__highest_semver "$_tags" false 2> /dev/null || true)"
      [[ -n "$_hi" ]] || {
        logging__error "oci.sh: no matching tags for '${_repo}'."
        return 1
      }
      printf '%s\n' "$_hi"
      return 0
      ;;
  esac

  local _norm="${_spec#v}" _allow_pre=false
  [[ "$_norm" == *-* ]] && _allow_pre=true
  if [[ "$_norm" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "$_norm"; then
      printf '%s\n' "$_norm"
      return 0
    fi
    logging__error "oci.sh: no tag found for spec '${_spec}' in '${_repo}'."
    return 1
  fi

  if [[ ! "$_norm" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "$_spec"; then
      printf '%s\n' "$_spec"
      return 0
    fi
    if [[ "$_spec" == v* ]] && printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "${_spec#v}"; then
      printf '%s\n' "${_spec#v}"
      return 0
    fi
  fi

  local _cands="" _t _sv
  while IFS= read -r _t; do
    _sv="$(_oci__semver_from_tag "$_t" 2> /dev/null || true)"
    [[ -n "$_sv" ]] || continue
    if [[ "$_norm" =~ ^[0-9]+$ ]]; then
      [[ "$_sv" == "${_norm}."* ]] || continue
    elif [[ "$_norm" =~ ^[0-9]+\.[0-9]+$ ]]; then
      [[ "$_sv" == "${_norm}."* ]] || continue
    else
      continue
    fi
    if [[ "$_allow_pre" != true ]] && _oci__semver_is_prerelease "$_sv"; then
      continue
    fi
    _cands="${_cands}${_sv}"$'\n'
  done <<< "$_tags"
  [[ -n "$_cands" ]] || {
    logging__error "oci.sh: no tag found for spec '${_spec}' in '${_repo}'."
    return 1
  }
  printf '%s' "$_cands" | sed '/^$/d' | sort -V | tail -n1
}

_oci__validate_feature_tgz() {
  local _tgz="${1-}" _list
  [[ -f "$_tgz" ]] || return 1
  _list="$(tar -tzf "$_tgz" 2> /dev/null)" || return 1
  printf '%s\n' "$_list" | grep -Eq '(^|/)\.?/?install\.sh$' || return 1
  printf '%s\n' "$_list" | grep -Eq '(^|/)\.?/?devcontainer-feature\.json$' || return 1
}

_oci__expected_layer_digest_for_ref() {
  local _ref="${1-}" _manifest _dig _target _plain
  IFS=$'\t' read -r _target _plain <<< "$(_oci__normalize_target "$_ref")"
  if [[ "$_plain" == "1" ]]; then
    _manifest="$(oras manifest fetch --plain-http "$_target" 2> /dev/null || true)"
  else
    _manifest="$(oras manifest fetch "$_target" 2> /dev/null || true)"
  fi
  [[ -n "$_manifest" ]] || return 1
  _dig="$(printf '%s' "$_manifest" |
    json__query -r '
      [
        .layers[]?
        | select(.mediaType == "application/vnd.devcontainers.layer.v1+tar"
            or .mediaType == "application/vnd.devcontainers.layer.v1+tgz"
            or .mediaType == "application/vnd.oci.image.layer.v1.tar+gzip"
            or .mediaType == "application/vnd.oci.image.layer.v1.tar")
        | .digest
      ][0] // empty
    ' 2> /dev/null)" || _dig=""
  if [[ -z "$_dig" || "$_dig" == "null" ]]; then
    _dig="$(printf '%s\n' "$_manifest" | sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\(sha256:[0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)"
  fi
  [[ -n "$_dig" && "$_dig" != "null" ]] || return 1
  printf '%s\n' "$_dig"
}

# @brief oci__pull_feature_tgz <oci-ref> <dest-tgz> — Pull OCI feature artifact as tgz.
oci__pull_feature_tgz() {
  local _ref="${1-}" _dest="${2-}" _target _plain
  [[ -n "$_ref" && -n "$_dest" ]] || {
    logging__error "oci__pull_feature_tgz: requires <oci-ref> and <dest-tgz>."
    return 1
  }
  oci__ensure_oras || return 1
  _oci__ensure_auth_for "$_ref" || return 1
  IFS=$'\t' read -r _target _plain <<< "$(_oci__normalize_target "$_ref")"
  local _tmp
  _tmp="$(mktemp -d)"
  local _expect_digest=""
  _expect_digest="$(_oci__expected_layer_digest_for_ref "$_ref" 2> /dev/null || true)"
  if [[ "$_plain" == "1" ]]; then
    oras pull --plain-http "$_target" -o "$_tmp" > /dev/null 2>&1 || {
      rm -rf "$_tmp"
      logging__error "oci.sh: failed to pull '${_ref}'."
      return 1
    }
  elif ! oras pull "$_target" -o "$_tmp" > /dev/null 2>&1; then
    rm -rf "$_tmp"
    logging__error "oci.sh: failed to pull '${_ref}'."
    return 1
  fi
  local _tgz
  for _tgz in "$_tmp"/*.tgz; do
    [[ -f "$_tgz" ]] && break
  done
  [[ "${_tgz:-}" == "$_tmp/*.tgz" ]] && _tgz=""
  [[ -n "$_tgz" ]] || {
    rm -rf "$_tmp"
    logging__error "oci.sh: no .tgz layer materialized for '${_ref}'."
    return 1
  }
  if ! _oci__validate_feature_tgz "$_tgz"; then
    rm -rf "$_tmp"
    logging__error "oci.sh: invalid feature artifact shape for '${_ref}'."
    return 1
  fi
  if [[ -n "$_expect_digest" && "$_expect_digest" == sha256:* ]]; then
    local _got
    _got="sha256:$(checksum__sha256_file "$_tgz" 2> /dev/null || true)"
    if [[ "$_got" != "$_expect_digest" ]]; then
      rm -rf "$_tmp"
      logging__error "oci.sh: pulled layer digest mismatch for '${_ref}'."
      return 1
    fi
  fi
  cp "$_tgz" "$_dest" || {
    rm -rf "$_tmp"
    return 1
  }
  rm -rf "$_tmp"
  return 0
}
