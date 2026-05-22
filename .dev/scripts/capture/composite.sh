#!/usr/bin/env bash

# Run multiple commands with per-step reports and a composite summary.
#
# Each step uses capture/single.sh (live tee + .local/reports/<step>/<timestamp>.log).
# Parses the result line from each step's stderr (not shown on the terminal).
#
# Usage:
#   bash .dev/scripts/capture/composite.sh <composite-name> -- \
#     <step-name> -- <command> [args...] \
#     [<step-name> -- <command> [args...]] ...

set -euo pipefail

usage() {
  echo "Usage: bash .dev/scripts/capture/composite.sh <composite-name> -- \\" >&2
  echo "  <step-name> -- <command> [args...] ..." >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
composite=$1
shift
[[ "${1:-}" == "--" ]] || usage
shift

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
single_sh="${script_dir}/single.sh"

timestamp=$(date +%Y-%m-%d--%H-%M-%S)
summary_dir=".local/reports/${composite}"
summary_file="${summary_dir}/${timestamp}.summary.md"
mkdir -p "$summary_dir"

time_tail="${timestamp#*--}"
time_tail="${time_tail//-/:}"
summary_time="${timestamp%%--*} ${time_tail}"

overall_rc=0
result_lines=()
summary_body=""

format_step_line() {
  local step=$1 status=$2 logfile=$3
  local icon
  if [[ "$status" == PASS ]]; then
    icon=✅
  else
    icon=❌
  fi
  printf '%s %s: %s  (full output: '\''%s'\'')' "$icon" "$step" "$status" "$logfile"
}

append_summary_section() {
  local step=$1 status=$2 logfile=$3
  local tail_block
  summary_body+=$'\n'"## ${step}"$'\n'
  local status_label
  if [[ "$status" == PASS ]]; then
    status_label=Pass
  else
    status_label=Fail
  fi
  summary_body+="- Status: ${status_label}"$'\n'
  summary_body+="- Report: \`${logfile}\`"$'\n'
  summary_body+="- Last 10 lines:"$'\n'
  summary_body+='```'$'\n'
  if [[ -f "$logfile" ]]; then
    tail_block=$(tail -n 10 "$logfile")
    if [[ -n "$tail_block" ]]; then
      summary_body+="${tail_block}"$'\n'
    fi
  else
    summary_body+="(log file unavailable)"$'\n'
  fi
  summary_body+='```'$'\n'
}

run_step() {
  local step=$1
  shift
  local stderr_cap
  stderr_cap=$(mktemp)
  local step_rc=0

  set +e
  bash "$single_sh" "$step" -- "$@" 2>"$stderr_cap"
  step_rc=$?
  set -e

  local logfile
  logfile=$(sed -n "s/.*full output: '\\([^']*\\)'.*/\1/p" "$stderr_cap" | tail -n 1)
  rm -f "$stderr_cap"

  local status
  if [[ $step_rc -eq 0 ]]; then
    status=PASS
  else
    status=FAIL
    overall_rc=1
  fi

  if [[ -z "$logfile" ]]; then
    logfile="(report path not found)"
  fi

  local line
  line=$(format_step_line "$step" "$status" "$logfile")
  result_lines+=("$line")
  printf '\n%s\n' "$line" >&2
  append_summary_section "$step" "$status" "$logfile"
}

while [[ $# -gt 0 ]]; do
  step=$1
  shift
  [[ "${1:-}" == "--" ]] || usage
  shift
  [[ $# -gt 0 ]] || usage

  cmd=()
  while [[ $# -gt 0 ]]; do
    if [[ $# -ge 2 && "$2" == "--" ]]; then
      break
    fi
    cmd+=("$1")
    shift
  done
  [[ ${#cmd[@]} -gt 0 ]] || usage

  run_step "$step" "${cmd[@]}"
done

overall_status=Pass
[[ $overall_rc -ne 0 ]] && overall_status=Fail

{
  printf '%s\n' '# Task Summary'
  printf '%s\n' "- Task: \`${composite}\`"
  printf '%s\n' "- Time: ${summary_time}"
  printf '%s\n' "- Status: ${overall_status}"
  printf '%s' "$summary_body"
} >"$summary_file"

printf '\n--- Results ---\n' >&2
for line in "${result_lines[@]}"; do
  printf '%s\n' "$line" >&2
done
printf '\nSummary saved at '\''%s'\''\n' "$summary_file" >&2
exit "$overall_rc"
