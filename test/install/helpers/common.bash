# shellcheck shell=bash
# Re-export lib test helpers and install-framework sourcing.

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
fi
export REPO_ROOT

# shellcheck source=/dev/null
source "${REPO_ROOT}/test/lib/helpers/common.bash"
# shellcheck source=/dev/null
source "${BATS_TEST_DIRNAME}/helpers/source_framework.bash"
