#!/usr/bin/env bash
# shellcheck source=_lib/os.sh
. "${_SELF_DIR}/_lib/os.sh"
# shellcheck source=_lib/net.sh
. "${_SELF_DIR}/_lib/net.sh"
# shellcheck source=_lib/ospkg.sh
. "${_SELF_DIR}/_lib/ospkg.sh"

_devcontainer_cli__detect_version() {
  command -v devcontainer > /dev/null 2>&1 || return 1
  devcontainer --version 2> /dev/null | head -n 1
}

_devcontainer_cli__resolve_prefix() {
  local _prefix="${1-}"
  if [[ -z "${_prefix}" || "${_prefix}" == "auto" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      printf '%s\n' "/usr/local/devcontainers"
    else
      printf '%s\n' "${HOME}/.devcontainers"
    fi
    return 0
  fi
  printf '%s\n' "${_prefix}"
}

_devcontainer_cli__install_script() {
  local _version="${1-}" _prefix="${2-}" _node_version="${3-}" _update="${4-}" _uninstall="${5-}"
  local _tmp_dir _script
  _tmp_dir="$(mktemp -d)"
  _script="${_tmp_dir}/install.sh"
  net__fetch_url_file \
    "https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh" \
    "${_script}" || {
    rm -rf "${_tmp_dir}"
    return 1
  }
  chmod +x "${_script}" || true

  local -a _args
  _args=(--prefix "${_prefix}" --node-version "${_node_version}")
  [[ -n "${_version}" && "${_version}" != "latest" ]] && _args+=(--version "${_version}")
  [[ "${_update}" == "true" ]] && _args+=(--update)
  [[ "${_uninstall}" == "true" ]] && _args+=(--uninstall)

  sh "${_script}" "${_args[@]}" || {
    rm -rf "${_tmp_dir}"
    return 1
  }
  rm -rf "${_tmp_dir}"
  return 0
}

_devcontainer_cli__ensure_npm() {
  command -v npm > /dev/null 2>&1 && return 0
  ospkg__install_user nodejs npm || ospkg__install_user nodejs || return 1
  command -v npm > /dev/null 2>&1
}

_devcontainer_cli__install_npm() {
  local _version="${1-}" _prefix="${2-}" _uninstall="${3-}"
  _devcontainer_cli__ensure_npm || {
    logging__error "install-devcontainer-cli: npm is required for method=npm."
    return 1
  }

  local -a _args
  _args=(-g)
  [[ -n "${_prefix}" && "${_prefix}" != "auto" ]] && _args+=(--prefix "${_prefix}")
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

_devcontainer_cli__auto_method() {
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

_resolved_method="${METHOD}"
if [[ "${_resolved_method}" == "auto" ]]; then
  _resolved_method="$(_devcontainer_cli__auto_method)"
fi
_resolved_prefix="$(_devcontainer_cli__resolve_prefix "${PREFIX}")"

_existing_ver="$(_devcontainer_cli__detect_version 2> /dev/null || true)"
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
    _devcontainer_cli__install_script "${VERSION}" "${_resolved_prefix}" "${NODE_VERSION}" "${UPDATE}" "${UNINSTALL}" || exit 1
    ;;
  npm)
    _devcontainer_cli__install_npm "${VERSION}" "${_resolved_prefix}" "${UNINSTALL}" || exit 1
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

if ! command -v devcontainer > /dev/null 2>&1; then
  logging__error "install-devcontainer-cli: devcontainer not found after install."
  exit 1
fi

logging__success "install-devcontainer-cli: installed $(devcontainer --version 2> /dev/null | head -n 1)"
