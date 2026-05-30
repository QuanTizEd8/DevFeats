# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# jq releases binaries for amd64, arm64, i386; fall back to package elsewhere.
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  case "$(os__release_arch)" in
    amd64 | arm64 | i386) printf 'binary\n' ;;
    *) printf 'package\n' ;;
  esac
}
