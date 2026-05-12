#!/bin/bash
# Verifies method=package installs a working shellcheck.
set -e

source dev-container-features-test-lib

check "shellcheck command is available" command -v shellcheck
check "shellcheck lints a valid script" bash -c 'printf "#!/bin/sh\necho hi\n" | shellcheck -'

reportResults
