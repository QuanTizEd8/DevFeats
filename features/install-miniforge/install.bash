if [ -z "${PREFIX-}" ] || [ "${PREFIX}" = "auto" ]; then
  if [ "$(id -u)" = "0" ]; then
    PREFIX="/opt/conda"
  else
    PREFIX="${HOME}/miniforge3"
  fi
  logging__info "Argument 'PREFIX' resolved from 'auto' to '${PREFIX}'."
fi

# _conda_init_snippet <shell>
# Runs `conda init <shell>` into a tmpdir with a clean HOME and prints the
# full content of the rc file conda wrote (including conda's own markers).
# Returns empty string if conda init fails or writes nothing.
_conda_init_snippet() {
  local _shell="$1"
  local _tmpdir _f
  _tmpdir="$(mktemp -d)"
  HOME="$_tmpdir" "$CONDA_EXEC" init "$_shell" -q 2> /dev/null || true
  for _f in "$_tmpdir"/.bashrc "$_tmpdir"/.bash_profile \
    "$_tmpdir"/.zshrc "$_tmpdir"/.zprofile; do
    if [[ -f "$_f" && -s "$_f" ]]; then
      cat "$_f"
      rm -rf "$_tmpdir"
      return 0
    fi
  done
  rm -rf "$_tmpdir"
  return 0
}

add_activation_to_rcfile() {
  logging__fn_entry "add_activation_to_rcfile"
  if [[ "${#SHELL_ACTIVATIONS[@]}" -eq 0 ]]; then
    logging__info "shell_activations is empty; skipping conda init."
    logging__fn_exit "add_activation_to_rcfile"
    return 0
  fi
  local _shell
  for _shell in "${SHELL_ACTIVATIONS[@]}"; do
    local _target_file
    case "$_shell" in
      bash)
        if [[ "$(id -u)" == "0" ]]; then
          _target_file="$(shell__detect_bashrc)"
        else
          _target_file="${HOME}/.bashrc"
        fi
        ;;
      zsh)
        if [[ "$(id -u)" == "0" ]]; then
          _target_file="$(shell__detect_zshdir)/zshrc"
        else
          local _zdotdir
          _zdotdir="$(shell__detect_zdotdir --home "${HOME}")"
          _target_file="${_zdotdir}/.zshrc"
        fi
        ;;
      *)
        logging__error "Unsupported shell for conda activation: '${_shell}' (supported: bash, zsh)"
        exit 1
        ;;
    esac
    logging__info "Capturing conda init snippet for ${_shell}..."
    local _snippet
    _snippet="$(_conda_init_snippet "$_shell")"
    if [[ -z "$_snippet" ]]; then
      logging__warn "conda init produced no output for '${_shell}'; skipping."
      continue
    fi
    # Optionally append conda activate after the conda init block.
    local _content="$_snippet"
    if [[ -n "${ACTIVATE_ENV:-}" && "$ACTIVATE_ENV" != "base" ]]; then
      _content="${_content}"$'\n'"conda activate ${ACTIVATE_ENV}"
    fi
    # Our marker is distinct from conda's "# >>> conda initialize >>>",
    # so shell__write_block handles idempotency without touching conda's markers.
    shell__write_block --file "$_target_file" --marker "conda init (install-miniforge)" \
      --content "$_content"
  done
  logging__fn_exit "add_activation_to_rcfile"
}

download_miniforge() {
  logging__fn_entry "download_miniforge"
  local installer_url="${_MINIFORGE_RELEASES_URL}/download/${MINIFORGE_VERSION}/${INSTALLER_FILENAME}"
  local checksum_url="${installer_url}.sha256"
  mkdir -p "$INSTALLER_DIR"
  logging__download "Downloading installer from $installer_url"
  net__fetch_url_file "$installer_url" "$INSTALLER"
  net__fetch_url_file "$checksum_url" "$CHECKSUM"
  logging__fn_exit "download_miniforge"
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

set_installer_filename() {
  logging__fn_entry "set_installer_filename"
  local installer_platform
  installer_platform="$(os__kernel)-$(os__arch)"
  INSTALLER_FILENAME="Miniforge3-${MINIFORGE_VERSION}-${installer_platform}.sh"
  INSTALLER="${INSTALLER_DIR}/${INSTALLER_FILENAME}"
  CHECKSUM="${INSTALLER}.sha256"
  logging__fn_exit "set_installer_filename"
}

resolve_miniforge_version() {
  logging__fn_entry "resolve_miniforge_version"
  local tag conda_ver
  if [[ "$VERSION" == "latest" ]]; then
    logging__info "Resolving latest Miniforge release tag from GitHub API."
    tag="$(github__latest_tag conda-forge/miniforge)" || {
      logging__error "Failed to resolve latest Miniforge version."
      exit 1
    }
  else
    logging__info "Resolving Miniforge release tag for conda version '${VERSION}' from GitHub API."
    # --all: many Miniforge releases; older conda versions are not on the first page.
    # --retries/--retry-delay: full replays for flakes (curl already retries HTTP).
    local releases
    releases="$(github__release_tags conda-forge/miniforge --all --retries 3 --retry-delay 4)" || {
      logging__error "Failed to list Miniforge releases."
      exit 1
    }
    [[ -z "$releases" ]] && {
      logging__error "Received empty release list from GitHub API."
      exit 1
    }
    # Find tags matching <version>-<build_number>, pick the highest build number.
    tag="$(printf '%s\n' "$releases" |
      grep -E "^${VERSION}-[0-9]+$" |
      sort -t- -k2 -n | tail -1)"
    [[ -z "$tag" ]] && {
      logging__error "No Miniforge release found for conda version '${VERSION}'. Check available releases at ${_MINIFORGE_RELEASES_URL}"
      exit 1
    }
  fi
  MINIFORGE_VERSION="$tag"
  # Extract conda version: the tag is "<version>-<build_number>"; strip the build suffix.
  conda_ver="${tag%-*}"
  RESOLVED_CONDA_VERSION="$conda_ver"
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

verify_miniforge() {
  logging__fn_entry "verify_miniforge"
  logging__install "Verifying installer checksum"
  checksum__verify_sidecar "$INSTALLER" "$CHECKSUM"
  logging__fn_exit "verify_miniforge"
}

export_path_main() {
  logging__fn_entry "export_path_main"
  if [ "${#EXPORT_PATH[@]}" -eq 0 ]; then
    logging__info "export_path is empty; skipping PATH export."
    logging__fn_exit "export_path_main"
    return
  fi
  local _content="export PATH=\"${PREFIX}/bin:\${PATH}\""
  local _marker="conda PATH (install-miniforge)"
  local _target_files
  if [ "${EXPORT_PATH[*]}" != "auto" ]; then
    _target_files="$(printf '%s\n' "${EXPORT_PATH[@]}")"
  else
    local _is_public=true _is_root=false
    case "$PREFIX" in "${HOME}"/*) _is_public=false ;; esac
    [ "$(id -u)" = "0" ] && _is_root=true
    logging__info "Platform: '$(os__platform)'; is_public=${_is_public}; is_root=${_is_root}."
    if [ "$_is_public" = true ] && [ "$_is_root" = true ]; then
      logging__info "Case A: system-wide PATH export (public install, root)."
      _target_files="$(shell__system_path_files --profile_d "conda_bin_path.sh")"
    else
      logging__info "Case B: user-scoped PATH export."
      # shellcheck disable=SC2119 # no args → uses $HOME default, intentional
      _target_files="$(shell__user_path_files)"
    fi
  fi
  shell__sync_block --files "$_target_files" --marker "$_marker" --content "$_content"
  logging__fn_exit "export_path_main"
  return
}

create_symlink() {
  logging__fn_entry "create_symlink"
  if [[ "$SYMLINK" != true ]]; then
    logging__info "symlink=false; skipping symlink creation."
    logging__fn_exit "create_symlink"
    return 0
  fi
  shell__create_symlink \
    --src "$PREFIX" \
    --system-target "/opt/conda" \
    --user-target "${HOME}/miniforge3"
  logging__fn_exit "create_symlink"
  return 0
}

_cleanup_hook() {
  logging__fn_entry "_cleanup_hook"
  if [[ "${KEEP_INSTALLER-}" != "true" ]]; then
    [ -f "${INSTALLER-}" ] && {
      logging__remove "Removing installer script at '$INSTALLER'"
      rm -f "$INSTALLER"
    }
    [ -f "${CHECKSUM-}" ] && {
      logging__remove "Removing checksum file at '$CHECKSUM'"
      rm -f "$CHECKSUM"
    }
    [ -d "${INSTALLER_DIR-}" ] && [ -z "$(ls -A "$INSTALLER_DIR")" ] && {
      logging__remove "Removing installation directory at '$INSTALLER_DIR'"
      rmdir "$INSTALLER_DIR"
    }
  fi
  if [ -n "${PREFIX-}" ] && [ -d "$PREFIX" ]; then
    find "$PREFIX" -follow -type f -name '*.a' -delete 2> /dev/null || true
    find "$PREFIX" -follow -type f -name '*.pyc' -delete 2> /dev/null || true
  fi
  logging__fn_exit "_cleanup_hook"
}

readonly _CONDA_INIT_SCRIPT_RELPATH="etc/profile.d/conda.sh"
readonly _MAMBA_INIT_SCRIPT_RELPATH="etc/profile.d/mamba.sh"

# shellcheck source=lib/shell.sh
. "$_SELF_DIR/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"
# shellcheck source=lib/json.sh
. "$_SELF_DIR/_lib/json.sh"
# shellcheck source=lib/checksum.sh
. "$_SELF_DIR/_lib/checksum.sh"
# shellcheck source=lib/users.sh
. "$_SELF_DIR/_lib/users.sh"

# ── Constants ────────────────────────────────────────────────────────────────
_MINIFORGE_RELEASES_URL="https://github.com/conda-forge/miniforge/releases"

check_root_requirement
set_executable_paths

resolve_miniforge_version
set_installer_filename
_download_deps__install
download_miniforge
if [[ -f "$CHECKSUM" ]]; then
  verify_miniforge
else
  logging__warn "Checksum file not found. Skipping verification."
fi

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

create_symlink
export_path_main

if [[ "${#SHELL_ACTIVATIONS[@]}" -gt 0 ]]; then add_activation_to_rcfile; fi
if [[ "$UPDATE_BASE" == true ]]; then
  logging__warn "Updating base conda environment."
  "$MAMBA_EXEC" update -n base --all -y
fi

if [[ -n "${WRITE_GROUP:-}" ]]; then
  export ADD_CURRENT_USER ADD_REMOTE_USER ADD_CONTAINER_USER ADD_USERS
  mapfile -t _write_users < <(users__resolve_list)
  users__set_write_permissions "$PREFIX" "$(id -nu)" "$WRITE_GROUP" "${_write_users[@]}"
fi
