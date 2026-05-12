# shellcheck source=lib/os.sh
. "$_SELF_DIR/_lib/os.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"
# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/file.sh
. "$_SELF_DIR/_lib/file.sh"

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

# ---------------------------------------------------------------------------
# 2. Ensure newuidmap / newgidmap have setuid bit
#
# The uidmap package ships these as setuid-root on Debian/Ubuntu.  Verify
# the bit is set — it is essential for rootless user-namespace creation.
# At runtime, privileged mode ensures nosuid is not applied.
# Use command -v to locate the binaries: on Fedora/RHEL/Alpine they may
# live in /usr/sbin or /sbin rather than /usr/bin.
# ---------------------------------------------------------------------------
users__ensure_setuid newuidmap newgidmap

# ---------------------------------------------------------------------------
# 3. Resolve user list
# ---------------------------------------------------------------------------
mapfile -t _RESOLVED_USERS < <(users__resolve_list)

if [ ${#_RESOLVED_USERS[@]} -eq 0 ]; then
  logging__info "install-podman: No users to configure."
fi

# ---------------------------------------------------------------------------
# 4. Write Podman configuration
# ---------------------------------------------------------------------------

# Devcontainer-only: force cgroupfs/file in system containers.conf.
# Rootless Podman already defaults to these, but root Podman defaults to
# the systemd cgroup manager and journald — neither available in Docker.
# On a host/standalone, systemd manages cgroups; overriding would break
# root Podman, so we leave containers.conf to Podman's own defaults.
if os__is_devcontainer_build; then
  mkdir -p /etc/containers
  printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' \
    > /etc/containers/containers.conf
fi

# Devcontainer-only: create the shared graphRoot parent directory on the
# image layer so it lands on the named volume with the correct permissions.
# The entrypoint re-creates it at startup (the volume shadows the image layer).
# On standalone, Podman uses ~/.local/share/containers/storage by default.
if os__is_devcontainer_build; then
  _STORAGE_BASE="/var/lib/containers/storage"
  _USERS_DIR="${_STORAGE_BASE}/users"
  mkdir -p "${_USERS_DIR}"
  chmod 1777 "${_USERS_DIR}"
fi

for _username in "${_RESOLVED_USERS[@]}"; do
  if ! id "$_username" > /dev/null 2>&1; then
    logging__info "install-podman: User '${_username}' does not exist — skipping."
    continue
  fi

  # Register subuid/subgid ranges (non-overlapping).
  # Probe the current high-water mark of each file immediately before
  # appending so the new range never collides with entries already present
  # in the base image or written by a prior iteration of this loop.
  if ! grep -q "^${_username}:" /etc/subuid 2> /dev/null; then
    echo "${_username}:$(users__next_subid_offset /etc/subuid):65536" >> /etc/subuid
  fi
  if ! grep -q "^${_username}:" /etc/subgid 2> /dev/null; then
    echo "${_username}:$(users__next_subid_offset /etc/subgid):65536" >> /etc/subgid
  fi

  _home=$(shell__resolve_home "$_username")
  _config_dir="${_home}/.config/containers"
  _group="$(id -gn "$_username")"
  # Always create Podman config dirs with correct ownership.
  # `install -d -o/-g` creates missing directories and sets ownership/mode in
  # one step — no separate chown pass needed.
  # cni/ is needed at runtime for network plugin config.
  file__install_dir --owner "${_username}" --group "${_group}" --mode 0755 \
    "${_home}/.config" \
    "${_config_dir}" \
    "${_home}/.config/cni"

  # Devcontainer-only: redirect graphRoot to the named volume.
  # On standalone/host, Podman's default (~/.local/share/containers/storage)
  # is correct — no storage.conf is written.
  if os__is_devcontainer_build; then
    _user_graph_root="${_USERS_DIR}/${_username}"
    cat > "${_config_dir}/storage.conf" << EOF
[storage]
driver = "overlay"
graphRoot = "${_user_graph_root}"
EOF
    chown "${_username}:${_group}" "${_config_dir}/storage.conf"
  fi
done

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
if os__is_devcontainer_build; then
  _ENTRYPOINT_DEST="${_FEAT_SHARE_DIR}/entrypoint.sh"
  mkdir -p "${_FEAT_SHARE_DIR}"
  cp "${_FILES_DIR}/entrypoint.sh" "$_ENTRYPOINT_DEST"
  chmod +x "$_ENTRYPOINT_DEST"
fi
