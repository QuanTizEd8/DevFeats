#!/bin/bash
# Default options: all three shims enabled.
# Verifies each shim is installed, executable, and on PATH at the expected
# location.  Also checks that the shim directory is first in PATH.
set -e

source dev-container-features-test-lib

_SHIM_BIN="${_FEAT_SHARE_DIR}/bin"

# PATH checks use bash -lc so /etc/profile sources profile.d (where export_path writes).
# Plain bash -c does not load login startup files, so PATH would miss the shim dir.

# --- shim directory exists and is in PATH ---
check "shim bin directory exists" test -d "${_SHIM_BIN}"
check "shim bin is in PATH" bash -lc "echo \"\$PATH\" | tr ':' '\\n' | grep -qxF \"${_SHIM_BIN}\""
check "shim bin is first in PATH" bash -lc "[ \"\$(echo \"\$PATH\" | cut -d: -f1)\" = \"${_SHIM_BIN}\" ]"

# --- code shim ---
check "code shim exists" test -f "${_SHIM_BIN}/code"
check "code shim is executable" test -x "${_SHIM_BIN}/code"
check "which code resolves to shim" bash -lc "[ \"\$(which code)\" = \"${_SHIM_BIN}/code\" ]"

# --- devcontainer-info shim ---
check "devcontainer-info shim exists" test -f "${_SHIM_BIN}/devcontainer-info"
check "devcontainer-info shim is executable" test -x "${_SHIM_BIN}/devcontainer-info"
check "which devcontainer-info resolves to shim" bash -lc "[ \"\$(which devcontainer-info)\" = \"${_SHIM_BIN}/devcontainer-info\" ]"

# --- systemctl shim ---
check "systemctl shim exists" test -f "${_SHIM_BIN}/systemctl"
check "systemctl shim is executable" test -x "${_SHIM_BIN}/systemctl"

reportResults
