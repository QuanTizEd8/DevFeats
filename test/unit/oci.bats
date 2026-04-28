#!/usr/bin/env bats
# Unit tests for lib/oci.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  reload_lib oci.sh
}

_test_sha256_file() {
  local _f="${1-}"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$_f" | awk '{print $1}'
    return 0
  fi
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "$_f" | awk '{print $1}'
    return 0
  fi
  return 1
}

@test "oci__ghcr_image_ref prints ghcr.io qualified name" {
  run oci__ghcr_image_ref "quantized8/sysset" "install-pixi" "1.2.3"
  assert_success
  assert_output "ghcr.io/quantized8/sysset/install-pixi:1.2.3"
}

@test "oci__is_feature_ref_key accepts OCI refs and rejects non-refs" {
  run oci__is_feature_ref_key "ghcr.io/devcontainers/features/git:1"
  assert_success

  run oci__is_feature_ref_key "localhost:5000/devcontainers/features/git:1"
  assert_success

  run oci__is_feature_ref_key "mcr.microsoft.com/devcontainers/features/common-utils@sha256:abc123"
  assert_success

  run oci__is_feature_ref_key "docker-in-docker"
  assert_failure

  run oci__is_feature_ref_key "localhost:abc/devcontainers/features/git:1"
  assert_failure

  run oci__is_feature_ref_key "foo:bar"
  assert_failure
}

@test "oci__resolve_version resolves latest and partial specs" {
  oci__list_tags() {
    cat <<'EOF'
latest
1
1.2
1.2.3
1.2.4
2.0.0-rc.1
EOF
  }
  export -f oci__list_tags

  run oci__resolve_version "ghcr.io/acme/feat" ""
  assert_success
  assert_output "latest"

  run oci__resolve_version "ghcr.io/acme/feat" "1.2"
  assert_success
  assert_output "1.2.4"

  run oci__resolve_version "ghcr.io/acme/feat" "2"
  assert_failure
}

@test "oci__resolve_version excludes prereleases unless explicitly requested" {
  oci__list_tags() {
    cat <<'EOF'
1.2.3
1.2.4-rc.1
1.2.4
2.0.0-beta.1
EOF
  }
  export -f oci__list_tags

  run oci__resolve_version "ghcr.io/acme/feat" ""
  assert_success
  assert_output "1.2.4"

  run oci__resolve_version "ghcr.io/acme/feat" "2.0.0-beta.1"
  assert_success
  assert_output "2.0.0-beta.1"
}

@test "oci__resolve_version falls back to highest semver when latest tag missing" {
  oci__list_tags() {
    cat <<'EOF'
1.0.0
1.1.0
2.0.0-rc.1
EOF
  }
  export -f oci__list_tags

  run oci__resolve_version "ghcr.io/acme/feat" "latest"
  assert_success
  assert_output "1.1.0"
}

@test "oci__pull_feature_tgz validates pulled archive shape" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  mkdir -p "${_tmp}/p"
  printf '%s\n' '#!/usr/bin/env sh' > "${_tmp}/p/install.sh"
  printf '%s\n' '{}' > "${_tmp}/p/devcontainer-feature.json"
  tar -czf "$_good" -C "${_tmp}/p" .
  local _hash
  _hash="$(_test_sha256_file "$_good")"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
      cat <<EOF
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${_hash}"}]}
EOF
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      mkdir -p "$4"
      cp "$_good" "$4/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_success
}

@test "oci__pull_feature_tgz performs registry login from SYSSET_OCI_AUTH" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  mkdir -p "${_tmp}/p"
  printf '%s\n' '#!/usr/bin/env sh' > "${_tmp}/p/install.sh"
  printf '%s\n' '{}' > "${_tmp}/p/devcontainer-feature.json"
  tar -czf "$_good" -C "${_tmp}/p" .
  local _hash
  _hash="$(_test_sha256_file "$_good")"
  local _log="${_tmp}/log"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "login" ]]; then
      printf '%s\n' "$*" >> "$_log"
      return 0
    fi
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
      cat <<EOF
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:${_hash}"}]}
EOF
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      mkdir -p "$4"
      cp "$_good" "$4/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  export SYSSET_OCI_AUTH="ghcr.io|u|t"
  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_success
  run bash -c "grep -q 'login ghcr.io -u u --password-stdin' '$_log'"
  assert_success
  [[ -f "$_out" ]]
}

@test "oci__list_tags authenticates using SYSSET_OCI_AUTH_FILE" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _authf="${_tmp}/auth.txt"
  local _log="${_tmp}/log"
  printf '%s' 'ghcr.io|user1|tok1' > "$_authf"

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "login" ]]; then
      printf '%s\n' "$*" >> "$_log"
      return 0
    fi
    if [[ "$1" == "repo" && "$2" == "tags" ]]; then
      printf '%s\n' "1.0.0"
      return 0
    fi
    return 1
  }
  export -f oras

  export SYSSET_OCI_AUTH=""
  export SYSSET_OCI_AUTH_FILE="$_authf"
  run oci__list_tags "ghcr.io/acme/feature"
  assert_success
  assert_output "1.0.0"
  run bash -c "grep -q 'login ghcr.io -u user1 --password-stdin' '$_log'"
  assert_success
}

@test "oci__pull_feature_tgz fails invalid archive shape" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _bad="${_tmp}/bad.tgz"
  mkdir -p "${_tmp}/q"
  printf '%s\n' '{}' > "${_tmp}/q/devcontainer-feature.json"
  tar -czf "$_bad" -C "${_tmp}/q" .

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      mkdir -p "$4"
      cp "$_bad" "$4/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_failure
}

@test "oci__pull_feature_tgz fails on manifest digest mismatch" {
  local _tmp
  _tmp="$(mktemp -d)"
  local _good="${_tmp}/good.tgz"
  mkdir -p "${_tmp}/p"
  printf '%s\n' '#!/usr/bin/env sh' > "${_tmp}/p/install.sh"
  printf '%s\n' '{}' > "${_tmp}/p/devcontainer-feature.json"
  tar -czf "$_good" -C "${_tmp}/p" .

  oras() {
    if [[ "$1" == "version" ]]; then
      printf '%s\n' "Version: 1.2.0"
      return 0
    fi
    if [[ "$1" == "manifest" && "$2" == "fetch" ]]; then
      cat <<'EOF'
{"layers":[{"mediaType":"application/vnd.devcontainers.layer.v1+tgz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}
EOF
      return 0
    fi
    if [[ "$1" == "pull" ]]; then
      mkdir -p "$4"
      cp "$_good" "$4/devcontainer-feature-x.tgz"
      return 0
    fi
    return 1
  }
  export -f oras

  local _out="${_tmp}/out.tgz"
  run oci__pull_feature_tgz "ghcr.io/acme/x:1.0.0" "$_out"
  assert_failure
}
