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
TEST_ORAS_DIR=""
TEST_ORAS_PAYLOAD=""
TEST_ORAS_SHA=""

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

setup_fake_oras() {
  local _tmp
  _tmp="$(mktemp -d)"
  TEST_ORAS_DIR="${_tmp}/fakebin"
  TEST_ORAS_PAYLOAD="${_tmp}/feature.tgz"
  mkdir -p "${TEST_ORAS_DIR}" "${_tmp}/payload"
  printf '%s\n' '#!/usr/bin/env sh' > "${_tmp}/payload/install.sh"
  printf '%s\n' '{}' > "${_tmp}/payload/devcontainer-feature.json"
  tar -czf "${TEST_ORAS_PAYLOAD}" -C "${_tmp}/payload" .
  if command -v sha256sum > /dev/null 2>&1; then
    TEST_ORAS_SHA="$(sha256sum "${TEST_ORAS_PAYLOAD}" | awk '{print $1}')"
  else
    TEST_ORAS_SHA="$(shasum -a 256 "${TEST_ORAS_PAYLOAD}" | awk '{print $1}')"
  fi
  cat > "${TEST_ORAS_DIR}/oras" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

_sha256_file() {
  local _f="${1-}"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$_f" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$_f" | awk '{print $1}'
}

_payload_for_ref() {
  local _ref="${1-}" _seg _id _cand
  _seg="${_ref##*/}"
  _id="${_seg%%:*}"
  _id="${_id%%@*}"
  if [[ -n "${SYSSET_TEST_REPO_ROOT:-}" ]]; then
    _cand="${SYSSET_TEST_REPO_ROOT}/dist/sysset-${_id}.tar.gz"
    if [[ -f "${_cand}" ]]; then
      printf '%s\n' "${_cand}"
      return 0
    fi
  fi
  printf '%s\n' "${SYSSET_TEST_FAKE_ORAS_TGZ}"
}

case "${1-}" in
  version)
    echo "Version: 1.2.0"
    ;;
  login)
    exit 0
    ;;
  repo)
    if [[ "${2-}" == "tags" ]]; then
      cat << 'TAGS'
latest
0
0.66
0.66.0
1
1.0
1.0.0
TAGS
      exit 0
    fi
    exit 1
    ;;
  manifest)
    if [[ "${2-}" == "fetch" ]]; then
      _payload="$(_payload_for_ref "${3-}")"
      _dig="sha256:$(_sha256_file "${_payload}")"
      cat <<JSON
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"${_dig}"}]}
JSON
      exit 0
    fi
    exit 1
    ;;
  pull)
    _ref="${2-}"
    _out=""
    while [[ $# -gt 0 ]]; do
      if [[ "${1}" == "-o" ]]; then
        _out="${2-}"
        shift 2
      else
        shift
      fi
    done
    [[ -n "${_out}" ]] || exit 1
    mkdir -p "${_out}"
    _payload="$(_payload_for_ref "${_ref}")"
    cp "${_payload}" "${_out}/devcontainer-feature-x.tgz"
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_ORAS_DIR}/oras"
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
    if PATH="${TEST_ORAS_DIR}:${PATH}" \
      SYSSET_TEST_FAKE_ORAS_TGZ="${TEST_ORAS_PAYLOAD}" \
      SYSSET_TEST_FAKE_ORAS_SHA="${TEST_ORAS_SHA}" \
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

setup_fake_oras

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
