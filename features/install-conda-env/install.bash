# shellcheck source=lib/uri.sh
. "$_SELF_DIR/_lib/uri.sh"

_URI_TMP="$(mktemp -d)"
_cleanup_hook() {
  rm -rf "${_URI_TMP:-}"
}

declare -p FETCH_HEADERS &> /dev/null || FETCH_HEADERS=()
[ "${FETCH_NETRC+defined}" ] || FETCH_NETRC=""

_uri_fetch_args=()
if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
  for _uh in "${FETCH_HEADERS[@]}"; do
    [[ -n "${_uh}" ]] && _uri_fetch_args+=(--header "$_uh")
  done
fi
[[ -n "${FETCH_NETRC:-}" ]] && _uri_fetch_args+=(--netrc-file "${FETCH_NETRC}")

if [[ ${#ENV_FILES[@]} -gt 0 ]]; then
  _env_list="$(printf '%s\n' "${ENV_FILES[@]}")"
  mapfile -t ENV_FILES < <(uri__resolve_list "$_env_list" "$_URI_TMP/env" "${_uri_fetch_args[@]}")
fi
if [[ ${#PIP_REQUIREMENTS_FILES[@]} -gt 0 ]]; then
  _pip_list="$(printf '%s\n' "${PIP_REQUIREMENTS_FILES[@]}")"
  mapfile -t PIP_REQUIREMENTS_FILES < <(uri__resolve_list "$_pip_list" "$_URI_TMP/pip" "${_uri_fetch_args[@]}")
fi
if [[ -n "${POST_ENV_SCRIPT:-}" ]]; then
  _post_tmp="$(mktemp "${_URI_TMP}/post_env.XXXXXX")"
  POST_ENV_SCRIPT="$(uri__resolve "$POST_ENV_SCRIPT" "$_post_tmp" "${_uri_fetch_args[@]}" --chmod-exec)"
fi

for elem in "${ENV_DIRS[@]}"; do
  [ -n "${elem-}" ] && [ ! -d "${elem}" ] && {
    logging__error "Directory argument to parameter 'env_dirs' not found: '${elem}'"
    exit 1
  }
done
for elem in "${ENV_FILES[@]}"; do
  [ -n "${elem-}" ] && [ ! -f "${elem}" ] && {
    logging__error "File argument to parameter 'env_files' not found: '${elem}'"
    exit 1
  }
done
for elem in "${PIP_REQUIREMENTS_FILES[@]}"; do
  [ -n "${elem-}" ] && [ ! -f "${elem}" ] && {
    logging__error "File argument to parameter 'pip_requirements_files' not found: '${elem}'"
    exit 1
  }
done
if [[ -n "$ENV_NAME" ]] && [[ -z "$PACKAGES" ]] && [[ -z "$PYTHON_VERSION" ]]; then
  logging__error "'env_name' requires at least one of 'packages' or 'python_version' to be set."
  exit 1
fi

discover_conda() {
  logging__fn_entry "discover_conda"
  CONDA_EXEC="${CONDA_DIR}/bin/conda"
  MAMBA_EXEC="${CONDA_DIR}/bin/mamba"
  if [[ -n "$CONDA_DIR" ]] && [[ -f "$CONDA_EXEC" ]]; then
    logging__info "Conda executable located at '$CONDA_EXEC'."
  elif [[ -n "$CONDA_DIR" ]]; then
    logging__error "conda_dir was set to '$CONDA_DIR' but conda executable not found at '$CONDA_EXEC'."
    exit 1
  elif command -v conda > /dev/null 2>&1; then
    CONDA_DIR="$(conda info --base)"
    CONDA_EXEC="${CONDA_DIR}/bin/conda"
    MAMBA_EXEC="${CONDA_DIR}/bin/mamba"
    logging__inspect "Auto-detected conda at '$CONDA_EXEC' (base: $CONDA_DIR)."
  else
    logging__error "Conda not found. Set 'conda_dir' or ensure conda is on PATH."
    logging__info "Install conda first, e.g. with the install-miniforge feature."
    exit 1
  fi
  if [[ ! -f "$MAMBA_EXEC" ]]; then
    logging__info "Mamba executable not found at '$MAMBA_EXEC'. Will use conda as fallback."
    MAMBA_EXEC=""
  else
    logging__info "Mamba executable located at '$MAMBA_EXEC'."
  fi
  logging__fn_exit "discover_conda"
}

resolve_solver() {
  logging__fn_entry "resolve_solver"
  case "$SOLVER" in
    mamba)
      if [[ -z "$MAMBA_EXEC" ]]; then
        logging__warn "Solver 'mamba' requested but mamba not found. Falling back to conda."
        SOLVER_EXEC="$CONDA_EXEC"
      else
        SOLVER_EXEC="$MAMBA_EXEC"
      fi
      ;;
    conda)
      SOLVER_EXEC="$CONDA_EXEC"
      ;;
    auto)
      if [[ -n "$MAMBA_EXEC" ]]; then
        SOLVER_EXEC="$MAMBA_EXEC"
        logging__info "Solver 'auto': using mamba."
      else
        SOLVER_EXEC="$CONDA_EXEC"
        logging__info "Solver 'auto': using conda (mamba not available)."
      fi
      ;;
    *)
      logging__error "Invalid value for 'solver': '$SOLVER'. Use 'auto', 'mamba', or 'conda'."
      exit 1
      ;;
  esac
  logging__info "Solver executable: '$SOLVER_EXEC'."
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
    "$CONDA_EXEC" config --add channels "$channel"
  done
  if [[ "$STRICT_CHANNEL_PRIORITY" == true ]]; then
    logging__info "Setting channel_priority to strict."
    "$CONDA_EXEC" config --set channel_priority strict
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

discover_conda
resolve_solver
apply_channels
if [[ -n "$ENV_NAME" ]]; then setup_inline_env; fi
if [[ ${#ENV_FILES[@]} -gt 0 || ${#ENV_DIRS[@]} -gt 0 ]]; then setup_environment; fi
if [[ "$KEEP_CACHE" == false ]]; then
  logging__clean "Cleaning up conda cache."
  "$SOLVER_EXEC" clean --all -y
fi
