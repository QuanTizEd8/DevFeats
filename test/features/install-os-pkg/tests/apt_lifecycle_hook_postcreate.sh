#!/bin/bash
# Verifies that when lifecycle_hook=postCreate is set, the feature writes a
# post-create.sh hook script instead of installing packages at build time.
set -e

source dev-container-features-test-lib

check "post-create.sh exists" test -f "${_FEAT_SHARE_DIR}/post-create.sh"
check "post-create.sh is executable" test -x "${_FEAT_SHARE_DIR}/post-create.sh"
check "post-create.sh references manifest" grep -q -- '--manifest' "${_FEAT_SHARE_DIR}/post-create.sh"
check "on-create.sh not written" test ! -f "${_FEAT_SHARE_DIR}/on-create.sh"
check "update-content.sh not written" test ! -f "${_FEAT_SHARE_DIR}/update-content.sh"
check "tree installed by postCreate hook" command -v tree

reportResults
