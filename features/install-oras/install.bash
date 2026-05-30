# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# Binary releases cover all common arches; fall back to package on unknown arches.
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  case "$(os__release_arch)" in
    amd64 | arm64 | armv7 | ppc64le | s390x | riscv64 | loong64) printf 'binary\n' ;;
    *) printf 'package\n' ;;
  esac
}
