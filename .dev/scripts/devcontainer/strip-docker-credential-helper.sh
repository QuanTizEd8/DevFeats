#!/usr/bin/env bash
# Remove stale dev-containers-* credsStore injected by VS Code/Cursor Dev Containers.
#
# Safe to run repeatedly. Preserves auths and credHelpers; only strips the IDE
# credential bridge that breaks in agent shells and after /tmp cleanup.
set -euo pipefail

_cfg="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
[[ -f "$_cfg" ]] || exit 0

_store="$(jq -r '.credsStore // empty' "$_cfg")"
[[ "$_store" == dev-containers-* ]] || exit 0

_tmp="${_cfg}.tmp.$$"
jq 'del(.credsStore)' "$_cfg" > "$_tmp"
mv "$_tmp" "$_cfg"
printf 'Removed stale dev-containers credsStore from %s\n' "$_cfg" >&2
