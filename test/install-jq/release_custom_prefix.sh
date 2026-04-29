#!/bin/bash
# method=release, prefix=/opt/jq-bin, symlink=true (default):
# Verifies jq is installed at the custom prefix AND a symlink is created at
# /usr/local/bin/jq pointing to the custom-prefix binary.
set -e

source dev-container-features-test-lib

# --- binary installed at custom path ---
check "jq binary installed at /opt/jq-bin/bin/jq" test -f /opt/jq-bin/bin/jq
check "jq binary at custom prefix is executable" test -x /opt/jq-bin/bin/jq
check "/opt/jq-bin/bin/jq --version succeeds" /opt/jq-bin/bin/jq --version

# --- symlink created at /usr/local/bin/jq ---
check "symlink exists at /usr/local/bin/jq" test -L /usr/local/bin/jq
check "symlink resolves to /opt/jq-bin/bin/jq" bash -c \
  '[ "$(readlink -f /usr/local/bin/jq)" = "/opt/jq-bin/bin/jq" ]'

# --- binary reachable via PATH through symlink ---
check "jq resolves from PATH" command -v jq
check "jq processes JSON via PATH" bash -c 'echo "{}" | jq . > /dev/null 2>&1'
check "jq processes JSON via custom path" bash -c 'echo "{}" | /opt/jq-bin/bin/jq . > /dev/null 2>&1'

reportResults
