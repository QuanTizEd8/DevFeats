#!/usr/bin/env bash
# Verify that if_exists=fail exits non-zero when pixi is already installed.
# SETUP_CMD (in if_exists_fail_preinstalled.conf) places a stub pixi binary.
set -euo pipefail

source dev-container-features-test-lib

check "pixi stub pre-installed by setup" command -v pixi

reportResults
