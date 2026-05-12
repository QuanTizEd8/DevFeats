#!/bin/sh

warn() { printf 'install-claude postCreateCommand: WARN: %s\n' "$*" >&2; }
die() {
  printf 'install-claude postCreateCommand: ERROR: %s\n' "$*" >&2
  exit 1
}

# Source runtime configuration written by the installer at image-build time.
_CONF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").conf"
[ -f "$_CONF" ] || die "runtime config not found: ${_CONF}"
# shellcheck source=/dev/null
. "$_CONF"

symlink_claude_config_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"
  _claude_config_dir_fullpath="${_container_workspace_folder}/${CLAUDE_CONFIG_DIR}"

  rm -rf ~/.claude
  mkdir -p "$_claude_config_dir_fullpath"
  ln -s "$_claude_config_dir_fullpath" ~/.claude
}

symlink_claude_config_dir "$1"
