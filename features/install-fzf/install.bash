# shellcheck shell=bash
# Functions are defined before library sourcing. Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

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
