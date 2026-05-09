#!/bin/bash
# Verifies that rootless Podman is fully functional for a user configured
# via the add_users option.
#
# This script runs as root (no remoteUser set); it uses runuser to switch
# to devuser for Podman invocations.
# The feature entrypoint (postStartCommand) has already run before this
# script executes, so rshared mount and cgroup delegation are in place.
# The container must be privileged (metadata.yaml: privileged: true).
set -e

source dev-container-features-test-lib

# Verify Podman uses the correct storage driver and graphRoot for devuser.
check "podman info: overlay storage driver for devuser" \
  runuser -l devuser -c "podman info --format '{{.Store.GraphDriverName}}' | grep -Fx overlay"
check "podman info: graphRoot on named volume for devuser" \
  runuser -l devuser -c "podman info --format '{{.Store.GraphRoot}}' | grep -Fq '/var/lib/containers/storage/users/devuser'"

# Primary rootless Podman functional test: pull and run a container as devuser.
check "podman run hello-world as devuser" \
  runuser -l devuser -c "podman run --rm docker.io/library/hello-world"

reportResults
