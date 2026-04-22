#!/usr/bin/env bash
# watch-gha-run.sh — Monitor GHA workflow runs and collect job logs.
#
# Usage:
#   watch-gha-run.sh [--log-base <dir>] --commit <commit-sha>
#   watch-gha-run.sh [--log-base <dir>] --run <workflow-run-id>
#   watch-gha-run.sh [--log-base <dir>] <commit-sha>   # same as --commit
#   watch-gha-run.sh --help
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
#       timestamps stripped), and one line per failing step appended to
#       failing.log in the format:
#           <job-name> --- <step-name> --- <log-filename>
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

# shellcheck source=scripts/git_helpers.sh
. "${_SCRIPT_DIR}/git_helpers.sh"

_usage() {
  cat << 'EOF'
watch-gha-run.sh — Monitor GHA workflow runs and collect job logs.

Usage:
  watch-gha-run.sh [options] --commit <commit-sha>
  watch-gha-run.sh [options] --run <workflow-run-id>
  watch-gha-run.sh [options] <commit-sha>   # same as --commit
  watch-gha-run.sh --help

  --commit       Monitor all runs for a commit
  --run          Monitor a single run; commit is taken from the run metadata
  --log-base DIR Directory to use instead of the default
                 <repo-root>/.local/logs/gha  (see below; relative → under repo)
  -h, --help

  Log layout (both modes):
    <log-base>/<full-40-char-sha>/<workflow-run-id>/
      passing.log, failing.log, and per-job <job-id>.log files

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
    c="$(git rev-parse "${c}" 2> /dev/null || echo "${c}")"
  fi
  printf '%s' "${c}"
}

if [[ "${_GHA_MODE}" == "commit" ]]; then
  LOG_COMMIT_SHA="$(_normalize_commit_sha "${COMMIT_SHA}")"
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

declare -A _processed # job_id → 1 (tracks already-handled jobs)
_stat_pass=0
_stat_fail=0
_any_failure=0
_poll_interval=10

# ---------------------------------------------------------------------------
# _ts — print a [HH:MM:SS] prefixed message to stdout
# ---------------------------------------------------------------------------
_ts() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

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
  gh api "/repos/${REPO_OWNER}/${REPO_NAME}/actions/jobs/${job_id}/logs" |
    awk '{ sub(/^[0-9T:.Z-]+[[:space:]]*/,""); print }' \
      > "${dest}" 2> /dev/null || true
  basename "${dest}"
}

# ---------------------------------------------------------------------------
# _handle_job <job-json>
# Processes one completed job. Updates passing.log / failing.log and sets
# _any_failure=1 on non-success conclusions.
# ---------------------------------------------------------------------------
_handle_job() {
  local job="$1"
  local job_id job_name conclusion
  job_id=$(jq -r '.id' <<< "${job}")
  job_name=$(jq -r '.name' <<< "${job}")
  conclusion=$(jq -r '.conclusion' <<< "${job}")

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

  # Identify failing steps
  local failing_steps
  failing_steps=$(jq -r '
    .steps[]
    | select(.conclusion == "failure" or .conclusion == "cancelled")
    | .name
  ' <<< "${job}")

  local logfile
  logfile=$(_download_log "${job_id}")

  if [[ -z "${failing_steps}" ]]; then
    echo "${job_name} --- (no failing step identified) --- ${logfile}" >> "${FAILING_LOG}"
    _stat_fail=$((_stat_fail + 1))
    return 0
  fi

  while IFS= read -r step_name; do
    echo "${job_name} --- ${step_name} --- ${logfile}" >> "${FAILING_LOG}"
    _stat_fail=$((_stat_fail + 1))
  done <<< "${failing_steps}"
}

# ---------------------------------------------------------------------------
# _process_run_jobs <run_id> <in_progress_array_name> <path_commit_sha>
# Fetches jobs for a run, handles completed jobs, appends in-progress job
# names to the named array. Log files live under
#   <GHA_LOG_BASE>/<path_commit_sha>/<run_id>/  . Returns 0 on success.
# ---------------------------------------------------------------------------
_process_run_jobs() {
  local run_id="$1"
  local -n _inprogress_ref="$2"
  local path_sha="$3"
  local jobs_resp job job_status

  _activate_run_logdir "${path_sha}" "${run_id}"

  jobs_resp=$(gh api \
    "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_id}/jobs?per_page=100" 2> /dev/null) || return 1

  while IFS= read -r job; do
    job_status=$(jq -r '.status' <<< "${job}")
    if [[ "${job_status}" == "completed" ]]; then
      _handle_job "${job}"
    elif [[ "${job_status}" == "in_progress" ]]; then
      _inprogress_ref+=("$(jq -r '.name' <<< "${job}")")
    fi
  done < <(jq -c '.jobs[]' <<< "${jobs_resp}")
  return 0
}

# ---------------------------------------------------------------------------
# Main polling
# ---------------------------------------------------------------------------
if [[ "${_GHA_MODE}" == "commit" ]]; then
  _ts "repo=${REPO_SLUG}  commit=${LOG_COMMIT_SHA}  (mode=commit)"
  _ts "log-base=${GHA_LOG_BASE}/<sha>/<run-id>/  (per workflow run)"

  while true; do
    runs_resp=$(gh api \
      "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?head_sha=${COMMIT_SHA}&per_page=100" 2> /dev/null) || {
      _ts 'API error — retrying...'
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
    run_json=$(gh api \
      "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}" 2> /dev/null) || {
      _ts 'API error — retrying (check run id and gh auth)...'
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
      _ts 'API error reading jobs — retrying...'
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
