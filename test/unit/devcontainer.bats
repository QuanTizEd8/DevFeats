#!/usr/bin/env bats
# Unit tests for lib/devcontainer.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/json_assert'
  load 'helpers/stubs'
  reload_lib devcontainer.sh
}

@test "devcontainer__parse_config prints normalized JSON" {
  _f="$(mktemp "${BATS_TEST_TMPDIR}/dc.XXXXXX")"
  printf '%s' '{"a":1}' > "$_f"
  run --separate-stderr devcontainer__parse_config "$_f"
  assert_success
  # Keep stdout contract strict: only normalized JSON belongs on stdout.
  assert_json_compact_equals "$output" '{"a":1}'
  rm -f "$_f"
}

@test "devcontainer__workspace_folder walks above .devcontainer" {
  _root="$(mktemp -d "${BATS_TEST_TMPDIR}/ws.XXXXXX")"
  mkdir -p "$_root/proj/.devcontainer"
  _cfg="$_root/proj/.devcontainer/devcontainer.json"
  printf '%s' '{}' > "$_cfg"
  _want="$(cd "$_root/proj" && pwd -P)"
  run devcontainer__workspace_folder "$_cfg"
  assert_success
  assert_output "$_want"
  rm -rf "$_root"
}

@test "devcontainer__workspace_folder walks above nested .devcontainer subdir" {
  _root="$(mktemp -d "${BATS_TEST_TMPDIR}/ws2.XXXXXX")"
  mkdir -p "$_root/proj/.devcontainer/full"
  _cfg="$_root/proj/.devcontainer/full/devcontainer.json"
  printf '%s' '{}' > "$_cfg"
  _want="$(cd "$_root/proj" && pwd -P)"
  run devcontainer__workspace_folder "$_cfg"
  assert_success
  assert_output "$_want"
  rm -rf "$_root"
}

@test "devcontainer__oci_id_and_tag splits OCI id and version" {
  run devcontainer__oci_id_and_tag "ghcr.io/org/install-pixI:1.2.3"
  assert_line -n 0 "install-pixI"
  assert_line -n 1 "1.2.3"
  assert_success
}

@test "devcontainer__lifecycle_disabled: all skips" {
  run devcontainer__lifecycle_disabled "all" feature "x" postCreateCommand
  assert_success
}

@test "devcontainer__lifecycle_disabled: bare phase skips that phase (feature scope)" {
  run devcontainer__lifecycle_disabled "postCreateCommand" feature "x" "postCreateCommand"
  assert_success
}

@test "devcontainer__lifecycle_disabled: bare phase does not skip other phases" {
  run devcontainer__lifecycle_disabled "postCreateCommand" feature "x" "onCreateCommand"
  assert_failure
}

@test "devcontainer__lifecycle_disabled: feature id skips at feature scope only" {
  run devcontainer__lifecycle_disabled "pixi" feature "pixi" "onCreateCommand"
  assert_success
  run devcontainer__lifecycle_disabled "pixi" container "_container_" "onCreateCommand"
  assert_failure
}

@test "devcontainer__lifecycle_disabled: feature:phase:cmd three-token form" {
  run devcontainer__lifecycle_disabled "pixi:postCreateCommand:setup" feature "pixi" "postCreateCommand" "setup"
  assert_success
  run devcontainer__lifecycle_disabled "pixi:postCreateCommand:setup" feature "pixi" "postCreateCommand" "other"
  assert_failure
}

@test "devcontainer__lifecycle_disabled: phase:cmd at container scope" {
  run devcontainer__lifecycle_disabled "onCreateCommand:build" container "_container_" "onCreateCommand" "build"
  assert_success
  run devcontainer__lifecycle_disabled "onCreateCommand:build" container "_container_" "postCreateCommand" "build"
  assert_failure
}

# ---------------------------------------------------------------------------
# devcontainer__parse_config
# ---------------------------------------------------------------------------

@test "devcontainer__parse_config strips JSONC comments and trailing commas" {
  _f="$(mktemp "${BATS_TEST_TMPDIR}/dc.XXXXXX")"
  cat > "$_f" << 'EOF'
// line comment
{
  /* block */
  "name": "x",
  "features": {
    "ghcr.io/foo/bar": {},
  },
}
EOF
  run devcontainer__parse_config "$_f"
  assert_success
  assert_output --partial '"name": "x"'
  assert_output --partial '"ghcr.io/foo/bar": {}'
  rm -f "$_f"
}

@test "devcontainer__parse_config rejects duplicate feature keys" {
  _f="$(mktemp "${BATS_TEST_TMPDIR}/dc.XXXXXX")"
  cat > "$_f" << 'EOF'
{"features":{"a":{},"a":{}}}
EOF
  run devcontainer__parse_config "$_f"
  assert_failure
  rm -f "$_f"
}

# ---------------------------------------------------------------------------
# devcontainer__iter_features
# ---------------------------------------------------------------------------

@test "devcontainer__iter_features filters by compatible prefix" {
  _f="$(mktemp "${BATS_TEST_TMPDIR}/dc.iter.XXXXXX")"
  cat > "$_f" << 'EOF'
{
  "features": {
    "ghcr.io/quantized8/sysset/install-pixi": { "version": "0.66.0" },
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/quantized8/sysset/install-os-pkg:1.0.0": {}
  }
}
EOF
  # Capture stdout only (the warning for non-compatible keys goes to stderr).
  _out="$(devcontainer__iter_features "$_f" "" "ghcr.io/quantized8/sysset/" 2> /dev/null)"
  [[ "$_out" == *"install-pixi"* ]] || false
  [[ "$_out" == *"install-os-pkg"* ]] || false
  [[ "$_out" != *"docker-in-docker"* ]] || false
  rm -f "$_f"
}

@test "devcontainer__iter_features parses trailing :tag from the OCI key" {
  _f="$(mktemp "${BATS_TEST_TMPDIR}/dc.iter2.XXXXXX")"
  cat > "$_f" << 'EOF'
{"features":{"ghcr.io/quantized8/sysset/install-pixi:1.2.3":{}}}
EOF
  run devcontainer__iter_features "$_f" "" "ghcr.io/quantized8/sysset/"
  assert_success
  # Output format: <id>\t<key>\t<tag>; assert id and tag parsed correctly.
  [[ "$output" == *$'\t'*$'\t'"1.2.3" ]] || false
  [[ "$output" == "install-pixi"$'\t'* ]] || false
  rm -f "$_f"
}

@test "devcontainer__iter_features resolves local-path features under workspace" {
  _root="$(mktemp -d "${BATS_TEST_TMPDIR}/dcws.XXXXXX")"
  mkdir -p "${_root}/features/my-feat"
  cat > "${_root}/features/my-feat/devcontainer-feature.json" << 'EOF'
{"id":"my-feat","version":"0.1.0"}
EOF
  _f="${_root}/devcontainer.json"
  cat > "$_f" << 'EOF'
{"features":{"./features/my-feat":{}}}
EOF
  run devcontainer__iter_features "$_f" "$_root" "ghcr.io/quantized8/sysset/"
  assert_success
  # id column = "my-feat" from the basename of the path.
  [[ "$output" == "my-feat"$'\t'* ]] || false
  rm -rf "$_root"
}

# ---------------------------------------------------------------------------
# devcontainer__feature_env_exports
# ---------------------------------------------------------------------------

@test "devcontainer__feature_env_exports coerces booleans + strings" {
  run bash -c '. "$1" && printf %s "{\"log_level\":\"trace\",\"prefix\":\"/opt\"}" | devcontainer__feature_env_exports' _ "${LIB_ROOT}/devcontainer.sh"
  assert_success
  assert_output --partial "export LOG_LEVEL=trace"
  assert_output --partial "export PREFIX=/opt"
}

@test "devcontainer__feature_env_exports rejects JSON array values" {
  run bash -c '. "$1" && printf %s "{\"packages\":[\"a\",\"b\"]}" | devcontainer__feature_env_exports' _ "${LIB_ROOT}/devcontainer.sh"
  assert_failure
  assert_output --partial "packages"
}

@test "devcontainer__feature_env_exports preserves embedded newlines in string values" {
  # The devcontainer spec forbids JSON arrays in option values; sysset's
  # type: array is transported as a newline-separated string.
  run bash -c '. "$1" && printf %s "{\"packages\":\"a\nb\"}" | devcontainer__feature_env_exports' _ "${LIB_ROOT}/devcontainer.sh"
  assert_success
  assert_output --partial "PACKAGES"
}

# ---------------------------------------------------------------------------
# devcontainer__name_version_suffix
# ---------------------------------------------------------------------------

@test "devcontainer__name_version_suffix matches trailing vX.Y.Z" {
  run devcontainer__name_version_suffix "Bundle v1.2.3"
  assert_output "1.2.3"
  assert_success
}

@test "devcontainer__name_version_suffix returns empty when no match" {
  run devcontainer__name_version_suffix "no version"
  assert_output ""
  assert_success
}

# ---------------------------------------------------------------------------
# devcontainer__build_ordering_inputs
# ---------------------------------------------------------------------------

@test "devcontainer__build_ordering_inputs emits hard/soft edges + priority" {
  _root="$(mktemp -d "${BATS_TEST_TMPDIR}/bo.XXXXXX")"
  mkdir -p "${_root}/a" "${_root}/b" "${_root}/c"
  cat > "${_root}/a/devcontainer-feature.json" << 'EOF'
{"id":"a","installsAfter":["ghcr.io/x/c"]}
EOF
  cat > "${_root}/b/devcontainer-feature.json" << 'EOF'
{"id":"b","dependsOn":{"ghcr.io/x/a":{}}}
EOF
  cat > "${_root}/c/devcontainer-feature.json" << 'EOF'
{"id":"c"}
EOF
  _cfg="$(mktemp "${BATS_TEST_TMPDIR}/bo-cfg.XXXXXX")"
  cat > "$_cfg" << 'EOF'
{"overrideFeatureInstallOrder":["ghcr.io/x/a","ghcr.io/x/b"]}
EOF
  _h="$(mktemp "${BATS_TEST_TMPDIR}/bo-h.XXXXXX")"
  _s="$(mktemp "${BATS_TEST_TMPDIR}/bo-s.XXXXXX")"
  _p="$(mktemp "${BATS_TEST_TMPDIR}/bo-p.XXXXXX")"
  run devcontainer__build_ordering_inputs \
    --hard-edges-file "$_h" \
    --soft-edges-file "$_s" \
    --priority-file "$_p" \
    --staged-root "$_root" \
    --config-file "$_cfg" \
    -- a b c
  assert_success
  # Hard edge: a (dependsOn of b) → b.
  run cat "$_h"
  assert_output --partial $'a\tb'
  # Soft edge: c → a (installsAfter).
  run cat "$_s"
  assert_output --partial $'c\ta'
  # Priority: a is first → highest value.
  run cat "$_p"
  assert_output --partial "a"
  assert_output --partial "b"
  rm -rf "$_root" "$_cfg" "$_h" "$_s" "$_p"
}

# ---------------------------------------------------------------------------
# devcontainer__lifecycle_iter
# ---------------------------------------------------------------------------

@test "devcontainer__lifecycle_iter emits features first, container last" {
  _root="$(mktemp -d "${BATS_TEST_TMPDIR}/lci.XXXXXX")"
  mkdir -p "${_root}/a" "${_root}/b"
  cat > "${_root}/a/devcontainer-feature.json" << 'EOF'
{"id":"a","postCreateCommand":"echo a"}
EOF
  cat > "${_root}/b/devcontainer-feature.json" << 'EOF'
{"id":"b","postCreateCommand":"echo b"}
EOF
  _cfg="$(mktemp "${BATS_TEST_TMPDIR}/lci-cfg.XXXXXX")"
  cat > "$_cfg" << 'EOF'
{"postCreateCommand":"echo container"}
EOF
  run devcontainer__lifecycle_iter --config-file "$_cfg" --staged-root "$_root" --phase postCreateCommand -- a b
  assert_success
  # First line must be feature a, last line must be container.
  [[ "${lines[0]}" == feature$'\t'a$'\t'* ]] || false
  [[ "${lines[1]}" == feature$'\t'b$'\t'* ]] || false
  [[ "${lines[2]}" == container$'\t'* ]] || false
  rm -rf "$_root" "$_cfg"
}
