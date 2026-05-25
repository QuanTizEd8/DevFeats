if [ ! -x "$USER_SHELL" ]; then
  logging__error "Shell '${USER_SHELL}' does not exist or is not executable on this image."
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve conflicts for the primary group
# ---------------------------------------------------------------------------

_group_already_ok=false
_group_by_gid=$(users__group_of_gid "$GROUP_ID" 2> /dev/null || true)
_gid_of_name=$(users__gid_of_group "$GROUP_NAME" 2> /dev/null || true)

if [ -n "$_gid_of_name" ] && [ "$_gid_of_name" = "$GROUP_ID" ]; then
  # Group already correctly configured
  logging__info "Group '${GROUP_NAME}' (GID ${GROUP_ID}) already exists."
  _group_already_ok=true
elif [ -n "$_gid_of_name" ] && [ "$_gid_of_name" != "$GROUP_ID" ]; then
  # Group name exists but with the wrong GID
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "Group '${GROUP_NAME}' has GID ${_gid_of_name} (want ${GROUP_ID}) — removing."
    users__delete_group "$GROUP_NAME" || true
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
      users__delete_user "$_u" || true
    done < <(users__users_by_primary_gid "$GROUP_ID")
    # userdel on Debian/Ubuntu auto-removes the primary group, so guard the call.
    if users__group_exists "$_group_by_gid"; then
      users__delete_group "$_group_by_gid" || true
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
_user_by_uid=$(users__username_of_uid "$USER_ID" 2> /dev/null || true)
_uid_of_name=$(users__uid_of_user "$USERNAME" 2> /dev/null || true)

if [ -n "$_uid_of_name" ] && [ "$_uid_of_name" = "$USER_ID" ]; then
  # User already correctly configured
  logging__info "User '${USERNAME}' (UID ${USER_ID}) already exists."
  _user_already_ok=true
elif [ -n "$_uid_of_name" ] && [ "$_uid_of_name" != "$USER_ID" ]; then
  # Username exists but has the wrong UID
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "User '${USERNAME}' has UID ${_uid_of_name} (want ${USER_ID}) — removing."
    users__delete_user "$USERNAME" || true
  else
    logging__error "User '${USERNAME}' exists with UID ${_uid_of_name} (want ${USER_ID}). Set replace_existing=true to override."
    exit 1
  fi
elif [ -n "$_user_by_uid" ] && [ "$_user_by_uid" != "$USERNAME" ]; then
  # UID is occupied by a different user
  if [ "$REPLACE_EXISTING" = "true" ]; then
    logging__inspect "UID ${USER_ID} is in use by '${_user_by_uid}' — removing."
    users__delete_user "$_user_by_uid" || true
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
  users__create_group "$GROUP_NAME" --gid "$GROUP_ID"
  logging__success "Group '${GROUP_NAME}' (GID ${GROUP_ID}) created."
fi

# ---------------------------------------------------------------------------
# Create user
# ---------------------------------------------------------------------------
if [ "$_user_already_ok" != "true" ]; then
  logging__info "Creating user '${USERNAME}' (UID=${USER_ID} GID=${GROUP_ID} home=${HOME_DIR} shell=${USER_SHELL})."
  users__create_user "$USERNAME" \
    --no-create-home \
    --home "$HOME_DIR" \
    --gid "$GROUP_ID" \
    --shell "$USER_SHELL" \
    --uid "$USER_ID"
  logging__success "User '${USERNAME}' (UID=${USER_ID}) created."
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
    if ! users__group_exists "$_grp"; then
      logging__warn "Supplementary group '${_grp}' does not exist — skipping."
      continue
    fi
    users__add_to_group "$USERNAME" "$_grp"
    logging__success "Added '${USERNAME}' to group '${_grp}'."
  done
fi

logging__success "User '${USERNAME}' (UID=${USER_ID}, GID=${GROUP_ID}) configured successfully."
