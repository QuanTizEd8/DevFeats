#!/bin/bash
# Same assertions as apt_lifecycle_hook_postcreate but with log_level=trace,
# so the build log will show the exact LIFECYCLE_HOOK env var value.
set -e

source dev-container-features-test-lib

check "post-create.sh exists" test -f "${_FEAT_SHARE_DIR}/post-create.sh"
check "post-create.sh is executable" test -x "${_FEAT_SHARE_DIR}/post-create.sh"
check "post-create.sh references manifest" grep -q -- '--manifest' "${_FEAT_SHARE_DIR}/post-create.sh"
check "on-create.sh not written" test ! -f "${_FEAT_SHARE_DIR}/on-create.sh"
check "update-content.sh not written" test ! -f "${_FEAT_SHARE_DIR}/update-content.sh"
check "tree installed by postCreate hook" command -v tree

reportResults
