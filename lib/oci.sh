#!/usr/bin/env bash
# oci.sh — Container registry reference helpers (bash ≥4).
# Do not edit _lib/ copies directly — edit lib/ instead.
[[ -n "${_OCI__LIB_LOADED-}" ]] && return 0
_OCI__LIB_LOADED=1

_OCI__ORAS_MIN_VERSION="${_OCI__ORAS_MIN_VERSION:-1.2.0}"

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
  if [[ "$_host" != "localhost" && "$_host" != *.* ]]; then
    return 1
  fi
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
  [[ -n "$_repo" ]] || return 1
  oci__ensure_oras || return 1
  local _raw
  if ! _raw="$(oras repo tags "$_repo" 2> /dev/null)"; then
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

  if printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "$_spec"; then
    printf '%s\n' "$_spec"
    return 0
  fi
  if [[ "$_spec" == v* ]] && printf '%s\n' "$_tags" | sed '/^$/d' | grep -qx "${_spec#v}"; then
    printf '%s\n' "${_spec#v}"
    return 0
  fi

  local _norm="${_spec#v}" _allow_pre=false
  [[ "$_norm" == *-* ]] && _allow_pre=true
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

# @brief oci__pull_feature_tgz <oci-ref> <dest-tgz> — Pull OCI feature artifact as tgz.
oci__pull_feature_tgz() {
  local _ref="${1-}" _dest="${2-}"
  [[ -n "$_ref" && -n "$_dest" ]] || {
    logging__error "oci__pull_feature_tgz: requires <oci-ref> and <dest-tgz>."
    return 1
  }
  oci__ensure_oras || return 1
  local _tmp
  _tmp="$(mktemp -d)"
  if ! oras pull "$_ref" -o "$_tmp" > /dev/null 2>&1; then
    rm -rf "$_tmp"
    logging__error "oci.sh: failed to pull '${_ref}'."
    return 1
  fi
  local _tgz
  _tgz="$(ls "$_tmp"/*.tgz 2> /dev/null | head -n1 || true)"
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
  cp "$_tgz" "$_dest" || {
    rm -rf "$_tmp"
    return 1
  }
  rm -rf "$_tmp"
  return 0
}
