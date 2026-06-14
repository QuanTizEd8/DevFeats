# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# The framework's make build system does not append PREFIX automatically (unlike
# autotools which gets --prefix= injected).  Override so make receives it explicitly.
# shellcheck disable=SC2329,SC2317
__install_run_source_build() {
  logging__build "Building direnv from source in '$1'."
  local _src_dir="$1"
  local _jobs
  _jobs="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || printf "1")"
  (
    cd "${_src_dir}" || {
      logging__error "direnv source build: cannot cd to '${_src_dir}'."
      exit 1
    }
    make -j"${_jobs}" install PREFIX="${_RESOLVED_PREFIX}"
  ) || {
    logging__error "direnv source build failed in '${_src_dir}'."
    return 1
  }
  logging__success "direnv built and installed to '${_RESOLVED_PREFIX}'."
}

# Interactive-only activation hook: eval "$(direnv hook <shell>)" (or shell-equivalent).
# Uses the fully resolved binary path (PREFIX/bin/direnv) so the snippet works regardless
# of whether the prefix bin dir is on PATH at shell startup time.
# Returns 1 → interactive-only; framework writes to rc files (not login files).
# shellcheck disable=SC2329,SC2317
__prefix_activation_snippet() {
  local _shell="$1"
  local _bin="${_RESOLVED_PREFIX}/bin/direnv"
  case "$_shell" in
    bash | zsh)
      printf "eval \"\$(%s hook %s)\"\n" "$_bin" "$_shell"
      ;;
    fish)
      printf '"%s" hook fish | source\n' "$_bin"
      ;;
    tcsh)
      printf "eval \`\"%s\" hook tcsh\`\n" "$_bin"
      ;;
    elvish)
      # Output the full hook inline; lib/shell.sh writes it directly to rc.elv.
      "${_bin}" hook elvish
      ;;
    nushell)
      # nushell config is a structured record; manual setup is required (see tool-ref.md).
      return 1
      ;;
  esac
  return 1
}
