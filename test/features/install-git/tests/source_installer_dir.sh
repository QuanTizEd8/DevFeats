#!/bin/bash
# method=source, version=stable, installer_dir=/tmp/git-build-trace: build directory preserved.
# Verifies git is installed and the installer_dir is NOT removed after a successful build.
set -e

source dev-container-features-test-lib

# --- binary ---
check "git at /usr/local/bin/git" test -f /usr/local/bin/git
check "git --version succeeds" /usr/local/bin/git --version

# --- installer_dir preserved ---
echo "=== /tmp/git-build-trace contents ==="
ls /tmp/git-build-trace 2> /dev/null || echo "(missing)"

check "installer_dir exists" test -d /tmp/git-build-trace
check "tarball preserved in dir" bash -c 'find /tmp/git-build-trace -maxdepth 1 -name "git-*.tar.gz" | grep -q .'
check "checksum file preserved in dir" test -f /tmp/git-build-trace/sha256sums.asc
check "source tree preserved in dir" bash -c 'find /tmp/git-build-trace -maxdepth 1 -type d -name "git-*" | grep -q .'

reportResults
