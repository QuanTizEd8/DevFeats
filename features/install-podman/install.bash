# shellcheck shell=bash

_USERS_DIR="/var/lib/containers/storage/users"

__install_run__() {
  # ---------------------------------------------------------------------------
  # 1. Devcontainer-context detection
  #
  # os__is_devcontainer_build() (lib/os.sh) returns 0 when this script is
  # invoked by the devcontainer CLI.  When true:
  #   - containers.conf is forced to cgroupfs/file (no systemd inside Docker).
  #   - The per-user graphRoot is redirected to the named volume.
  #   - The startup entrypoint script is installed.
  # When false (standalone / host / SysSet):
  #   - containers.conf is left to Podman's defaults (correct for systemd).
  #   - The per-user graphRoot stays at ~/.local/share/containers/storage.
  #   - No entrypoint is installed (nothing calls it outside a devcontainer).
  # ---------------------------------------------------------------------------
  if os__is_devcontainer_build; then
    logging__install "Configuring Podman for devcontainer build."
  else
    logging__install "Configuring Podman for standalone/host install."
  fi

  # ---------------------------------------------------------------------------
  # 2. Ensure newuidmap / newgidmap have setuid bit
  #
  # The uidmap package ships these as setuid-root on Debian/Ubuntu.  Verify
  # the bit is set — it is essential for rootless user-namespace creation.
  # At runtime, privileged mode ensures nosuid is not applied.
  # Use command -v to locate the binaries: on Fedora/RHEL/Alpine they may
  # live in /usr/sbin or /sbin rather than /usr/bin.
  # ---------------------------------------------------------------------------
  logging__inspect "Ensuring newuidmap/newgidmap have setuid bit."
  users__ensure_setuid newuidmap newgidmap

  # ---------------------------------------------------------------------------
  # 4. Write Podman configuration
  # ---------------------------------------------------------------------------

  # Devcontainer-only: force cgroupfs/file in system containers.conf.
  # Rootless Podman already defaults to these, but root Podman defaults to
  # the systemd cgroup manager and journald — neither available in Docker.
  # On a host/standalone, systemd manages cgroups; overriding would break
  # root Podman, so we leave containers.conf to Podman's own defaults.
  if os__is_devcontainer_build; then
    logging__install "Writing devcontainer containers.conf (cgroupfs/file)."
    file__mkdir /etc/containers
    printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' |
      file__tee /etc/containers/containers.conf
  else
    logging__skip "Standalone/host install; leaving system containers.conf at Podman defaults."
  fi

  # Devcontainer-only: create the shared graphRoot parent directory on the
  # image layer so it lands on the named volume with the correct permissions.
  # The entrypoint re-creates it at startup (the volume shadows the image layer).
  # On standalone, Podman uses ~/.local/share/containers/storage by default.
  if os__is_devcontainer_build; then
    logging__install "Creating shared graphRoot parent '${_USERS_DIR}'."
    file__mkdir "${_USERS_DIR}"
    file__chmod 1777 "${_USERS_DIR}"
  else
    logging__skip "Standalone/host install; using default per-user graphRoot."
  fi

  # ---------------------------------------------------------------------------
  # 5. Install entrypoint (devcontainer-only).
  #    a) Mark "/" as rshared so bind-mount propagation works inside
  #       rootless Podman's user namespace.
  #    b) On cgroup v2, enable controller delegation so root Podman can
  #       create and manage its libpod_parent cgroup hierarchy.  Docker
  #       places container processes in the root cgroup; the kernel's
  #       "no internal process" rule then blocks writes to subtree_control
  #       (EBUSY).  Moving processes to /sys/fs/cgroup/init/ makes the
  #       root cgroup process-free, allowing all available controllers to
  #       be enabled.  Mirrors the Moby docker-in-docker entrypoint:
  #       https://github.com/moby/moby/blob/master/hack/dind
  #
  # On standalone/host, systemd handles mount propagation and cgroup
  # delegation; the entrypoint is not installed (nothing would call it).
  # ---------------------------------------------------------------------------

  logging__success "Podman system configuration complete."
}

__configure_user() {
  local _username="$1"
  local _home _config_dir _group

  logging__info "Configuring Podman for user '${_username}'."

  # Register subuid/subgid ranges (non-overlapping).
  # Probe the current high-water mark of each file immediately before
  # appending so the new range never collides with entries already present
  # in the base image or written by a prior iteration of this loop.
  if ! grep -q "^${_username}:" /etc/subuid 2> /dev/null; then
    logging__install "Registering subuid range for '${_username}'."
    printf '%s:%s:65536\n' "${_username}" "$(users__next_subid_offset /etc/subuid)" |
      file__tee --append /etc/subuid
  else
    logging__skip "subuid entry already present for '${_username}'."
  fi
  if ! grep -q "^${_username}:" /etc/subgid 2> /dev/null; then
    logging__install "Registering subgid range for '${_username}'."
    printf '%s:%s:65536\n' "${_username}" "$(users__next_subid_offset /etc/subgid)" |
      file__tee --append /etc/subgid
  else
    logging__skip "subgid entry already present for '${_username}'."
  fi

  _home=$(users__resolve_home "$_username")
  _config_dir="${_home}/.config/containers"
  _group="$(users__primary_group_of "$_username")"
  # Always create Podman config dirs with correct ownership.
  # `install -d -o/-g` creates missing directories and sets ownership/mode in
  # one step — no separate chown pass needed.
  # cni/ is needed at runtime for network plugin config.
  logging__install "Creating Podman config directories for '${_username}' at '${_config_dir}'."
  file__install_dir --owner "${_username}" --group "${_group}" --mode 0755 \
    "${_home}/.config" \
    "${_config_dir}" \
    "${_home}/.config/cni"

  # Devcontainer-only: redirect graphRoot to the named volume.
  # On standalone/host, Podman's default (~/.local/share/containers/storage)
  # is correct — no storage.conf is written.
  if os__is_devcontainer_build; then
    local _user_graph_root="${_USERS_DIR}/${_username}"
    logging__install "Writing devcontainer storage.conf for '${_username}' (graphRoot='${_user_graph_root}')."
    printf '[storage]\ndriver = "overlay"\ngraphRoot = "%s"\n' "${_user_graph_root}" |
      file__tee "${_config_dir}/storage.conf"
    file__chown "${_username}:${_group}" "${_config_dir}/storage.conf"
  else
    logging__skip "Standalone/host install; using default graphRoot for '${_username}'."
  fi

  logging__success "Podman user configuration complete for '${_username}'."
}

__install_finish_post() {
  logging__info "Running per-user Podman configuration."
  __feat_do_configure_users__
}
