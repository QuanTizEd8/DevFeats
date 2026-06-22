# shellcheck shell=bash
# Re-export lib bootstrap_tools helpers for install-framework bats tests.

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/test/lib/helpers/bootstrap_tools.bash"
