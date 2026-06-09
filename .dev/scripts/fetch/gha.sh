#!/usr/bin/env bash
# gha.sh — Monitor GHA workflow runs and collect job logs.
#
# Preferred entry point: just fetch-gha [args]
#
# Usage:
#   bash .dev/scripts/fetch/gha.sh [--log-base <dir>] --commit <commit-sha>
#   bash .dev/scripts/fetch/gha.sh [--log-base <dir>] --run <workflow-run-id>
#   bash .dev/scripts/fetch/gha.sh [--log-base <dir>] <commit-sha>   # same as --commit
#   bash .dev/scripts/fetch/gha.sh --help
#
#   --commit, <commit-sha>  Full or short commit SHA. Short SHAs are
#                 expanded via git rev-parse (fetching from origin if needed).
#                 Monitors all workflow runs for that commit.
#   --run         Monitor a single workflow run by its numeric run id.
#
# Polls every 10 seconds until the relevant run(s) have completed. Progress
# and job status are printed to stderr.
#
# For each completed job:
#   Passing/skipped → job name appended to passing.log
#   Any other conclusion → full job log saved to <job-id>.log (GHA
#       timestamps stripped). For each failing step, a slice of that log
#       (from the workflow-step ##[group]Run header through ##[error]) is
#       saved to <job-id>-step<N>.log when extraction succeeds; failing.log
#       references the slice file, otherwise the full job log:
#           <job-name> --- <step-name> --- <log-filename>
#       When the job name matches a feature-test matrix job (reusable workflow:
#       "Test Feature <feature-id> / <scenario> (devcontainer|linux|macOS)",
#       or legacy "<scenario> (mode)"), downloads the matching feat-log-*
#       workflow artifact (trace-level install log) to <job-id>.trace.log
#       beside the GHA log.
#
# All log files are written to:
#   <log-base defaults to repo>/.local/logs/gha/<full-sha>/<run-id>/
# Use --log-base to set the directory that replaces the default
#   <repo-root>/.local/logs/gha
#
# On completion, one path per workflow run is printed to stdout (commit mode
# can print several lines). Exits 0 if all jobs passed/skipped, 1 if any job
# failed.

set -euo pipefail
export GH_PAGER=cat

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=.dev/scripts/git_helpers.sh
. "${_SCRIPT_DIR}/../git_helpers.sh"

_usage() {
  cat << 'EOF'
gha.sh — Monitor GHA workflow runs and collect job logs.

Usage:
  just fetch-gha [options] --commit <commit-sha>
  just fetch-gha [options] --run <workflow-run-id>
  just fetch-gha [options] <commit-sha>   # same as --commit
  bash .dev/scripts/fetch/gha.sh …         # same flags (direct invocation)

  --commit       Monitor all runs for a commit
  --run          Monitor a single run; commit is taken from the run metadata
  --log-base DIR Directory to use instead of the default
                 <repo-root>/.local/logs/gha  (see below; relative → under repo)
  -h, --help

  Log layout (both modes):
    <log-base>/<full-40-char-sha>/<workflow-run-id>/
      passing.log, failing.log, per-job <job-id>.log (full GHA job log),
      per failing step <job-id>-step<N>.log when slice extraction succeeds,
      and for failed feature-test jobs <job-id>.trace.log (feat-log artifact)

  On success, prints one line per run directory (sorted).

Exits 0 if all jobs passed/skipped, 1 if any job failed.
EOF
  exit "${1:-0}"
}

_GHA_MODE=
COMMIT_SHA=
RUN_ID=
GHA_LOG_BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      _usage 0
      ;;
    --log-base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --log-base requires a path." >&2
        exit 2
      fi
      GHA_LOG_BASE="$2"
      shift 2
      ;;
    --commit)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --commit requires a SHA." >&2
        exit 2
      fi
      if [[ -n "${_GHA_MODE}" && "${_GHA_MODE}" != "commit" ]]; then
        echo "Error: use only one of --commit or --run." >&2
        exit 2
      fi
      _GHA_MODE=commit
      COMMIT_SHA="$2"
      shift 2
      ;;
    --run)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --run requires a workflow run id." >&2
        exit 2
      fi
      if [[ -n "${_GHA_MODE}" && "${_GHA_MODE}" != "run" ]]; then
        echo "Error: use only one of --commit or --run." >&2
        exit 2
      fi
      _GHA_MODE=run
      RUN_ID="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      _usage 2
      ;;
    *)
      if [[ -n "${_GHA_MODE}" ]]; then
        echo "Error: unexpected argument: $1" >&2
        exit 2
      fi
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Error: ambiguous bare numeric argument: $1" >&2
        echo "Hint: use --run <workflow-run-id> (or --commit <sha>)." >&2
        exit 2
      fi
      _GHA_MODE=commit
      COMMIT_SHA="$1"
      shift
      break
      ;;
  esac
done

if [[ -n "$*" ]]; then
  echo "Error: too many arguments." >&2
  exit 2
fi

if [[ -z "${_GHA_MODE}" ]]; then
  echo "Error: specify --commit <sha>, --run <id>, or a single commit SHA." >&2
  echo "See --help." >&2
  exit 2
fi

if [[ "${_GHA_MODE}" == "run" ]]; then
  if [[ ! "${RUN_ID}" =~ ^[0-9]+$ ]]; then
    echo "Error: --run must be a numeric workflow run id, got: ${RUN_ID}" >&2
    exit 2
  fi
fi

REPO_ROOT="$(git__require_repo_root)"

# Default: <repo>/.local/logs/gha  — override with --log-base
if [[ -z "${GHA_LOG_BASE}" ]]; then
  GHA_LOG_BASE="${REPO_ROOT}/.local/logs/gha"
elif [[ "${GHA_LOG_BASE}" != /* ]]; then
  GHA_LOG_BASE="${REPO_ROOT}/${GHA_LOG_BASE#./}"
fi
GHA_LOG_BASE="${GHA_LOG_BASE%/}"

# Detect GitHub slug + owner/name from git remote
REPO_SLUG="$(git__require_origin_slug)"
REPO_OWNER="$(git__require_origin_owner)"
REPO_NAME="$(git__require_origin_name)"

# commit SHA for API queries and for paths; run mode sets path SHA from the API
LOG_COMMIT_SHA=

_normalize_commit_sha() {
  local c="$1"
  if [[ ! "${c}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    git fetch --quiet origin 2> /dev/null || true
    # Use --verify so invalid refs do not emit partial stdout that could
    # pollute fallback values with embedded newlines.
    c="$(git rev-parse --verify "${c}^{commit}" 2> /dev/null || true)"
    if [[ -z "${c}" ]]; then
      c="$1"
    fi
  fi
  printf '%s' "${c}"
}

if [[ "${_GHA_MODE}" == "commit" ]]; then
  LOG_COMMIT_SHA="$(_normalize_commit_sha "${COMMIT_SHA}")"
  if [[ ! "${LOG_COMMIT_SHA}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "Error: --commit must resolve to a commit SHA, got: ${COMMIT_SHA}" >&2
    echo "Hint: use --run <workflow-run-id> for numeric run IDs." >&2
    exit 2
  fi
  COMMIT_SHA="${LOG_COMMIT_SHA}"
else
  # Resolved from GET /actions/runs/{id} on first successful poll
  :
fi

# Populated the first time we touch a run's log directory (for stdout)
GHA_LOGDIRS=()
declare -A _logdir_inited
LOGDIR=
PASSING_LOG=
FAILING_LOG=

declare -A _processed           # job_id → 1 (tracks already-handled jobs)
declare -A _run_artifacts_cache # run_id → JSON from .../runs/{id}/artifacts
_stat_pass=0
_stat_fail=0
_any_failure=0
_poll_interval=10
# Large matrix runs (400+ jobs) exceed GitHub's response-size limit at per_page=100
# and return persistent HTTP 502. 50 is safe for runs with heavy per-job payloads.
_GHA_JOBS_PER_PAGE=50

# ---------------------------------------------------------------------------
# _ts — print a [HH:MM:SS] prefixed message to stdout
# ---------------------------------------------------------------------------
_ts() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# ---------------------------------------------------------------------------
# _gh_err_summary <text> — one line for logs; hide HTML 5xx bodies from gh.
# ---------------------------------------------------------------------------
_gh_err_summary() {
  local t="${1//$'\r'/ }"
  t="${t//$'\n'/ }"
  while [[ "${t}" == *"  "* ]]; do t="${t//  / }"; done
  if [[ "${t}" == *'<'* ]]; then
    printf '%s' 'upstream HTML (5xx gateway or GitHub error page); stderr suppressed'
    return 0
  fi
  [[ ${#t} -gt 160 ]] && t="${t:0:160}…"
  printf '%s' "${t}"
}

# True when a retry may help (empty body, server/rate errors, HTML blob).
# ---------------------------------------------------------------------------
_gh_should_retry() {
  local _ec="$1" _body="$2"
  [[ "${_ec}" -ne 0 && -z "${_body}" ]] && return 0
  [[ "${_body}" == *'<'* ]] && return 0
  jq -e '
    (.message? // "")
    | test("Server Error|API rate limit exceeded|Bad Gateway|timed out|timeout"; "i")
  ' > /dev/null 2>&1 <<< "${_body}" && return 0
  return 1
}

# ---------------------------------------------------------------------------
# _gh_api_json <path>  — GET JSON from the GitHub API via gh. Retries transient
# 5xx / rate limits with backoff. Suppresses gh stderr during attempts so HTML
# error pages are not dumped to the terminal. On failure, logs once and returns 1.
# ---------------------------------------------------------------------------
_gh_api_json() {
  local _path="$1"
  local _attempt=1 _max=8 _delay=2 _out _ec _both

  while [[ ${_attempt} -le ${_max} ]]; do
    _ec=0
    _out=$(gh api "${_path}" 2> /dev/null) || _ec=$?

    if [[ ${_ec} -eq 0 ]]; then
      if _gh_should_retry 0 "${_out}"; then
        sleep "${_delay}"
        [[ ${_delay} -lt 25 ]] && _delay=$((_delay * 2)) || _delay=25
        _attempt=$((_attempt + 1))
        continue
      fi
      printf '%s' "${_out}"
      return 0
    fi

    if _gh_should_retry "${_ec}" "${_out}"; then
      sleep "${_delay}"
      [[ ${_delay} -lt 25 ]] && _delay=$((_delay * 2)) || _delay=25
      _attempt=$((_attempt + 1))
      continue
    fi

    _both=$(gh api "${_path}" 2>&1) || true
    _ts "gh api failed: $(_gh_err_summary "${_both}")"
    return 1
  done

  _both=$(gh api "${_path}" 2>&1) || true
  _ts "gh api failed after ${_max} retries: $(_gh_err_summary "${_both}")"
  return 1
}

# ---------------------------------------------------------------------------
# _activate_run_logdir <path_sha> <run_id>
# Sets LOGDIR, PASSING_LOG, FAILING_LOG. Creates
#   <GHA_LOG_BASE>/<path_sha>/<run_id>/ once and records it for final stdout.
# ---------------------------------------------------------------------------
_activate_run_logdir() {
  local path_sha="$1"
  local run_id="$2"
  LOGDIR="${GHA_LOG_BASE}/${path_sha}/${run_id}"
  mkdir -p "${LOGDIR}"
  if [[ -z "${_logdir_inited[${LOGDIR}]+_}" ]]; then
    : > "${LOGDIR}/passing.log"
    : > "${LOGDIR}/failing.log"
    _logdir_inited["${LOGDIR}"]=1
    GHA_LOGDIRS+=("${LOGDIR}")
  fi
  PASSING_LOG="${LOGDIR}/passing.log"
  FAILING_LOG="${LOGDIR}/failing.log"
}

# ---------------------------------------------------------------------------
# _download_log <job_id>
# Downloads the full log for a job to ${LOGDIR}/<job_id>.log (stripping
# timestamps). Prints the saved filename (basename only).
# ---------------------------------------------------------------------------
_download_log() {
  local job_id="$1"
  local dest="${LOGDIR}/${job_id}.log"
  local _attempt=1 _max=8 _delay=2 _gh_ec

  # gh writes HTML 5xx bodies to stderr; keep stderr off the terminal (same
  # as _gh_api_json). Retry transient failures; PIPESTATUS tracks gh, not awk.
  while [[ ${_attempt} -le ${_max} ]]; do
    gh api "/repos/${REPO_OWNER}/${REPO_NAME}/actions/jobs/${job_id}/logs" 2> /dev/null |
      awk '{ sub(/^[0-9T:.Z-]+[[:space:]]*/,""); print }' > "${dest}"
    _gh_ec=${PIPESTATUS[0]}
    if [[ ${_gh_ec} -eq 0 ]] && [[ -s "${dest}" ]]; then
      basename "${dest}"
      return 0
    fi
    : > "${dest}"
    sleep "${_delay}"
    [[ ${_delay} -lt 25 ]] && _delay=$((_delay * 2)) || _delay=25
    _attempt=$((_attempt + 1))
  done

  basename "${dest}"
}

# ---------------------------------------------------------------------------
# _run_artifacts_json <run_id> — cached GET .../actions/runs/{id}/artifacts
# (paginated; merged into one {"artifacts":[...]} object)
# ---------------------------------------------------------------------------
_run_artifacts_json() {
  local run_id="$1"
  if [[ -n "${_run_artifacts_cache[${run_id}]+_}" ]]; then
    printf '%s' "${_run_artifacts_cache[${run_id}]}"
    return 0
  fi

  local page=1 artifacts_json='{"artifacts":[]}' page_json n total
  while true; do
    page_json=$(_gh_api_json \
      "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_id}/artifacts?per_page=100&page=${page}") ||
      page_json='{"artifacts":[],"total_count":0}'
    n=$(jq '.artifacts | length' <<< "${page_json}")
    total=$(jq '.total_count' <<< "${page_json}")
    artifacts_json=$(jq --argjson page "${page_json}" '
      {artifacts: (.artifacts + $page.artifacts)}
    ' <<< "${artifacts_json}")
    if [[ "${n}" -lt 100 ]] || [[ $((page * 100)) -ge "${total}" ]]; then
      break
    fi
    page=$((page + 1))
  done
  _run_artifacts_cache["${run_id}"]="${artifacts_json}"
  printf '%s' "${artifacts_json}"
}

# ---------------------------------------------------------------------------
# _feat_log_artifact_name <job_name> <run_id>
# Resolve feat-log-<feature>-<scenario>-<mode> from a feature-test job name.
# Prints artifact name or empty string.
# ---------------------------------------------------------------------------
_feat_log_artifact_name() {
  local job_name="$1"
  local run_id="$2"
  local feature scenario mode_lc expected
  local _gha_matrix_prefix
  _gha_matrix_prefix="$(printf '%s%s' '$' '{{')"

  if [[ "${job_name}" =~ ^Test\ Feature\ ([^/]+)\ /\ (.+)\ \((devcontainer|linux|macOS)\)$ ]]; then
    feature="${BASH_REMATCH[1]}"
    scenario="${BASH_REMATCH[2]}"
    case "${BASH_REMATCH[3]}" in
      macOS) mode_lc=macos ;;
      *) mode_lc="${BASH_REMATCH[3]}" ;;
    esac
  elif [[ "${job_name}" =~ ^(.+)\ \((devcontainer|linux|macOS)\)$ ]]; then
    feature=""
    scenario="${BASH_REMATCH[1]}"
    case "${BASH_REMATCH[2]}" in
      macOS) mode_lc=macos ;;
      *) mode_lc="${BASH_REMATCH[2]}" ;;
    esac
  else
    return 0
  fi

  if [[ "${scenario}" == *"${_gha_matrix_prefix}"* ]]; then
    return 0
  fi

  if [[ -n "${feature}" ]]; then
    expected="feat-log-${feature}-${scenario}-${mode_lc}"
    jq -r --arg n "${expected}" '
      [.artifacts[] | select(.name == $n) | .name][0] // empty
    ' <<< "$(_run_artifacts_json "${run_id}")"
    return 0
  fi

  local suffix="${scenario}-${mode_lc}"
  jq -r --arg suf "${suffix}" '
    [.artifacts[]
     | select(.name | startswith("feat-log-"))
     | select(.name | endswith("-" + $suf))
     | .name][0] // empty
  ' <<< "$(_run_artifacts_json "${run_id}")"
}

# ---------------------------------------------------------------------------
# _step_log_basename <job_id> <step_number>
# Prints <job-id>-step<N>.log (basename only).
# ---------------------------------------------------------------------------
_step_log_basename() {
  printf '%s-step%s.log' "$1" "$2"
}

# ---------------------------------------------------------------------------
# _extract_failing_step_log <job_id> <step_number> <full_log> <start> <end>
# Copy lines [start,end] from full_log into <job-id>-step<N>.log.
# Prints the step log basename on success, empty string on failure.
# ---------------------------------------------------------------------------
_extract_failing_step_log() {
  local job_id="$1" step_num="$2" full_log="$3" start="$4" end="$5"
  local dest="${LOGDIR}/$(_step_log_basename "${job_id}" "${step_num}")"

  if [[ ! -s "${full_log}" || "${start}" -le 0 || "${end}" -lt "${start}" ]]; then
    printf ''
    return 0
  fi

  if ! sed -n "${start},${end}p" "${full_log}" > "${dest}"; then
    rm -f "${dest}"
    printf ''
    return 0
  fi

  if [[ ! -s "${dest}" ]]; then
    rm -f "${dest}"
    printf ''
    return 0
  fi

  basename "${dest}"
}

# ---------------------------------------------------------------------------
# _slice_ranges_from_job_log <full_log>
# Print one "start:end" line per ##[error]Process completed slice in log order.
# Each slice starts at the nearest preceding workflow-level ##[group]Run line
# (composite-action internals like "##[group]Run #..." are skipped).
# ---------------------------------------------------------------------------
_slice_ranges_from_job_log() {
  local full_log="$1"
  [[ -s "${full_log}" ]] || return 0

  awk '
    /^##\[group\]Run / {
      title = substr($0, 15)
      sub(/^[[:space:]]+/, "", title)
      if (title !~ /^#/) {
        run_count++
        run_line[run_count] = NR
      }
    }
    /^##\[error\]Process completed with exit code/ {
      err_count++
      err_line[err_count] = NR
    }
    END {
      for (i = 1; i <= err_count; i++) {
        start = 1
        for (j = run_count; j >= 1; j--) {
          if (run_line[j] < err_line[i]) {
            start = run_line[j]
            break
          }
        }
        printf "%d:%d\n", start, err_line[i]
      }
    }
  ' "${full_log}"
}

# ---------------------------------------------------------------------------
# _failing_step_log_for <job_id> <full_log_basename> <step_number> <slice_index>
# Pair one failing step with the Nth ##[error] slice in the full job log
# (1-based among failing steps). Prints the per-step log basename, or the full
# job log basename when extraction fails.
# ---------------------------------------------------------------------------
_failing_step_log_for() {
  local job_id="$1" full_log_base="$2" step_num="$3" slice_index="$4"
  local full_log="${LOGDIR}/${full_log_base}"
  local ranges range start end step_base _n=0

  ranges=$(_slice_ranges_from_job_log "${full_log}")
  if [[ -z "${ranges}" ]]; then
    printf '%s' "${full_log_base}"
    return 0
  fi

  while IFS= read -r range; do
    [[ -z "${range}" ]] && continue
    _n=$((_n + 1))
    [[ "${_n}" -eq "${slice_index}" ]] || continue
    start="${range%%:*}"
    end="${range#*:}"
    step_base=$(_extract_failing_step_log "${job_id}" "${step_num}" "${full_log}" \
      "${start}" "${end}")
    if [[ -n "${step_base}" ]]; then
      printf '%s' "${step_base}"
      return 0
    fi
    break
  done <<< "${ranges}"

  printf '%s' "${full_log_base}"
}

# ---------------------------------------------------------------------------
# _download_trace_log <job_id> <job_name> <run_id>
# For feature-test matrix jobs, download feat-log-* artifact to
# ${LOGDIR}/<job_id>.trace.log (best-effort; warns on stderr when missing).
# ---------------------------------------------------------------------------
_download_trace_log() {
  local job_id="$1"
  local job_name="$2"
  local run_id="$3"
  local dest="${LOGDIR}/${job_id}.trace.log"
  local artifact_name tmpdir src

  artifact_name=$(_feat_log_artifact_name "${job_name}" "${run_id}")
  if [[ -z "${artifact_name}" ]]; then
    _ts "  (no feat-log artifact for feature-test job: ${job_name})"
    return 0
  fi

  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/gha-trace-log.XXXXXX")
  if ! gh run download "${run_id}" -R "${REPO_SLUG}" -n "${artifact_name}" -D "${tmpdir}" \
    > /dev/null 2>&1; then
    _ts "  (feat-log download failed: ${artifact_name})"
    rm -rf "${tmpdir}"
    return 0
  fi

  src=$(find "${tmpdir}" -type f -name '*.log' -print -quit 2> /dev/null || true)
  if [[ -z "${src}" || ! -f "${src}" ]]; then
    _ts "  (feat-log artifact has no .log file: ${artifact_name})"
    rm -rf "${tmpdir}"
    return 0
  fi

  cp "${src}" "${dest}"
  rm -rf "${tmpdir}"
  _ts "  trace log → $(basename "${dest}")"
}

# ---------------------------------------------------------------------------
# _handle_job <job-json> <run_id>
# Processes one completed job. Updates passing.log / failing.log and sets
# _any_failure=1 on non-success conclusions.
# ---------------------------------------------------------------------------
_handle_job() {
  local job="$1"
  local run_id="$2"
  local job_id job_name conclusion
  job_id=$(jq -r '.id' <<< "${job}")
  job_name=$(jq -r '.name' <<< "${job}")
  conclusion=$(jq -r '.conclusion' <<< "${job}")

  # GHA never resolves matrix expressions for skipped jobs; the API returns
  # literal strings like "${{ matrix.sc.scenario }}". Replace them so log
  # files are legible.
  job_name="${job_name//\$\{\{*\}\}/<matrix>}"

  # Skip already-processed jobs
  [[ ${_processed[${job_id}]+_} ]] && return 0
  _processed["${job_id}"]=1

  _ts "  [$(printf '%-10s' "${conclusion}")] ${job_name}"

  if [[ "${conclusion}" == "success" || "${conclusion}" == "skipped" ]]; then
    echo "${job_name}" >> "${PASSING_LOG}"
    _stat_pass=$((_stat_pass + 1))
    return 0
  fi

  _any_failure=1

  local log_file
  log_file=$(_download_log "${job_id}")
  _download_trace_log "${job_id}" "${job_name}" "${run_id}"

  local failing_steps_json
  failing_steps_json=$(jq -c '
    [.steps[]
     | select(.conclusion == "failure" or .conclusion == "cancelled")
     | {number, name}]
    | sort_by(.number)
  ' <<< "${job}")

  local failing_count
  failing_count=$(jq 'length' <<< "${failing_steps_json}")

  if [[ "${failing_count}" -eq 0 ]]; then
    echo "${job_name} --- (no failing step identified) --- ${log_file}" >> "${FAILING_LOG}"
    _stat_fail=$((_stat_fail + 1))
    return 0
  fi

  local slice_index=0 step_num step_name step_log
  while IFS= read -r step_row; do
    [[ -z "${step_row}" ]] && continue
    slice_index=$((slice_index + 1))
    step_num=$(jq -r '.number' <<< "${step_row}")
    step_name=$(jq -r '.name' <<< "${step_row}")
    step_log=$(_failing_step_log_for "${job_id}" "${log_file}" \
      "${step_num}" "${slice_index}")
    echo "${job_name} --- ${step_name} --- ${step_log}" >> "${FAILING_LOG}"
    _stat_fail=$((_stat_fail + 1))
  done < <(jq -c '.[]' <<< "${failing_steps_json}")
}

# ---------------------------------------------------------------------------
# _process_run_jobs <run_id> <in_progress_array_name> <path_commit_sha>
# Fetches jobs for a run, handles completed jobs, appends in-progress job
# names to the named array. Log files live under
#   <GHA_LOG_BASE>/<path_commit_sha>/<run_id>/  . Returns 0 on success.
# Paginates through all job pages (runs can have well over 100 jobs).
# ---------------------------------------------------------------------------
_process_run_jobs() {
  local run_id="$1"
  local -n _inprogress_ref="$2"
  local path_sha="$3"
  local job job_status
  local jobs_page total_count n_jobs page=1

  _activate_run_logdir "${path_sha}" "${run_id}"

  # Do not use `gh api --paginate` with `--jq` here: for >100 jobs, gh can
  # feed jq a stream that jq rejects ("invalid character '<'…") after the
  # first page. Page explicitly instead (same REST shape each time).
  while true; do
    if ! jobs_page=$(_gh_api_json \
      "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_id}/jobs?per_page=${_GHA_JOBS_PER_PAGE}&page=${page}"); then
      return 1
    fi

    if ! jq -e '.jobs | type == "array"' > /dev/null 2>&1 <<< "${jobs_page}"; then
      local _one="${jobs_page//$'\n'/ }"
      [[ ${#_one} -gt 200 ]] && _one="${_one:0:200}…"
      _ts "jobs API returned unexpected JSON: ${_one}"
      return 1
    fi

    n_jobs=$(jq '.jobs | length' <<< "${jobs_page}")
    total_count=$(jq '.total_count' <<< "${jobs_page}")

    if [[ "${n_jobs}" -eq 0 ]]; then
      break
    fi

    while IFS= read -r job; do
      [[ -z "${job}" ]] && continue
      job_status=$(jq -r '.status' <<< "${job}")
      if [[ "${job_status}" == "completed" ]]; then
        _handle_job "${job}" "${run_id}"
      elif [[ "${job_status}" == "in_progress" ]]; then
        _inprogress_ref+=("$(jq -r '.name' <<< "${job}")")
      fi
    done < <(jq -c '.jobs[]' <<< "${jobs_page}")

    if [[ "${n_jobs}" -lt "${_GHA_JOBS_PER_PAGE}" ]] ||
      [[ $((page * _GHA_JOBS_PER_PAGE)) -ge "${total_count}" ]]; then
      break
    fi
    page=$((page + 1))
  done
  return 0
}

# ---------------------------------------------------------------------------
# Main polling
# ---------------------------------------------------------------------------
if [[ "${_GHA_MODE}" == "commit" ]]; then
  _ts "repo=${REPO_SLUG}  commit=${LOG_COMMIT_SHA}  (mode=commit)"
  _ts "log-base=${GHA_LOG_BASE}/<sha>/<run-id>/  (per workflow run)"

  while true; do
    runs_resp=$(_gh_api_json \
      "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?head_sha=${COMMIT_SHA}&per_page=100") || {
      sleep "${_poll_interval}"
      continue
    }

    total_runs=$(jq '.total_count' <<< "${runs_resp}")
    if [[ "${total_runs}" -eq 0 ]]; then
      _ts 'no workflow runs found yet, waiting...'
      sleep "${_poll_interval}"
      continue
    fi

    all_done=true
    in_progress_jobs=()

    while IFS= read -r run; do
      run_id=$(jq -r '.id' <<< "${run}")
      run_status=$(jq -r '.status' <<< "${run}")

      [[ "${run_status}" != "completed" ]] && all_done=false

      _process_run_jobs "${run_id}" in_progress_jobs "${LOG_COMMIT_SHA}" || continue

    done < <(jq -c '.workflow_runs[]' <<< "${runs_resp}")

    if [[ "${all_done}" == "true" ]]; then
      _ts 'all workflow runs completed'
      break
    fi

    if [[ ${#in_progress_jobs[@]} -gt 0 ]]; then
      _ts "in progress (${#in_progress_jobs[@]}): ${in_progress_jobs[*]}"
    fi

    sleep "${_poll_interval}"
  done
else
  _ts "repo=${REPO_SLUG}  run_id=${RUN_ID}  (mode=run)"
  _ts "log-base=${GHA_LOG_BASE}/<sha>/${RUN_ID}/  (commit from run metadata)"

  while true; do
    run_json=$(_gh_api_json \
      "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}") || {
      sleep "${_poll_interval}"
      continue
    }

    if [[ -z "${LOG_COMMIT_SHA}" ]]; then
      _gh_head=$(jq -r '.head_sha // empty' <<< "${run_json}")
      if [[ -z "${_gh_head}" || "${_gh_head}" == "null" ]]; then
        _ts 'run response had no head_sha — retrying...'
        sleep "${_poll_interval}"
        continue
      fi
      LOG_COMMIT_SHA="$(_normalize_commit_sha "${_gh_head}")"
    fi

    run_status=$(jq -r '.status' <<< "${run_json}")
    in_progress_jobs=()

    _process_run_jobs "${RUN_ID}" in_progress_jobs "${LOG_COMMIT_SHA}" || {
      sleep "${_poll_interval}"
      continue
    }

    if [[ "${run_status}" == "completed" ]]; then
      _ts 'workflow run completed'
      break
    fi

    if [[ ${#in_progress_jobs[@]} -gt 0 ]]; then
      _ts "in progress (${#in_progress_jobs[@]}): ${in_progress_jobs[*]}"
    fi

    sleep "${_poll_interval}"
  done
fi

echo '' >&2
_ts "${#_processed[@]} job(s) finished — ${_stat_pass} job(s) passed, ${_stat_fail} failure line(s) in failing.log"
if [[ ${#GHA_LOGDIRS[@]} -gt 0 ]]; then
  printf '%s\n' "${GHA_LOGDIRS[@]}" | sort -u
fi
exit "${_any_failure}"
