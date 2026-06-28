# shellcheck shell=bash

# shellcheck disable=SC2329,SC2317
__configure_user() {
  local _user="$1"
  local _home
  _home="$(users__resolve_home "$_user")"
  local _bash_zsh_content="" _fish_content="" _tcsh_content="" _elvish_content=""
  if [[ -n "${COPILOT_HOME:-}" ]]; then
    local _copilot_home
    _copilot_home="$(users__expand_path --user "$_user" "${COPILOT_HOME}")"
    _bash_zsh_content+="export COPILOT_HOME=${_copilot_home}"$'\n'
    _fish_content+="set -gx COPILOT_HOME ${_copilot_home}"$'\n'
    _tcsh_content+="setenv COPILOT_HOME ${_copilot_home}"$'\n'
    _elvish_content+="set-env COPILOT_HOME ${_copilot_home}"$'\n'
  fi
  if [[ -n "${COPILOT_MODEL:-}" ]]; then
    _bash_zsh_content+="export COPILOT_MODEL=${COPILOT_MODEL}"$'\n'
    _fish_content+="set -gx COPILOT_MODEL ${COPILOT_MODEL}"$'\n'
    _tcsh_content+="setenv COPILOT_MODEL ${COPILOT_MODEL}"$'\n'
    _elvish_content+="set-env COPILOT_MODEL ${COPILOT_MODEL}"$'\n'
  fi
  if [[ -n "${_bash_zsh_content}${_fish_content}${_tcsh_content}${_elvish_content}" ]]; then
    local -a _sc_args=(
      --scope user --home "$_home"
      --marker "install-copilot-env" --profile-d "install-copilot.sh"
    )
    [[ -n "$_bash_zsh_content" ]] && _sc_args+=(
      --bash-content "$_bash_zsh_content" --bash-everywhere
      --zsh-content "$_bash_zsh_content" --zsh-everywhere
    )
    [[ -n "$_fish_content" ]] && _sc_args+=(--fish-content "$_fish_content")
    [[ -n "$_tcsh_content" ]] && _sc_args+=(--tcsh-content "$_tcsh_content")
    [[ -n "$_elvish_content" ]] && _sc_args+=(--elvish-content "$_elvish_content")
    shell__sync_config "${_sc_args[@]}"
  fi
  # In devcontainer builds plugin installation is deferred to postCreateCommand.
  # In standalone installs there is no lifecycle hook, so install immediately.
  os__is_devcontainer_build && return 0
  local _plugin
  for _plugin in "${PLUGINS[@]+"${PLUGINS[@]}"}"; do
    [[ -z "$_plugin" ]] && continue
    logging__install "Installing Copilot plugin '${_plugin}' for user '${_user}'..."
    if [[ "$_user" != "$(users__get_current --no-sudo)" ]]; then
      users__run_as "$_user" -- bash -c "copilot plugin install '${_plugin}'" || {
        logging__warn "Failed to install Copilot plugin '${_plugin}' for '${_user}' (non-fatal)."
      }
    else
      copilot plugin install "${_plugin}" || {
        logging__warn "Failed to install Copilot plugin '${_plugin}' (non-fatal)."
      }
    fi
  done
}

# shellcheck disable=SC2329,SC2317
_write_plugins_list() {
  os__is_devcontainer_build || return 0
  local _dest="${_FEAT_LIFECYCLE_POST_CREATE}install-plugins.sh.plugins"
  : > "${_dest}"
  local _plugin
  for _plugin in "${PLUGINS[@]+"${PLUGINS[@]}"}"; do
    [[ -z "$_plugin" ]] && continue
    printf '%s\n' "$_plugin" >> "${_dest}"
  done
}

# shellcheck disable=SC2329,SC2317
__install_finish_post() {
  __feat_do_configure_users__
  _write_plugins_list
}

# shellcheck disable=SC2329,SC2317
__skip_post() {
  __feat_do_configure_users__
  _write_plugins_list
}

# shellcheck disable=SC2329,SC2317
__uninstall_finish_post() {
  local -a _users=()
  mapfile -t _users < <(users__resolve_list)
  local _user _home
  for _user in "${_users[@]+"${_users[@]}"}"; do
    users__uid_of_user "${_user}" > /dev/null 2>&1 || continue
    _home="$(users__resolve_home "${_user}")"
    shell__sync_config \
      --scope user --home "$_home" \
      --marker "install-copilot-env" --profile-d "install-copilot.sh" \
      bash zsh fish tcsh elvish
  done
}
