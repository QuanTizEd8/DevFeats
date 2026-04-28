#!/usr/bin/env bash
# shellcheck source=lib/install/oras.sh
. "${_SELF_DIR}/_lib/install/oras.sh"

install__oras \
  --context user \
  --owner-group "feature::install-oras" \
  --version "${VERSION}" \
  --method "${METHOD}" \
  --prefix "${PREFIX}" \
  --if-exists "${IF_EXISTS}" \
  --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
  --download-url "${DOWNLOAD_URL}" > /dev/null
