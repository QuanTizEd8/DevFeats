#!/bin/bash
# Verifies that rootless Podman is fully functional for the vscode user:
# storage driver, per-user graphRoot on the named volume, and end-to-end
# container execution.
#
# This script runs as vscode (devcontainer.remoteUser: vscode).
# The feature entrypoint (postStartCommand) has already run before this
# script executes, so rshared mount and cgroup delegation are in place.
# The container must be privileged (metadata.yaml: privileged: true).
set -e

source dev-container-features-test-lib

# Verify Podman uses the correct storage driver and graphRoot.
check "podman info: overlay storage driver" \
  bash -c "podman info --format '{{.Store.GraphDriverName}}' | grep -Fx overlay"
check "podman info: graphRoot on named volume" \
  bash -c "podman info --format '{{.Store.GraphRoot}}' | grep -Fq '/var/lib/containers/storage/users/vscode'"

# Primary rootless Podman functional test: pull and run a container.
check "podman run hello-world succeeds" \
  podman run --rm docker.io/library/hello-world

reportResults
