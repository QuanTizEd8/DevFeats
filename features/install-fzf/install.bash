# shellcheck shell=bash
# Functions are defined before library sourcing. Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# fzf publishes binaries for amd64, arm64, armv5/6/7, ppc64le, riscv64, s390x,
# and loong64; fall back to the package manager for other architectures.
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  logging__inspect "Resolving METHOD=auto for fzf."
  case "$(os__release_arch)" in
    amd64 | arm64 | armv7 | armv6 | armv5 | ppc64le | riscv64 | s390x | loong64)
      logging__info "Resolved METHOD=auto → 'binary'."
      printf 'binary\n'
      ;;
    *)
      logging__info "Resolved METHOD=auto → 'package'."
      printf 'package\n'
      ;;
  esac
}

# fzf shell integration uses interactive-only constructs (eval, process
# substitution) and must not be sourced in non-interactive or login-only
# contexts. Return 1 to request rc-only mode (writes to .bashrc / .zshrc
# only, not to /etc/profile.d or .zshenv).
# shellcheck disable=SC2329,SC2317
__prefix_activation_snippet() {
  local _shell="$1"
  local _bin="${_RESOLVED_PREFIX}/bin/fzf"
  case "$_shell" in
    bash)
      printf "eval \"\$(\"%s\" --bash)\"\n" "$_bin"
      ;;
    zsh)
      printf 'source <("%s" --zsh)\n' "$_bin"
      ;;
    fish)
      printf '"%s" --fish | source\n' "$_bin"
      ;;
    *)
      return 1
      ;;
  esac
  return 1
}
