# shellcheck shell=bash

__resolve_method() {
  logging__inspect "Resolving METHOD=auto."
  case "$(os__release_kernel):$(os__release_arch)" in
    linux:amd64 | linux:arm64 | darwin:amd64 | darwin:arm64)
      logging__info "Resolved METHOD=auto → 'binary'."
      printf 'binary\n'
      ;;
    *)
      logging__info "Resolved METHOD=auto → 'package'."
      printf 'package\n'
      ;;
  esac
}
