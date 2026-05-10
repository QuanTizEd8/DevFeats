#!/usr/bin/env bash
# macOS: package + if_exists=skip (options from scenarios.yaml).
#
# The test orchestrator runs install.sh once with scenario options exported as
# environment variables (no CLI flags). Hosted runners already have git
# (Homebrew / CLT); the feature should hit the if_exists=skip early exit and
# leave ~/.config/git/config untouched.
#
# Validates post-install state only — no installation in this script.
set -e

# shellcheck source=test/support/assert.sh
source dev-container-features-test-lib

check "git on PATH" command -v git
check "git --version succeeds" git --version
check "git version line looks valid" bash -c 'git --version | grep -qE "^git version [0-9]"'
check "skip did not write user system config" bash -c '! test -e "${HOME}/.config/git/config"'

reportResults
