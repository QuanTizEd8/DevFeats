resolve_solver() {
  logging__fn_entry "resolve_solver"
  local _solver="${SOLVER:-}"
  SOLVER_EXEC=""

  if [[ -z "${_solver}" ]]; then
    # Auto-detect: mamba then conda; install-time PATH then RUNTIME_PATH.
    local _cmd _candidate
    for _cmd in mamba conda; do
      _candidate="$(command -v "${_cmd}" 2> /dev/null || true)"
      if [[ -n "${_candidate}" ]]; then
        SOLVER_EXEC="${_candidate}"
        break
      fi
      if [[ -v RUNTIME_PATH && -n "${RUNTIME_PATH}" ]]; then
        _candidate="$(PATH="${RUNTIME_PATH}" command -v "${_cmd}" 2> /dev/null || true)"
        if [[ -n "${_candidate}" ]]; then
          SOLVER_EXEC="${_candidate}"
          break
        fi
      fi
    done
    if [[ -z "${SOLVER_EXEC}" ]]; then
      logging__error "Neither mamba nor conda found on PATH or RUNTIME_PATH."
      logging__info "Install a conda distribution first, e.g. with the install-miniforge feature."
      exit 1
    fi
  elif [[ "${_solver}" == */* ]]; then
    # Full path: must be an executable file.
    if [[ ! -x "${_solver}" ]]; then
      logging__error "solver='${_solver}': not an executable file."
      exit 1
    fi
    SOLVER_EXEC="${_solver}"
  else
    # Named command: search install-time PATH then RUNTIME_PATH.
    SOLVER_EXEC="$(command -v "${_solver}" 2> /dev/null || true)"
    if [[ -z "${SOLVER_EXEC}" ]] && [[ -v RUNTIME_PATH && -n "${RUNTIME_PATH}" ]]; then
      SOLVER_EXEC="$(PATH="${RUNTIME_PATH}" command -v "${_solver}" 2> /dev/null || true)"
    fi
    if [[ -z "${SOLVER_EXEC}" ]]; then
      logging__error "solver='${_solver}': command not found on PATH or RUNTIME_PATH."
      exit 1
    fi
  fi

  logging__info "Solver: '${SOLVER_EXEC}'."
  CONDA_DIR="$("${SOLVER_EXEC}" info --base)"
  if [[ -z "${CONDA_DIR}" ]]; then
    logging__error "'${SOLVER_EXEC} info --base' returned empty; cannot determine conda base directory."
    exit 1
  fi
  logging__info "Conda base: '${CONDA_DIR}'."
  logging__fn_exit "resolve_solver"
}

apply_channels() {
  logging__fn_entry "apply_channels"
  if [[ ${#CHANNELS[@]} -eq 0 ]] && [[ "$STRICT_CHANNEL_PRIORITY" == false ]]; then
    logging__info "No channels or channel priority changes requested."
    logging__fn_exit "apply_channels"
    return
  fi
  for channel in "${CHANNELS[@]}"; do
    logging__info "Adding channel: $channel"
    "${SOLVER_EXEC}" config --add channels "$channel"
  done
  if [[ "$STRICT_CHANNEL_PRIORITY" == true ]]; then
    logging__info "Setting channel_priority to strict."
    "${SOLVER_EXEC}" config --set channel_priority strict
  fi
  logging__fn_exit "apply_channels"
}

create_or_update_env() {
  logging__fn_entry "create_or_update_env"
  local env_file=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env_file)
        shift
        env_file="$1"
        logging__read "Read argument 'env_file': '${env_file}'"
        shift
        ;;
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
  [ -z "${env_file-}" ] && {
    logging__error "Missing required argument 'env_file'."
    exit 1
  }
  local env_name
  env_name=$(grep -E '^name:' "$env_file" | head -1 | awk '{print $2}')
  local env_prefix
  if [ "$env_name" = "base" ]; then
    env_prefix="$CONDA_DIR"
  else
    env_prefix="$CONDA_DIR/envs/$env_name"
  fi
  if [ -n "$env_name" ] && [ -d "$env_prefix" ]; then
    logging__install "Updating existing conda environment '$env_name' from '$env_file'."
    "$SOLVER_EXEC" env update --file "$env_file" --yes
  else
    logging__install "Creating conda environment from '$env_file'."
    "$SOLVER_EXEC" env create --file "$env_file" --yes
  fi
  logging__fn_exit "create_or_update_env"
}

install_pip_requirements() {
  logging__fn_entry "install_pip_requirements"
  local env_name=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env_name)
        shift
        env_name="$1"
        logging__read "Read argument 'env_name': '${env_name}'"
        shift
        ;;
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
  [ -z "${env_name-}" ] && {
    logging__error "Missing required argument 'env_name'."
    exit 1
  }
  if [[ ${#PIP_REQUIREMENTS_FILES[@]} -eq 0 ]]; then
    logging__info "No pip requirements files specified."
    logging__fn_exit "install_pip_requirements"
    return
  fi
  local pip_exec
  if [[ "$env_name" == "base" ]]; then
    pip_exec="${CONDA_DIR}/bin/pip"
  else
    pip_exec="${CONDA_DIR}/envs/${env_name}/bin/pip"
  fi
  if [[ ! -f "$pip_exec" ]]; then
    logging__warn "pip not found at '$pip_exec'. Skipping pip requirements for env '$env_name'."
    logging__fn_exit "install_pip_requirements"
    return
  fi
  for req_file in "${PIP_REQUIREMENTS_FILES[@]}"; do
    logging__install "Installing pip requirements from '$req_file' into env '$env_name'."
    "$pip_exec" install -r "$req_file"
  done
  logging__fn_exit "install_pip_requirements"
}

run_post_env_script() {
  logging__fn_entry "run_post_env_script"
  local env_name=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env_name)
        shift
        env_name="$1"
        logging__read "Read argument 'env_name': '${env_name}'"
        shift
        ;;
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
  [ -z "${env_name-}" ] && {
    logging__error "Missing required argument 'env_name'."
    exit 1
  }
  if [[ -z "$POST_ENV_SCRIPT" ]]; then
    logging__fn_exit "run_post_env_script"
    return
  fi
  if [[ ! -f "$POST_ENV_SCRIPT" ]]; then
    logging__error "post_env_script not found: '$POST_ENV_SCRIPT'."
    exit 1
  fi
  if [[ ! -x "$POST_ENV_SCRIPT" ]]; then
    logging__error "post_env_script is not executable: '$POST_ENV_SCRIPT'."
    exit 1
  fi
  logging__launch "Running post-env script '$POST_ENV_SCRIPT' for env '$env_name'."
  "$POST_ENV_SCRIPT" "$env_name"
  logging__fn_exit "run_post_env_script"
}

setup_inline_env() {
  logging__fn_entry "setup_inline_env"
  local tmp_env_file
  tmp_env_file="$(mktemp --suffix=.yml)"
  printf 'name: %s\n' "$ENV_NAME" > "$tmp_env_file"
  printf 'dependencies:\n' >> "$tmp_env_file"
  if [[ -n "$PYTHON_VERSION" ]]; then
    printf '  - python=%s\n' "$PYTHON_VERSION" >> "$tmp_env_file"
  fi
  for pkg in $PACKAGES; do
    printf '  - %s\n' "$pkg" >> "$tmp_env_file"
  done
  logging__info "Generated inline environment file:"
  cat "$tmp_env_file" >&2
  create_or_update_env --env_file "$tmp_env_file"
  rm -f "$tmp_env_file"
  local _pip_target="${PIP_ENV:-$ENV_NAME}"
  install_pip_requirements --env_name "$_pip_target"
  run_post_env_script --env_name "$ENV_NAME"
  logging__fn_exit "setup_inline_env"
}

setup_environment() {
  logging__fn_entry "setup_environment"
  umask 0002
  for env_file in "${ENV_FILES[@]}"; do
    local env_name
    env_name=$(grep -E '^name:' "$env_file" | head -1 | awk '{print $2}')
    create_or_update_env --env_file "$env_file"
    local _pip_target="${PIP_ENV:-$env_name}"
    install_pip_requirements --env_name "$_pip_target"
    run_post_env_script --env_name "$env_name"
  done
  for env_dir in "${ENV_DIRS[@]}"; do
    while IFS= read -r env_file; do
      local env_name
      env_name=$(grep -E '^name:' "$env_file" | head -1 | awk '{print $2}')
      create_or_update_env --env_file "$env_file"
      local _pip_target="${PIP_ENV:-$env_name}"
      install_pip_requirements --env_name "$_pip_target"
      run_post_env_script --env_name "$env_name"
    done < <(find "$env_dir" -type f \( -name "*.yml" -o -name "*.yaml" \) | sort)
  done
  logging__fn_exit "setup_environment"
}

__init_args_post() {
  if [[ -n "$ENV_NAME" ]] && [[ -z "$PACKAGES" ]] && [[ -z "$PYTHON_VERSION" ]]; then
    logging__error "'env_name' requires at least one of 'packages' or 'python_version' to be set."
    exit 1
  fi
}

__verify_system_requirements_post() {
  resolve_solver
}

# shellcheck disable=SC2329,SC2317
__install_run__() {
  apply_channels
  [[ -n "$ENV_NAME" ]] && setup_inline_env
  if [[ ${#ENV_FILES[@]} -gt 0 || ${#ENV_DIRS[@]} -gt 0 ]]; then setup_environment; fi
}

__install_finish_post() {
  [[ "${KEEP_CACHE}" != true ]] || return 0
  logging__clean "Cleaning up conda cache."
  "${SOLVER_EXEC}" clean --all --yes
}
