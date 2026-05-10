#!/bin/sh

warn() {
  printf 'install-podman entrypoint: WARN: %s\n' "$*" >&2
}

ensure_rshared_root() {
  # Unconditionally attempt mount --make-rshared (idempotent when / is already
  # rshared).  The pre-check (reading /proc/self/mountinfo) was removed because
  # macOS Docker Desktop's LinuxKit VM presents / as shared:N in the
  # container's mountinfo — causing the pre-check to return a false positive
  # and skip the call entirely — while Podman's internal rootless user-namespace
  # setup still checks propagation from a different context and sees it as
  # private.  Always calling the mount ensures the attempt is made; on macOS
  # Docker Desktop it will fail (error 5005) which is an OS-level restriction
  # that cannot be worked around from inside the container.
  if ! mount --make-rshared /; then
    warn "failed to set '/' mount propagation to rshared — rootless bind-mount propagation may break (expected on macOS Docker Desktop)"
    return 0
  fi
}

setup_cgroup_v2_delegation() {
  [ -f /sys/fs/cgroup/cgroup.controllers ] || return 0

  # mkdir -p on a cgroupfs path requires CAP_SYS_ADMIN; on macOS Docker Desktop
  # and other restricted environments this is denied even with privileged: true.
  # Capture stderr so mkdir's own error message doesn't bypass our warn function.
  if ! mkdir -p /sys/fs/cgroup/init 2> /dev/null; then
    warn "could not create /sys/fs/cgroup/init (permission denied) — cgroup v2 controller delegation skipped"
    return 0
  fi

  # Move all processes out of the cgroup v2 root so controllers can
  # be enabled for child cgroups (no-internal-process rule).
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true

  if ! sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
    > /sys/fs/cgroup/cgroup.subtree_control; then
    warn "failed to enable cgroup v2 controllers in /sys/fs/cgroup/cgroup.subtree_control"
  fi
}

ensure_graphroot_users_parent() {
  _USERS_DIR="/var/lib/containers/storage/users"
  # The named volume shadows the image layer when the container starts, so the
  # users/ parent directory must exist on the volume for each configured user
  # to be able to initialise their own graphRoot subdirectory on first Podman
  # run.  Podman creates the per-user subdirectory itself (mode 0700).
  if ! mkdir -p "$_USERS_DIR" 2> /dev/null; then
    warn "could not create $_USERS_DIR; per-user Podman storage may fail"
    return 0
  fi
  # chmod requires owning the directory.  When the feature entrypoint runs as a
  # non-root containerUser, it cannot chmod root-owned directories.  Skip the
  # chmod if permissions are already correct (1777) — this is the normal case
  # because the install script creates users/ with 1777 in the image layer and
  # Docker copies that into a fresh named volume on first use.  Only warn when
  # permissions are wrong AND cannot be fixed.
  _users_perms=$(stat -c '%a' "$_USERS_DIR" 2> /dev/null) || true
  if [ "$_users_perms" != "1777" ]; then
    chmod 1777 "$_USERS_DIR" 2> /dev/null ||
      warn "could not set permissions on $_USERS_DIR (current: ${_users_perms:-unknown}); per-user Podman storage may fail"
  fi
}

# Mark '/' as rshared so bind-mount propagation works inside rootless
# Podman user namespaces. Emit warnings if this cannot be enforced.
ensure_rshared_root || true

# cgroup v2: enable nested controller delegation. Docker places container
# processes in the cgroup root; this prevents subtree controller enablement
# until processes are moved out. Mirrors the Moby dind approach.
setup_cgroup_v2_delegation

# Ensure the per-user graphRoot parent exists on the named volume with the
# correct permissions so each configured user can initialise their own
# Podman storage subdirectory on first run.
ensure_graphroot_users_parent
