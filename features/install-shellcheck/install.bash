# shellcheck shell=bash

__resolve_method() {
  logging__inspect "Resolving METHOD=auto."
  # Upstream does not publish a binary release for darwin/arm64 (Apple Silicon).
  if [[ "$(os__release_kernel)" == "darwin" && "$(os__arch)" == "arm64" ]]; then
    logging__info "Resolved METHOD=auto → 'package'."
    printf 'package\n'
  else
    logging__info "Resolved METHOD=auto → 'binary'."
    printf 'binary\n'
  fi
}
