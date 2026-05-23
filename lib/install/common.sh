# shellcheck shell=bash
# Do not edit _lib/ copies directly — edit lib/ instead.

# @brief _install__sanitize_key <raw> — Convert arbitrary tool/group identifiers to safe lowercase key fragments.
_install__sanitize_key() {
  local _raw="${1-}"
  _raw="${_raw,,}"
  _raw="${_raw//\//_}"
  _raw="${_raw//[^a-z0-9._-]/_}"
  printf '%s\n' "$_raw"
}

# @brief install__state_dir — Print installer state directory path under `_LOGGING__SYSSET_TMPDIR` (creates it if missing).
install__state_dir() {
  file__tmpdir "install-state"
}

# @brief install__state_file <tool> — Print state file path for a tool key.
install__state_file() {
  local _tool="${1-}" _key
  _key="$(_install__sanitize_key "$_tool")"
  printf '%s/%s.state\n' "$(install__state_dir)" "$_key"
}

# @brief install__state_context <tool> — Read `context` field from tool state file.
install__state_context() {
  local _tool="${1-}" _f _ctx
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _ctx="$(sed -n 's/^context=//p' "$_f" | head -n1)"
  [[ -n "$_ctx" ]] || return 1
  printf '%s\n' "$_ctx"
}

# @brief install__state_install_path <tool> — Read `install_path` field from tool state file.
install__state_install_path() {
  local _tool="${1-}" _f _p
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _p="$(sed -n 's/^install_path=//p' "$_f" | head -n1)"
  [[ -n "$_p" ]] || return 1
  printf '%s\n' "$_p"
}

# @brief install__state_owner_group <tool> — Read `owner_group` field from tool state file.
install__state_owner_group() {
  local _tool="${1-}" _f _g
  _f="$(install__state_file "$_tool")"
  [[ -f "$_f" ]] || return 1
  _g="$(sed -n 's/^owner_group=//p' "$_f" | head -n1)"
  [[ -n "$_g" ]] || return 1
  printf '%s\n' "$_g"
}

# @brief install__state_record <tool> <context> <method> <install_path> <owner_group> — Persist ownership metadata for a tool install.
install__state_record() {
  local _tool="${1-}" _context="${2-}" _method="${3-}" _install_path="${4-}" _owner_group="${5-}"
  local _f
  [[ -n "$_tool" && -n "$_context" ]] || return 1
  _f="$(install__state_file "$_tool")"
  cat > "$_f" << EOF
tool=${_tool}
context=${_context}
method=${_method}
install_path=${_install_path}
owner_group=${_owner_group}
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2> /dev/null || true)
EOF
  return 0
}

# @brief install__copy_bin <src> <dest> — Copy a binary to `<dest>` with executable permissions (0755), creating parent directories as needed.
#
# Uses `install` (coreutils) when available for an atomic copy+mode operation;
# falls back to `cp` + `chmod` otherwise. Both `cp` and `chmod` are POSIX
# mandated and available on any bare OS, so no package bootstrapping is needed.
#
# Args:
#   <src>   Path to the source binary.
#   <dest>  Destination file path (not a directory).
#
# Returns: 0 on success, 1 on failure.
install__copy_bin() {
  local _src="$1" _dest="$2"
  mkdir -p "$(dirname "$_dest")" || {
    logging__error "install__copy_bin: failed to create directory '$(dirname "$_dest")'."
    return 1
  }
  if command -v install > /dev/null 2>&1; then
    install -m 0755 "$_src" "$_dest"
  else
    cp "$_src" "$_dest" && chmod 0755 "$_dest"
  fi
}

# @brief install__read_state <tool> <ctx_var> <path_var> <group_var> — Read all three installation-state fields into caller-named variables in a single call.
#
# Each field is populated from the state file written by `install__state_record`.
# Fields absent from the state file (missing file or missing key) are set to
# empty strings. Uses `printf -v` so no extra subshell is spawned per field.
#
# Args:
#   <tool>       Tool name key (same value passed to `install__state_record`).
#   <ctx_var>    Name of the variable to receive the `context` field.
#   <path_var>   Name of the variable to receive the `install_path` field.
#   <group_var>  Name of the variable to receive the `owner_group` field.
install__read_state() {
  local _tool="$1" _ctx_var="$2" _path_var="$3" _group_var="$4"
  printf -v "$_ctx_var" '%s' "$(install__state_context "$_tool" 2> /dev/null || true)"
  printf -v "$_path_var" '%s' "$(install__state_install_path "$_tool" 2> /dev/null || true)"
  printf -v "$_group_var" '%s' "$(install__state_owner_group "$_tool" 2> /dev/null || true)"
}

# @brief install__parse_common_opts <caller> <ctx_v> <ver_v> <method_v> <prefix_v> <ife_v> <repos_v> <group_v> <idir_v> <ghrepo_v> <extra_arr_v> "$@" — Parse standard install-module flags into caller-named variables.
#
# Recognised flags (each takes one value argument):
#   --context, --version, --method, --prefix, --if-exists,
#   --repos-manifest, --owner-group, --installer-dir, --gh-repo
#
# Unknown flags are appended (with their following value token) to the array
# variable named by <extra_arr_v>.  Pass "" for <extra_arr_v> to make unknown
# flags a fatal error (logged under <caller>).
#
# Callers must initialise variables to their defaults before calling this
# function; only flags that are present on the command line are written.
#
# Args:
#   <caller>       Function name used in error messages.
#   <ctx_v>        Variable name for --context.
#   <ver_v>        Variable name for --version.
#   <method_v>     Variable name for --method.
#   <prefix_v>     Variable name for --prefix.
#   <ife_v>        Variable name for --if-exists.
#   <repos_v>      Variable name for --repos-manifest.
#   <group_v>      Variable name for --owner-group.
#   <idir_v>       Variable name for --installer-dir.
#   <ghrepo_v>     Variable name for --gh-repo.
#   <extra_arr_v>  Array variable name for unrecognised flags (or "" to error).
#   "$@"           Remaining positional args from the caller.
#
# Returns: 0 on success, 1 on unrecognised flag when <extra_arr_v> is "".
install__parse_common_opts() {
  local _caller="$1" _pctx="$2" _pver="$3" _pmethod="$4" _pprefix="$5"
  local _pife="$6" _prepos="$7" _pgroup="$8" _pidir="$9" _pghrepo="${10-}" _pextra="${11-}"
  shift 11
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context)
        shift
        printf -v "$_pctx" '%s' "${1-}"
        ;;
      --version)
        shift
        printf -v "$_pver" '%s' "${1-}"
        ;;
      --method)
        shift
        printf -v "$_pmethod" '%s' "${1-}"
        ;;
      --prefix)
        shift
        printf -v "$_pprefix" '%s' "${1-}"
        ;;
      --if-exists)
        shift
        printf -v "$_pife" '%s' "${1-}"
        ;;
      --repos-manifest)
        shift
        printf -v "$_prepos" '%s' "${1-}"
        ;;
      --owner-group)
        shift
        printf -v "$_pgroup" '%s' "${1-}"
        ;;
      --installer-dir)
        shift
        printf -v "$_pidir" '%s' "${1-}"
        ;;
      --gh-repo)
        shift
        [[ -n "$_pghrepo" ]] && printf -v "$_pghrepo" '%s' "${1-}"
        ;;
      *)
        if [[ -n "$_pextra" ]]; then
          eval "${_pextra}+=($(printf '%q' "$1"))"
        else
          logging__error "${_caller}: unknown option '$1'"
          return 1
        fi
        ;;
    esac
    shift
  done
}

# @brief install__build_release_args <context> <group> <installer_dir> <out_owner_group_arr> <out_idir_arr> — Build the `--owner-group` and `--installer-dir` argument arrays for `github__install_release`.
#
# Populates the array variables named by <out_owner_group_arr> and <out_idir_arr>:
#   --owner-group <group>      added when context == "internal"
#   --installer-dir <dir>      added when installer_dir is non-empty
#
# Args:
#   <context>           "internal" or "user".
#   <group>             Resource-tracking group ID.
#   <installer_dir>     Optional persistent work directory (may be empty).
#   <out_owner_group_arr>  Name of the caller's array variable for --owner-group args.
#   <out_idir_arr>         Name of the caller's array variable for --installer-dir args.
install__build_release_args() {
  local _context="$1" _group="$2" _installer_dir="$3"
  # shellcheck disable=SC2178
  local -n _bra_og="$4" _bra_id="$5"
  _bra_og=()
  _bra_id=()
  [[ "$_context" == "internal" ]] && _bra_og=(--owner-group "$_group")
  [[ -n "$_installer_dir" ]] && _bra_id=(--installer-dir "$_installer_dir")
}

# @brief install__maybe_promote_to_user <tool> <context> <method> <owner_group> <existing> <state_ctx_var> <state_path_var> <state_group_var> — Promote an internal install to user-owned when context==user and recorded state==internal.
#
# If the conditions are met: untracks the artifact from cleanup, re-records it
# as user-owned, and sets the caller's state_ctx variable to "user".  A no-op
# when the conditions are not met.
#
# Args:
#   <tool>            Tool name key (e.g. "jq").
#   <context>         Caller's requested context ("internal" or "user").
#   <method>          Install method string recorded in the state file.
#   <owner_group>     Fallback owner-group when the state file has none.
#   <existing>        Path to the existing binary (empty → always a no-op).
#   <state_ctx_var>   Name of caller's variable holding the recorded context.
#   <state_path_var>  Name of caller's variable holding the recorded install path.
#   <state_group_var> Name of caller's variable holding the recorded owner group.
install__maybe_promote_to_user() {
  local _tool="$1" _context="$2" _method="$3" _owner_group="$4" _existing="$5"
  local _ctx_var="$6" _path_var="$7" _group_var="$8"
  local _state_ctx="${!_ctx_var}" _state_path="${!_path_var}" _state_group="${!_group_var}"
  [[ -n "$_existing" && "$_context" == "user" && "$_state_ctx" == "internal" ]] || return 0
  install__promote_path_to_user "${_state_group:-$_owner_group}" "$_state_path"
  install__state_record "$_tool" "user" "${_method}" "${_existing}" "$_owner_group" || true
  printf -v "$_ctx_var" '%s' "user"
}

# @brief install__track_internal_path <group-id> <path> — Register internal non-PM artifact path for cleanup via ospkg resource tracking.
install__track_internal_path() {
  local _group="${1-}" _path="${2-}"
  [[ -n "$_group" && -n "$_path" ]] || return 0
  command -v ospkg__track_resource > /dev/null 2>&1 || return 0
  ospkg__track_resource "$_group" "$_path" || true
  return 0
}

# @brief install__promote_path_to_user <group-id> <path> — Remove a previously tracked internal artifact path from cleanup tracking.
install__promote_path_to_user() {
  local _group="${1-}" _path="${2-}"
  [[ -n "$_path" ]] || return 0
  command -v ospkg__untrack_resource > /dev/null 2>&1 || return 0
  ospkg__untrack_resource "$_group" "$_path" || true
  return 0
}
