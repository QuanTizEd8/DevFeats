#!/usr/bin/env bash
# shellcheck source=lib/install/yq.sh
. "${_SELF_DIR}/_lib/install/yq.sh"

install__yq \
  --context user \
  --owner-group "feature::install-yq" \
  --method "${METHOD}" \
  --if-exists "${IF_EXISTS}" \
  --repos-manifest "${_BASE_DIR}/dependencies/run/os-pkg.yaml" \
  --prefix "${PREFIX}" > /dev/null
