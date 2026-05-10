#!/bin/bash
# Standalone install with an explicit add_users target (devuser).
# Invoked directly — no _REMOTE_USER. Verifies per-user Podman config dirs
# are created with correct ownership and that devcontainer-specific artifacts
# (containers.conf override, graphRoot redirect, entrypoint) are NOT written.
set -e

source dev-container-features-test-lib

# --- packages ---
check "podman is installed" command -v podman

# --- devuser subuid/subgid ---
check "devuser in /etc/subuid" grep -q "^devuser:" /etc/subuid
check "devuser in /etc/subgid" grep -q "^devuser:" /etc/subgid

# --- devuser config dirs created with correct ownership ---
check "devuser .config/containers exists" test -d /home/devuser/.config/containers
check "devuser .config/cni exists" test -d /home/devuser/.config/cni
check "devuser .config/containers owned by devuser" bash -c '[ "$(stat -c %U /home/devuser/.config/containers)" = "devuser" ]'
check "devuser .config/cni owned by devuser" bash -c '[ "$(stat -c %U /home/devuser/.config/cni)" = "devuser" ]'

# --- devcontainer-specific artifacts must be absent ---
check "containers.conf NOT written" bash -c '! test -f /etc/containers/containers.conf'
check "devuser storage.conf NOT written" bash -c '! test -f /home/devuser/.config/containers/storage.conf'
check "entrypoint NOT installed" bash -c '! test -f /usr/local/share/devfeats/install-podman/entrypoint.sh'

reportResults
