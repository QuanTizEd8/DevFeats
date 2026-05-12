#!/usr/bin/env bash
# shellcheck source=lib/install/yq.sh
. "${_SELF_DIR}/_lib/install/yq.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/github.sh
. "${_SELF_DIR}/_lib/github.sh"

# _yq__resolve_version — resolve VERSION to a bare semver string (no "v" prefix).
# Mutates the VERSION global. Exits 1 on API error or unrecognised format.
_yq__resolve_version() {
  logging__fn_entry "_yq__resolve_version"
  if [ "${VERSION}" = "latest" ]; then
    local _tag
    _tag="$(github__latest_tag "mikefarah/yq")" || {
      logging__error "Failed to fetch latest yq tag from GitHub."
      exit 1
    }
    VERSION="${_tag#v}"
    logging__info "Resolved 'latest' to version '${VERSION}'"
  else
    VERSION="${VERSION#v}"
    if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      logging__error "Unrecognised version string '${VERSION}'. Expected X.Y.Z or vX.Y.Z."
      exit 1
    fi
  fi
  logging__fn_exit "_yq__resolve_version"
  return 0
}

# _yq__get_installed_version <bin> — print bare semver of installed yq, or empty.
_yq__get_installed_version() {
  local _bin="${1-}"
  [[ -x "${_bin}" ]] || return 0
  "${_bin}" --version 2> /dev/null | awk '{print $NF}' | sed 's/^v//' || true
}

# _yq__install_completions — write shell completion files for shells in SHELL_COMPLETIONS.
_yq__install_completions() {
  logging__fn_entry "_yq__install_completions"
  if [ "${#SHELL_COMPLETIONS[@]}" -eq 0 ]; then
    logging__info "shell_completions is empty; skipping completion install."
    logging__fn_exit "_yq__install_completions"
    return 0
  fi
  local _yq_bin
  if command -v yq > /dev/null 2>&1; then
    _yq_bin="$(command -v yq)"
  elif [ -x "${PREFIX}/bin/yq" ]; then
    _yq_bin="${PREFIX}/bin/yq"
  else
    logging__warn "yq not found on PATH or at '${PREFIX}/bin/yq'; skipping completion install."
    logging__fn_exit "_yq__install_completions"
    return 0
  fi
  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    local _content
    _content="$("${_yq_bin}" shell-completion "${_shell}" 2> /dev/null)" || {
      logging__warn "yq shell-completion ${_shell} failed; skipping."
      continue
    }
    case "${_shell}" in
      bash)
        if [ "$(id -u)" = "0" ]; then
          mkdir -p /etc/bash_completion.d
          printf '%s\n' "${_content}" > /etc/bash_completion.d/yq
          logging__success "Bash completion written to /etc/bash_completion.d/yq"
        else
          mkdir -p "${HOME}/.local/share/bash-completion/completions"
          printf '%s\n' "${_content}" > "${HOME}/.local/share/bash-completion/completions/yq"
          logging__success "Bash completion written to ${HOME}/.local/share/bash-completion/completions/yq"
        fi
        ;;
      zsh)
        if [ "$(id -u)" = "0" ]; then
          local _zshdir
          _zshdir="$(shell__detect_zshdir)"
          mkdir -p "${_zshdir}/completions"
          printf '%s\n' "${_content}" > "${_zshdir}/completions/_yq"
          logging__success "Zsh completion written to ${_zshdir}/completions/_yq"
        else
          mkdir -p "${HOME}/.zfunc"
          printf '%s\n' "${_content}" > "${HOME}/.zfunc/_yq"
          logging__success "Zsh completion written to ${HOME}/.zfunc/_yq"
        fi
        ;;
      fish)
        local _fish_dir="${HOME}/.config/fish/completions"
        mkdir -p "${_fish_dir}"
        printf '%s\n' "${_content}" > "${_fish_dir}/yq.fish"
        logging__success "Fish completion written to ${_fish_dir}/yq.fish"
        ;;
      *)
        logging__error "Unsupported shell: '${_shell}' (expected: bash, zsh, fish)"
        exit 1
        ;;
    esac
  done
  logging__fn_exit "_yq__install_completions"
  return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────
_yq__resolve_version

# Version-match idempotency: skip reinstall when the binary at the target
# location already matches the resolved version (regardless of if_exists).
_YQ_TARGET_BIN="${PREFIX}/bin/yq"
_INSTALLED_VER=""
if [ "${METHOD}" != "package" ] && [ -x "${_YQ_TARGET_BIN}" ]; then
  _INSTALLED_VER="$(_yq__get_installed_version "${_YQ_TARGET_BIN}")"
fi
_SKIP_INSTALL=false
if [ -n "${_INSTALLED_VER}" ] && [ "${_INSTALLED_VER}" = "${VERSION}" ]; then
  logging__info "yq ${VERSION} is already installed at '${_YQ_TARGET_BIN}' — skipping install."
  _SKIP_INSTALL=true
elif [ "${METHOD}" != "package" ] && [ -x "${_YQ_TARGET_BIN}" ]; then
  case "${IF_EXISTS}" in
    skip)
      logging__info "yq already installed at '${_YQ_TARGET_BIN}' (${_INSTALLED_VER}) — skipping (if_exists=skip)."
      _SKIP_INSTALL=true
      ;;
    fail)
      logging__error "yq already installed at '${_YQ_TARGET_BIN}' (${_INSTALLED_VER}) and if_exists=fail."
      exit 1
      ;;
    reinstall)
      logging__info "Removing existing yq binary at '${_YQ_TARGET_BIN}' (if_exists=reinstall)."
      rm -f "${_YQ_TARGET_BIN}"
      ;;
  esac
fi

if [ "${_SKIP_INSTALL}" != "true" ]; then
  install__yq \
    --context user \
    --owner-group "feature::install-yq" \
    --method "${METHOD}" \
    --if-exists "${IF_EXISTS}" \
    --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
    --prefix "${PREFIX}" \
    --version "${VERSION}" > /dev/null
fi
if [ "${METHOD}" = "auto" ]; then
  if [ -x "${PREFIX}/bin/yq" ]; then
    METHOD=binary
  else
    METHOD=package
  fi
fi
_yq__install_completions
