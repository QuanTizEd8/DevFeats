install__oras \
  --context user \
  --owner-group "feature::install-oras" \
  --version "${VERSION}" \
  --method "${METHOD}" \
  --prefix "${PREFIX}" \
  --if-exists "${IF_EXISTS}" \
  --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
  --installer-dir "${INSTALLER_DIR}" \
  --gh-repo "${GH_REPO}" > /dev/null
if [[ "${METHOD}" == "auto" ]]; then
  if [[ -x "${PREFIX}/bin/oras" ]]; then
    METHOD=binary
  else
    METHOD=package
  fi
fi
