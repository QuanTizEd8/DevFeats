os__require_root

if [[ ! "$USER_ID" =~ ^[0-9]+$ ]]; then
  logging__error "user_id must be a non-negative integer, got: '${USER_ID}'"
  exit 1
fi

if [[ ! "$GROUP_ID" =~ ^[0-9]+$ ]]; then
  logging__error "group_id must be a non-negative integer, got: '${GROUP_ID}'"
  exit 1
fi

if [ ! -x "$USER_SHELL" ]; then
  logging__error "Shell '${USER_SHELL}' does not exist or is not executable on this image."
  exit 1
fi

# Values derived from USERNAME
[ -z "$GROUP_NAME" ] && GROUP_NAME="$USERNAME"
[ -z "$HOME_DIR" ] && HOME_DIR="/home/${USERNAME}"

# ---------------------------------------------------------------------------
# Resolve conflicts for the primary group
# ---------------------------------------------------------------------------

_group_already_ok=false
_group_by_gid=$(getent group | awk -F: -v gid="$GROUP_ID" '$3 == gid {print $1}' || true)
_gid_of_name=$(getent group "$GROUP_NAME" 2> /dev/null | cut -d: -f3 || true)

if [ -n "$_gid_of_name" ] && [ "$_gid_of_name" = "$GROUP_ID" ]; then
  # Group already correctly configured
  logging__info "Group '${GROUP_NAME}' (GID ${GROUP_ID}) already exists."
  _group_already_ok=true
elif [ -n "$_gid_of_name" ] && [ "$_gid_of_name" != "$GROUP_ID" ]; then
  # Group name exists but with the wrong GID
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "Group '${GROUP_NAME}' has GID ${_gid_of_name} (want ${GROUP_ID}) — removing."
    groupdel "$GROUP_NAME" 2> /dev/null || logging__warn "Failed to delete group '${GROUP_NAME}'."
  else
    logging__error "Group '${GROUP_NAME}' exists with GID ${_gid_of_name} (want ${GROUP_ID}). Set replace_existing=true to override."
    exit 1
  fi
elif [ -n "$_group_by_gid" ] && [ "$_group_by_gid" != "$GROUP_NAME" ]; then
  # GID is occupied by a different group
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "GID ${GROUP_ID} is in use by group '${_group_by_gid}' — removing members and group."
    while IFS= read -r _u; do
      [ -z "$_u" ] && continue
      logging__info "Removing user '${_u}' (primary group conflict)."
      userdel "$_u" 2> /dev/null || logging__warn "Failed to remove user '${_u}'."
    done < <(awk -F: -v gid="$GROUP_ID" '$4 == gid {print $1}' /etc/passwd)
    # userdel on Debian/Ubuntu auto-removes the primary group, so guard the call.
    if getent group "$_group_by_gid" > /dev/null 2>&1; then
      groupdel "$_group_by_gid" 2> /dev/null || logging__warn "Failed to delete group '${_group_by_gid}'."
    fi
  else
    logging__error "GID ${GROUP_ID} is already used by group '${_group_by_gid}'. Set replace_existing=true to override."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Resolve conflicts for the user account
# ---------------------------------------------------------------------------
_user_already_ok=false
_user_by_uid=$(awk -F: -v uid="$USER_ID" '$3 == uid {print $1}' /etc/passwd || true)
_uid_of_name=$(users__uid_of_user "$USERNAME" 2> /dev/null || true)

if [ -n "$_uid_of_name" ] && [ "$_uid_of_name" = "$USER_ID" ]; then
  # User already correctly configured
  logging__info "User '${USERNAME}' (UID ${USER_ID}) already exists."
  _user_already_ok=true
elif [ -n "$_uid_of_name" ] && [ "$_uid_of_name" != "$USER_ID" ]; then
  # Username exists but has the wrong UID
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "User '${USERNAME}' has UID ${_uid_of_name} (want ${USER_ID}) — removing."
    userdel "$USERNAME" 2> /dev/null || logging__warn "Failed to remove user '${USERNAME}'."
  else
    logging__error "User '${USERNAME}' exists with UID ${_uid_of_name} (want ${USER_ID}). Set replace_existing=true to override."
    exit 1
  fi
elif [ -n "$_user_by_uid" ] && [ "$_user_by_uid" != "$USERNAME" ]; then
  # UID is occupied by a different user
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "UID ${USER_ID} is in use by '${_user_by_uid}' — removing."
    userdel "$_user_by_uid" 2> /dev/null || logging__warn "Failed to remove user '${_user_by_uid}'."
  else
    logging__error "UID ${USER_ID} is already used by user '${_user_by_uid}'. Set replace_existing=true to override."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Create primary group
# ---------------------------------------------------------------------------
if [ "$_group_already_ok" != "true" ]; then
  logging__info "Creating group '${GROUP_NAME}' (GID ${GROUP_ID})."
  groupadd --gid "$GROUP_ID" "$GROUP_NAME"
fi

# ---------------------------------------------------------------------------
# Create user
# ---------------------------------------------------------------------------
if [ "$_user_already_ok" != "true" ]; then
  logging__info "Creating user '${USERNAME}' (UID=${USER_ID} GID=${GROUP_ID} home=${HOME_DIR} shell=${USER_SHELL})."
  useradd \
    --no-create-home \
    --home-dir "$HOME_DIR" \
    --gid "$GROUP_ID" \
    --shell "$USER_SHELL" \
    --uid "$USER_ID" \
    "$USERNAME"
fi

# Ensure home directory exists with correct ownership and skel contents
if [ ! -d "$HOME_DIR" ]; then
  mkdir -p "$HOME_DIR"
  cp -rn /etc/skel/. "$HOME_DIR/" 2> /dev/null || true
  chown -R "${USERNAME}:${GROUP_NAME}" "$HOME_DIR"
  logging__info "Created home directory '${HOME_DIR}'."
else
  chown "${USERNAME}:${GROUP_NAME}" "$HOME_DIR"
  logging__info "Home directory '${HOME_DIR}' already exists — ownership set."
fi

# ---------------------------------------------------------------------------
# Sudo access
# ---------------------------------------------------------------------------
if [ "$SUDO_ACCESS" = "true" ]; then
  _dep_install_runtime_sudo
  mkdir -p "$SUDOERS_DIR"
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_DIR}/${USERNAME}"
  chmod 0440 "${SUDOERS_DIR}/${USERNAME}"
  if command -v visudo > /dev/null 2>&1; then
    visudo -c -f "${SUDOERS_DIR}/${USERNAME}" || {
      logging__error "sudoers file validation failed."
      rm -f "${SUDOERS_DIR}/${USERNAME}"
      exit 1
    }
  fi
  logging__success "Granted passwordless sudo to '${USERNAME}'."
fi

# ---------------------------------------------------------------------------
# Supplementary groups
# ---------------------------------------------------------------------------
if [ "${#EXTRA_GROUPS[@]}" -gt 0 ]; then
  for _grp in "${EXTRA_GROUPS[@]}"; do
    _grp="${_grp// /}" # trim spaces
    [ -z "$_grp" ] && continue
    if ! getent group "$_grp" > /dev/null 2>&1; then
      logging__warn "Supplementary group '${_grp}' does not exist — skipping."
      continue
    fi
    usermod -aG "$_grp" "$USERNAME"
    logging__success "Added '${USERNAME}' to group '${_grp}'."
  done
fi

logging__success "User '${USERNAME}' (UID=${USER_ID}, GID=${GROUP_ID}) configured successfully."
