#!/usr/bin/env bats
# Unit tests for lib/oci.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib oci.sh
}

@test "oci__ghcr_image_ref prints ghcr.io qualified name" {
  run oci__ghcr_image_ref "quantized8/sysset" "install-pixi" "1.2.3"
  assert_success
  assert_output "ghcr.io/quantized8/sysset/install-pixi:1.2.3"
}
