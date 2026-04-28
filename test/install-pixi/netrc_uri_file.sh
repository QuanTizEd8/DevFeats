#!/bin/bash
# netrc=file:///tmp/test.netrc — pixi installs with a file:// .netrc (no real secrets).
set -e

source dev-container-features-test-lib

check "pixi binary installed" test -x /usr/local/bin/pixi
check "pixi --version succeeds" /usr/local/bin/pixi --version

reportResults
