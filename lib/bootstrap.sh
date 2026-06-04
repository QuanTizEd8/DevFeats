# shellcheck shell=bash
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# Bootstrap installer functions for tools that lib modules depend on at runtime.
# These call install__release_asset directly to avoid circular dependencies:
# if the feature scripts were used instead, their base-dependency install would
# call back into the same lib (e.g. ospkg → yq → ospkg).

# @brief _bootstrap__yq_compatible <bin> — Return 0 when <bin> is mikefarah/yq (supports -o=json).
_bootstrap__yq_compatible() {
  local _bin="${1-}"
  [[ -n "$_bin" ]] || return 1
  "$_bin" -o=json '.' /dev/null > /dev/null 2>&1
}

# @brief bootstrap__yq [<version-spec>] — Ensure mikefarah/yq is available and print its path.
#
# Returns the path of an already-installed compatible yq when one exists (fast
# path).  Otherwise downloads the release binary, verifies via yq's custom
# checksum script, and caches the result via install__state_record so repeated
# calls within the same process lifetime are cheap.
#
# Args:
#   [version-spec]  Version spec accepted by github__resolve_version (e.g.
#                   "stable", "latest", "4.44.3"). Defaults to "stable".
#
# Stdout: absolute path to a mikefarah/yq-compatible binary.
# Returns: 0 on success, 1 on any failure.
bootstrap__yq() {
  local _spec="${1:-stable}"

  # Fast path 1: compatible yq already on PATH.
  local _existing
  _existing="$(command -v yq 2> /dev/null || true)"
  if [[ -n "${_existing}" ]] && _bootstrap__yq_compatible "${_existing}"; then
    printf '%s\n' "${_existing}"
    return 0
  fi

  # Fast path 2: previously bootstrapped binary still alive.
  local _state_ctx _state_path _state_group
  install__read_state "yq" _state_ctx _state_path _state_group
  if [[ -x "${_state_path:-}" ]] && _bootstrap__yq_compatible "${_state_path}"; then
    printf '%s\n' "${_state_path}"
    return 0
  fi

  # Resolve version.
  local _resolved_ver
  _resolved_ver="$(github__resolve_version "mikefarah/yq" "${_spec}" --version)" || return 1

  local _os _arch
  _os="$(os__release_kernel)" || return 1
  _arch="$(os__release_arch)" || return 1
  case "${_arch}" in
    amd64 | arm64) ;;
    *)
      logging__error "bootstrap__yq: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac

  local _base="https://github.com/mikefarah/yq/releases/download/v${_resolved_ver}"

  # Compute SHA-256 via yq's custom checksum extraction script.
  local _hdir _f _expected_hash
  _hdir="$(file__mktmpdir "bootstrap/yq-checksums")"
  for _f in checksums checksums_hashes_order extract-checksum.sh; do
    net__fetch_url_file "${_base}/${_f}" "${_hdir}/${_f}" || return 1
  done
  _expected_hash="$(cd "${_hdir}" && shell__bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  if [[ ! "${_expected_hash:-}" =~ ^[0-9a-f]{64}$ ]]; then
    logging__error "bootstrap__yq: invalid SHA-256 for yq_${_os}_${_arch}."
    return 1
  fi

  local _install_dir
  _install_dir="$(file__tmpdir "bootstrap/yq")"
  install__release_asset \
    --asset-uri "${_base}/yq_${_os}_${_arch}" \
    --sha256 "${_expected_hash}" \
    --binary-dest "${_install_dir}/yq" || return 1

  install__state_record "yq" "internal" "binary" "${_install_dir}/yq" "devfeats-bootstrap-yq" || true
}

# @brief bootstrap__oras [<version-spec>] — Ensure oras is available and print its path.
#
# Returns an already-installed oras path when one exists on PATH.  Otherwise
# downloads the release archive, verifies GPG signature, installs the binary to
# a process-lifetime temp directory, and caches the result.
#
# Args:
#   [version-spec]  Version spec accepted by github__resolve_version (e.g.
#                   "stable", "latest", "1.2.3"). Defaults to "stable".
#
# Stdout: absolute path to the oras binary.
# Returns: 0 on success, 1 on any failure.
bootstrap__oras() {
  local _spec="${1:-stable}"

  # Fast path 1: oras already on PATH.
  local _existing
  _existing="$(command -v oras 2> /dev/null || true)"
  if [[ -n "${_existing}" ]]; then
    printf '%s\n' "${_existing}"
    return 0
  fi

  # Fast path 2: previously bootstrapped binary still alive.
  local _state_ctx _state_path _state_group
  install__read_state "oras" _state_ctx _state_path _state_group
  if [[ -x "${_state_path:-}" ]]; then
    printf '%s\n' "${_state_path}"
    return 0
  fi

  # Resolve version.
  local _resolved_ver
  _resolved_ver="$(github__resolve_version "oras-project/oras" "${_spec}" --version)" || return 1

  local _os _arch
  _os="$(os__release_kernel)" || return 1
  _arch="$(os__release_arch)" || return 1
  case "${_arch}" in
    amd64 | arm64 | armv7 | ppc64le | s390x | riscv64 | loong64) ;;
    *)
      logging__error "bootstrap__oras: unsupported architecture '${_arch}'."
      return 1
      ;;
  esac

  local _tag="v${_resolved_ver}"
  local _asset="oras_${_resolved_ver}_${_os}_${_arch}.tar.gz"
  local _install_dir
  _install_dir="$(file__tmpdir "bootstrap/oras")"
  install__release_asset \
    --asset-uri "https://github.com/oras-project/oras/releases/download/${_tag}/${_asset}" \
    --binary-src oras \
    --binary-dest "${_install_dir}/" \
    --gpg-key "https://raw.githubusercontent.com/oras-project/oras/refs/heads/main/KEYS" || return 1

  install__state_record "oras" "internal" "binary" "${_install_dir}/oras" "devfeats-bootstrap-oras" || true
}

# @brief bootstrap__git — Ensure git is available via the OS package manager.
# Returns: 0 on success, 1 on failure.
bootstrap__git() {
  ospkg__install_tracked "lib-git" git || {
    logging__error "bootstrap__git: git could not be installed."
    return 1
  }
}
