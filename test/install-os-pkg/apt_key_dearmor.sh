#!/bin/bash
# Verifies the full key+repo+package lifecycle with a dearmored (.gpg) key:
# ASCII-armored nginx key fetched and converted to binary GPG format, repo
# added, nginx installed from the third-party repo, key and repo cleaned up.
set -e

source dev-container-features-test-lib

check "nginx is installed"       command -v nginx
check "key file was cleaned up"  bash -c '! test -f /usr/share/keyrings/nginx-archive-keyring.gpg'
check "repo file was cleaned up" bash -c '! test -f /etc/apt/sources.list.d/syspkg-installer.list'

reportResults
