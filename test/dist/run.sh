#!/usr/bin/env bash
# run.sh — Runner for test/dist/ scenarios.
#
# Usage:
#   bash test/dist/run.sh [--suite <build|get|sysset|macos>] [--filter <name>]
#
# Discovers and runs scenario scripts under test/dist/scenarios/<suite>/*.sh.
# Each scenario is executed in a subshell; return code determines pass/fail.
#
# Exit code: 0 if all scenarios pass, 1 if any fail.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIOS_BASE="${REPO_ROOT}/test/dist/scenarios"
SUITES=(build get sysset macos)

SUITE_FILTER=""
NAME_FILTER=""
BUILD=true
VERSION="v0.1.0-test"
SYSSET_TEST_REGISTRY_HOST="${SYSSET_TEST_REGISTRY_HOST:-}"
_REGISTRY_CONTAINER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      shift
      SUITE_FILTER="${1:?--suite requires a value (build|get|sysset|macos)}"
      shift
      ;;
    --filter)
      shift
      NAME_FILTER="${1:?--filter requires a value}"
      shift
      ;;
    --version)
      shift
      VERSION="${1:?--version requires a value}"
      shift
      ;;
    --no-build)
      BUILD=false
      shift
      ;;
    --help | -h)
      cat << EOF
Usage: bash test/dist/run.sh [--suite <build|get|sysset|macos>] [--filter <name>] [--version <tag>] [--no-build]
EOF
      exit 0
      ;;
    *)
      echo "⛔ Unknown option: '$1'" >&2
      exit 1
      ;;
  esac
done

# ── Centralised build (skipped with --no-build) ───────────────────────────────
export SYSSET_BUILD_VERSION=""
if [[ "$BUILD" == true ]]; then
  echo "ℹ️  Building dist/ artifacts for tag '${VERSION}' ..." >&2
  bash "${REPO_ROOT}/scripts/build-artifacts.sh" "${VERSION}"
  export SYSSET_BUILD_VERSION="${VERSION}"
fi

_pass=0
_fail=0
_skip=0
_errors=()

_sep() {
  printf '%.0s─' {1..60}
  echo
}
_bold_sep() {
  printf '%.0s═' {1..60}
  echo
}

# ── Local OCI registry (skipped with --no-build for build/ suite only) ───────
# Starts a registry:2 container on a random local port and exports
# SYSSET_TEST_REGISTRY_HOST for use by get/ and sysset/ scenario scripts.
# If SYSSET_TEST_REGISTRY_HOST is already set in the environment (e.g. for
# sysset/ scenarios inside a minimal docker container where docker is not
# available), the existing value is used as-is and no container is started.
setup_local_registry() {
  if [[ -n "${SYSSET_TEST_REGISTRY_HOST:-}" ]]; then
    echo "ℹ️  Using pre-configured test OCI registry: ${SYSSET_TEST_REGISTRY_HOST}" >&2
    return 0
  fi
  local _port _cid
  _port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); p=s.getsockname()[1]; s.close(); print(p)')" || {
    echo "⛔ Could not pick a free port for the local OCI registry" >&2
    return 1
  }
  _cid="$(docker run -d --rm -p "${_port}:5000" registry:2 2>&1)" || {
    echo "⛔ Could not start local OCI registry (is docker available?): ${_cid}" >&2
    return 1
  }
  _REGISTRY_CONTAINER="${_cid}"
  SYSSET_TEST_REGISTRY_HOST="localhost:${_port}"
  local _deadline _ready=0
  _deadline=$(( $(date +%s) + 30 ))
  while [[ $(date +%s) -lt $_deadline ]]; do
    if curl -sf "http://127.0.0.1:${_port}/v2/" > /dev/null 2>&1; then
      _ready=1
      break
    fi
    sleep 0.5
  done
  if [[ "$_ready" -eq 0 ]]; then
    echo "⛔ Local OCI registry did not become ready at port ${_port}" >&2
    docker stop "$_REGISTRY_CONTAINER" > /dev/null 2>&1 || true
    _REGISTRY_CONTAINER=""
    return 1
  fi
  export SYSSET_TEST_REGISTRY_HOST
  echo "ℹ️  Local OCI registry ready at ${SYSSET_TEST_REGISTRY_HOST}" >&2
}

teardown_local_registry() {
  if [[ -n "$_REGISTRY_CONTAINER" ]]; then
    docker stop "$_REGISTRY_CONTAINER" > /dev/null 2>&1 || true
    _REGISTRY_CONTAINER=""
  fi
}

run_scenario() {
  local _suite="$1"
  local _script="$2"
  local _name
  _name="$(basename "$_script" .sh)"

  [[ -n "$NAME_FILTER" && "$_name" != "$NAME_FILTER" ]] && {
    ((_skip++)) || true
    return 0
  }

  echo ""
  _sep
  echo "▶  dist / ${_suite} / ${_name}"
  _sep
  if [[ "$_suite" == "get" || "$_suite" == "sysset" ]]; then
    if SYSSET_REGISTRY_HOST="${SYSSET_TEST_REGISTRY_HOST}" \
      SYSSET_TEST_REPO_ROOT="${REPO_ROOT}" \
      bash "$_script" "$REPO_ROOT"; then
      echo "✅ PASS: ${_suite}/${_name}"
      ((_pass++)) || true
    else
      echo "❌ FAIL: ${_suite}/${_name}"
      _errors+=("${_suite}/${_name}")
      ((_fail++)) || true
    fi
  elif bash "$_script" "$REPO_ROOT"; then
    echo "✅ PASS: ${_suite}/${_name}"
    ((_pass++)) || true
  else
    echo "❌ FAIL: ${_suite}/${_name}"
    _errors+=("${_suite}/${_name}")
    ((_fail++)) || true
  fi
}

_needs_registry=false
if [[ -z "$SUITE_FILTER" || "$SUITE_FILTER" == "get" || "$SUITE_FILTER" == "sysset" ]]; then
  _needs_registry=true
fi
if [[ "$_needs_registry" == true ]]; then
  setup_local_registry
  trap 'teardown_local_registry' EXIT
fi

for suite in "${SUITES[@]}"; do
  [[ -n "$SUITE_FILTER" && "$suite" != "$SUITE_FILTER" ]] && continue
  suite_dir="${SCENARIOS_BASE}/${suite}"
  [[ -d "$suite_dir" ]] || continue

  for script in "${suite_dir}"/*.sh; do
    [[ -f "$script" ]] || continue
    run_scenario "$suite" "$script"
  done
done

echo ""
_bold_sep
echo "dist tests: ${_pass} passed, ${_fail} failed, ${_skip} skipped."
_bold_sep

if [[ ${_fail} -gt 0 ]]; then
  echo "Failing scenarios:"
  for e in "${_errors[@]}"; do
    printf '  — %s\n' "$e"
  done
  exit 1
fi
