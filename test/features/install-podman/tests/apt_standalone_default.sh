#!/bin/bash
# Standalone install with default options; no devcontainer CLI context.
# The install script is invoked directly (no _REMOTE_USER injection).
# Root is the configured user via the add_current_user fallback:
# no non-root users exist, so root is included as the last resort.
# Verifies that packages and per-user infra are installed correctly,
# and that devcontainer-specific artifacts are NOT written.
set -e

source dev-container-features-test-lib

# --- packages ---
check "podman is installed" command -v podman
check "slirp4netns is installed" command -v slirp4netns
check "newuidmap is installed" command -v newuidmap
check "newgidmap is installed" command -v newgidmap

# --- setuid bits ---
check "newuidmap is setuid root" bash -c 'test -u "$(command -v newuidmap)"'
check "newgidmap is setuid root" bash -c 'test -u "$(command -v newgidmap)"'

# --- root subuid/subgid ---
check "root in /etc/subuid" grep -q "^root:" /etc/subuid
check "root in /etc/subgid" grep -q "^root:" /etc/subgid

# --- root config dirs created with correct ownership ---
check "root .config/containers exists" test -d /root/.config/containers
check "root .config/cni exists" test -d /root/.config/cni

# --- devcontainer-specific artifacts must be absent ---
check "containers.conf NOT written" bash -c '! test -f /etc/containers/containers.conf'
check "root storage.conf NOT written" bash -c '! test -f /root/.config/containers/storage.conf'
check "entrypoint NOT installed" bash -c '! test -f /usr/local/share/devfeats/install-podman/entrypoint.sh'

reportResults
