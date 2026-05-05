#!/bin/bash
# prefix=/opt/jq-bin, symlink=false:
# Verifies jq is installed at the custom prefix and no symlink is created.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "jq binary installed at /opt/jq-bin/bin/jq" test -f /opt/jq-bin/bin/jq
check "jq binary at custom prefix is executable" test -x /opt/jq-bin/bin/jq
check "/opt/jq-bin/bin/jq --version succeeds" /opt/jq-bin/bin/jq --version
check "jq processes JSON via custom path" bash -c 'echo "{}" | /opt/jq-bin/bin/jq . > /dev/null 2>&1'

# --- no symlink created ---
check "no symlink at /usr/local/bin/jq" bash -c '! test -L /usr/local/bin/jq && ! test -e /usr/local/bin/jq'

reportResults
