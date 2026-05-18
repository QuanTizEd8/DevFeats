# shellcheck source=lib/shell.sh
. "$_BASE_DIR/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "$_BASE_DIR/_lib/github.sh"
# shellcheck source=lib/json.sh
. "$_BASE_DIR/_lib/json.sh"
# shellcheck source=lib/verify.sh
. "${_BASE_DIR}/_lib/verify.sh"
# shellcheck source=lib/users.sh
. "$_BASE_DIR/_lib/users.sh"
# shellcheck source=lib/file.sh
. "$_BASE_DIR/_lib/file.sh"

# ── Constants ────────────────────────────────────────────────────────────────
readonly _MINIFORGE_RELEASES_URL="https://github.com/conda-forge/miniforge/releases"
readonly _CONDA_INIT_SCRIPT_RELPATH="etc/profile.d/conda.sh"
readonly _MAMBA_INIT_SCRIPT_RELPATH="etc/profile.d/mamba.sh"

# shellcheck disable=SC2329,SC2317
prefix_activation_snippet() {
  local _shell="$1"
  local _tmpdir _f _snippet
  _tmpdir="$(mktemp -d)"
  HOME="$_tmpdir" "$CONDA_EXEC" init "$_shell" > /dev/null 2>&1 || true
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

setup_activate_env() {
  logging__fn_entry "setup_activate_env"
  [ -z "${ACTIVATE_ENV:-}" ] && {
    logging__fn_exit "setup_activate_env"
    return 0
  }
  local -a _ae_users=("$@")
  local _marker="conda env activation (install-miniforge)"
  local _u _user_home
  for _u in "${_ae_users[@]}"; do
    [[ -z "$_u" ]] && continue
    _user_home="$(getent passwd "$_u" | cut -d: -f6)" || continue
    [[ -z "$_user_home" ]] && continue
    if [[ "$ACTIVATE_ENV" == "base" ]]; then
      [[ "${PRESERVE_CONFIG:-}" == "false" ]] && continue
      if "$CONDA_EXEC" config --describe auto_activate &> /dev/null; then
        # conda ≥26.3: auto_activate_base is a deprecated alias; remove it first to avoid MultipleKeysError
        "$CONDA_EXEC" config --remove-key auto_activate_base --file "$_user_home/.condarc" 2> /dev/null || true
        "$CONDA_EXEC" config --set auto_activate true --file "$_user_home/.condarc"
      else
        "$CONDA_EXEC" config --set auto_activate_base true --file "$_user_home/.condarc"
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
          --marker "$_marker" \
          --content "conda activate ${ACTIVATE_ENV}"
      done
    fi
  done
  logging__fn_exit "setup_activate_env"
}

_prefix_post_install() {
  _prefix_post_install__generated
  setup_activate_env "${_write_users[@]}"
  if os__is_devcontainer_build; then
    mkdir -p "${_FEAT_SHARE_DIR}"
    printf '#!/bin/sh\n"%s" info\n' "${_DF_EXPECTED_CMD}" \
      > "${_FEAT_SHARE_DIR}/lifecycle--on-create--verification.sh"
    chmod +x "${_FEAT_SHARE_DIR}/lifecycle--on-create--verification.sh"
  fi
}

check_root_requirement() {
  logging__fn_entry "check_root_requirement"
  local _require
  case "$PREFIX" in
    /opt/* | /usr/* | /var/* | /srv/* | /snap/*) _require=true ;;
    *) _require=false ;;
  esac
  if [[ "$_require" == true ]]; then
    os__require_root
  else
    logging__info "Root not required for prefix '$PREFIX'. Skipping root check."
  fi
  logging__fn_exit "check_root_requirement"
}

get_script_dir() {
  logging__fn_entry "get_script_dir"
  local script_dir
  script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
  logging__info "Write output 'script_dir': '${script_dir}'"
  echo "${script_dir}"
  logging__fn_exit "get_script_dir"
}

install_miniforge() {
  logging__fn_entry "install_miniforge"
  logging__install "Installing Miniforge to $PREFIX"
  if [[ "$INTERACTIVE" == true ]]; then
    /bin/bash "$INSTALLER" -p "$PREFIX"
  else
    /bin/bash "$INSTALLER" -b -p "$PREFIX"
  fi
  echo "Displaying conda info:"
  "$CONDA_EXEC" info
  echo "Displaying conda config:"
  "$CONDA_EXEC" config --show
  echo "Displaying conda env list:"
  "$CONDA_EXEC" env list
  echo "Displaying conda list:"
  "$CONDA_EXEC" list --name base
  logging__fn_exit "install_miniforge"
}

set_executable_paths() {
  logging__fn_entry "set_executable_paths"
  __usage__() {
    logging__info "Usage:"
    logging__info "  --verify (boolean): This is useful before running the post-installation steps
  (especially when the installation steps were skipped)
  to ensure that the executables are available.
  "
    exit 0
  }
  local verify=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --verify)
        shift
        verify=true
        logging__read "Read argument 'verify': '${verify}'"
        ;;
      --help | -h) __usage__ ;;
      --*)
        logging__error "Unknown option: '${1}'"
        exit 1
        ;;
      *)
        logging__error "Unexpected argument: '${1}'"
        exit 1
        ;;
    esac
  done
  [ -z "${verify-}" ] && {
    logging__info "Argument 'verify' set to default value 'false'."
    verify=false
  }
  CONDA_EXEC="${PREFIX}/bin/conda"
  MAMBA_EXEC="${PREFIX}/bin/mamba"
  if [[ "$verify" == false ]]; then
    return
  fi
  if [[ ! -f "$CONDA_EXEC" ]]; then
    if command -v conda > /dev/null 2>&1; then
      PREFIX="$(conda info --base)"
      CONDA_EXEC="${PREFIX}/bin/conda"
    else
      logging__error "Conda executable not found at '$CONDA_EXEC'."
      exit 1
    fi
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
    if command -v mamba > /dev/null 2>&1; then
      MAMBA_EXEC="$(mamba info --base | tail -n 2 | head -n 1)/bin/mamba"
    else
      logging__error "Mamba executable not found at '$MAMBA_EXEC'."
      exit 1
    fi
  fi
  if [[ ! -f "$CONDA_EXEC" ]]; then
    logging__error "Conda executable not found."
    exit 1
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
    logging__error "Mamba executable not found."
    exit 1
  fi
  echo "🎛 Conda executable located at '$CONDA_EXEC'."
  echo "🎛 Mamba executable located at '$MAMBA_EXEC'."
  logging__fn_exit "set_executable_paths"
}

resolve_miniforge_version() {
  logging__fn_entry "resolve_miniforge_version"
  local _spec="$VERSION"
  local _out
  _out="$(github__resolve_version "conda-forge/miniforge" "$_spec")" || {
    logging__error "Failed to resolve Miniforge version."
    exit 1
  }
  MINIFORGE_VERSION="${_out%%$'\n'*}"
  RESOLVED_CONDA_VERSION="${MINIFORGE_VERSION%-*}"
  logging__info "Resolved Miniforge tag: '${MINIFORGE_VERSION}' (conda version: '${RESOLVED_CONDA_VERSION}')."
  logging__fn_exit "resolve_miniforge_version"
}

export_envs() {
  logging__fn_entry "export_envs"
  local tmpdir="$1"
  mkdir -p "$tmpdir"
  # Get non-base env paths: parse JSON array from 'conda env list --json'.
  # Filter to lines containing '"', extract the quoted value, then keep only
  # absolute paths (starts with '/') to skip the 'envs' key and other JSON tokens,
  # then exclude the base dir (PREFIX itself).
  local env_paths
  env_paths="$("$CONDA_EXEC" env list --json 2> /dev/null |
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
    if "$CONDA_EXEC" env export --from-history --name "$env_name" > "$yaml_path" 2> /dev/null; then
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
    if "$CONDA_EXEC" env create --file "$yaml_path"; then
      logging__success "Recreated environment '${env_name}'."
      rm -f "$yaml_path" # only delete on success; keep on failure for manual recovery
    else
      logging__warn "Failed to recreate environment '${env_name}'. YAML preserved at '${yaml_path}' for manual recovery."
    fi
  done
  if [[ "$found" == false ]]; then
    logging__info "No preserved environment YAMLs found in '${tmpdir}'."
  fi
  # Remove tmpdir only if empty (all YAMLs were successfully recreated and deleted above).
  # If any recreations failed, their YAMLs remain in tmpdir for manual recovery.
  [ -d "$tmpdir" ] && [ -z "$(ls -A "$tmpdir")" ] && rm -rf "$tmpdir"
  logging__fn_exit "recreate_envs"
}

uninstall_miniforge() {
  logging__fn_entry "uninstall_miniforge"
  logging__remove "Uninstalling conda (Miniforge)."
  if [[ "$PRESERVE_CONFIG" != "true" ]]; then
    "$CONDA_EXEC" init --reverse
  fi
  rm -rf "$("$CONDA_EXEC" info --base)"
  if [[ "$PRESERVE_CONFIG" != "true" ]]; then
    rm -f "$HOME/.condarc"
    rm -rf "$HOME/.conda"
    mapfile -t _uninstall_users < <(users__resolve_list)
    for _u in "${_uninstall_users[@]}"; do
      [[ -z "$_u" ]] && continue
      user_home=$(getent passwd "$_u" | cut -d: -f6)
      rm -rf "$user_home/.condarc"
      rm -rf "$user_home/.conda"
    done
  fi
  logging__fn_exit "uninstall_miniforge"
}

_cleanup_hook() {
  logging__fn_entry "_cleanup_hook"
  if [ -n "${PREFIX-}" ] && [ -d "$PREFIX" ]; then
    find "$PREFIX" -follow -type f -name '*.a' -delete 2> /dev/null || true
    find "$PREFIX" -follow -type f -name '*.pyc' -delete 2> /dev/null || true
    "$CONDA_EXEC" clean --all --yes 2> /dev/null || true
  fi
  logging__fn_exit "_cleanup_hook"
}

check_root_requirement
set_executable_paths

resolve_miniforge_version
[ -z "${INSTALLER_DIR:-}" ] && INSTALLER_DIR="$(file__mktmpdir "miniforge-installer")"
_installer_filename="Miniforge3-${MINIFORGE_VERSION}-$(os__kernel)-$(os__arch).sh"
github__install_release \
  --repo "conda-forge/miniforge" \
  --tag "${MINIFORGE_VERSION}" \
  --asset "${_installer_filename}" \
  --sidecar "${_MINIFORGE_RELEASES_URL}/download/${MINIFORGE_VERSION}/${_installer_filename}.sha256" \
  --installer-dir "${INSTALLER_DIR}" || exit 1
INSTALLER="${INSTALLER_DIR}/asset/${_installer_filename}"

if [[ -f "${PREFIX}/bin/conda" ]] || command -v conda > /dev/null 2>&1; then
  logging__warn "Conda installation found at '$PREFIX'."
  # Version-match idempotency: if installed conda version already matches the
  # resolved version, skip silently regardless of if_exists.
  _installed_ver="$("${PREFIX}/bin/conda" --version 2> /dev/null | awk '{print $NF}')" || true
  if [[ -n "$_installed_ver" && "$_installed_ver" == "$RESOLVED_CONDA_VERSION" ]]; then
    logging__info "Installed conda version '${_installed_ver}' matches resolved version '${RESOLVED_CONDA_VERSION}'. Skipping install and continuing to post-install steps."
  else
    case "$IF_EXISTS" in
      skip)
        logging__info "if_exists=skip: existing conda detected; skipping install and continuing to post-install steps."
        ;;
      fail)
        logging__error "if_exists=fail: conda already installed at '$PREFIX'. Remove it first or set if_exists=skip/reinstall."
        exit 1
        ;;
      reinstall)
        logging__info "if_exists=reinstall: uninstalling existing conda, then installing fresh."
        set_executable_paths --verify
        _env_preserve_dir="/tmp/conda-env-preserve"
        if [[ "$PRESERVE_ENVS" == "true" ]]; then
          export_envs "$_env_preserve_dir"
        fi
        uninstall_miniforge
        install_miniforge
        if [[ "$PRESERVE_ENVS" == "true" ]]; then
          set_executable_paths --verify
          recreate_envs "$_env_preserve_dir"
        fi
        ;;
      update)
        logging__info "if_exists=update: updating conda base environment to version '${RESOLVED_CONDA_VERSION}'."
        set_executable_paths --verify
        "$CONDA_EXEC" install --name base --yes "conda=${RESOLVED_CONDA_VERSION}"
        ;;
      *)
        logging__error "Invalid value for 'if_exists': '$IF_EXISTS'. Use 'skip', 'fail', 'reinstall', or 'update'."
        exit 1
        ;;
    esac
  fi
else
  install_miniforge
fi

set_executable_paths --verify

if [[ "$UPDATE_BASE" == true ]]; then
  logging__warn "Updating base conda environment."
  "$MAMBA_EXEC" update -n base --all -y
fi
