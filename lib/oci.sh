#!/usr/bin/env bash
# oci.sh — Container registry reference helpers (bash ≥4).
# Do not edit _lib/ copies directly — edit lib/ instead.
[[ -n "${_OCI__LIB_LOADED-}" ]] && return 0
_OCI__LIB_LOADED=1

# @brief oci__ghcr_image_ref <namespace/path> <image-name> <tag> — Print ghcr.io/<namespace>/<image>:<tag>
#
# Example: oci__ghcr_image_ref quantized8/sysset install-pixi 1.0.0
#   → ghcr.io/quantized8/sysset/install-pixi:1.0.0
oci__ghcr_image_ref() {
  local _ns="${1-}" _name="${2-}" _tag="${3-}"
  printf 'ghcr.io/%s/%s:%s\n' "$_ns" "$_name" "$_tag"
}
