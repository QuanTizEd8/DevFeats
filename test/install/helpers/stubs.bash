# shellcheck shell=bash
# Re-export lib test stubs for install framework bats tests.

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/test/lib/helpers/stubs.bash"
