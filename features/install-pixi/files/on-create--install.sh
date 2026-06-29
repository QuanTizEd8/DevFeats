#!/bin/sh

# Exit when install args are empty — pixi install is disabled.
[ -n "${INSTALL:-}" ] || exit 0

# eval re-parses INSTALL as shell words so quoted paths with spaces work,
# e.g. --manifest-path 'path/with spaces/pixi.toml'.
eval "pixi install ${INSTALL}" || warn "pixi install failed; skipping."
