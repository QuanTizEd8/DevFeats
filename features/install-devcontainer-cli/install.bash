_detect_version() {
  command -v devcontainer > /dev/null 2>&1 || return 1
  devcontainer --version 2> /dev/null | head -n 1
}

_install_script() {
  local _version="${1-}" _install_prefix="${2-}" _node_version="${3-}" _update="${4-}" _uninstall="${5-}"
  local _asset_dir
  _asset_dir="$(uri__fetch_asset \
    "https://raw.githubusercontent.com/${GH_REPO}/main/scripts/install.sh" \
    --chmod-exec install.sh \
    --installer-dir "${INSTALLER_DIR}")" || return 1

  local -a _args
  _args=(--prefix "${_install_prefix}" --node-version "${_node_version}")
  [[ -n "${_version}" && "${_version}" != "latest" ]] && _args+=(--version "${_version}")
  [[ "${_update}" == "true" ]] && _args+=(--update)
  [[ "${_uninstall}" == "true" ]] && _args+=(--uninstall)

  sh "${_asset_dir}/install.sh" "${_args[@]}"
}

_ensure_npm() {
  command -v npm > /dev/null 2>&1 && return 0
  ospkg__install_user nodejs npm || ospkg__install_user nodejs || return 1
  command -v npm > /dev/null 2>&1
}

_install_npm() {
  local _version="${1-}" _install_prefix="${2-}" _uninstall="${3-}"
  _ensure_npm || {
    logging__error "install-devcontainer-cli: npm is required for method=npm."
    return 1
  }

  local -a _args
  _args=(-g)
  [[ -n "${_install_prefix}" ]] && _args+=(--prefix "${_install_prefix}")
  if [[ "${_uninstall}" == "true" ]]; then
    npm "${_args[@]}" uninstall "@devcontainers/cli"
    return 0
  fi

  if [[ -z "${_version}" || "${_version}" == "latest" ]]; then
    npm "${_args[@]}" install "@devcontainers/cli"
  else
    npm "${_args[@]}" install "@devcontainers/cli@${_version}"
  fi
}

_resolve_auto_method() {
  local _kernel _arch
  _kernel="$(os__kernel)"
  _arch="$(os__arch)"
  case "${_kernel}:${_arch}" in
    Linux:x86_64 | Linux:amd64 | Linux:aarch64 | Linux:arm64 | Darwin:x86_64 | Darwin:amd64 | Darwin:arm64 | Darwin:aarch64)
      printf '%s\n' "script"
      ;;
    *)
      printf '%s\n' "npm"
      ;;
  esac
}

_run() {
  _resolved_method="${METHOD}"
  if [[ "${_resolved_method}" == "auto" ]]; then
    _resolved_method="$(_resolve_auto_method)"
  fi

  _existing_ver="$(_detect_version 2> /dev/null || true)"
  if [[ -n "${_existing_ver}" && "${UNINSTALL}" != "true" ]]; then
    if [[ "${IF_EXISTS}" == "fail" ]]; then
      logging__error "install-devcontainer-cli: devcontainer already present (${_existing_ver})."
      exit 1
    fi
    if [[ "${IF_EXISTS}" == "skip" && "${UPDATE}" != "true" ]]; then
      logging__info "install-devcontainer-cli: existing devcontainer detected, skipping."
      exit 0
    fi
  fi

  case "${_resolved_method}" in
    script)
      _dep_install_buildtime_download || exit 1
      _install_script "${VERSION}" "${PREFIX}" "${NODE_VERSION}" "${UPDATE}" "${UNINSTALL}" || exit 1
      ;;
    npm)
      _install_npm "${VERSION}" "${PREFIX}" "${UNINSTALL}" || exit 1
      ;;
    *)
      logging__error "install-devcontainer-cli: unsupported method '${_resolved_method}'."
      exit 1
      ;;
  esac

  if [[ "${UNINSTALL}" == "true" ]]; then
    logging__success "install-devcontainer-cli: uninstall complete."
    exit 0
  fi

  if [[ ! -x "${PREFIX}/bin/devcontainer" ]]; then
    logging__error "install-devcontainer-cli: devcontainer not found at ${PREFIX}/bin/devcontainer after install."
    exit 1
  fi

  logging__success "install-devcontainer-cli: installed $("${PREFIX}/bin/devcontainer" --version 2> /dev/null | head -n 1)"
}

_run
