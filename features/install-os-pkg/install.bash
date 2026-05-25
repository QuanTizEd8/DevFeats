if [[ -z "$MANIFEST" && "$INSTALL_SELF" != true ]]; then
  logging__error "'MANIFEST' is required when 'install_self' is false."
  exit 1
fi
# Normalize: some environments (e.g. devcontainer CLI build args) serialize
# multi-line strings with literal \n rather than real newlines.  Expand them
# so inline-manifest detection works correctly.
if [[ -n "$MANIFEST" && "$MANIFEST" != *$'\n'* && "$MANIFEST" == *'\n'* ]]; then
  MANIFEST="$(printf '%b' "$MANIFEST")"
  printf 'ℹ️  Expanded literal \\n escapes in MANIFEST value.\n' >&2
fi

declare -p FETCH_HEADERS &> /dev/null || FETCH_HEADERS=()
[ "${FETCH_NETRC+defined}" ] || FETCH_NETRC=""

if [[ -n "$LIFECYCLE_HOOK" ]]; then
  if [[ -z "$MANIFEST" ]]; then
    logging__error "'manifest' is required when 'lifecycle_hook' is set."
    exit 1
  fi
fi

if ! [[ "$LISTS_MAX_AGE" =~ ^[0-9]+$ ]]; then
  logging__error "Invalid lists_max_age value: '$LISTS_MAX_AGE'. Must be a non-negative integer."
  exit 1
fi

# Always install the backing library so lifecycle hook scripts can reference it.
# The user-visible wrapper script (/usr/local/bin/install-os-pkg) is optional
# and only written when install_self=true.
_LIB_DIR="/usr/local/lib/install-os-pkg"
if [ ! -d "$_LIB_DIR" ]; then
  file__mkdir "$_LIB_DIR"
  file__cp "$0" "$_LIB_DIR/install.sh"
  file__chmod +x "$_LIB_DIR/install.sh"
  file__cp -r "$_FEAT_DIR/_lib" "$_LIB_DIR/"
fi

if [[ "$INSTALL_SELF" == true ]]; then
  _BIN="/usr/local/bin/install-os-pkg"
  if [ ! -x "$_BIN" ]; then
    printf '#!/bin/sh\nexec bash "%s/install.sh" "$@"\n' "$_LIB_DIR" | file__tee "$_BIN"
    file__chmod +x "$_BIN"
    logging__success "Installed system command: $_BIN"
  fi
else
  logging__info "Skipping system command installation (install_self=false)."
fi

# When lifecycle_hook is set, write a hook script and exit without installing.
if [[ -n "$LIFECYCLE_HOOK" ]]; then
  _HOOK_DIR="${_LIFECYCLE_SCRIPT_DIR}"
  file__mkdir "$_HOOK_DIR"
  _MANIFEST_ARG="$MANIFEST"
  if [[ "$MANIFEST" == *$'\n'* ]]; then
    printf '%s' "$MANIFEST" | file__tee "$_HOOK_DIR/manifest.yaml"
    _MANIFEST_ARG="$_HOOK_DIR/manifest.yaml"
    logging__info "Saved inline manifest to '$_MANIFEST_ARG'."
  fi
  _HOOK_OPTS="--manifest $(printf '%q' "$_MANIFEST_ARG")"
  [[ -n "${FETCH_NETRC:-}" ]] && _HOOK_OPTS+=" --fetch-netrc-file $(printf '%q' "$FETCH_NETRC")"
  if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
    for _osh in "${FETCH_HEADERS[@]}"; do
      [[ -n "${_osh}" ]] && _HOOK_OPTS+=" --fetch-header $(printf '%q' "$_osh")"
    done
  fi
  [[ "${LOG_LEVEL:-info}" == "trace" ]] && _HOOK_OPTS+=" --log_level trace"
  [[ "$INTERACTIVE" == true ]] && _HOOK_OPTS+=" --interactive true"
  [[ "$KEEP_REPOS" == true ]] && _HOOK_OPTS+=" --keep_repos true"
  [[ -n "$LOG_FILE" ]] && _HOOK_OPTS+=" --log_file $(printf '%q' "$LOG_FILE")"
  [[ "$UPDATE" == false ]] && _HOOK_OPTS+=" --update-index false"
  _HOOK_OPTS+=" --lists_max_age $LISTS_MAX_AGE"
  [[ "$DRY_RUN" == true ]] && _HOOK_OPTS+=" --dry_run true"
  [[ "$SKIP_INSTALLED" == true ]] && _HOOK_OPTS+=" --skip_installed true"
  [[ "$PREFER_LINUXBREW" == true ]] && _HOOK_OPTS+=" --prefer_linuxbrew true"
  _HOOK_OPTS+=" --keep_cache $KEEP_CACHE"
  case "$LIFECYCLE_HOOK" in
    onCreate) _HOOK_FILE="$_HOOK_DIR/on-create.sh" ;;
    updateContent) _HOOK_FILE="$_HOOK_DIR/update-content.sh" ;;
    postCreate) _HOOK_FILE="$_HOOK_DIR/post-create.sh" ;;
  esac
  printf '#!/bin/sh\nset -e\nexec bash "%s" %s\n' \
    "/usr/local/lib/install-os-pkg/install.sh" "$_HOOK_OPTS" | file__tee "$_HOOK_FILE"
  file__chmod +x "$_HOOK_FILE"
  logging__success "Registered lifecycle hook '$LIFECYCLE_HOOK': $_HOOK_FILE"
  exit 0
fi

_OSPKG_ARGS=()
[[ -n "$MANIFEST" ]] && _OSPKG_ARGS+=(--manifest "$MANIFEST")
[[ -n "${FETCH_NETRC:-}" ]] && _OSPKG_ARGS+=(--fetch-netrc-file "$FETCH_NETRC")
if [[ ${#FETCH_HEADERS[@]} -gt 0 ]]; then
  for _osh in "${FETCH_HEADERS[@]}"; do
    [[ -n "${_osh}" ]] && _OSPKG_ARGS+=(--fetch-header "$_osh")
  done
fi
[[ "$UPDATE" == false ]] && _OSPKG_ARGS+=(--update-index false)

[[ "$KEEP_REPOS" == true ]] && _OSPKG_ARGS+=(--keep_repos)
_OSPKG_ARGS+=(--lists_max_age "$LISTS_MAX_AGE")
[[ "$DRY_RUN" == true ]] && _OSPKG_ARGS+=(--dry_run)
[[ "$SKIP_INSTALLED" == true ]] && _OSPKG_ARGS+=(--skip_installed)
[[ "$PREFER_LINUXBREW" == true ]] && _OSPKG_ARGS+=(--prefer_linuxbrew)
[[ "$INTERACTIVE" == true ]] && _OSPKG_ARGS+=(--interactive)
ospkg__run "${_OSPKG_ARGS[@]}"
