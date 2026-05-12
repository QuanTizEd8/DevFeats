_SHIM_BIN="${_FEAT_SHARE_DIR}/bin"

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"

# Write shim PATH exports to shell startup files.
_shim_export_path_main() {
  if [ "${#EXPORT_PATH[@]}" -eq 0 ]; then
    logging__info "export_path is empty; skipping PATH export."
    return 0
  fi
  shell__write_env_block \
    --opt "$(printf '%s\n' "${EXPORT_PATH[@]}")" \
    --profile-d "${_EXPORT_PROFILE_D}" \
    --marker "shim PATH (setup-shim)" \
    --content "export PATH=\"${_SHIM_BIN}:\${PATH}\""
  return 0
}

# ---------------------------------------------------------------------------
# Install shims
# ---------------------------------------------------------------------------
mkdir -p "${_SHIM_BIN}"

install_shim() {
  _src="${_FILES_DIR}/$1"
  _dst="${_SHIM_BIN}/$1"
  if [ ! -f "$_src" ]; then
    logging__error "setup-shim: source file not found: ${_src}"
    exit 1
  fi
  cp "$_src" "$_dst"
  chmod +rx "$_dst"
  logging__success "  $1 → ${_dst}"
  return
}

if [ "${CODE:-true}" = "true" ]; then
  install_shim "code"
fi

if [ "${DEVCONTAINER_INFO:-true}" = "true" ]; then
  install_shim "devcontainer-info"
fi

if [ "${SYSTEMCTL:-true}" = "true" ]; then
  install_shim "systemctl"
fi

# Make shims available for current process and persist PATH for future shells.
export PATH="${_SHIM_BIN}:${PATH}"
_shim_export_path_main

exit 0
