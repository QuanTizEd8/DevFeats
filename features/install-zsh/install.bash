# shellcheck shell=bash

# shellcheck disable=SC2329,SC2317
__resolve_method() {
  printf 'package\n'
}

# shellcheck disable=SC2329,SC2317
__zsh__fetch_release_index() {
  local _dest="$1"
  uri__fetch_asset "${SOURCE_SIDECAR_URI}" \
    --file-dest "${_dest}" \
    --sha256 none > /dev/null
}

# shellcheck disable=SC2329,SC2317
__zsh__list_release_versions() {
  local _sum_file="$1"
  awk '/^[^ ]+ +zsh-[0-9]+\.[0-9]+(\.[0-9]+)?\.tar\.xz$/ {
    sub(/^.*zsh-/, ""); sub(/\.tar\.xz$/, ""); print
  }' "${_sum_file}" | sort -V -r
}

# shellcheck disable=SC2329,SC2317
__resolve_version() {
  logging__info "Resolving Zsh version from zsh.org..."
  mkdir -p "${INSTALLER_DIR}"
  local _sum_file="${INSTALLER_DIR}/SHA256SUM"
  __zsh__fetch_release_index "${_sum_file}" || return 1

  local _spec="${VERSION:-stable}"
  local _versions _resolved=""
  mapfile -t _versions < <(__zsh__list_release_versions "${_sum_file}")

  ((${#_versions[@]} == 0)) && {
    logging__error "Could not find any zsh release versions in SHA256SUM."
    return 1
  }

  case "${_spec}" in
    stable | latest)
      _resolved="${_versions[0]}"
      ;;
    *)
      if ver__extract_version --full-match "${_spec}" > /dev/null; then
        _resolved="$(ver__extract_version --full-match "${_spec}")"
      else
        _resolved="$(printf '%s\n' "${_versions[@]}" | ver__first_matching_prefix "${_spec}")" || {
          logging__error "No zsh release matching version spec '${_spec}'."
          return 1
        }
      fi
      ;;
  esac

  [[ -n "${_resolved}" ]] || {
    logging__error "Failed to resolve zsh version from spec '${_spec}'."
    return 1
  }
  printf '%s\n' "${_resolved}"
}

__install_run_package__() {
  local _pkg_version=""
  case "${VERSION:-latest}" in
    stable | latest) ;;
    *) _pkg_version="${VERSION}" ;;
  esac
  __dep_install__ run os-pkg --extra-var "VERSION=${_pkg_version}"
}

__update_run_package__() {
  local _pkg_version=""
  case "${VERSION:-latest}" in
    stable | latest) ;;
    *) _pkg_version="${VERSION}" ;;
  esac
  __dep_install__ run os-pkg --extra-var "VERSION=${_pkg_version}" --update
}

__install_run_source_pre() {
  file__mkdir "${PREFIX}" || {
    logging__error "PREFIX '${PREFIX}' could not be created (check privilege)."
    return 1
  }
  if users__is_user_path "${PREFIX}" && [[ ! -w "${PREFIX}" ]]; then
    logging__error "PREFIX '${PREFIX}' is not writable."
    return 1
  fi

  if [[ "$(os__kernel)" == "Darwin" ]]; then
    xcode-select --print-path > /dev/null 2>&1 || {
      logging__error "Xcode Command Line Tools are required for source builds on macOS."
      logging__info "Install with: xcode-select --install"
      return 1
    }
  fi

  if ! users__is_user_path "${PREFIX}"; then
    __dep_install__ build source-build
  else
    logging__info "User-local mode: skipping build dependency installation; expecting required packages to be preinstalled."
  fi
}

__zsh__fetch_source_asset() {
  local _asset_uri="$1"
  local _verify="${2:-sidecar}"
  local -a _fetch_args=(--installer-dir "${INSTALLER_DIR}")

  case "${_verify}" in
    none)
      _fetch_args+=(--sha256 none)
      ;;
    sidecar)
      if [[ -v SOURCE_SIDECAR_URI && -n "${SOURCE_SIDECAR_URI}" ]]; then
        local _sc_uri
        _sc_uri="$(os__expand_release_pattern "${SOURCE_SIDECAR_URI}" "${VERSION:-}" "${_FEAT_RESOLVED_TAG:-}")"
        _fetch_args+=(--sidecar "${_sc_uri}")
      fi
      ;;
  esac

  uri__fetch_asset "${_asset_uri}" "${_fetch_args[@]}"
}

__install_run_source__() {
  if declare -f __install_run_source_pre > /dev/null; then
    __install_run_source_pre
  fi

  local _tag _primary_uri _old_uri
  _tag="${_FEAT_RESOLVED_TAG:-${VERSION:+v${VERSION}}}"
  _primary_uri="$(os__expand_release_pattern "${SOURCE_ASSET_URI}" "${VERSION:-}" "${_tag:-}")"
  _old_uri="https://www.zsh.org/pub/old/zsh-${VERSION}.tar.xz"

  if ! __zsh__fetch_source_asset "${_primary_uri}"; then
    logging__warn "Primary source URI failed; trying old/ mirror for zsh-${VERSION}..."
    if ! __zsh__fetch_source_asset "${_old_uri}" none; then
      logging__error "Failed to download zsh-${VERSION} from primary and old/ mirrors."
      return 1
    fi
  fi

  local _src_dir
  _src_dir="$(find "${INSTALLER_DIR}/asset" -maxdepth 1 -mindepth 1 -type d 2> /dev/null | head -1)"
  if [[ -z "${_src_dir}" ]]; then
    logging__error "METHOD=source: no directory found under '${INSTALLER_DIR}/asset' after extraction."
    return 1
  fi

  __install_run_source_build "${_src_dir}"

  if declare -f __install_run_source_post > /dev/null; then
    __install_run_source_post
  fi
}

__install_run_source_build() {
  local _src_dir="$1"
  local _jobs
  _jobs="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || printf '1')"

  local -a _configure_args=(
    --prefix="${PREFIX}"
    --with-term-lib="ncursesw ncurses curses termcap"
    --enable-multibyte
    --enable-function-subdirs
  )

  logging__build "Building zsh ${VERSION}..."
  (
    cd "${_src_dir}" || exit 1
    ./configure "${_configure_args[@]}" || exit 1
    make -j"${_jobs}" all || exit 1
    make install.bin install.modules install.fns || exit 1
  ) || return 1

  "${PREFIX}/bin/zsh" --version
  logging__success "zsh ${VERSION} installed to ${PREFIX}/bin/zsh."
}

__install_finish_post() {
  [[ "${METHOD}" == "source" && "${PREFIX_SCOPE}" == "system" ]] || return 0

  local _zsh="${PREFIX}/bin/zsh"
  [[ -x "${_zsh}" ]] || return 0

  local _shells_file=/etc/shells
  [[ -f /usr/share/defaults/etc/shells ]] && _shells_file=/usr/share/defaults/etc/shells
  if [[ -f "${_shells_file}" ]] && ! grep -qx "${_zsh}" "${_shells_file}" 2> /dev/null; then
    printf '%s\n' "${_zsh}" | file__append_privileged "${_shells_file}"
    logging__info "Added '${_zsh}' to '${_shells_file}'."
  fi
}

__uninstall_run_prefix_post() {
  local _prefix="${PREFIX}"
  [[ -n "${_prefix}" && "${_prefix}" != "/" ]] || return 0
  file__rm -rf "${_prefix}/lib/zsh/"
  file__rm -rf "${_prefix}/share/zsh/"
}
