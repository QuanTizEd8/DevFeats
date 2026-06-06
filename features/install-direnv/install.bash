# shellcheck shell=bash
# Functions are defined before library sourcing.  Bash does not evaluate
# function bodies until they are called, so lib functions referenced here are
# resolved at call-time, not at definition-time.

# Binary releases cover linux and darwin for amd64 and arm64; fall back to package elsewhere.
# shellcheck disable=SC2329,SC2317
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

# The framework's make build system does not append PREFIX automatically (unlike
# autotools which gets --prefix= injected).  Override so make receives it explicitly.
# shellcheck disable=SC2329,SC2317
__install_run_source_build() {
  local _src_dir="$1"
  local _jobs
  _jobs="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || printf "1")"
  (
    cd "${_src_dir}" || exit 1
    make -j"${_jobs}" install PREFIX="${_RESOLVED_PREFIX}"
  )
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
