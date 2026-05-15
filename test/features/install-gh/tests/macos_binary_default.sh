#!/usr/bin/env bash
# macOS: default install (if_exists=skip).
#
# macOS GHA runners have gh pre-installed (GitHub CLI 2.x).
# Our feature detects the existing installation and exits 0 without making
# any changes, thanks to the if_exists=skip early-exit path that fires
# BEFORE os__require_root. This validates:
#   - the feature script succeeds (exits 0) on macOS without Docker and
#     without root privileges
#   - the early-exit path (VERSION=stable + gh in PATH + if_exists=skip)
#     works correctly end-to-end on macOS
#   - CLI argument parsing works end-to-end
set -e

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

# --- baseline: gh is in PATH before the feature runs ---
check "gh pre-installed on runner" command -v gh
check "gh --version succeeds" gh --version

# --- run the feature (if_exists=skip default, version=stable default) ---
bash "${REPO_ROOT}/src/install-gh/install.sh" \
  --log_level trace

# --- gh is still functional after the feature skips ---
check "gh on PATH after feature run" command -v gh
check "gh still returns version string" bash -c 'gh --version | grep -qE "^gh version [0-9]"'

reportResults
