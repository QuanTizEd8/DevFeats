#!/usr/bin/env bash
# .dev/scripts/test/run-unit.sh — local runner for lib/ unit tests.
#
# Usage:
#   bash .dev/scripts/test/run-unit.sh                       # run all modules
#   bash .dev/scripts/test/run-unit.sh --module os           # run test/lib/os.bats only
#   bash .dev/scripts/test/run-unit.sh --filter "platform"   # regex filter (--filter-tags)
#   bash .dev/scripts/test/run-unit.sh --jobs 1              # serial execution (default: auto)
#   bash .dev/scripts/test/run-unit.sh --paths test/lib/integration
#   bash .dev/scripts/test/run-unit.sh --integration

set -euo pipefail

# macOS ships bash 3.2; re-exec with bash ≥4 if needed.
if ((BASH_VERSINFO[0] < 4)); then
  for _try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_try_bash" ]] && "$_try_bash" -c '(( BASH_VERSINFO[0] >= 4 ))' 2> /dev/null; then
      exec "$_try_bash" "$0" "$@"
    fi
  done
  printf '⛔ bash ≥4.0 required (found %s). Install via: brew install bash\n' \
    "$BASH_VERSION" >&2
  exit 1
fi

# Ensure 'env bash' resolves to the same bash ≥4 we re-exec'd with.
# bats forks sub-scripts (bats-exec-test, bats-exec-suite, …) via their
# #!/usr/bin/env bash shebang; without this, those pick up /bin/bash 3.2.
export PATH
PATH="$(dirname "$BASH"):$PATH"

if [[ -n "${REPO_ROOT:-}" ]]; then
  _REPO_ROOT="$REPO_ROOT"
else
  _REPO_ROOT="$(git -C "$(cd "$(dirname "$0")" && pwd)" rev-parse --show-toplevel)"
fi
export REPO_ROOT="$_REPO_ROOT"
_BATS="${_REPO_ROOT}/test/lib/bats/bats-core/bin/bats"
_UNIT_DIR="${_REPO_ROOT}/test/lib"

# ── Argument parsing ─────────────────────────────────────────────────────────
_module=""
_filter=""
_jobs=0 # 0 = let bats decide (auto / num CPUs)
_integration=false
_exclude_integration=true
_clean_path=false
_path_prepend=""
declare -a _paths=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --module)
      shift
      _module="$1"
      shift
      ;;
    --filter)
      shift
      _filter="$1"
      shift
      ;;
    --jobs)
      shift
      _jobs="$1"
      shift
      ;;
    --paths)
      shift
      _paths+=("$1")
      shift
      ;;
    --integration)
      _integration=true
      _exclude_integration=false
      shift
      ;;
    --exclude-integration)
      # Last flag wins: explicitly disable integration-only selection.
      _integration=false
      _exclude_integration=true
      shift
      ;;
    --clean-path)
      _clean_path=true
      shift
      ;;
    --path-prepend)
      shift
      _path_prepend="$1"
      shift
      ;;
    --help | -h)
      cat << 'HELP'
Usage: bash .dev/scripts/test/run-unit.sh [--module <name>] [--filter <regex>] [--jobs <n>] [--paths <glob>] [--integration] [--path-prepend <dirs>]

  --module <name>       Run only test/lib/<name>.bats  (e.g. os, shell, ospkg)
  --filter <regex>      Pass --filter to bats (matches test names by regex)
  --jobs <n>            Parallel job count (default: auto)
  --paths <glob>        Add explicit test file/path glob (repeatable)
  --integration         Run integration tests under test/lib/integration
  --exclude-integration Exclude test/lib/integration (default)
  --clean-path          Strip PATH to system baseline (macOS)
  --path-prepend <dirs> Prepend colon-separated dirs to PATH after --clean-path
HELP
      exit 0
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

# ── PATH isolation ───────────────────────────────────────────────────────────
# Strips the GHA runner's pre-installed tools, keeping only the macOS system
# baseline plus the bash ≥4 binary selected by the re-exec above.
if [[ "$_clean_path" == true ]]; then
  PATH="$(dirname "$BASH"):/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
fi
if [[ -n "$_path_prepend" ]]; then
  PATH="${_path_prepend}:${PATH}"
  export PATH
fi

# ── Pre-flight checks ────────────────────────────────────────────────────────
if [[ ! -x "$_BATS" ]]; then
  echo "⛔ bats not found at '${_BATS}'." >&2
  echo "   Run: git submodule update --init --recursive" >&2
  exit 1
fi

# ── Build file list ──────────────────────────────────────────────────────────
declare -a _test_files=()
if [[ ${#_paths[@]} -gt 0 ]]; then
  for _path_glob in "${_paths[@]}"; do
    while IFS= read -r -d '' _f; do
      _test_files+=("$_f")
    done < <(compgen -G "${_path_glob}" | while IFS= read -r _m; do
      [[ -d "$_m" ]] && find "$_m" -name '*.bats' -print0 || printf '%s\0' "$_m"
    done)
  done
elif [[ -n "$_module" ]]; then
  _target="${_UNIT_DIR}/${_module}.bats"
  if [[ ! -f "$_target" ]]; then
    echo "⛔ Module test not found: '${_target}'" >&2
    exit 1
  fi
  _test_files=("$_target")
else
  if [[ "$_integration" == true ]]; then
    while IFS= read -r -d '' _f; do
      _test_files+=("$_f")
    done < <(find "$_UNIT_DIR/integration" -name '*.bats' -print0 2> /dev/null | sort -z)
  elif [[ "$_exclude_integration" == true ]]; then
    while IFS= read -r -d '' _f; do
      _test_files+=("$_f")
    done < <(find "$_UNIT_DIR" -maxdepth 1 -name '*.bats' -print0 | sort -z)
  else
    while IFS= read -r -d '' _f; do
      _test_files+=("$_f")
    done < <(find "$_UNIT_DIR" -name '*.bats' -print0 | sort -z)
  fi
fi

if [[ ${#_test_files[@]} -eq 0 ]]; then
  echo "⚠️  No .bats files found in '${_UNIT_DIR}'." >&2
  exit 0
fi

# ── Run ──────────────────────────────────────────────────────────────────────
declare -a _bats_args=(--print-output-on-failure)

[[ "$_jobs" -gt 0 ]] && _bats_args+=(--jobs "$_jobs")
[[ -n "$_filter" ]] && _bats_args+=(--filter "$_filter")

# Invoke bats via the same bash ≥4 binary we re-exec'd with, so bats and all
# test files run under bash ≥4 regardless of what `env bash` resolves to.
exec "$BASH" "$_BATS" "${_bats_args[@]}" "${_test_files[@]}"
