#!/usr/bin/env bash

# Run a command with live tee to stdout and a timestamped log.
#
# Writes plain-text stdout/stderr to .local/reports/<recipe-name>/YYYY-MM-DD--HH-MM-SS.log
# (ANSI escapes stripped from the log; the terminal still receives color when interactive).
# Prints a PASS/FAIL result line to stderr (composite.sh captures stderr without showing it).
#
# Usage:
#   bash .dev/scripts/capture/single.sh <recipe-name> -- <command> [args...]

set -euo pipefail

usage() {
  echo "Usage: bash .dev/scripts/capture/single.sh <recipe-name> -- <command> [args...]" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
name=$1
shift
[[ "${1:-}" == "--" ]] || usage
shift
# just `+command` includes the caller's `--` separator as the first token
[[ "${1:-}" == "--" ]] && shift
[[ $# -gt 0 ]] || usage

timestamp=$(date +%Y-%m-%d--%H-%M-%S)
logdir=".local/reports/${name}"
logfile="${logdir}/${timestamp}.log"
mkdir -p "$logdir"

# Decide before piping to tee (stdout is not a TTY inside the pipeline).
interactive=false
[[ -t 1 || -t 2 ]] && interactive=true

use_pty=false
if [[ "$interactive" == true ]] && command -v script > /dev/null 2>&1; then
  use_pty=true
fi

# Interactive runs: pseudo-TTY plus FORCE_COLOR/PIXI_COLOR so piped tools still emit ANSI.
run_logged() {
  local -a run_env=()
  if [[ "$interactive" == true ]]; then
    run_env+=(
      FORCE_COLOR=1
      CLICOLOR_FORCE=1
      PIXI_COLOR=always
      TERM="${TERM:-xterm-256color}"
    )
  fi

  if [[ "$use_pty" == true ]]; then
    if script --version 2> /dev/null | grep -qi util-linux; then
      local qcmd
      printf -v qcmd '%q ' "$@"
      qcmd=${qcmd% }
      env "${run_env[@]}" script -qec "$qcmd" /dev/null
      return $?
    fi
    env "${run_env[@]}" script -q /dev/null "$@"
    return $?
  fi

  if [[ ${#run_env[@]} -gt 0 ]]; then
    env "${run_env[@]}" "$@"
  else
    "$@"
  fi
  return $?
}

# Strip CSI/OSC escape sequences for plain-text log files.
strip_ansi() {
  sed -E \
    -e 's/\x1b\[[0-9;?]*[[:alpha:]]//g' \
    -e 's/\x1b\][0-9;]*[^[:cntrl:]]*(\x07|\x1b\\)//g'
}

set +e
run_logged "$@" 2>&1 | tee >(strip_ansi > "$logfile")
_rc=${PIPESTATUS[0]}
set -e

if [[ $_rc -eq 0 ]]; then
  printf '\n✅ %s: PASS  (full output: '\''%s'\'')\n' "$name" "$logfile" >&2
else
  printf '\n❌ %s: FAIL  (full output: '\''%s'\'')\n' "$name" "$logfile" >&2
fi
exit "$_rc"
