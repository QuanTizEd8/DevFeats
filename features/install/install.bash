# Write inline script content to a file, prepending '#!/bin/bash' if no shebang.
_write_inline() {
  local _content="$1" _dest="$2"
  if [[ "${_content}" == '#!'* ]]; then
    printf '%s\n' "${_content}" > "${_dest}"
  else
    printf '#!/bin/bash\n%s\n' "${_content}" > "${_dest}"
  fi
  chmod +x "${_dest}"
}

# Execute a script, optionally escalated to root.
_exec_script() {
  local _path="$1" _label="$2"
  logging__launch "Executing ${_label}..."
  if [[ "${RUN_AS_ROOT}" == "true" ]]; then
    users__run_privileged "${_path}"
  else
    "${_path}"
  fi
}

# shellcheck disable=SC2329,SC2317
__install_run__() {
  local _failed=0

  # Stage 1: prescript
  if [[ -n "${PRESCRIPT}" ]]; then
    local _prescript="${INSTALLER_DIR}/prescript.sh"
    _write_inline "${PRESCRIPT}" "${_prescript}"
    if _exec_script "${_prescript}" "prescript"; then
      logging__success "Prescript completed."
    else
      local _rc=$?
      if [[ "${FAIL_FAST}" == "true" ]]; then
        logging__error "Prescript failed (exit ${_rc}); aborting."
        return 1
      fi
      _failed=$((_failed + 1))
      logging__warn "Prescript failed (exit ${_rc}); continuing."
    fi
  fi

  # Stage 2: scripts array
  local _script_idx=0
  local _uri
  for _uri in "${SCRIPTS[@]}"; do
    [[ -z "${_uri}" ]] && continue
    _script_idx=$((_script_idx + 1))
    local _script_dest="${INSTALLER_DIR}/script-${_script_idx}.sh"
    logging__info "Fetching script ${_script_idx} from '${_uri}'..."
    if ! uri__fetch_asset "${_uri}" \
      --binary-dest "${_script_dest}" \
      --installer-dir "${INSTALLER_DIR}" > /dev/null; then
      if [[ "${FAIL_FAST}" == "true" ]]; then
        logging__error "Failed to fetch script ${_script_idx} ('${_uri}'); aborting."
        return 1
      fi
      _failed=$((_failed + 1))
      logging__warn "Failed to fetch script ${_script_idx} ('${_uri}'); continuing."
      continue
    fi
    if _exec_script "${_script_dest}" "script ${_script_idx}"; then
      logging__success "Script ${_script_idx} completed."
    else
      local _rc=$?
      if [[ "${FAIL_FAST}" == "true" ]]; then
        logging__error "Script ${_script_idx} ('${_uri}') failed (exit ${_rc}); aborting."
        return 1
      fi
      _failed=$((_failed + 1))
      logging__warn "Script ${_script_idx} ('${_uri}') failed (exit ${_rc}); continuing."
    fi
  done

  # Stage 3: postscript
  if [[ -n "${POSTSCRIPT}" ]]; then
    local _postscript="${INSTALLER_DIR}/postscript.sh"
    _write_inline "${POSTSCRIPT}" "${_postscript}"
    if _exec_script "${_postscript}" "postscript"; then
      logging__success "Postscript completed."
    else
      local _rc=$?
      if [[ "${FAIL_FAST}" == "true" ]]; then
        logging__error "Postscript failed (exit ${_rc}); aborting."
        return 1
      fi
      _failed=$((_failed + 1))
      logging__warn "Postscript failed (exit ${_rc}); continuing."
    fi
  fi

  if [[ "${_failed}" -gt 0 ]]; then
    logging__error "${_failed} script(s) failed."
    return 1
  fi
  return 0
}
