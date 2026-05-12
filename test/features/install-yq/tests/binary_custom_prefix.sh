#!/bin/bash
# method=binary, prefix=/opt/yq-bin, symlink=true (default):
# Verifies yq is installed at the custom prefix AND a symlink is created at
# /usr/local/bin/yq pointing to the custom-prefix binary.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "yq binary installed at /opt/yq-bin/bin/yq" test -f /opt/yq-bin/bin/yq
check "yq binary at custom prefix is executable" test -x /opt/yq-bin/bin/yq
check "/opt/yq-bin/bin/yq --version succeeds" /opt/yq-bin/bin/yq --version

# --- symlink created at /usr/local/bin/yq ---
check "symlink exists at /usr/local/bin/yq" test -L /usr/local/bin/yq
check "symlink resolves to /opt/yq-bin/bin/yq" bash -c \
  '[ "$(readlink -f /usr/local/bin/yq)" = "/opt/yq-bin/bin/yq" ]'

# --- binary reachable via PATH through symlink ---
check "yq resolves from PATH" command -v yq
check "yq supports -o=json mode" bash -c 'yq -o=json "." /dev/null > /dev/null 2>&1'
check "custom-prefix yq supports -o=json mode" bash -c '/opt/yq-bin/bin/yq -o=json "." /dev/null > /dev/null 2>&1'

reportResults
