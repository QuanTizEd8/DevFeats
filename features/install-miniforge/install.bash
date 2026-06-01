# shellcheck shell=bash

# Invoked by the generated prefix activation system for each configured shell.
# shellcheck disable=SC2329,SC2317
prefix_activation_snippet() {
  local _shell="$1"
  local _tmpdir _f _snippet
  _tmpdir="$(mktemp -d)"
  HOME="$_tmpdir" "${PREFIX}/bin/conda" init "$_shell" > /dev/null 2>&1 || true
  for _f in "$_tmpdir"/.bashrc "$_tmpdir"/.bash_profile \
    "$_tmpdir"/.zshrc "$_tmpdir"/.zprofile; do
    if [[ -f "$_f" && -s "$_f" ]]; then
      _snippet="$(cat "$_f")"
      rm -rf "$_tmpdir"
      printf '%s\n' "$_snippet"
      return 1
    fi
  done
  rm -rf "$_tmpdir"
  return 1
}

# Miniforge tags are <conda-version>-<build> (e.g. 26.3.1-0). Strip the build
# suffix so VERSION matches 'conda --version' output for idempotency checks.
__resolve_input_version_post() {
  VERSION="${VERSION%-*}"
}

# Only the script method is supported.
__resolve_method() { printf 'script\n'; }

# Run the downloaded Miniforge installer, then display post-install info.
__install_run_script_run() {
  local _installer="$1"
  logging__install "Installing Miniforge to ${PREFIX}"
  if [[ "${INTERACTIVE:-}" == true ]]; then
    /bin/bash "${_installer}" -p "${PREFIX}"
  else
    /bin/bash "${_installer}" -b -p "${PREFIX}"
  fi
  logging__info "Conda info:"
  "${PREFIX}/bin/conda" info
  logging__info "Conda config:"
  "${PREFIX}/bin/conda" config --show
  logging__info "Conda env list:"
  "${PREFIX}/bin/conda" env list
  logging__info "Conda package list (base):"
  "${PREFIX}/bin/conda" list --name base
}

export_envs() {
  logging__fn_entry "export_envs"
  local tmpdir="$1"
  mkdir -p "$tmpdir"
  local env_paths
  env_paths="$("${PREFIX}/bin/conda" env list --json 2> /dev/null |
    json__object_key_string_lines_stdin envs |
    grep '^/' |
    grep -v "^${PREFIX}/*$")" || true
  if [[ -z "$env_paths" ]]; then
    logging__info "No non-base environments found to preserve."
    logging__fn_exit "export_envs"
    return
  fi
  while IFS= read -r env_path; do
    [[ -z "$env_path" ]] && continue
    local env_name
    env_name="$(basename "$env_path")"
    local yaml_path="${tmpdir}/${env_name}.yml"
    logging__info "Exporting environment '${env_name}' to '${yaml_path}'."
    if "${PREFIX}/bin/conda" env export --from-history --name "$env_name" > "$yaml_path" 2> /dev/null; then
      logging__success "Exported environment '${env_name}'."
    else
      logging__warn "Failed to export environment '${env_name}'. Skipping."
      rm -f "$yaml_path"
    fi
  done <<< "$env_paths"
  logging__fn_exit "export_envs"
}

recreate_envs() {
  logging__fn_entry "recreate_envs"
  local tmpdir="$1"
  if [[ ! -d "$tmpdir" ]]; then
    logging__info "No preserved environments directory found at '${tmpdir}'. Skipping."
    logging__fn_exit "recreate_envs"
    return
  fi
  local found=false
  for yaml_path in "${tmpdir}"/*.yml; do
    [[ -f "$yaml_path" ]] || continue
    found=true
    local env_name
    env_name="$(basename "$yaml_path" .yml)"
    logging__download "Recreating environment '${env_name}' from '${yaml_path}'."
    if "${PREFIX}/bin/conda" env create --file "$yaml_path"; then
      logging__success "Recreated environment '${env_name}'."
      rm -f "$yaml_path"
    else
      logging__warn "Failed to recreate environment '${env_name}'. YAML preserved at '${yaml_path}' for manual recovery."
    fi
  done
  if [[ "$found" == false ]]; then
    logging__info "No preserved environment YAMLs found in '${tmpdir}'."
  fi
  [ -d "$tmpdir" ] && [ -z "$(ls -A "$tmpdir")" ] && rm -rf "$tmpdir"
  logging__fn_exit "recreate_envs"
}

# Override: conda teardown requires conda init --reverse and per-user config cleanup.
# shellcheck disable=SC2329,SC2317
__uninstall_run__() {
  logging__remove "Uninstalling conda (Miniforge)."
  if [[ "${PRESERVE_CONFIG:-}" != "true" ]]; then
    "${_FEAT_EXISTING_PATH}" init --reverse
  fi
  rm -rf "$("${_FEAT_EXISTING_PATH}" info --base)"
  if [[ "${PRESERVE_CONFIG:-}" != "true" ]]; then
    local -a _wargs=()
    if [[ "${#WRITE_USERS[@]}" -gt 0 ]]; then
      _wargs=(--current false --remote false --container false)
      for _u in "${WRITE_USERS[@]}"; do _wargs+=(--user "$_u"); done
    fi
    local -a _uninstall_users
    mapfile -t _uninstall_users < <(users__resolve_list "${_wargs[@]}")
    for _u in "${_uninstall_users[@]}"; do
      [[ -z "$_u" ]] && continue
      local _user_home
      _user_home="$(users__resolve_home "$_u")" || continue
      [[ -z "$_user_home" ]] && continue
      rm -f "$_user_home/.condarc"
      rm -rf "$_user_home/.conda"
    done
  fi
}

# Export all non-base conda environments before the uninstall step.
__reinstall_run_pre() {
  [[ "${PRESERVE_ENVS:-}" == "true" ]] || return 0
  export_envs "/tmp/conda-env-preserve"
}

# Recreate preserved environments after the fresh install step.
__reinstall_run_post() {
  [[ "${PRESERVE_ENVS:-}" == "true" ]] || return 0
  recreate_envs "/tmp/conda-env-preserve"
}

# Override: conda install handles version pinning directly; no re-download needed.
# shellcheck disable=SC2329,SC2317
__update_run__() {
  logging__info "Updating conda base environment to version '${VERSION}'."
  "${_FEAT_EXISTING_PATH}" install --name base --yes "conda=${VERSION}"
}

# Map WRITE_USERS → ADD_USERS so __feat_do_configure_users__ scopes per-user
# config to the same users that received write-group permissions.
__feat_do_configure_users_pre() {
  [[ "${#WRITE_USERS[@]}" -gt 0 ]] && ADD_USERS=("${WRITE_USERS[@]}")
  return 0
}

__configure_user() {
  local _u="$1"
  [ -z "${ACTIVATE_ENV:-}" ] && return 0
  local _user_home
  _user_home="$(users__resolve_home "$_u")" || return 0
  [[ -z "$_user_home" ]] && return 0
  if [[ "$ACTIVATE_ENV" == "base" ]]; then
    [[ "${PRESERVE_CONFIG:-}" == "false" ]] && return 0
    if "${PREFIX}/bin/conda" config --describe auto_activate &> /dev/null; then
      "${PREFIX}/bin/conda" config --remove-key auto_activate_base --file "$_user_home/.condarc" 2> /dev/null || true
      "${PREFIX}/bin/conda" config --set auto_activate true --file "$_user_home/.condarc"
    else
      "${PREFIX}/bin/conda" config --set auto_activate_base true --file "$_user_home/.condarc"
    fi
  else
    local _bashrc _zshrc
    if [[ "$_u" == "root" ]]; then
      _bashrc="$(shell__detect_bashrc)"
      _zshrc="$(shell__detect_zshdir)/zshrc"
    else
      _bashrc="$_user_home/.bashrc"
      _zshrc="$_user_home/.zshrc"
    fi
    local _rc
    for _rc in "$_bashrc" "$_zshrc"; do
      [[ -f "$_rc" ]] || continue
      shell__sync_block --files "$_rc" \
        --marker "conda env activation (install-miniforge)" \
        --content "conda activate ${ACTIVATE_ENV}"
    done
  fi
}

__install_finish_post() {
  __feat_do_configure_users__
  if [[ "${UPDATE_BASE:-}" == true ]]; then
    logging__warn "Updating base conda environment."
    "${PREFIX}/bin/mamba" update -n base --all -y
  fi
  if os__is_devcontainer_build; then
    mkdir -p "${_FEAT_LIFECYCLE_DIR}"
    printf '#!/bin/sh\n"%s" info\n' "${_DF_EXPECTED_CMD}" \
      > "${_FEAT_LIFECYCLE_ON_CREATE}verification.sh"
    chmod +x "${_FEAT_LIFECYCLE_ON_CREATE}verification.sh"
  fi
}

__update_finish_post() {
  if [[ "${UPDATE_BASE:-}" == true ]]; then
    logging__warn "Updating base conda environment."
    "${PREFIX}/bin/mamba" update -n base --all -y
  fi
}

__exit_pre() {
  if [ -n "${PREFIX-}" ] && [ -d "$PREFIX" ]; then
    find "$PREFIX" -follow -type f -name '*.a' -delete 2> /dev/null || true
    find "$PREFIX" -follow -type f -name '*.pyc' -delete 2> /dev/null || true
    "${PREFIX}/bin/conda" clean --all --yes 2> /dev/null || true
  fi
}
