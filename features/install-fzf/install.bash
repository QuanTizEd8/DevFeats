# shellcheck shell=bash
# Functions are defined before library sourcing. Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# fzf publishes binaries for amd64, arm64, armv5/6/7, ppc64le, riscv64, s390x,
# and loong64; fall back to the package manager for other architectures.
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  case "$(os__release_arch)" in
    amd64 | arm64 | armv7 | armv6 | armv5 | ppc64le | riscv64 | s390x | loong64)
      printf 'binary\n'
      ;;
    *)
      printf 'package\n'
      ;;
  esac
}

# fzf shell integration uses interactive-only constructs (eval, process
# substitution) and must not be sourced in non-interactive or login-only
# contexts.  Return 1 to request rc-only mode from
# shell__write_activation_snippets (writes to .bashrc / .zshrc only, not
# to /etc/profile.d or .zshenv).
# shellcheck disable=SC2329,SC2317
__prefix_activation_snippet() {
  local _shell="$1"
  case "$_shell" in
    bash)
      # shellcheck disable=SC2016
      printf 'command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"\n'
      ;;
    zsh)
      # shellcheck disable=SC2016
      printf 'command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)\n'
      ;;
    *)
      return 1
      ;;
  esac
  return 1
}
