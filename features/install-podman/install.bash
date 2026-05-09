# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"

_FILES_DIR="${_BASE_DIR}/files"

# ---------------------------------------------------------------------------
# 2. Ensure newuidmap / newgidmap have setuid bit
#
# The uidmap package ships these as setuid-root on Debian/Ubuntu.  Verify
# the bit is set — it is essential for rootless user-namespace creation.
# At runtime, privileged mode ensures nosuid is not applied.
# ---------------------------------------------------------------------------
chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap 2> /dev/null || true

# ---------------------------------------------------------------------------
# 3. Resolve user list
# ---------------------------------------------------------------------------
mapfile -t _RESOLVED_USERS < <(users__resolve_list)

if [ ${#_RESOLVED_USERS[@]} -eq 0 ]; then
  logging__info "install-podman: No users to configure."
fi

# ---------------------------------------------------------------------------
# 4. Write Podman configuration
#
# storage.conf (per-user): native overlay on a per-user subdirectory of the
# named volume (/var/lib/containers/storage/users/<username>).  Each user
# gets an isolated graphRoot, preventing ownership conflicts between root and
# non-root Podman runs.  The parent users/ directory is 1777 (sticky +
# world-writable) so each user can create their own subdirectory; Podman
# initialises the subdirectory itself with mode 0700 on first run.
# Written to each user's config dir because rootless Podman ignores the
# system-level graphRoot.
# ---------------------------------------------------------------------------
# Write system-level containers.conf.
# These settings are only required when running Podman as root. Rootless
# Podman already defaults to cgroupfs and file, but root defaults to the
# systemd cgroup manager and journald — neither of which is available inside
# a Docker container.
# - cgroup_manager=cgroupfs: no systemd inside the container, so the default
#   systemd manager would fail with cgroup.subtree_control errors at runtime.
# - events_logger=file: journald is not available inside the container.
mkdir -p /etc/containers
printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' \
  > /etc/containers/containers.conf

_STORAGE_BASE="/var/lib/containers/storage"
_USERS_DIR="${_STORAGE_BASE}/users"
# Create the per-user graphRoot parent on the image layer.  The entrypoint
# re-creates it at startup because the named volume shadows the image layer.
mkdir -p "${_USERS_DIR}"
chmod 1777 "${_USERS_DIR}"

SUBUID_OFFSET=100000
for _username in "${_RESOLVED_USERS[@]}"; do
  if ! id "$_username" > /dev/null 2>&1; then
    logging__info "install-podman: User '${_username}' does not exist — skipping."
    continue
  fi

  # Register subuid/subgid ranges (non-overlapping)
  if ! grep -q "^${_username}:" /etc/subuid 2> /dev/null; then
    echo "${_username}:${SUBUID_OFFSET}:65536" >> /etc/subuid
  fi
  if ! grep -q "^${_username}:" /etc/subgid 2> /dev/null; then
    echo "${_username}:${SUBUID_OFFSET}:65536" >> /etc/subgid
  fi
  SUBUID_OFFSET=$((SUBUID_OFFSET + 65536))

  # Write per-user storage.conf pointing at the user's own graphRoot subdir.
  # Podman creates the subdirectory on first run (mode 0700, owned by user).
  _user_graph_root="${_USERS_DIR}/${_username}"
  _home=$(eval echo "~${_username}")
  _config_dir="${_home}/.config/containers"
  mkdir -p "${_config_dir}"
  cat > "${_config_dir}/storage.conf" << EOF
[storage]
driver = "overlay"
graphRoot = "${_user_graph_root}"
EOF

  # Fix ownership so Podman can write to config dirs at runtime
  chown -R "${_username}:$(id -gn "$_username")" "${_home}/.config"
done

# ---------------------------------------------------------------------------
# 5. Install entrypoint:
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
# ---------------------------------------------------------------------------
_ENTRYPOINT_DEST="/usr/local/share/devfeats/install-podman/entrypoint.sh"
mkdir -p "$(dirname "$_ENTRYPOINT_DEST")"
cp "${_FILES_DIR}/entrypoint.sh" "$_ENTRYPOINT_DEST"
chmod +x "$_ENTRYPOINT_DEST"
