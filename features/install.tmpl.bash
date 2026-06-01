#!/usr/bin/env bash
set -euo pipefail

__print_docs__() {
  cat << 'EOF'
${{ name }}$ v${{ version }}$

Usage: install.bash [OPTIONS]

Options:
${{ _script.usage_options }}$
EOF
  return
}

__main__() {
  # Main entry point for the install script.

  __init__ "$@"

  if [[ ! -v IF_EXISTS ]]; then
    # No `if_exists` option; no existence checks or conditional logic needed. Just install.
    __install__
    exit 0
  fi

  logging__info "Checking for existing installation"
  __detect_existing__

  if [[ -z "${_FEAT_EXISTING_PATH}" ]]; then
    case "${IF_EXISTS}" in
      uninstall)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' not found; nothing to uninstall (if_exists=uninstall)."
        exit 0
        ;;
      *)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' not found; installing (if_exists=${IF_EXISTS})."
        __install__
        exit 0
        ;;
    esac
  else
    case "${IF_EXISTS}" in
      skip)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; skipping (if_exists=skip)."
        exit 0
        ;;
      fail)
        logging__error "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; failing (if_exists=fail)."
        exit 1
        ;;
      uninstall)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; uninstalling (if_exists=uninstall)."
        __uninstall__
        exit 0
        ;;
      reinstall)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; reinstalling (if_exists=reinstall)."
        __reinstall__
        exit 0
        ;;
      update)
        logging__info "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' already present at '${_FEAT_EXISTING_PATH}'; updating (if_exists=update)."
        __update__
        exit 0
        ;;
      *)
        logging__error "Unknown if_exists value: '${IF_EXISTS}'"
        exit 1
        ;;
    esac
  fi
}

# Initialization
# ==============
__init__() {
  # Initialize the script.

  if declare -f __init_pre > /dev/null; then
    __init_pre
  fi

  __init_env__
  __init_lib__
  __init_script__
  __init_args__ "$@"

  if declare -f __init_post > /dev/null; then
    __init_post
  fi
}

__init_env__() {
  # Set internal environment variables.

  if declare -f __init_env_pre > /dev/null; then
    __init_env_pre
  fi

  # Runtime-computed variables (not in metadata; depend on script location):
  _FEAT_DIR="$(cd "$(dirname "$0")" && pwd)"
  _FEAT_FILES_DIR="${_FEAT_DIR}/files"
  _FEAT_DEPS_DIR="${_FEAT_DIR}/dependencies"

  # Metadata-derived variables (canonical source: metadata.shared.yaml _env_vars):
  ${{ _script.env_vars.assignments }}$

  # Contract variables (derived from _options.version and _options.method in metadata.yaml):
  ${{ _script.install_contract_vars.assignments }}$

  # Unexport variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare -g +x _FEAT_DIR _FEAT_FILES_DIR _FEAT_DEPS_DIR \
    ${{ _script.env_vars.unexports }}$ \
    ${{ _script.install_contract_vars.unexports }}$

  _SYSSET_BUILD_CONTEXT="${_SYSSET_BUILD_CONTEXT:-feature::$_FEAT_ID}"
  export _SYSSET_BUILD_CONTEXT

  if declare -f __init_env_post > /dev/null; then
    __init_env_post
  fi
}

__init_lib__() {
  # Source library functions.

  if declare -f __init_lib_pre > /dev/null; then
    __init_lib_pre
  fi

  # shellcheck source=lib/__init__.bash
  . "$_FEAT_DIR/lib/__init__.bash"

  if declare -f __init_lib_post > /dev/null; then
    __init_lib_post
  fi
}

__init_script__() {
  # Set up logging and exit trap.

  if declare -f __init_script_pre > /dev/null; then
    __init_script_pre
  fi

  logging__setup
  logging__feature_entry "$_FEAT_NAME v$_FEAT_VERSION"
  trap '__exit__' EXIT

  if declare -f __init_script_post > /dev/null; then
    __init_script_post
  fi
}

__init_args__() {
  # Parse and validate input arguments and apply defaults.

  if declare -f __init_args_pre > /dev/null; then
    __init_args_pre "$@"
  fi

  if [ "$#" -gt 0 ]; then
    logging__info "Script called with arguments: $*"

    ${{ _script.argparse.cli_inits }}$

    while [ "$#" -gt 0 ]; do
      case $1 in
        ${{ _script.argparse.case_arms }}$
        -h | --help)
          __print_docs__
          exit 0
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
  else
    logging__info "Script called with no arguments. Read environment variables."

    ${{ _script.argparse.env_reads }}$
  fi

  logging__set_level

  # Apply defaults.
  ${{ _script.argparse.defaults }}$

  # Normalize array options (trim elements; drop blank/whitespace-only lines).
  ${{ _script.argparse.normalize_arrays }}$

  # Resolve URI-capable option values to local filesystem paths (INSTALLER_DIR or a private temp dir).
  ${{ _script.argparse.uri_resolution }}$

  # Validate input options.
  ${{ _script.argparse.validations }}$

  # Unexport option variables — values remain accessible in this script,
  # but are not inherited by child processes.
  declare -g +x ${{ _script.argparse.unexports }}$

  if declare -f __init_args_post > /dev/null; then
    __init_args_post
  fi
}

# Existing installation detection
# ===============================
__detect_existing__() {

  if declare -f __detect_existing_pre > /dev/null; then
    __detect_existing_pre
  fi

  # Existence detection (cheap; side-effect-free)
  __detect_existing_path__
  # Existing installation method detection (no-op when nothing found)
  __detect_existing_method__

  if declare -f __detect_existing_post > /dev/null; then
    __detect_existing_post
  fi
}

__detect_existing_path__() {
  # Answer "is the tool already installed?" and record the result in
  # _FEAT_EXISTING_PATH (empty string = not found).
  #
  # Searches three locations in order, stopping as soon as one yields a hit:
  #  1. The feature's configured prefix directory — a binary installed there may
  #     be absent from PATH when the shell profile has not been sourced yet, which
  #     is common in fresh container builds where dotfiles are not yet loaded.
  #  2. RUNTIME_PATH (the user's PATH at container runtime, after all profiles are
  #     sourced) — tried when the feature exposes a RUNTIME_PATH option, because
  #     the runtime PATH may include directories not present at install time (e.g.
  #     ~/.local/bin added by a previously installed tool's profile snippet).
  #  3. The install-time PATH via 'command -v' — always tried as a final fallback
  #     when the prefix and RUNTIME_PATH checks both come up empty, to catch
  #     system-wide installs that bypass this feature's prefix entirely.
  #
  # Use __detect_existing_path_pre to set _FEAT_EXISTING_PATH before the auto-impl
  # runs, or override __detect_existing_path__ entirely when the tool's presence
  # cannot be determined by looking for a single binary (e.g. shell function,
  # directory, non-standard layout).
  #
  # If no primary binary name is known, _FEAT_EXISTING_PATH stays "". The
  # early-exit logic then treats the tool as absent and proceeds with a fresh
  # install regardless of if_exists.

  if declare -f __detect_existing_path_pre > /dev/null; then
    __detect_existing_path_pre
  fi

  declare -g _FEAT_EXISTING_PATH=""

  if [[ -n "${_FEAT_CONTRACT_PRIMARY_BIN:-}" ]]; then
    local _prefix_bin=""
    if [[ -v PREFIX ]]; then
      _prefix_bin="${PREFIX}/bin/${_FEAT_CONTRACT_PRIMARY_BIN}"
    fi
    if [[ -n "${_prefix_bin}" && -x "${_prefix_bin}" ]]; then
      _FEAT_EXISTING_PATH="${_prefix_bin}"
    else
      if [[ -v RUNTIME_PATH ]]; then
        _FEAT_EXISTING_PATH="$(PATH="${RUNTIME_PATH}" command -v "${_FEAT_CONTRACT_PRIMARY_BIN}" 2>/dev/null || true)"
      fi
      if [[ -z "${_FEAT_EXISTING_PATH}" ]]; then
        _FEAT_EXISTING_PATH="$(command -v "${_FEAT_CONTRACT_PRIMARY_BIN}" 2>/dev/null || true)"
      fi
    fi
  fi

  if declare -f __detect_existing_path_post > /dev/null; then
    __detect_existing_path_post
  fi
}

__detect_existing_method__() {
  # Determine how the existing installation (recorded in _FEAT_EXISTING_PATH) was
  # installed, and record the result in _FEAT_EXISTING_METHOD. Called as step 1b
  # immediately after __detect_existing_path__; no-op when _FEAT_EXISTING_PATH is
  # empty (nothing installed).
  #
  # Auto-implementation probe order (stops at first match):
  #  1. ospkg__is_managed: the OS package manager owns _FEAT_EXISTING_PATH.
  #     → "package"
  #  2. npm__is_bundled: the binary lives inside an npm package directory.
  #     → "npm-bundled"
  #  3. npm__is_managed: the npm global registry lists NPM_PACKAGE.
  #     Only tried when NPM_PACKAGE is non-empty.
  #     → "npm"
  #  4. Prefix path: _FEAT_EXISTING_PATH is under the feature's configured prefix.
  #     → "prefix" (exact sub-method — binary, cargo, source, script — is not
  #       distinguished; __uninstall__ removes the binary and any
  #       declared sidecar, which is sufficient for most tools).
  #  5. No match → "" (unknown; override __uninstall_run__ to handle custom
  #     teardown, or use __uninstall_run_pre to set _FEAT_EXISTING_METHOD).
  #
  # Use __detect_existing_method_pre to set _FEAT_EXISTING_METHOD before the
  # auto-impl runs, or override __detect_existing_method__ for fully custom logic.

  if declare -f __detect_existing_method_pre > /dev/null; then
    __detect_existing_method_pre
  fi

  declare -g _FEAT_EXISTING_METHOD=""
  [[ -n "${_FEAT_EXISTING_PATH}" ]] || return 0

  if ospkg__is_managed "${_FEAT_EXISTING_PATH}" 2>/dev/null; then
    if [[ -f "$(__dep_manifest_path__ run upstream-package)" ]]; then
      _FEAT_EXISTING_METHOD="upstream-package"
    else
      _FEAT_EXISTING_METHOD="package"
    fi
  elif npm__is_bundled "${_FEAT_EXISTING_PATH}" 2>/dev/null; then
    _FEAT_EXISTING_METHOD="npm-bundled"
  elif [[ -n "${NPM_PACKAGE:-}" ]] \
    && npm__is_managed "${_FEAT_EXISTING_PATH}" 2>/dev/null; then
    _FEAT_EXISTING_METHOD="npm"
  elif [[ -v PREFIX ]]; then
    local _prefix_val="${PREFIX:-}"
    if [[ -n "${_prefix_val}" && "${_FEAT_EXISTING_PATH}" == "${_prefix_val}/"* ]]; then
      _FEAT_EXISTING_METHOD="prefix"
    fi
  fi

  if declare -f __detect_existing_method_post > /dev/null; then
    __detect_existing_method_post
  fi
}

# Uninstallation
# ===============
__uninstall__() {

  if declare -f __uninstall_pre > /dev/null; then
    __uninstall_pre
  fi

  __uninstall_init__
  __uninstall_run__
  __uninstall_finish__

  if declare -f __uninstall_post > /dev/null; then
    __uninstall_post
  fi
}

__uninstall_init__() {

  if declare -f __uninstall_init_pre > /dev/null; then
    __uninstall_init_pre
  fi

  __verify_system_requirements__

  if declare -f __uninstall_init_post > /dev/null; then
    __uninstall_init_post
  fi
}

__uninstall_run__() {
  # Uninstall the existing installation recorded in _FEAT_EXISTING_PATH, using
  # the method detected by __detect_existing_method__ (step 1b).
  #
  # Called in three contexts:
  #   Step 2:                     if_exists=uninstall
  #   __reinstall__: if_exists=reinstall (existing path non-empty)
  #   __update__:    method migration during update
  #
  # Requires __detect_existing_path__ (step 1) and __detect_existing_method__
  # (step 1b) to have already run.
  #
  # Auto-implementations (keyed by _FEAT_EXISTING_METHOD):
  #   prefix            file__rm the primary binary (_FEAT_EXISTING_PATH) and any sidecar
  #                     declared in BINARY_SIDECAR_URI. Suitable for binary, cargo,
  #                     and simple source/script installs.
  #   npm               npm__uninstall_package for NPM_PACKAGE.
  #   npm-bundled       npm__uninstall_bundled --bin _FEAT_EXISTING_PATH.
  #   package           ospkg__run --manifest <run/os-pkg.yaml> --remove.
  #   upstream-package  ospkg__run --manifest <run/upstream-package.yaml> --remove.
  #   ""                No auto-impl — method unknown.
  #
  # For custom teardown (config files, extra binaries, etc.), use
  # __uninstall_run_pre to act before the auto-impl, or override __uninstall_run__
  # entirely when you need to replace it.

  if declare -f __uninstall_run_pre > /dev/null; then
    __uninstall_run_pre
  fi

  case "${_FEAT_EXISTING_METHOD:-}" in
    prefix)
      __uninstall_run_prefix__
      ;;
    npm)
      __uninstall_run_npm__
      ;;
    npm-bundled)
      __uninstall_run_npm_bundled__
      ;;
    package)
      __uninstall_run_package__
      ;;
    upstream-package)
      __uninstall_run_upstream_package__
      ;;
    "")
      logging__error "Cannot auto-uninstall '${_FEAT_EXISTING_PATH}': installation method unknown. Override __uninstall_run__ or use __uninstall_run_pre to handle it."
      return 1
      ;;
    *)
      logging__error "Cannot auto-uninstall '${_FEAT_EXISTING_PATH}': unrecognized _FEAT_EXISTING_METHOD='${_FEAT_EXISTING_METHOD}'. Override __uninstall_run__ or use __uninstall_run_pre to handle it."
      return 1
      ;;
  esac

  if declare -f __uninstall_run_post > /dev/null; then
    __uninstall_run_post
  fi
}

__uninstall_run_prefix__() {
  if declare -f __uninstall_run_prefix_pre > /dev/null; then
    __uninstall_run_prefix_pre
  fi
  file__rm -f "${_FEAT_EXISTING_PATH}"
  if [[ -v BINARY_SIDECAR_URI && -n "${BINARY_SIDECAR_URI}" ]]; then
    local _prefix_bin="${_FEAT_EXISTING_PATH%/*}"
    local _sc
    _sc="$(os__expand_release_pattern "${BINARY_SIDECAR_URI}" "${_FEAT_INSTALLED_VER:-${VERSION:-}}" "${_FEAT_RESOLVED_TAG:-}")"
    _sc="${_sc##*/}"
    [[ "${_sc}" != *'{'*'}'* ]] && file__rm -f "${_prefix_bin}/${_sc}"
  fi
  if declare -f __uninstall_run_prefix_post > /dev/null; then
    __uninstall_run_prefix_post
  fi
}

__uninstall_run_npm__() {
  if declare -f __uninstall_run_npm_pre > /dev/null; then
    __uninstall_run_npm_pre
  fi
  if [[ -z "${NPM_PACKAGE:-}" ]]; then
    logging__error "Cannot auto-uninstall npm-managed install: _options.method.npm not declared in metadata."
    return 1
  fi
  npm__uninstall_package --package "${NPM_PACKAGE}"
  if declare -f __uninstall_run_npm_post > /dev/null; then
    __uninstall_run_npm_post
  fi
}

__uninstall_run_npm_bundled__() {
  if declare -f __uninstall_run_npm_bundled_pre > /dev/null; then
    __uninstall_run_npm_bundled_pre
  fi
  npm__uninstall_bundled --bin "${_FEAT_EXISTING_PATH}"
  if declare -f __uninstall_run_npm_bundled_post > /dev/null; then
    __uninstall_run_npm_bundled_post
  fi
}

__uninstall_run_package__() {
  if declare -f __uninstall_run_package_pre > /dev/null; then
    __uninstall_run_package_pre
  fi
  __dep_uninstall__ run "${PACKAGE_MANIFEST:-os-pkg}"
  if declare -f __uninstall_run_package_post > /dev/null; then
    __uninstall_run_package_post
  fi
}

__uninstall_run_upstream_package__() {
  if declare -f __uninstall_run_upstream_package_pre > /dev/null; then
    __uninstall_run_upstream_package_pre
  fi
  __dep_uninstall__ run upstream-package
  if declare -f __uninstall_run_upstream_package_post > /dev/null; then
    __uninstall_run_upstream_package_post
  fi
}

__uninstall_finish__() {

  if declare -f __uninstall_finish_pre > /dev/null; then
    __uninstall_finish_pre
  fi

  # Remove the dummy PM registration when the tool was installed via a non-PM method.
  if [[ -v REGISTER_PACKAGE_NAME && -n "${REGISTER_PACKAGE_NAME}" ]]; then
    case "${_FEAT_EXISTING_METHOD:-}" in
      package | upstream-package | "") ;;
      *) ospkg__unregister_dummy "${REGISTER_PACKAGE_NAME}" ;;
    esac
  fi

  _FEAT_EXISTING_PATH=""
  _FEAT_EXISTING_METHOD=""
  logging__success "'${_FEAT_CONTRACT_PRIMARY_BIN:-tool}' uninstalled."

  if declare -f __uninstall_finish_post > /dev/null; then
    __uninstall_finish_post
  fi
}

# Installation
# ============
__install__() {

  if declare -f __install_pre > /dev/null; then
    __install_pre
  fi

  __install_init__
  __install_run__
  __install_finish__

  if declare -f __install_post > /dev/null; then
    __install_post
  fi
}

__install_init__() {

  if declare -f __install_init_pre > /dev/null; then
    __install_init_pre
  fi

  __verify_system_requirements__
  __resolve_input_method__
  __resolve_input_version__
  __resolve_input_prefixes__
  __dep_install_base__

  if declare -f __install_init_post > /dev/null; then
    __install_init_post
  fi
}

__install_run__() {
  # Dispatches to the auto-implementation for each METHOD. Override
  # __install_run_<method>__ or use __install_run_<method>_pre/_post for custom logic.

  if declare -f __install_run_pre > /dev/null; then
    __install_run_pre
  fi

  if [[ -v METHOD ]]; then
    case "${METHOD}" in
      binary)
        __install_run_binary__
        ;;
      package)
        __install_run_package__
        ;;
      upstream-package)
        __install_run_upstream_package__
        ;;
      script)
        __install_run_script__
        ;;
      cargo)
        __install_run_cargo__
        ;;
      npm)
        __install_run_npm__
        ;;
      npm-bundled)
        __install_run_npm_bundled__
        ;;
      source)
        __install_run_source__
        ;;
      *)
        logging__error "Unknown METHOD '${METHOD}': no auto-implementation exists. Override __install_run__."
        return 1
        ;;
    esac
  else
    logging__error "No METHOD option defined."
    return 1
  fi

  if declare -f __install_run_post > /dev/null; then
    __install_run_post
  fi
}

# Populate <out_arr> with (--sha256 <hex>) when VERSION_RESOLUTION is GitHub-based
# and the release API publishes a digest for <asset_name>.  No-op otherwise.
__github_release_sha256_args__() {
  local _asset_name="$1"
  local -n _out_arr="$2"
  _out_arr=()
  case "${VERSION_RESOLUTION:-}" in
    github_release | github_tag)
      [[ -n "${VERSION_URI:-}" && -n "${_FEAT_RESOLVED_TAG:-}" ]] || return 0
      local _digest
      _digest="$(github__release_json_digest_from_uri \
        "${VERSION_URI}/releases/tags/${_FEAT_RESOLVED_TAG}" "$_asset_name")" || _digest=""
      if [[ -n "$_digest" ]]; then
        _out_arr=(--sha256 "$_digest")
      else
        logging__warn "no JSON digest for '${_asset_name}' in GitHub release metadata — skipping JSON SHA-256."
      fi
      ;;
  esac
}

__install_run_binary__() {
  if declare -f __install_run_binary_pre > /dev/null; then
    __install_run_binary_pre
  fi
  if [[ -v BINARY_ASSET_URI && -n "${BINARY_ASSET_URI}" ]]; then
    if [[ ! -v VERSION ]]; then
      logging__error "METHOD=binary asset URI requires a version option; VERSION is unset (missing options.version in metadata?)."
      return 1
    fi
    local _tag _asset_uri _asset_name _bin_dest
    local -a _sha256_args=() _sidecar_args=() _installer_dir_arg=() _binary_src_args=() _netrc_arg=() _gpg_key_arg=() _gpg_sig_arg=()
    _tag="${_FEAT_RESOLVED_TAG:-v${VERSION}}"
    _asset_uri="$(os__expand_release_pattern "${BINARY_ASSET_URI}" "${VERSION}" "${_tag}")"
    _asset_name="${_asset_uri%%\?*}"
    _asset_name="${_asset_name##*/}"
    if [[ -n "${BINARY_SRC:-}" ]]; then
      _bin_dest="${PREFIX}/bin/${BINARY_SRC##*/}"
      _binary_src_args=(--binary-src "${BINARY_SRC}")
    else
      _bin_dest="${PREFIX}/bin/${_FEAT_CONTRACT_PRIMARY_BIN}"
    fi
    if [[ -v BINARY_SIDECAR_URI && -n "${BINARY_SIDECAR_URI}" ]]; then
      local _sc_uri
      _sc_uri="$(os__expand_release_pattern "${BINARY_SIDECAR_URI}" "${VERSION}" "${_tag}")"
      _sidecar_args=(--sidecar "${_sc_uri}")
    fi
    # Use pre-computed SHA-256 (set by __install_run_binary_pre) when available;
    # otherwise probe from GitHub release metadata.
    if [[ -v BINARY_SHA256 && -n "${BINARY_SHA256}" ]]; then
      _sha256_args=(--sha256 "${BINARY_SHA256}")
    else
      __github_release_sha256_args__ "$_asset_name" _sha256_args
    fi
    if [[ -v BINARY_GPG_KEY_URI && -n "${BINARY_GPG_KEY_URI}" ]]; then
      local _gpg_key_uri
      _gpg_key_uri="$(os__expand_release_pattern "${BINARY_GPG_KEY_URI}" "${VERSION}" "${_tag}")"
      _gpg_key_arg=(--gpg-key "${_gpg_key_uri}")
    fi
    if [[ -v BINARY_GPG_SIG_URI && -n "${BINARY_GPG_SIG_URI}" ]]; then
      local _gpg_sig_uri
      _gpg_sig_uri="$(os__expand_release_pattern "${BINARY_GPG_SIG_URI}" "${VERSION}" "${_tag}")"
      _gpg_sig_arg=(--gpg-sig "${_gpg_sig_uri}")
    fi
    [[ -n "${INSTALLER_DIR:-}" ]] && _installer_dir_arg=(--installer-dir "${INSTALLER_DIR}")
    [[ -n "${BINARY_NETRC:-}" ]] && _netrc_arg=(--netrc-file "${BINARY_NETRC}")
    install__release_asset \
      --asset-uri "${_asset_uri}" \
      "${_sha256_args[@]+"${_sha256_args[@]}"}" \
      "${_sidecar_args[@]+"${_sidecar_args[@]}"}" \
      "${_binary_src_args[@]+"${_binary_src_args[@]}"}" \
      --binary-dest "${_bin_dest}" \
      "${_installer_dir_arg[@]+"${_installer_dir_arg[@]}"}" \
      "${_netrc_arg[@]+"${_netrc_arg[@]}"}" \
      "${_gpg_key_arg[@]+"${_gpg_key_arg[@]}"}" \
      "${_gpg_sig_arg[@]+"${_gpg_sig_arg[@]}"}"
  else
    logging__error "METHOD=binary: no BINARY_ASSET_URI set (missing _options.method.binary in metadata?). Override __install_run_binary__ for a fully custom binary install."
    return 1
  fi
  if declare -f __install_run_binary_post > /dev/null; then
    __install_run_binary_post
  fi
}

__install_run_package__() {
  if declare -f __install_run_package_pre > /dev/null; then
    __install_run_package_pre
  fi
  __dep_install__ run "${PACKAGE_MANIFEST:-os-pkg}"
  if declare -f __install_run_package_post > /dev/null; then
    __install_run_package_post
  fi
}

__install_run_upstream_package__() {
  if declare -f __install_run_upstream_package_pre > /dev/null; then
    __install_run_upstream_package_pre
  fi
  __dep_install__ run upstream-package
  if declare -f __install_run_upstream_package_post > /dev/null; then
    __install_run_upstream_package_post
  fi
}

__install_run_script__() {
  if declare -f __install_run_script_pre > /dev/null; then
    __install_run_script_pre
  fi

  local _script_path
  if [[ -v SCRIPT_ASSET_URI && -n "${SCRIPT_ASSET_URI}" ]]; then
    local _tag _asset_uri _asset_name
    local -a _sha256_args=() _sidecar_args=() _installer_dir_arg=() _netrc_arg=()
    _tag="${_FEAT_RESOLVED_TAG:-${VERSION:+v${VERSION}}}"
    _asset_uri="$(os__expand_release_pattern "${SCRIPT_ASSET_URI}" "${VERSION:-}" "${_tag:-}")"
    _asset_name="${_asset_uri%%\?*}"
    _asset_name="${_asset_name##*/}"
    if [[ -v SCRIPT_SIDECAR_URI && -n "${SCRIPT_SIDECAR_URI}" ]]; then
      local _sc_uri
      _sc_uri="$(os__expand_release_pattern "${SCRIPT_SIDECAR_URI}" "${VERSION:-}" "${_tag:-}")"
      _sidecar_args=(--sidecar "${_sc_uri}")
    fi
    __github_release_sha256_args__ "$_asset_name" _sha256_args
    [[ -n "${INSTALLER_DIR:-}" ]] && _installer_dir_arg=(--installer-dir "${INSTALLER_DIR}")
    [[ -n "${SCRIPT_NETRC:-}" ]] && _netrc_arg=(--netrc-file "${SCRIPT_NETRC}")
    local _asset_dir
    _asset_dir="$(install__release_asset \
      --asset-uri "${_asset_uri}" \
      --chmod-exec "${_asset_name}" \
      "${_sha256_args[@]+"${_sha256_args[@]}"}" \
      "${_sidecar_args[@]+"${_sidecar_args[@]}"}" \
      "${_installer_dir_arg[@]+"${_installer_dir_arg[@]}"}" \
      "${_netrc_arg[@]+"${_netrc_arg[@]}"}")" || return 1
    _script_path="${_asset_dir}/${_asset_name}"
  else
    logging__error "METHOD=script: no SCRIPT_ASSET_URI set (missing _options.method.script in metadata?). Override __install_run_script__ for a fully custom script install."
    return 1
  fi

  if declare -f __install_run_script_run > /dev/null; then
    __install_run_script_run "${_script_path}"
  else
    local -a _all_script_args=("${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}")
    if [[ -v _FEAT_INSTALL_SCRIPT_ARGS ]]; then
      _all_script_args+=("${_FEAT_INSTALL_SCRIPT_ARGS[@]+"${_FEAT_INSTALL_SCRIPT_ARGS[@]}"}")
    fi
    "${_script_path}" "${_all_script_args[@]+"${_all_script_args[@]}"}"
  fi

  if declare -f __install_run_script_post > /dev/null; then
    __install_run_script_post
  fi
}

__install_run_cargo__() {
  # Auto-implementation for METHOD=cargo.
  #
  # Command selection (in priority order):
  #   1. _FEAT_CARGO_COMMAND array set by __install_run_cargo_pre — use verbatim.
  #   2. cargo-binstall available — prefer it (downloads pre-built binary; falls
  #      back to source compilation automatically when no binary is published).
  #   3. cargo install — compile from source.
  #
  # Standard args added automatically (before _FEAT_CARGO_INSTALL_ARGS):
  #   --root  ${PREFIX}   when prefix is configured.
  #   --version ${VERSION}                    when VERSION is set.
  #
  # _FEAT_CARGO_INSTALL_ARGS (array): set in __install_run_cargo_pre to pass
  #   any additional args (e.g. --force, --locked, --no-confirm).
  #   Appended after the standard args above.

  if declare -f __install_run_cargo_pre > /dev/null; then
    __install_run_cargo_pre
  fi

  if [[ -z "${CARGO_CRATE:-}" ]]; then
    logging__error "METHOD=cargo: no CARGO_CRATE set (missing _options.method.cargo in metadata?). Override __install_run_cargo__ for a fully custom cargo install."
    return 1
  fi

  local -a _cargo_cmd
  local -a _cargo_args=()
  if [[ -v _FEAT_CARGO_COMMAND ]]; then
    _cargo_cmd=("${_FEAT_CARGO_COMMAND[@]}")
  elif command -v cargo-binstall > /dev/null 2>&1; then
    _cargo_cmd=(cargo binstall)
    _cargo_args+=(--no-confirm)
  else
    _cargo_cmd=(cargo install)
  fi
  if [[ -v PREFIX && -n "${PREFIX}" ]]; then
    _cargo_args+=(--root "${PREFIX}")
  fi
  [[ -v VERSION && -n "${VERSION}" ]] && _cargo_args+=(--version "${VERSION}")
  if [[ -v _FEAT_CARGO_INSTALL_ARGS ]]; then
    _cargo_args+=("${_FEAT_CARGO_INSTALL_ARGS[@]+"${_FEAT_CARGO_INSTALL_ARGS[@]}"}")
  fi

  "${_cargo_cmd[@]}" "${CARGO_CRATE}" "${_cargo_args[@]+"${_cargo_args[@]}"}"

  if declare -f __install_run_cargo_post > /dev/null; then
    __install_run_cargo_post
  fi
}

__install_run_npm__() {
  if declare -f __install_run_npm_pre > /dev/null; then
    __install_run_npm_pre
  fi
  if [[ -z "${NPM_PACKAGE:-}" ]]; then
    logging__error "METHOD=npm: no NPM_PACKAGE set (missing _options.method.npm in metadata?). Override __install_run_npm__ for a fully custom npm install."
    return 1
  fi

  # Build versioned package spec (pkg@version; omit for 'latest' since npm handles it).
  local _pkg="${NPM_PACKAGE}"
  [[ -v VERSION && -n "${VERSION}" && "${VERSION}" != "latest" ]] && _pkg+="@${VERSION}"

  local -a _install_args=(install -g)
  # Install into feature prefix when configured.
  if [[ -v PREFIX && -n "${PREFIX}" ]]; then
    _install_args+=(--prefix "${PREFIX}")
  fi
  [[ -n "${NPM_REGISTRY:-}" ]] && _install_args+=(--registry "${NPM_REGISTRY}")
  if [[ -v NPM_INSTALL_ARGS ]]; then
    _install_args+=("${NPM_INSTALL_ARGS[@]+"${NPM_INSTALL_ARGS[@]}"}")
  fi
  _install_args+=("${_pkg}")

  npm "${_install_args[@]}"

  if declare -f __install_run_npm_post > /dev/null; then
    __install_run_npm_post
  fi
}

__install_run_npm_bundled__() {
  # Auto-implementation for METHOD=npm-bundled.
  #
  # Installs NPM_PACKAGE with a self-contained bundled Node.js runtime using
  # npm__install_bundled. The runtime is isolated from any system Node.js.
  #
  # Passes --update when _FEAT_EXISTING_PATH is non-empty (update flow).
  # _FEAT_EXISTING_PATH is cleared by __uninstall_finish__ before reinstall or
  # method-migration, so --update is absent in those cases even when METHOD
  # remains npm-bundled.
  #
  # Use __install_run_npm_bundled_pre for pre-install setup (e.g. dep installs).
  # Override __install_run_npm_bundled__ entirely for full control.

  if declare -f __install_run_npm_bundled_pre > /dev/null; then
    __install_run_npm_bundled_pre
  fi

  if [[ -z "${NPM_PACKAGE:-}" ]]; then
    logging__error "METHOD=npm-bundled: no NPM_PACKAGE set (missing _options.method.npm-bundled in metadata?). Override __install_run_npm_bundled__ for a fully custom npm-bundled install."
    return 1
  fi

  local -a _flags=() _cmd_arg=() _registry_arg=()
  [[ -n "${_FEAT_EXISTING_PATH:-}" ]] && _flags+=(--update)
  [[ -v NPM_CMD ]] && _cmd_arg=(--cmd "${NPM_CMD}")
  [[ -n "${NPM_REGISTRY:-}" ]] && _registry_arg=(--registry "${NPM_REGISTRY}")

  npm__install_bundled \
    --package "${NPM_PACKAGE}" \
    "${_cmd_arg[@]+"${_cmd_arg[@]}"}" \
    --prefix "${PREFIX}" \
    --version "${VERSION:-latest}" \
    --node-version "${NODE_VERSION:-lts}" \
    "${_registry_arg[@]+"${_registry_arg[@]}"}" \
    "${_flags[@]+"${_flags[@]}"}"

  if declare -f __install_run_npm_bundled_post > /dev/null; then
    __install_run_npm_bundled_post
  fi
}

__install_run_source__() {
  # Auto-implementation for METHOD=source.
  #
  # Downloads the source archive declared in SOURCE_ASSET_URI (with optional
  # SOURCE_SIDECAR_URI verification), extracts it to ${INSTALLER_DIR}/asset/,
  # then dispatches to the build step.
  #
  # Build dispatch (in priority order):
  #   1. __install_run_source_build <src_dir>  — explicit feature hook.
  #      Receives the path to the top-level extracted directory.  Use this
  #      whenever the build requires logic that cannot be expressed declaratively
  #      (e.g. platform-specific flags, post-install steps, multiple make passes).
  #   2. __install_run_source_auto_build__ <src_dir> — framework auto-impl.
  #      Driven by SOURCE_BUILD_SYSTEM / SOURCE_CONFIGURE_ARGS /
  #      SOURCE_MAKE_FLAGS / SOURCE_MAKE_TARGETS.  Covers autotools and bare make.
  #      Active when SOURCE_BUILD_SYSTEM is non-empty.
  #
  # Use __install_run_source_pre for pre-build setup (e.g. installing build deps
  # that cannot be expressed in _dependencies.build).  Override
  # __install_run_source__ entirely only when you need a fully custom fetch+build.

  if declare -f __install_run_source_pre > /dev/null; then
    __install_run_source_pre
  fi

  if [[ ! -v SOURCE_ASSET_URI || -z "${SOURCE_ASSET_URI}" ]]; then
    logging__error "METHOD=source: no SOURCE_ASSET_URI set (missing _options.method.source.asset_uri in metadata?). Override __install_run_source__ for a fully custom source install."
    return 1
  fi

  local _tag _asset_uri
  _tag="${_FEAT_RESOLVED_TAG:-${VERSION:+v${VERSION}}}"
  _asset_uri="$(os__expand_release_pattern "${SOURCE_ASSET_URI}" "${VERSION:-}" "${_tag:-}")"

  local -a _fetch_args=(--installer-dir "${INSTALLER_DIR}")
  if [[ -v SOURCE_SIDECAR_URI && -n "${SOURCE_SIDECAR_URI}" ]]; then
    local _sc_uri
    _sc_uri="$(os__expand_release_pattern "${SOURCE_SIDECAR_URI}" "${VERSION:-}" "${_tag:-}")"
    _fetch_args+=(--sidecar "${_sc_uri}")
  fi

  uri__fetch_asset "${_asset_uri}" "${_fetch_args[@]}" || return 1

  local _src_dir
  _src_dir="$(find "${INSTALLER_DIR}/asset" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
  if [[ -z "${_src_dir}" ]]; then
    logging__error "METHOD=source: no directory found under '${INSTALLER_DIR}/asset' after extraction."
    return 1
  fi

  if declare -f __install_run_source_build > /dev/null; then
    __install_run_source_build "${_src_dir}"
  else
    __install_run_source_auto_build__ "${_src_dir}"
  fi

  if declare -f __install_run_source_post > /dev/null; then
    __install_run_source_post
  fi
}

__install_run_source_auto_build__() {
  # Framework auto-build for METHOD=source, driven by SOURCE_BUILD_SYSTEM.
  # Called when __install_run_source_build is not defined.
  # Supports SOURCE_BUILD_SYSTEM=autotools and SOURCE_BUILD_SYSTEM=make.
  local _src_dir="$1"
  local _jobs
  _jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || printf '1')"

  local -a _make_flags=()
  if [[ -v SOURCE_MAKE_FLAGS ]]; then
    _make_flags+=("${SOURCE_MAKE_FLAGS[@]+"${SOURCE_MAKE_FLAGS[@]}"}")
  fi

  local -a _make_targets=()
  if [[ -v SOURCE_MAKE_TARGETS && "${#SOURCE_MAKE_TARGETS[@]}" -gt 0 ]]; then
    _make_targets=("${SOURCE_MAKE_TARGETS[@]}")
  else
    _make_targets=(all install)
  fi

  case "${SOURCE_BUILD_SYSTEM:-}" in
    autotools)
      local -a _configure_args=()
      if [[ -v SOURCE_CONFIGURE_ARGS ]]; then
        _configure_args+=("${SOURCE_CONFIGURE_ARGS[@]+"${SOURCE_CONFIGURE_ARGS[@]}"}")
      fi
      if [[ -v PREFIX && -n "${PREFIX}" ]]; then
        _configure_args+=(--prefix="${PREFIX}")
      fi
      (
        cd "${_src_dir}" || exit 1
        ./configure "${_configure_args[@]+"${_configure_args[@]}"}" || exit 1
        local _t
        for _t in "${_make_targets[@]}"; do
          make -j"${_jobs}" "${_make_flags[@]+"${_make_flags[@]}"}" "${_t}" || exit 1
        done
      ) || return 1
      ;;
    make)
      (
        cd "${_src_dir}" || exit 1
        local _t
        for _t in "${_make_targets[@]}"; do
          make -j"${_jobs}" "${_make_flags[@]+"${_make_flags[@]}"}" "${_t}" || exit 1
        done
      ) || return 1
      ;;
    "")
      logging__error "METHOD=source: SOURCE_BUILD_SYSTEM is not set. Define __install_run_source_build or set source_build_system in metadata."
      return 1
      ;;
    *)
      logging__error "METHOD=source: SOURCE_BUILD_SYSTEM='${SOURCE_BUILD_SYSTEM}' is not supported. Use 'autotools' or 'make', or define __install_run_source_build."
      return 1
      ;;
  esac
}

__install_register_dummy__() {
  # Register a dummy OS package so downstream Depends: constraints are satisfied.
  # Only runs when REGISTER_PACKAGE_NAME is set and METHOD is a non-PM method.
  # Debian/Ubuntu only; no-op elsewhere (ospkg__register_dummy handles the guard).
  [[ -v REGISTER_PACKAGE_NAME && -n "${REGISTER_PACKAGE_NAME}" ]] || return 0
  case "${METHOD:-}" in
    package | upstream-package) return 0 ;;
  esac
  [[ -v VERSION && -n "${VERSION}" ]] || {
    logging__warn "__install_register_dummy__: VERSION not set; skipping dummy registration for '${REGISTER_PACKAGE_NAME}'."
    return 0
  }
  ospkg__register_dummy "${REGISTER_PACKAGE_NAME}" "${VERSION}"
}

__install_shell_completions__() {
  # shellcheck disable=SC2329,SC2317
  [[ -v SHELL_COMPLETIONS && "${#SHELL_COMPLETIONS[@]}" -gt 0 ]] || return 0

  local _name="${_FEAT_CONTRACT_PRIMARY_BIN:-}"
  if [[ -z "${_name}" ]]; then
    logging__warn "__install_shell_completions__: no completion name resolved — skipping."
    return 0
  fi

  local _scope_flag="" _home
  if ! users__is_user_path "${PREFIX:-/usr/local}"; then
    _scope_flag="--system"
    _home="${HOME:-}"
  else
    _home="$(users__home_of_path_owner "${PREFIX}")"
  fi

  declare -A _completion_files_map
  if [[ -v SHELL_COMPLETIONS_FILES ]]; then
    local _entry _k _v
    for _entry in "${SHELL_COMPLETIONS_FILES[@]}"; do
      _k="${_entry%%=*}"
      _v="${_entry#*=}"
      [[ -n "${_k}" ]] && _completion_files_map["${_k}"]="${_v}"
    done
  fi

  local _shell
  for _shell in "${SHELL_COMPLETIONS[@]}"; do
    local _content=""
    if declare -f __get_completion_content__ > /dev/null; then
      _content="$(__get_completion_content__ "${_shell}")" || {
        logging__warn "__install_shell_completions__: __get_completion_content__ ${_shell} failed; skipping."
        continue
      }
    elif [[ -n "${_completion_files_map[${_shell}]+x}" ]]; then
      local _src="${PREFIX}/${_completion_files_map[${_shell}]}"
      _content="$(cat "${_src}" 2> /dev/null)" || {
        logging__warn "__install_shell_completions__: source file '${_src}' not found; skipping ${_shell}."
        continue
      }
    elif [[ -n "${SHELL_COMPLETIONS_CMD:-}" ]]; then
      local _bin="${PREFIX}/bin/${_FEAT_CONTRACT_PRIMARY_BIN}"
      command -v "${_bin}" > /dev/null 2>&1 \
        || _bin="$(command -v "${_FEAT_CONTRACT_PRIMARY_BIN}" 2> /dev/null)" || {
        logging__warn "__install_shell_completions__: '${_FEAT_CONTRACT_PRIMARY_BIN}' not found; skipping."
        return 0
      }
      # shellcheck disable=SC2086
      _content="$("${_bin}" ${SHELL_COMPLETIONS_CMD} "${_shell}" 2> /dev/null)" || {
        logging__warn "__install_shell_completions__: ${_FEAT_CONTRACT_PRIMARY_BIN} ${SHELL_COMPLETIONS_CMD} ${_shell} failed; skipping."
        continue
      }
    else
      logging__warn "__install_shell_completions__: no completion source for '${_shell}' — skipping."
      continue
    fi
    shell__install_completion ${_scope_flag:+"${_scope_flag}"} --home "${_home}" \
      "${_shell}" "${_name}" "${_content}"
  done
}

__install_finish__() {

  if declare -f __install_finish_pre > /dev/null; then
    __install_finish_pre
  fi

  # shellcheck disable=SC2317
  _feat_prefix_applies() {
    # Returns 0 when this installation method is covered by the prefix config.
    # When no guard var is configured (_FEAT_PREFIX_GUARD_VAR is empty) every
    # method qualifies.
    [[ -z "${_FEAT_PREFIX_GUARD_VAR:-}" ]] && return 0
    local _val="${!_FEAT_PREFIX_GUARD_VAR:-}"
    local _v
    for _v in ${_FEAT_PREFIX_GUARD_VALS}; do
      [[ "${_val}" == "${_v}" ]] && return 0
    done
    return 1
  }

  if [[ -v PREFIX ]] && _feat_prefix_applies; then
    # -- discovery --
    [[ -v PREFIX_DISCOVERY ]] && {
      local -a _disc_args=(
        --prefix "${PREFIX}"
        --bin-dir "${PREFIX_BIN_DIR}"
        --discovery "${PREFIX_DISCOVERY}"
        --runtime-path "${RUNTIME_PATH}"
        --bin "${_FEAT_CONTRACT_PRIMARY_BIN}"
        --cmd-var "_DF_EXPECTED_CMD"
        --marker "${_FEAT_CONTRACT_PRIMARY_BIN:+${_FEAT_CONTRACT_PRIMARY_BIN} }PATH (${_FEAT_ID})"
      )
      [[ -v PREFIX_BINS ]] && _disc_args+=(--bins "${PREFIX_BINS[*]}")
      # declare -p correctly detects declared-but-empty arrays; [[ -v arr ]] does not
      # (it checks arr[0], returning false for empty arrays).
      { declare -p PREFIX_SYMLINKS &>/dev/null; } && _disc_args+=(
        --symlinks-ref "PREFIX_SYMLINKS"
        --symlink-root "${PREFIX_SYMLINK_ROOT}"
        --symlink-nonroot "${PREFIX_SYMLINK_NONROOT}"
      )
      { declare -p PREFIX_EXPORTS &>/dev/null; } && _disc_args+=(
        --exports-ref "PREFIX_EXPORTS"
        --profile-d "${_FEAT_PROFILE_D_FILE}"
      )
      { declare -p PREFIX_SYMLINKS &>/dev/null; } || _disc_args+=(--no-symlinks)
      { declare -p PREFIX_EXPORTS &>/dev/null; } || _disc_args+=(--no-exports)
      logging__fn_entry "prefix_discovery"
      shell__run_prefix_discovery "${_disc_args[@]}"
      logging__fn_exit "prefix_discovery"
    }
    : "${_DF_EXPECTED_CMD:=${_FEAT_CONTRACT_PRIMARY_BIN}}"

    # -- activation --
    [[ -v PREFIX_ACTIVATIONS ]] && {
      local _act_home_arg=""
      [ "${PREFIX_SCOPE}" = "user" ] && \
        _act_home_arg="$(users__home_of_path_owner "${PREFIX}")"
      shell__write_activation_snippets \
        --scope "${PREFIX_SCOPE}" \
        ${_act_home_arg:+--home "${_act_home_arg}"} \
        "prefix activation (${_FEAT_ID})" "${_FEAT_ACTIVATION_PROFILE_D_FILE}" "prefix_activation_snippet" \
        "${PREFIX_ACTIVATIONS[@]}"
      unset _act_home_arg
    }

    # -- write_group --
    [[ -n "${WRITE_GROUP:-}" ]] && {
      local _wargs=()
      if [[ "${#WRITE_USERS[@]}" -gt 0 ]]; then
        _wargs=(--current false --remote false --container false)
        for _u in "${WRITE_USERS[@]}"; do _wargs+=(--user "$_u"); done
      fi
      mapfile -t _write_users < <(users__resolve_list "${_wargs[@]}")
      users__set_write_permissions "${PREFIX}" \
        "${INSTALL_USER:-$(id -nu)}" "${WRITE_GROUP}" "${_write_users[@]}"
    }
  fi

  __install_register_dummy__
  ${{ _script.shell_completions_call }}$
  logging__success "Installation complete."

  if declare -f __install_finish_post > /dev/null; then
    __install_finish_post
  fi
}

# Reinstallation
# ===============
__reinstall__() {

  if declare -f __reinstall_pre > /dev/null; then
    __reinstall_pre
  fi

  __reinstall_init__
  __reinstall_run__
  __reinstall_finish__

  if declare -f __reinstall_post > /dev/null; then
    __reinstall_post
  fi
}

__reinstall_init__() {

  if declare -f __reinstall_init_pre > /dev/null; then
    __reinstall_init_pre
  fi

  __verify_system_requirements__
  __resolve_input_method__
  __resolve_input_version__
  __resolve_input_prefixes__

  if declare -f __reinstall_init_post > /dev/null; then
    __reinstall_init_post
  fi
}

__reinstall_run__() {
  # Uninstall the existing installation (if any) then perform a fresh install.
  # Called when if_exists=reinstall. _FEAT_EXISTING_PATH is guaranteed non-empty.

  if declare -f __reinstall_run_pre > /dev/null; then
    __reinstall_run_pre
  fi

  __uninstall_run__
  __uninstall_finish__
  __dep_install_base__
  __install_run__
  __install_finish__

  if declare -f __reinstall_run_post > /dev/null; then
    __reinstall_run_post
  fi
}

__reinstall_finish__() {

  if declare -f __reinstall_finish_pre > /dev/null; then
    __reinstall_finish_pre
  fi

  logging__success "Reinstallation complete."

  if declare -f __reinstall_finish_post > /dev/null; then
    __reinstall_finish_post
  fi
}

# Update
# ======
__update__() {

  if declare -f __update_pre > /dev/null; then
    __update_pre
  fi

  __update_init__
  __update_run__
  __update_finish__

  if declare -f __update_post > /dev/null; then
    __update_post
  fi
}

__update_init__() {

  if declare -f __update_init_pre > /dev/null; then
    __update_init_pre
  fi

  __verify_system_requirements__
  __resolve_input_method__
  __resolve_input_version__
  __resolve_input_prefixes__
  __dep_install_base__ --update

  if declare -f __update_init_post > /dev/null; then
    __update_init_post
  fi
}

__update_run__() {
  # Apply an update to the existing installation. Called when if_exists=update.
  # _FEAT_EXISTING_PATH is guaranteed non-empty.
  #
  # Requires __detect_existing_path__ (step 1) and __detect_existing_method__
  # (step 1b) to have already run. Version and method have been resolved by
  # steps 4–5.
  #
  # Auto-implementation:
  #
  # Method migration — when the detected existing install method is incompatible
  # with the new METHOD, the old installation is cleaned up first before
  # installing with the new method:
  #   "package"          → METHOD≠package          PM owns the binary; must uninstall via PM.
  #   "upstream-package" → METHOD≠upstream-package Vendor-repo binary; must uninstall via PM.
  #   "npm"              → METHOD≠npm              npm owns the package; must npm-uninstall.
  #   "npm-bundled"      → any METHOD              bundled installs are always distinct from
  #                                                any METHOD value; always clean up first.
  #   "prefix"           → METHOD∈{package,        Prefix binary is orphaned when PM installs
  #                         upstream-package}       to /usr/bin; clean up before PM takes over.
  # "" (unknown): overwrite is safe; no cleanup needed.
  #
  # Same/compatible method — dispatches on METHOD:
  #   package           ospkg__run --update (PM upgrade).
  #   upstream-package  ospkg__run --update against upstream-package.yaml.
  #   binary       __install__ (download + overwrite).
  #   cargo        __install__ (cargo install upgrades in place).
  #   npm          __install__ (npm install -g upgrades).
  #   npm-bundled  __install_run__ (__install_run_npm_bundled__ detects _FEAT_EXISTING_PATH → passes --update).
  #   script       __install__ (re-run upstream installer).
  #   source       __install__ (compile + overwrite-in-place).
  #   (none)       Error — no auto-implementation.
  #
  # For tools with their own update mechanism (e.g. pixi self-update, rustup
  # update), use __update_run_pre or override __update_run__ entirely.

  if declare -f __update_run_pre > /dev/null; then
    __update_run_pre
  fi

  if [[ ! -v METHOD ]]; then
    logging__fatal "Update without METHOD; overwrite __update_run__."
    exit 1
  fi

  # Detect method migration.
  local _needs_migration=false
  case "${_FEAT_EXISTING_METHOD:-}" in
    package)          [[ "${METHOD}" != "package" ]] && _needs_migration=true ;;
    upstream-package) [[ "${METHOD}" != "upstream-package" ]] && _needs_migration=true ;;
    npm)              [[ "${METHOD}" != "npm" ]] && _needs_migration=true ;;
    npm-bundled)      [[ "${METHOD}" != "npm-bundled" ]] && _needs_migration=true ;;
    prefix)
      case "${METHOD}" in
        package | upstream-package) _needs_migration=true ;;
      esac
      ;;
  esac

  if [[ "${_needs_migration}" == true ]]; then
    __update_run_migrate__
    return
  fi

  case "${METHOD}" in
    package)
      __update_run_package__
      ;;
    upstream-package)
      __update_run_upstream_package__
      ;;
    npm-bundled)
      # __install_run_npm_bundled__ detects _FEAT_EXISTING_PATH → passes --update.
      __install_run__
      __install_finish__
      ;;
    *)
      # binary, cargo, npm, script, source: install path overwrites / upgrades naturally.
      __install_run__
      __install_finish__
      ;;
  esac

  if declare -f __update_run_post > /dev/null; then
    __update_run_post
  fi
}

__update_run_migrate__() {
  if declare -f __update_run_migrate_pre > /dev/null; then
    __update_run_migrate_pre
  fi
  logging__info "Installation method changing from '${_FEAT_EXISTING_METHOD}' to '${METHOD}'; uninstalling before reinstalling."
  __uninstall_run__
  __uninstall_finish__
  __install_run__
  __install_finish__
  if declare -f __update_run_migrate_post > /dev/null; then
    __update_run_migrate_post
  fi
}

__update_run_package__() {
  if declare -f __update_run_package_pre > /dev/null; then
    __update_run_package_pre
  fi
  __dep_install__ run "${PACKAGE_MANIFEST:-os-pkg}" --update
  if declare -f __update_run_package_post > /dev/null; then
    __update_run_package_post
  fi
}

__update_run_upstream_package__() {
  if declare -f __update_run_upstream_package_pre > /dev/null; then
    __update_run_upstream_package_pre
  fi
  __dep_install__ run upstream-package --update
  if declare -f __update_run_upstream_package_post > /dev/null; then
    __update_run_upstream_package_post
  fi
}

__update_finish__() {

  if declare -f __update_finish_pre > /dev/null; then
    __update_finish_pre
  fi

  logging__success "Update complete."

  if declare -f __update_finish_post > /dev/null; then
    __update_finish_post
  fi
}

# Finalization
# ============
__exit__() {
  local _rc=$?

  if [[ $_rc -eq 0 ]]; then
    logging__success "$_FEAT_NAME script finished successfully."
  else
    logging__fatal "$_FEAT_NAME script exited with error ${_rc}."
  fi

  # Define __exit_pre in the hand-written section
  # for feature-specific cleanup (e.g. removing temp files).
  if declare -f __exit_pre > /dev/null; then __exit_pre; fi

  if [[ "${KEEP_CACHE:-true}" != true ]]; then
    if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
      ospkg__clean
    else
      logging__info "Skipping package-manager cache cleanup (no privilege available)."
    fi
  fi

  [[ "${KEEP_BUILD_DEPS:-false}" != true ]] && [[ -z "${_SYSSET_SESSION_TRACK_DIR:-}" ]] && ospkg__cleanup_all_build_groups

  logging__cleanup
  logging__feature_exit "$_FEAT_NAME v$_FEAT_VERSION"
  return
}

# Helpers
# =======
__verify_system_requirements__() {
  if declare -f __verify_system_requirements_pre > /dev/null; then
    __verify_system_requirements_pre
  fi
  ${{ _script.system_requirements_guard }}$
  if declare -f __verify_system_requirements_post > /dev/null; then
    __verify_system_requirements_post
  fi
}

__feat_check_version_match__() {
  # Sets _FEAT_INSTALLED_VER. Returns 0 when already at the target version
  # (caller should skip), 1 when installation should proceed.
  # Available via __update_run_pre to short-circuit when the installed version
  # already matches the resolved VERSION.
  declare -g _FEAT_INSTALLED_VER=""
  [[ -n "${_FEAT_EXISTING_PATH}" ]] || return 1
  [[ -v VERSION && -n "${VERSION}" ]] || return 1
  if declare -f __installed_version > /dev/null; then
    _FEAT_INSTALLED_VER="$(__installed_version "${_FEAT_EXISTING_PATH}")"
  elif [[ -n "${_FEAT_CONTRACT_PRIMARY_BIN:-}" && -n "${VERSION_FLAG:-}" ]]; then
    _FEAT_INSTALLED_VER="$("${_FEAT_EXISTING_PATH}" "${VERSION_FLAG}" 2>&1 \
      | ver__extract_version || true)"
  fi
  [[ -n "${_FEAT_INSTALLED_VER}" && "${_FEAT_INSTALLED_VER}" == "${VERSION}" ]] || return 1
  logging__info "Already at version '${VERSION}'; skipping."
}

__feat_do_configure_users__() {
  if declare -f __feat_do_configure_users_pre > /dev/null; then
    __feat_do_configure_users_pre
  fi
  if ! declare -f __configure_user > /dev/null; then
    if declare -f __feat_do_configure_users_post > /dev/null; then
      __feat_do_configure_users_post
    fi
    return 0
  fi

  declare -g _FEAT_CONFIGURE_USERS
  local -a _ul_args=()

  [[ -v ADD_CURRENT_USER ]] && _ul_args+=(--current "${ADD_CURRENT_USER}")
  [[ -v ADD_REMOTE_USER ]] && _ul_args+=(--remote "${ADD_REMOTE_USER}")
  [[ -v ADD_CONTAINER_USER ]] && _ul_args+=(--container "${ADD_CONTAINER_USER}")
  if [[ -v ADD_USERS ]]; then
    for _u in "${ADD_USERS[@]+"${ADD_USERS[@]}"}"; do
      _ul_args+=(--user "${_u}")
    done
  fi

  mapfile -t _FEAT_CONFIGURE_USERS < <(users__resolve_list "${_ul_args[@]}")

  local _user
  for _user in "${_FEAT_CONFIGURE_USERS[@]+"${_FEAT_CONFIGURE_USERS[@]}"}"; do
    if ! id "${_user}" > /dev/null 2>&1; then
      logging__warn "User '${_user}' not found; skipping configuration."
      continue
    fi
    if ! __configure_user "${_user}"; then
      logging__warn "__configure_user '${_user}' failed; continuing."
    fi
  done
  if declare -f __feat_do_configure_users_post > /dev/null; then
    __feat_do_configure_users_post
  fi
  return
}

# Input Resolution
# ================
__resolve_input_method__() {
  # Resolves METHOD=auto to a concrete value via __resolve_method hook.
  # No-op when METHOD is not set or already concrete. Error if METHOD=auto
  # but no hook is defined.
  [[ -v METHOD && "${METHOD}" == "auto" ]] || return 0
  if declare -f __resolve_method > /dev/null; then
    METHOD="$(__resolve_method)"
    logging__info "Resolved METHOD=auto → '${METHOD}'."
  else
    logging__error "METHOD=auto requires __resolve_method to be defined; none found."
    return 1
  fi
}

__resolve_input_version__() {
  # Translate the user-visible version spec ("stable", "1.2", "latest", …) into
  # a concrete version string that can be compared against what is already
  # installed and used in download URL patterns.
  #
  # _FEAT_RESOLVED_TAG is always reset to "" at entry so downstream steps can
  # reference it unconditionally regardless of which path was taken.
  #
  # Early exits (no resolution performed, returns 0):
  #  - VERSION is not declared or is empty — the feature has no version option.
  #  - METHOD=package — the OS package manager controls which version is
  #    installed; a version spec would be silently ignored by the package
  #    manager anyway, so resolution is skipped entirely.
  #
  # Hook: __resolve_version
  #   Provide this when none of the standard resolution types fits — e.g. a
  #   proprietary registry, a version file fetched from a repo, or any logic
  #   that requires custom shell code.  The hook receives the user's raw spec
  #   in $VERSION and must print the resolved concrete version string on stdout;
  #   the orchestrator captures that output and writes it back to VERSION.  The
  #   hook must not modify VERSION directly.
  #
  # Auto-implementations (when no hook is defined, keyed by
  # _options.version.resolution in metadata):
  #
  #   github_release  Resolves against the GitHub Releases API (--endpoint
  #                   release) via VERSION_URI.  Handles "stable", "latest",
  #                   and semver-prefix specs.  Sets _FEAT_RESOLVED_TAG to the
  #                   full release tag (e.g. "v1.7.1") so the binary download
  #                   step can use the exact resolved tag without reconstructing
  #                   it.  Requires VERSION_URI to be the API base URL.
  #
  #   github_tag      Same as github_release but queries the git tags API
  #                   (--endpoint tag), for repos that publish lightweight tags
  #                   without formal GitHub Releases.  Also sets
  #                   _FEAT_RESOLVED_TAG.  Requires VERSION_URI.
  #
  #   npm             Resolves against the npm registry via VERSION_URI using
  #                   npm__resolve_version_uri.  _FEAT_RESOLVED_TAG is left
  #                   empty (npm installs are addressed by version, not tag).
  #                   Requires VERSION_URI to be the registry package URL.
  #
  #   none / ""       VERSION is already a concrete value; no network resolution
  #                   is needed.  A silent no-op.
  #
  #   anything else   Error — no auto-implementation exists for this type.
  #                   Define _feat_resolve_version to handle it.
  #
  # Globals written:
  #   VERSION             Concrete resolved version string (e.g. "1.7.1").
  #   _FEAT_RESOLVED_TAG  Full release or git tag when resolved via GitHub
  #                       (e.g. "v1.7.1", "jq-1.7.1"); empty string otherwise.
  if declare -f __resolve_input_version_pre > /dev/null; then
    __resolve_input_version_pre
  fi

  declare -g _FEAT_RESOLVED_TAG=""
  if ! { [[ -v VERSION && -n "${VERSION}" ]] && [[ ! -v METHOD || "${METHOD}" != "package" ]]; }; then
    if declare -f __resolve_input_version_post > /dev/null; then
      __resolve_input_version_post
    fi
    return 0
  fi

  if declare -f __resolve_version > /dev/null; then
    VERSION="$(__resolve_version)"
  else
    case "${VERSION_RESOLUTION:-}" in
      github_release | github_tag)
        if [[ -z "${VERSION_URI:-}" ]]; then
          logging__error "_options.version.resolution=${VERSION_RESOLUTION} requires VERSION_URI to be set in metadata."
          return 1
        fi
        local _endpoint="${VERSION_RESOLUTION#github_}"
        local _both
        _both="$(github__resolve_version "${VERSION_URI}" "${VERSION}" --endpoint "${_endpoint}")" || return 1
        _FEAT_RESOLVED_TAG="$(printf '%s\n' "${_both}" | head -1)"
        VERSION="$(printf '%s\n' "${_both}" | tail -1)"
        ;;
      npm)
        if [[ -z "${VERSION_URI:-}" ]]; then
          logging__error "_options.version.resolution=npm requires VERSION_URI to be set in metadata."
          return 1
        fi
        VERSION="$(npm__resolve_version_uri "${VERSION_URI}" "${VERSION}")" || return 1
        ;;
      none | "")
        # Explicit 'none' or no resolution declared: VERSION is used as-is.
        ;;
      *)
        logging__error "_options.version.resolution='${VERSION_RESOLUTION}' has no auto-implementation; define __resolve_version to handle it."
        return 1
        ;;
    esac
  fi
  if [[ -n "${_FEAT_RESOLVED_TAG}" ]]; then
    logging__info "Resolved version: '${VERSION}' (tag: '${_FEAT_RESOLVED_TAG}')."
  else
    logging__info "Resolved version: '${VERSION}'."
  fi

  if declare -f __resolve_input_version_post > /dev/null; then
    __resolve_input_version_post
  fi
}

__resolve_input_prefixes__() {
  if declare -f __resolve_input_prefixes_pre > /dev/null; then
    __resolve_input_prefixes_pre
  fi
  resolve_prefix
  if declare -f __resolve_input_prefixes_post > /dev/null; then
    __resolve_input_prefixes_post
  fi
  return
}

# shellcheck disable=SC2329,SC2317
resolve_prefix() {
  logging__fn_entry "resolve_prefix"
  [[ -v PREFIX ]] || { logging__fn_exit "resolve_prefix"; return 0; }
  users__can_write "${PREFIX}" || {
    logging__error "Option 'prefix': '${PREFIX}' is not writable."
    exit 1
  }
  [[ -v PREFIX_ACTIVATIONS ]] && \
    PREFIX_SCOPE="$(users__is_user_path "${PREFIX}" && printf user || printf system)"
  logging__info "Option 'prefix' resolved to '${PREFIX}'."
  logging__fn_exit "resolve_prefix"
  return
}
# shellcheck disable=SC2329,SC2317
prefix_activation_snippet() { return 1; }

# Dependency Installation
# =======================
__dep_manifest_path__() {
  local _dep_type="$1"
  local _dep_group="$2"
  printf '%s\n' "${_FEAT_DEPS_DIR}/${_dep_type}/${_dep_group}.yaml"
}

__dep_install__() {
  local _dep_type="$1"
  local _dep_group="$2"
  shift 2

  if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
    local -a _args=(--manifest "$(__dep_manifest_path__ "${_dep_type}" "${_dep_group}")")
    [[ "$_dep_type" == "build" ]] && _args+=(--build-group "${_SYSSET_BUILD_CONTEXT}::${_dep_group}")
    ospkg__run "${_args[@]}" "$@"
  else
    logging__warn "Skipping '$_dep_group' group $_dep_type dependency installation (no privilege available); ensure dependencies are pre-installed."
  fi
  return
}

__dep_uninstall__() {
  local _dep_type="$1"
  local _dep_group="$2"
  shift 2
  local _manifest
  _manifest="$(__dep_manifest_path__ "${_dep_type}" "${_dep_group}")"
  if [[ ! -f "${_manifest}" ]]; then
    logging__error "Cannot uninstall '${_dep_group}' (${_dep_type}): manifest not found at '${_manifest}'."
    return 1
  fi
  ospkg__run --manifest "${_manifest}" --remove "$@"
  return
}

__dep_install_base__() {
  local _manifest
  _manifest="$(__dep_manifest_path__ build base)"
  if [[ -f "${_manifest}" ]]; then
    __dep_install__ build base "$@"
  fi
  _manifest="$(__dep_manifest_path__ run base)"
  if [[ -f "${_manifest}" ]]; then
    __dep_install__ run base "$@"
  fi
  return 0
}

# Feature Functions
# =================
${{ _script.feature_functions }}$

__main__ "$@"

# =============================================================================
# FEATURE HOOK CONTRACT
# =============================================================================
#
# CUSTOMIZATION MECHANISMS (in order of preference)
# --------------------------------------------------
#
# 1. _pre / _post hooks — inject code before/after any template function.
#    Every template function foo() checks for __foo_pre and __foo_post at its
#    entry and exit. Define them in install.bash to run custom logic around the
#    auto-implementation without replacing it.
#
#    Available pre/post pairs (all optional):
#      __install_pre / __install_post
#      __install_init_pre / __install_init_post
#      __install_run_pre / __install_run_post
#      __install_run_binary_pre / __install_run_binary_post
#      __install_run_package_pre / __install_run_package_post
#      __install_run_script_pre / __install_run_script_post
#      __install_run_source_pre / __install_run_source_post
#      __install_run_cargo_pre / __install_run_cargo_post
#      __install_run_npm_pre / __install_run_npm_post
#      __install_finish_pre / __install_finish_post
#      __uninstall_pre / __uninstall_post
#      __uninstall_init_pre / __uninstall_init_post
#      __uninstall_run_pre / __uninstall_run_post
#      __uninstall_run_prefix_pre / __uninstall_run_prefix_post
#      __uninstall_run_npm_pre / __uninstall_run_npm_post
#      __uninstall_run_npm_bundled_pre / __uninstall_run_npm_bundled_post
#      __uninstall_run_package_pre / __uninstall_run_package_post
#      __uninstall_finish_pre / __uninstall_finish_post
#      __reinstall_pre / __reinstall_post
#      __reinstall_init_pre / __reinstall_init_post
#      __reinstall_run_pre / __reinstall_run_post
#      __reinstall_finish_pre / __reinstall_finish_post
#      __update_pre / __update_post
#      __update_init_pre / __update_init_post
#      __update_run_pre / __update_run_post
#      __update_run_migrate_pre / __update_run_migrate_post
#      __update_run_package_pre / __update_run_package_post
#      __update_finish_pre / __update_finish_post
#      __verify_system_requirements_pre / __verify_system_requirements_post
#      __feat_do_configure_users_pre / __feat_do_configure_users_post
#      __resolve_input_version_pre / __resolve_input_version_post
#      __resolve_input_prefixes_pre / __resolve_input_prefixes_post
#      __exit_pre  (no post; runs in the trap handler)
#
# 2. Data arrays — set in a _pre hook to influence the auto-implementation.
#    _FEAT_INSTALL_SCRIPT_ARGS  (array) — extra args appended to the installer
#      script invocation in __install_run_script__. Set in
#      __install_run_script_pre. (For static args, set _options.method.script.args
#      in metadata instead.)
#    _FEAT_CARGO_COMMAND        (array) — overrides the cargo command, e.g.
#      (cargo binstall). Defaults to (cargo install) or (cargo binstall) when
#      cargo-binstall is on PATH. Set in __install_run_cargo_pre.
#    _FEAT_CARGO_INSTALL_ARGS   (array) — extra args appended after the
#      standard --root / --version / --no-confirm args in
#      __install_run_cargo__. Set in __install_run_cargo_pre.
#
# 3. Function override — redefine any template function in install.bash.
#    Feature functions are injected after all template definitions, so a
#    feature-defined __install_run_binary__() completely replaces the
#    template's version. Use this as a last resort when neither _pre/_post
#    hooks nor data arrays are sufficient.
#
# DISPATCHED HOOKS (called via declare -f at runtime)
# ----------------------------------------------------
# __resolve_method()
#   Required when METHOD=auto. Stdout: one concrete method name.
#   Called by __resolve_input_method__; error if absent when METHOD=auto.
#
# __resolve_version()
#   Called by __resolve_input_version__ when VERSION is set and METHOD!=package.
#   Stdout: resolved bare version (e.g. "1.2.3").
#   May also set _FEAT_RESOLVED_TAG via declare -g for full tag access.
#   Auto-impl: github__resolve_version when _options.version.resolution is set.
#
# __installed_version <installed_path>
#   Called by __feat_check_version_match__ to probe the installed version.
#   Stdout: installed version string.
#   Auto-impl: "${path}" "${VERSION_FLAG}" | ver__extract_version
#
# __install_run_script_run <script_path>
#   Called by __install_run_script__ after fetching the script URL, when
#   METHOD=script and this hook is defined. Receives the downloaded script
#   path. Use when you need full control over how the script is invoked.
#   If absent, the script is run directly with the static args from
#   _options.method.script.args and any _FEAT_INSTALL_SCRIPT_ARGS.
#
# __install_run_source_build <src_dir>
#   Called by __install_run_source__ after download+extraction.
#   Receives the path to the top-level extracted source directory.
#   Use for platform-specific flags, multi-pass builds, or post-install steps.
#   When absent, __install_run_source_auto_build__ is invoked instead
#   (driven by SOURCE_BUILD_SYSTEM / SOURCE_CONFIGURE_ARGS /
#   SOURCE_MAKE_FLAGS / SOURCE_MAKE_TARGETS).
#
# __get_completion_content__ <shell>
#   Called by __install_shell_completions__ to produce completion text for one
#   shell. Stdout: completion script. Return non-zero to skip that shell.
#   Auto-impl: run `${PREFIX}/bin/<PRIMARY_BIN> ${SHELL_COMPLETIONS_CMD} <shell>`
#   when SHELL_COMPLETIONS_CMD is set, or cat the path from SHELL_COMPLETIONS_FILES
#   matching <shell> when set.
#   Only needed when neither auto-impl applies (e.g. bespoke generation logic).
#
# __configure_user <username>
#   Called per resolved user by __feat_do_configure_users__. No auto-impl.
#   __feat_do_configure_users__ must be called explicitly (e.g. from
#   __install_finish_post) to trigger user configuration.
#
# CONTRACT GLOBALS (declare -g; set by orchestrators, readable in hooks)
# -----------------------------------------------------------------------
# _FEAT_EXISTING_PATH    Path to the detected existing binary, or "".
# _FEAT_EXISTING_METHOD  Install method of the existing binary, or "".
#                        Values: "package", "npm", "npm-bundled", "prefix", "".
# _FEAT_INSTALLED_VER    Installed version string from __feat_check_version_match__.
# _FEAT_RESOLVED_TAG     Full VCS tag from version resolution (e.g. "v1.7.1").
# _FEAT_CONFIGURE_USERS  Array of usernames resolved by __feat_do_configure_users__.
#
# MIGRATION PATTERN
# -----------------
# 1. In metadata.yaml: replace options.version / options.method with
#    _options.version / _options.method contract data.
# 2. In install.bash: define only the hooks needed. All module-level code
#    must become hook functions; the template's __main__ drives execution.
#
# Example — install-shellcheck:
#
#   # metadata.yaml adds:
#   _options:
#     gh_repo: koalaman/shellcheck
#     version:
#       resolution: github_release
#       default: stable
#       inputs: [stable, latest, semver]
#     method:
#       binary:
#         asset_pattern: "shellcheck-v{VERSION}.{OS}.{OS_ARCH}.tar.xz"
#         binary_src: shellcheck
#       package: {}
#
#   # install.bash (only hook needed):
#   __resolve_method() {
#     if [[ "$(os__release_kernel)" == "darwin" && "$(os__arch)" == "arm64" ]]; then
#       printf 'package\n'
#     else
#       printf 'binary\n'
#     fi
#   }
# =============================================================================
