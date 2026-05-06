#!/usr/bin/env bash
# shellcheck source=lib/install/oras.sh
. "${_SELF_DIR}/_lib/install/oras.sh"
# shellcheck source=lib/shell.sh
. "${_SELF_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_SELF_DIR}/_lib/users.sh"

_oras__create_symlink() {
  if [[ "${SYMLINK}" != "true" ]]; then
    logging__info "symlink=false; skipping symlink creation."
    return 0
  fi
  if [[ "${METHOD}" == "repos" ]]; then
    logging__info "method=repos; symlink not applicable."
    return 0
  fi
  if [[ ! -x "${PREFIX}/bin/oras" ]]; then
    return 0
  fi
  shell__create_symlink \
    --src "${PREFIX}/bin/oras" \
    --system-target "/usr/local/bin/oras" \
    --user-target "${HOME}/.local/bin/oras"
}

if [[ -z "${PREFIX}" ]]; then
  PREFIX="$(users__default_prefix)"
fi

install__oras \
  --context user \
  --owner-group "feature::install-oras" \
  --version "${VERSION}" \
  --method "${METHOD}" \
  --prefix "${PREFIX}" \
  --if-exists "${IF_EXISTS}" \
  --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
  --download-url "${DOWNLOAD_URL}" > /dev/null

_oras__create_symlink
