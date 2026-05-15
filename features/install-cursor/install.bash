# shellcheck source=lib/os.sh
. "${_BASE_DIR}/_lib/os.sh"

if os__is_devcontainer_build; then
  _ON_CREATE_SCRIPT_NAME="lifecycle--on-create--symlink-cursor-user-dir.sh"
  _ON_CREATE_SCRIPT_DEST="${_FEAT_SHARE_DIR}/${_ON_CREATE_SCRIPT_NAME}"
  mkdir -p "$(dirname "$_ON_CREATE_SCRIPT_DEST")"
  cp "${_FILES_DIR}/${_ON_CREATE_SCRIPT_NAME}" "$_ON_CREATE_SCRIPT_DEST"
  chmod +x "$_ON_CREATE_SCRIPT_DEST"
  printf 'CURSOR_USER_DIR="%s"\n' "${CURSOR_USER_DIR}" \
    > "${_FEAT_SHARE_DIR}/${_ON_CREATE_SCRIPT_NAME}.conf"
fi
