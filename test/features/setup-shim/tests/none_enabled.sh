#!/bin/bash
# All shims disabled.  The shim directory should exist (created by install.sh)
# but contain no shim scripts.
set -e

source dev-container-features-test-lib

_SHIM_BIN="${_FEAT_SHARE_DIR}/bin"

# --- shim directory still created ---
check "shim bin directory exists" test -d "${_SHIM_BIN}"

# --- no shims installed ---
check "code shim NOT present" bash -c "! test -f ${_SHIM_BIN}/code"
check "devcontainer-info shim NOT present" bash -c "! test -f ${_SHIM_BIN}/devcontainer-info"
check "systemctl shim NOT present" bash -c "! test -f ${_SHIM_BIN}/systemctl"

reportResults
