#!/bin/bash
# Verifies that add_users with an explicit username configures exactly
# that user. All devcontainer-injected user options are off so only the
# explicit list path is exercised.
set -e

source dev-container-features-test-lib

_GRAPH_ROOT="/var/lib/containers/storage/users/devuser"
_DEVUSER_HOME="/home/devuser"

# --- devuser configured via add_users ---
check "devuser in /etc/subuid" grep -q "^devuser:" /etc/subuid
check "devuser in /etc/subgid" grep -q "^devuser:" /etc/subgid
check "devuser storage.conf exists" test -f "${_DEVUSER_HOME}/.config/containers/storage.conf"
check "devuser storage.conf overlay driver" grep -q 'driver = "overlay"' "${_DEVUSER_HOME}/.config/containers/storage.conf"
check "devuser storage.conf graphRoot correct" grep -qF "graphRoot = \"${_GRAPH_ROOT}\"" "${_DEVUSER_HOME}/.config/containers/storage.conf"

# --- home directory and config dir ownership ---
check "devuser home owned by devuser" bash -c '[ "$(stat -c %U /home/devuser)" = "devuser" ]'
check "devuser .config/containers owned by devuser" bash -c '[ "$(stat -c %U /home/devuser/.config/containers)" = "devuser" ]'
check "devuser .config/cni exists" test -d /home/devuser/.config/cni
check "devuser .config/cni owned by devuser" bash -c '[ "$(stat -c %U /home/devuser/.config/cni)" = "devuser" ]'

# --- root should NOT be configured ---
check "root NOT in /etc/subuid" bash -c '! grep -q "^root:" /etc/subuid'
check "root storage.conf NOT written" bash -c '! test -f /root/.config/containers/storage.conf'

reportResults
