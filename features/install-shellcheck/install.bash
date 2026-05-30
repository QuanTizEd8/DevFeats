# shellcheck shell=bash

__resolve_method() {
  # Upstream does not publish a binary release for darwin/arm64 (Apple Silicon).
  if [[ "$(os__release_kernel)" == "darwin" && "$(os__arch)" == "arm64" ]]; then
    printf 'package\n'
  else
    printf 'binary\n'
  fi
}
