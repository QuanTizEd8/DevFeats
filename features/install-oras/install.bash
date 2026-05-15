# shellcheck source=lib/install/oras.sh
. "${_BASE_DIR}/_lib/install/oras.sh"
# shellcheck source=lib/shell.sh
. "${_BASE_DIR}/_lib/shell.sh"
# shellcheck source=lib/users.sh
. "${_BASE_DIR}/_lib/users.sh"

install__oras \
  --context user \
  --owner-group "feature::install-oras" \
  --version "${VERSION}" \
  --method "${METHOD}" \
  --prefix "${PREFIX}" \
  --if-exists "${IF_EXISTS}" \
  --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
  --download-url "${DOWNLOAD_URL}" > /dev/null
if [[ "${METHOD}" == "auto" ]]; then
  if [[ -x "${PREFIX}/bin/oras" ]]; then
    METHOD=binary
  else
    METHOD=package
  fi
fi
