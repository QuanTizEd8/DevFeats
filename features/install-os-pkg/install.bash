# shellcheck shell=bash

__install_run__() {
  logging__install "Running install-os-pkg (install_self='${INSTALL_SELF}', lifecycle_hook='${LIFECYCLE_HOOK:-}')."
  if [[ -z "$MANIFEST" && "$INSTALL_SELF" != true ]]; then
    logging__error "'MANIFEST' is required when 'install_self' is false."
    return 1
  fi
  # Normalize: some environments (e.g. devcontainer CLI build args) serialize
  # multi-line strings with literal \n rather than real newlines.  Expand them
  # so inline-manifest detection works correctly.
  if [[ -n "$MANIFEST" && "$MANIFEST" != *$'\n'* && "$MANIFEST" == *'\n'* ]]; then
    MANIFEST="$(printf '%b' "$MANIFEST")"
    logging__info "Expanded literal \\n escapes in MANIFEST value."
  fi

  if [[ -n "$LIFECYCLE_HOOK" ]]; then
    if [[ -z "$MANIFEST" ]]; then
      logging__error "'manifest' is required when 'lifecycle_hook' is set."
      return 1
    fi
  fi

  if ! [[ "$LISTS_MAX_AGE" =~ ^[0-9]+$ ]]; then
    logging__error "Invalid lists_max_age value: '$LISTS_MAX_AGE'. Must be a non-negative integer."
    return 1
  fi

  # Always install the backing library so lifecycle hook scripts can reference it.
  # The user-visible wrapper script (/usr/local/bin/install-os-pkg) is optional
  # and only written when install_self=true.
  local _LIB_DIR="/usr/local/lib/install-os-pkg"
  if [ ! -d "$_LIB_DIR" ]; then
    logging__install "Installing backing library to '${_LIB_DIR}'."
    file__mkdir "$_LIB_DIR"
    file__cp "$0" "$_LIB_DIR/install.sh"
    file__chmod +x "$_LIB_DIR/install.sh"
    file__cp -r "$_FEAT_DIR/lib" "$_LIB_DIR/"
  else
    logging__skip "Backing library already present at '${_LIB_DIR}'; skipping bootstrap."
  fi

  if [[ "$INSTALL_SELF" == true ]]; then
    local _BIN="/usr/local/bin/install-os-pkg"
    if [ ! -x "$_BIN" ]; then
      printf '#!/bin/sh\nexec bash "%s/install.sh" "$@"\n' "$_LIB_DIR" | file__tee "$_BIN"
      file__chmod +x "$_BIN"
      logging__success "Installed system command: $_BIN"
    fi
  else
    logging__skip "install_self=false; skipping system command installation."
  fi

  # When lifecycle_hook is set, write a hook script and exit without installing.
  if [[ -n "$LIFECYCLE_HOOK" ]]; then
    local _HOOK_OPTS
    local _HOOK_DIR="${_FEAT_LIFECYCLE_DIR}"
    file__mkdir "$_HOOK_DIR"
    local _MANIFEST_ARG="$MANIFEST"
    if [[ "$MANIFEST" == *$'\n'* ]]; then
      printf '%s' "$MANIFEST" | file__tee "$_HOOK_DIR/manifest.yaml"
      _MANIFEST_ARG="$_HOOK_DIR/manifest.yaml"
      logging__info "Saved inline manifest to '$_MANIFEST_ARG'."
    fi
    _HOOK_OPTS="--manifest $(printf '%q' "$_MANIFEST_ARG")"
    [[ -n "${FETCH_NETRC:-}" ]] && _HOOK_OPTS+=" --fetch-netrc-file $(printf '%q' "$FETCH_NETRC")"
    if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
      local _osh
      for _osh in "${FETCH_HEADERS[@]}"; do
        [[ -n "${_osh}" ]] && _HOOK_OPTS+=" --fetch-header $(printf '%q' "$_osh")"
      done
    fi
    [[ -n "${LOG_LEVEL:-}" ]] && _HOOK_OPTS+=" --log_level $(printf '%q' "$LOG_LEVEL")"
    [[ -n "${LOG_FILE_LEVEL:-}" ]] && _HOOK_OPTS+=" --log_file_level $(printf '%q' "$LOG_FILE_LEVEL")"
    [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive true"
    [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos true"
    [[ -n "$LOG_FILE" ]] && _HOOK_OPTS+=" --log_file $(printf '%q' "$LOG_FILE")"
    [[ "$UPDATE" == false ]] && _HOOK_OPTS+=" --update-index false"
    _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
    [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run true"
    [[ "$PREFER_LINUXBREW" == true ]] && _HOOK_OPTS+=" --prefer_linuxbrew true"
    _HOOK_OPTS+=" --keep_cache $KEEP_CACHE"
    local _HOOK_FILE
    case "$LIFECYCLE_HOOK" in
      onCreate) _HOOK_FILE="${_FEAT_LIFECYCLE_ON_CREATE}install.sh" ;;
      updateContent) _HOOK_FILE="${_FEAT_LIFECYCLE_UPDATE_CONTENT}install.sh" ;;
      postCreate) _HOOK_FILE="${_FEAT_LIFECYCLE_POST_CREATE}install.sh" ;;
    esac
    printf '#!/bin/sh\nset -e\nexec bash "%s" %s\n' \
      "/usr/local/lib/install-os-pkg/install.sh" "$_HOOK_OPTS" | file__tee "$_HOOK_FILE"
    file__chmod +x "$_HOOK_FILE"
    logging__success "Registered lifecycle hook '$LIFECYCLE_HOOK': $_HOOK_FILE"
    return 0
  fi

  local -a _OSPKG_ARGS=()
  [[ -n "$MANIFEST" ]] && _OSPKG_ARGS+=(--manifest "$MANIFEST")
  [[ -n "${FETCH_NETRC:-}" ]] && _OSPKG_ARGS+=(--fetch-netrc-file "$FETCH_NETRC")
  if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
    local _osh
    for _osh in "${FETCH_HEADERS[@]}"; do
      [[ -n "${_osh}" ]] && _OSPKG_ARGS+=(--fetch-header "$_osh")
    done
  fi
  [[ "$UPDATE" == false ]] && _OSPKG_ARGS+=(--update-index false)

  [[ "$KEEP_REPOS" == true ]] && _OSPKG_ARGS+=(--keep_repos)
  _OSPKG_ARGS+=(--lists_max_age "$LISTS_MAX_AGE")
  [[ "$DRY_RUN" == true ]] && _OSPKG_ARGS+=(--dry_run)
  [[ "$PREFER_LINUXBREW" == true ]] && _OSPKG_ARGS+=(--prefer_linuxbrew)
  [[ "$INTERACTIVE" == true ]] && _OSPKG_ARGS+=(--interactive)
  logging__install "Running package installation via ospkg__run."
  ospkg__run "${_OSPKG_ARGS[@]}"
}
