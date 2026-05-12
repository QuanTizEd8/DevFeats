#!/bin/sh

warn() { printf 'install-codex postCreateCommand: WARN: %s\n' "$*" >&2; }
die() {
  printf 'install-codex postCreateCommand: ERROR: %s\n' "$*" >&2
  exit 1
}

# Source runtime configuration written by the installer at image-build time.
_CONF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").conf"
[ -f "$_CONF" ] || die "runtime config not found: ${_CONF}"
# shellcheck source=/dev/null
. "$_CONF"

symlink_codex_config_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"
  _codex_config_dir_fullpath="${_container_workspace_folder}/${CODEX_HOME}"

  rm -rf ~/.codex
  mkdir -p "$_codex_config_dir_fullpath"
  ln -s "$_codex_config_dir_fullpath" ~/.codex
}

symlink_codex_config_dir "$1"
