#!/bin/sh

# Exit immediately when CONFIG_DIR is empty — symlink creation is disabled.
[ -n "${CONFIG_DIR:-}" ] || exit 0

symlink_codex_config_dir() {
  # $1 is the containerWorkspaceFolder variable,
  # passed directly by the devcontainer CLI — see metadata.yaml.
  _container_workspace_folder="${1}"
  _codex_config_dir="${_container_workspace_folder}/${CONFIG_DIR}"

  rm -rf ~/.codex
  mkdir -p "${_codex_config_dir}"
  ln -s "${_codex_config_dir}" ~/.codex

  # Write config.toml with any feature-level defaults — only when the file
  # does not already exist so user edits are never overwritten.
  if [ -n "${MODEL:-}" ] || [ -n "${APPROVAL_POLICY:-}" ] || [ -n "${SANDBOX_MODE:-}" ]; then
    _config_file="${_codex_config_dir}/config.toml"
    if [ ! -f "${_config_file}" ]; then
      : > "${_config_file}"
      [ -n "${MODEL:-}" ] && printf 'model = "%s"\n' "${MODEL}" >> "${_config_file}"
      [ -n "${APPROVAL_POLICY:-}" ] && printf 'approval_policy = "%s"\n' "${APPROVAL_POLICY}" >> "${_config_file}"
      [ -n "${SANDBOX_MODE:-}" ] && printf 'sandbox_mode = "%s"\n' "${SANDBOX_MODE}" >> "${_config_file}"
    fi
  fi
}

symlink_codex_config_dir "$1"
