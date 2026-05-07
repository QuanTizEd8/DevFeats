#!/usr/bin/env bash
# Thin yq wrapper for reading .dev/config/ YAML files.
# Usage: config_get <file> <key>
# Example: config_get ci image.suffix

config_get() {
  local file="${1:?config_get requires a file argument (e.g. ci, project)}"
  local key="${2:?config_get requires a key argument (e.g. image.suffix)}"
  yq e ".${key}" "${REPO_ROOT}/.dev/config/${file}.yaml"
}
