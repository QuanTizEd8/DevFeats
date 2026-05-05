#!/bin/bash
# prefix=/opt/yq-bin, symlink=false:
# Verifies yq is installed at the custom prefix and no symlink is created.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "yq binary installed at /opt/yq-bin/bin/yq" test -f /opt/yq-bin/bin/yq
check "yq binary at custom prefix is executable" test -x /opt/yq-bin/bin/yq
check "/opt/yq-bin/bin/yq --version succeeds" /opt/yq-bin/bin/yq --version
check "yq supports -o=json mode via custom path" bash -c '/opt/yq-bin/bin/yq -o=json "." /dev/null > /dev/null 2>&1'

# --- no symlink created ---
check "no symlink at /usr/local/bin/yq" bash -c '! test -L /usr/local/bin/yq && ! test -e /usr/local/bin/yq'

reportResults
