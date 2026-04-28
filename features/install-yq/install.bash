#!/usr/bin/env bash
# shellcheck source=lib/install/yq.sh
. "${_SELF_DIR}/_lib/install/yq.sh"

install__yq \
  --context user \
  --owner-group "feature::install-yq" \
  --method "${METHOD}" \
  --if-exists "${IF_EXISTS}" \
  --prefix "${PREFIX}" > /dev/null
