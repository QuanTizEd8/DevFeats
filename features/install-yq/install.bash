# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# Binary releases cover amd64 and arm64; other arches fall back to package manager.
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  case "$(os__release_arch)" in
    amd64 | arm64) printf 'binary\n' ;;
    *) printf 'package\n' ;;
  esac
}

# yq uses a custom checksum extraction script rather than a standard sidecar.
# Downloads the checksums bundle and runs extract-checksum.sh to get the SHA-256,
# then sets BINARY_SHA256 so __install_run_binary__ uses it instead of auto-probing.
# shellcheck disable=SC2329,SC2317
__install_run_binary_pre() {
  local _os _arch _base _hdir _f
  _os="$(os__release_kernel)" || return 1
  _arch="$(os__release_arch)" || return 1
  _base="$(os__expand_release_pattern "${BINARY_ASSET_URI%/*}" "${VERSION}" "${_FEAT_RESOLVED_TAG:-}")" || return 1
  _hdir="$(file__mktmpdir "install/yq-checksums")"
  for _f in checksums checksums_hashes_order extract-checksum.sh; do
    net__fetch_url_file "${_base}/${_f}" "${_hdir}/${_f}" || return 1
  done
  BINARY_SHA256="$(cd "${_hdir}" && bash extract-checksum.sh SHA-256 "yq_${_os}_${_arch}" | awk '{print $2}')"
  if [[ ! "${BINARY_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then
    logging__error "yq: invalid SHA-256 for yq_${_os}_${_arch}."
    return 1
  fi
}

# After package install, verify the distro package is mikefarah/yq (supports -o=json),
# not the unrelated Python jq-wrapper that some distros also name "yq".
# shellcheck disable=SC2329,SC2317
__install_run_package_post() {
  local _bin
  _bin="$(command -v yq 2> /dev/null || true)"
  if ! _bootstrap__yq_compatible "${_bin:-}"; then
    logging__error "yq: method=package did not yield a mikefarah/yq-compatible binary (missing -o=json support). Use method=binary or specify a different package repository."
    return 1
  fi
}
