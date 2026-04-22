#!/usr/bin/env bash
# Used by .github/workflows/ci.yaml test-features job: run inside the
# devcontainer image with --privileged so an inner dockerd can power
# `devcontainer features test`. See workflow comments for why DinD is required.
set -euo pipefail

FEATURE="${1:?usage: run-feature-tests-dind.sh <feature-name>}"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# GHA job containers bind-mount the runner's Docker socket at
# /var/run/docker.sock; plain `docker run` usually does not. If a host socket
# is present, remove it so clients use our inner dockerd only.
export container=docker
if [[ -d /sys/kernel/security ]] && ! mountpoint -q /sys/kernel/security; then
  mount -t securityfs none /sys/kernel/security 2> /dev/null || true
fi
if ! mountpoint -q /tmp; then
  mount -t tmpfs none /tmp 2> /dev/null || true
fi
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
  mkdir -p /sys/fs/cgroup/init
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2> /dev/null || true
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
    > /sys/fs/cgroup/cgroup.subtree_control 2> /dev/null || true
fi
mount --make-rshared / 2> /dev/null || true
find /run /var/run -iname 'docker*.pid' -delete 2> /dev/null || true
find /run /var/run -iname 'container*.pid' -delete 2> /dev/null || true
if mountpoint -q /var/run/docker.sock 2> /dev/null; then
  umount /var/run/docker.sock
elif [[ -e /var/run/docker.sock ]]; then
  rm -f /var/run/docker.sock
fi

DIND_ROOT="${REPO_ROOT}/.dind-docker"
mkdir -p "$DIND_ROOT"
dockerd --data-root "$DIND_ROOT" --storage-driver overlay2 > /tmp/dockerd.log 2>&1 &
timeout 60 sh -c 'until docker info >/dev/null 2>&1; do sleep 0.5; done'

exec bash test/run.sh feature "$FEATURE"
