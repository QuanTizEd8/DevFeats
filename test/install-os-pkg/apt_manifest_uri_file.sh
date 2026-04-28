#!/bin/bash
# manifest=file:///tmp/manifest.yaml — same checks as apt_installs_packages using a file:// URI.
set -e

source dev-container-features-test-lib

check "tree is installed (manifest file URI)" command -v tree
check "curl is installed (manifest file URI)" command -v curl

reportResults
