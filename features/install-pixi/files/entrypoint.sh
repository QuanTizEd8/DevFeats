#!/bin/sh
# install-pixi entrypoint
# Runs as root (containerUser) at container start via the devcontainer CLI.
# Fixes ownership of the .pixi workspace volume mount so the configured
# remote user can write to it (Docker creates named volumes owned by root).

warn() { printf 'install-pixi entrypoint: WARN: %s\n' "$*" >&2; }
die() {
  printf 'install-pixi entrypoint: ERROR: %s\n' "$*" >&2
  exit 1
}

# Source runtime configuration written by the installer at image-build time.
_CONF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").conf"
[ -f "$_CONF" ] || die "runtime config not found: ${_CONF}"
# shellcheck source=/dev/null
. "$_CONF"

fix_pixi_volume_ownership() {
  [ -n "${PIXI_VOLUME_USER:-}" ] || return 0
  # $1 is the .pixi volume mount path (containerWorkspaceFolder/.pixi), passed
  # directly by the devcontainer CLI — see the entrypoint field in metadata.yaml.
  _pixi_dir="${1}"
  if [ ! -d "$_pixi_dir" ]; then
    warn "'${_pixi_dir}' is not a directory; the .pixi volume may not be mounted"
    return 1
  fi
  if ! chown "${PIXI_VOLUME_USER}:" "$_pixi_dir" 2> /dev/null; then
    # Direct chown failed (entrypoint may not be running as root).
    # Try sudo for environments where the entrypoint user has passwordless sudo.
    if ! sudo chown "${PIXI_VOLUME_USER}:" "$_pixi_dir" 2> /dev/null; then
      warn "could not chown '${_pixi_dir}' to '${PIXI_VOLUME_USER}'; the container user may not be able to write to it"
    fi
  fi
}

fix_pixi_volume_ownership "$1"
