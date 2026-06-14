# shellcheck shell=bash

# Prefer the Anthropic OS package repo (system-wide) when a supported package
# manager is available; fall back to npm-bundled (self-contained, no system
# Node.js required).
# shellcheck disable=SC2329,SC2317
__resolve_method() {
  logging__inspect "Resolving METHOD=auto for Claude Code."
  ospkg__detect 2> /dev/null || true
  case "${_OSPKG__FAMILY:-}" in
    apt | dnf | apk | brew)
      logging__info "Resolved METHOD=auto → 'upstream-package' (${_OSPKG__FAMILY})."
      printf 'upstream-package\n'
      ;;
    *)
      logging__info "Resolved METHOD=auto → 'npm-bundled' (no supported OS package repo)."
      printf 'npm-bundled\n'
      ;;
  esac
}

# script: when running as root, the bootstrap script installs to
# ${HOME}/.local/bin/claude (i.e. /root/.local/bin/claude).  Copy it to
# ${_RESOLVED_PREFIX}/bin/claude so it is accessible system-wide, and open the runtime
# directory so non-root users can execute the installed binary.
# shellcheck disable=SC2329,SC2317
__install_run_script_post() {
  if users__is_privileged; then
    local _src="${HOME}/.local/bin/claude"
    local _dest="${_RESOLVED_PREFIX}/bin/claude"
    if [[ -x "${_src}" && "${_src}" != "${_dest}" ]]; then
      logging__info "Copying claude from '${_src}' to '${_dest}'..."
      file__mkdir "${_RESOLVED_PREFIX}/bin"
      install -m 755 "${_src}" "${_dest}"
      local _runtime="${HOME}/.local/share/claude"
      if [[ -d "${_runtime}" ]]; then
        file__chmod -R a+rX "${_runtime}"
        logging__info "Made claude runtime at '${_runtime}' world-readable."
      fi
    fi
  fi
}
