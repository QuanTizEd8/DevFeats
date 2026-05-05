#!/bin/bash
# Verifies default install installs a working shellcheck.
set -e

source dev-container-features-test-lib

check "shellcheck command is available" command -v shellcheck
check "shellcheck reports a version" bash -c 'shellcheck --version | grep -Eq "version:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+"'
check "shellcheck lints a valid script" bash -c 'printf "#!/bin/sh\necho hi\n" | shellcheck -'

reportResults
