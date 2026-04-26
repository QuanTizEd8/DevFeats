#!/bin/bash
# Verifies the full key+repo+package lifecycle with a raw (ASCII-armored) key:
# nginx key fetched without dearmoring, repo added, nginx installed from the
# third-party repo, key and repo cleaned up after install.
set -e

source dev-container-features-test-lib

check "nginx is installed" command -v nginx
check "key file was cleaned up" bash -c '! test -f /usr/share/keyrings/nginx-signing.key'
check "repo file was cleaned up" bash -c '! test -f /etc/apt/sources.list.d/syspkg-installer.list'

reportResults
