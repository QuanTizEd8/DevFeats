# shellcheck shell=bash

__resolve_method() {
  case "$(os__release_kernel):$(os__release_arch)" in
    linux:amd64 | linux:arm64 | darwin:amd64 | darwin:arm64)
      printf 'binary\n'
      ;;
    *)
      printf 'package\n'
      ;;
  esac
}
