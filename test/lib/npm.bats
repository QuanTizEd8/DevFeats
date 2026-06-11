#!/usr/bin/env bats
# Unit tests for lib/npm.sh
#
# Network calls are replaced with function stubs that return canned JSON.

bats_require_minimum_version 1.7.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
  reload_lib net.sh
  reload_lib ver.sh
  reload_lib json.sh
  reload_lib npm.sh
  # Stub out network-layer helpers so no real connections are made.
  net__ensure_fetch_tool() {
    _NET__FETCH_TOOL=curl
    _NET__CA_CERTS_OK=true
    return 0
  }
  net__ensure_ca_certs() {
    _NET__CA_CERTS_OK=true
    return 0
  }
  export -f net__ensure_fetch_tool net__ensure_ca_certs
}

# ---------------------------------------------------------------------------
# npm__fetch_package_json
# ---------------------------------------------------------------------------

@test "npm__fetch_package_json fetches full doc to stdout by default" {
  net__fetch_url_stdout() {
    printf '{"name":"typescript","dist-tags":{"latest":"5.4.5"}}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run npm__fetch_package_json "typescript"
  assert_output --partial '"name":"typescript"'
  assert_success
}

@test "npm__fetch_package_json writes to --dest file" {
  net__fetch_url_file() {
    printf '{"name":"typescript"}\n' > "$2"
    return 0
  }
  export -f net__fetch_url_file
  local _dest="${BATS_TEST_TMPDIR}/pkg.json"
  run npm__fetch_package_json "typescript" --dest "$_dest"
  assert_success
  assert [ -f "$_dest" ]
  run cat "$_dest"
  assert_output --partial '"name":"typescript"'
}

@test "npm__fetch_package_json appends version to URL when --version given" {
  local _url_file="${BATS_TEST_TMPDIR}/url.txt"
  _npm__registry_get() {
    printf '%s\n' "$1" > "${_url_file}"
    printf '{"version":"5.4.5"}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__fetch_package_json "typescript" --version "5.4.5"
  assert_success
  run cat "$_url_file"
  assert_output --partial "/typescript/5.4.5"
}

@test "npm__fetch_package_json rejects unknown option" {
  run npm__fetch_package_json "typescript" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# npm__dist_tags
# ---------------------------------------------------------------------------

@test "npm__dist_tags prints name=version pairs" {
  net__fetch_url_stdout() {
    printf '{"latest":"5.4.5","next":"5.5.0-beta.1","beta":"5.5.0-beta.1"}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run npm__dist_tags "typescript"
  assert_success
  assert_output --partial "latest=5.4.5"
  assert_output --partial "next=5.5.0-beta.1"
}

@test "npm__dist_tags fails when network call fails" {
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  run npm__dist_tags "typescript"
  assert_failure
}

@test "npm__dist_tags fails on empty response" {
  net__fetch_url_stdout() {
    printf ''
    return 0
  }
  export -f net__fetch_url_stdout
  run npm__dist_tags "typescript"
  assert_failure
}

# ---------------------------------------------------------------------------
# npm__latest_version
# ---------------------------------------------------------------------------

@test "npm__latest_version returns the latest dist-tag version" {
  npm__dist_tags() {
    printf 'latest=5.4.5\nnext=5.5.0-beta.1\n'
    return 0
  }
  export -f npm__dist_tags
  run npm__latest_version "typescript"
  assert_output "5.4.5"
  assert_success
}

@test "npm__latest_version fails when dist_tags call fails" {
  npm__dist_tags() { return 1; }
  export -f npm__dist_tags
  run npm__latest_version "typescript"
  assert_failure
  assert_output --partial "could not fetch dist-tags"
}

@test "npm__latest_version fails when no latest tag present" {
  npm__dist_tags() {
    printf 'next=5.5.0-beta.1\n'
    return 0
  }
  export -f npm__dist_tags
  run npm__latest_version "typescript"
  assert_failure
  assert_output --partial "no 'latest' dist-tag"
}

# ---------------------------------------------------------------------------
# npm__versions
# ---------------------------------------------------------------------------

@test "npm__versions returns stable versions sorted newest-first" {
  net__fetch_url_stdout() {
    printf '{"versions":{"1.0.0":{},"1.2.0":{},"2.0.0":{},"2.0.1":{},"3.0.0-beta.1":{}}}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run npm__versions "somepackage"
  assert_success
  # 3.0.0-beta.1 is prerelease — must be absent; rest sorted newest-first.
  refute_output --partial "3.0.0-beta.1"
  assert_output --partial "2.0.1"
  # First line must be the newest stable version.
  [[ "$(printf '%s\n' "$output" | head -1)" == "2.0.1" ]]
}

@test "npm__versions --all includes prerelease versions" {
  net__fetch_url_stdout() {
    printf '{"versions":{"1.0.0":{},"2.0.0-beta.1":{}}}\n'
    return 0
  }
  export -f net__fetch_url_stdout
  run npm__versions "somepackage" --all
  assert_success
  assert_output --partial "2.0.0-beta.1"
  assert_output --partial "1.0.0"
}

@test "npm__versions rejects unknown option" {
  run npm__versions "somepackage" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "npm__versions fails when network call fails" {
  net__fetch_url_stdout() { return 1; }
  export -f net__fetch_url_stdout
  run npm__versions "somepackage"
  assert_failure
}

# ---------------------------------------------------------------------------
# npm__resolve_version
# ---------------------------------------------------------------------------

@test "npm__resolve_version stable / empty resolves dist-tags.latest" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{},"5.4.4":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "stable"
  assert_output "5.4.5"
  assert_success
}

@test "npm__resolve_version empty spec resolves as stable" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{},"5.4.4":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" ""
  assert_output "5.4.5"
  assert_success
}

@test "npm__resolve_version latest returns newest including prereleases" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.5.0-beta.1":{},"5.4.5":{},"5.4.4":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "latest"
  assert_output "5.5.0-beta.1"
  assert_success
}

@test "npm__resolve_version numeric prefix finds newest stable match" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{},"5.4.4":{},"5.4.0":{},"5.3.3":{},"4.9.5":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "5.4"
  assert_output "5.4.5"
  assert_success
}

@test "npm__resolve_version exact version matches" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{},"5.4.4":{},"5.3.0":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "5.4.4"
  assert_output "5.4.4"
  assert_success
}

@test "npm__resolve_version major-only spec finds newest stable match" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{},"5.3.0":{},"4.9.5":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "5"
  assert_output "5.4.5"
  assert_success
}

@test "npm__resolve_version symbolic dist-tag resolves to its version" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5","next":"5.5.0-beta.1"},"versions":{"5.5.0-beta.1":{},"5.4.5":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "next"
  assert_output "5.5.0-beta.1"
  assert_success
}

@test "npm__resolve_version fails for unknown dist-tag" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "nosuchcanary"
  assert_failure
  assert_output --partial "dist-tag 'nosuchcanary' not found"
}

@test "npm__resolve_version fails for numeric spec with no matching version" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"5.4.5"},"versions":{"5.4.5":{},"5.3.0":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "typescript" "4.9"
  assert_failure
  assert_output --partial "no stable version matching"
}

@test "npm__resolve_version rejects unknown option" {
  run npm__resolve_version "typescript" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "npm__resolve_version --registry strips trailing slash from base URL" {
  local _url_file="${BATS_TEST_TMPDIR}/registry-url.txt"
  _npm__registry_get() {
    printf '%s\n' "$1" > "${_url_file}"
    printf '{"dist-tags":{"latest":"1.0.0"},"versions":{"1.0.0":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "@scope/pkg" "stable" --registry "https://example.com/"
  assert_success
  assert_output "1.0.0"
  run cat "${_url_file}"
  assert_output "https://example.com/@scope/pkg"
}

@test "npm__resolve_version --registry passes custom base to package document URL" {
  local _url_file="${BATS_TEST_TMPDIR}/registry-url.txt"
  _npm__registry_get() {
    printf '%s\n' "$1" > "${_url_file}"
    printf '{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version "my-pkg" "stable" --registry "https://registry.example.com"
  assert_success
  assert_output "2.3.4"
  run cat "${_url_file}"
  assert_output "https://registry.example.com/my-pkg"
}

# ---------------------------------------------------------------------------
# npm__resolve_version_uri
# ---------------------------------------------------------------------------

@test "npm__resolve_version_uri stable resolves latest dist-tag from full URI" {
  local _uri_file="${BATS_TEST_TMPDIR}/resolve-uri.txt"
  _npm__registry_get() {
    printf '%s\n' "$1" > "${_uri_file}"
    printf '{"dist-tags":{"latest":"9.9.9"},"versions":{"9.9.9":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version_uri "https://registry.example.com/acme-widget" "stable"
  assert_success
  assert_output "9.9.9"
  run cat "${_uri_file}"
  assert_output "https://registry.example.com/acme-widget"
}

@test "npm__resolve_version_uri fails when uri is empty" {
  run npm__resolve_version_uri ""
  assert_failure
  assert_output --partial "uri is required"
}

@test "npm__resolve_version_uri symbolic dist-tag resolves without path construction" {
  _npm__registry_get() {
    printf '{"dist-tags":{"latest":"1.0.0","canary":"1.1.0-rc.1"},"versions":{"1.1.0-rc.1":{},"1.0.0":{}}}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__resolve_version_uri "https://registry.npmjs.org/pkg" "canary"
  assert_success
  assert_output "1.1.0-rc.1"
}

@test "npm__fetch_package_json --registry strips trailing slash from URL" {
  local _url_file="${BATS_TEST_TMPDIR}/fetch-url.txt"
  _npm__registry_get() {
    printf '%s\n' "$1" > "${_url_file}"
    printf '{"name":"pkg"}\n'
    return 0
  }
  export -f _npm__registry_get
  run npm__fetch_package_json "@scope/pkg" --registry "https://example.com/"
  assert_success
  run cat "${_url_file}"
  assert_output "https://example.com/@scope/pkg"
}

# ---------------------------------------------------------------------------
# npm__install_package
# ---------------------------------------------------------------------------

@test "npm__install_package installs versioned package globally" {
  bootstrap__npm() { return 0; }
  export -f bootstrap__npm
  npm() {
    printf '%s\n' "$*"
    return 0
  }
  export -f npm
  run npm__install_package --package "typescript" --version "5.4.5"
  assert_success
  assert_output --partial "-g"
  assert_output --partial "install typescript@5.4.5"
}

@test "npm__install_package installs without version when omitted" {
  bootstrap__npm() { return 0; }
  export -f bootstrap__npm
  npm() {
    printf '%s\n' "$*"
    return 0
  }
  export -f npm
  run npm__install_package --package "typescript"
  assert_success
  assert_output --partial "install typescript"
  refute_output --partial "typescript@"
}

@test "npm__install_package passes --prefix to npm" {
  bootstrap__npm() { return 0; }
  export -f bootstrap__npm
  npm() {
    printf '%s\n' "$*"
    return 0
  }
  export -f npm
  run npm__install_package --package "typescript" --version "5.4.5" --prefix "/usr/local"
  assert_success
  assert_output --partial "--prefix /usr/local"
}

@test "npm__install_package fails when --package is missing" {
  run npm__install_package --version "5.4.5"
  assert_failure
  assert_output --partial "--package is required"
}

@test "npm__install_package fails when npm unavailable" {
  bootstrap__npm() { return 1; }
  export -f bootstrap__npm
  run npm__install_package --package "typescript" --version "5.4.5"
  assert_failure
  assert_output --partial "npm is required"
}

@test "npm__install_package rejects unknown option" {
  run npm__install_package --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# npm__uninstall_package
# ---------------------------------------------------------------------------

@test "npm__uninstall_package calls npm uninstall globally" {
  bootstrap__npm() { return 0; }
  export -f bootstrap__npm
  npm() {
    printf 'npm %s\n' "$*"
  }
  export -f npm
  run npm__uninstall_package --package "typescript"
  assert_success
  assert_output --partial "uninstall typescript"
}

@test "npm__uninstall_package passes --prefix to npm" {
  bootstrap__npm() { return 0; }
  export -f bootstrap__npm
  npm() {
    printf 'npm %s\n' "$*"
  }
  export -f npm
  run npm__uninstall_package --package "typescript" --prefix "/usr/local"
  assert_success
  assert_output --partial "--prefix /usr/local"
  assert_output --partial "uninstall typescript"
}

@test "npm__uninstall_package fails when --package is missing" {
  run npm__uninstall_package
  assert_failure
  assert_output --partial "--package is required"
}

@test "npm__uninstall_package rejects unknown option" {
  run npm__uninstall_package --bogus
  assert_failure
  assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# npm__is_managed
# ---------------------------------------------------------------------------

@test "npm__is_managed returns false for empty path" {
  run npm__is_managed ""
  assert_failure
}

@test "npm__is_managed returns false for nonexistent path" {
  run npm__is_managed "/no/such/binary"
  assert_failure
}

@test "npm__is_managed returns false when npm is not available" {
  local _bin="${BATS_TEST_TMPDIR}/mybin"
  touch "$_bin"
  npm() { return 1; }
  export -f npm
  run npm__is_managed "$_bin"
  assert_failure
}

@test "npm__is_managed returns true for binary in npm global bin dir" {
  export _NPM_TEST_PREFIX="${BATS_TEST_TMPDIR}/npm-prefix"
  mkdir -p "${_NPM_TEST_PREFIX}/bin" "${_NPM_TEST_PREFIX}/lib/node_modules"
  local _bin="${_NPM_TEST_PREFIX}/bin/mybin"
  touch "$_bin"

  npm() {
    case "$*" in
      "prefix -g") printf '%s\n' "${_NPM_TEST_PREFIX}" ;;
      "root -g") printf '%s\n' "${_NPM_TEST_PREFIX}/lib/node_modules" ;;
    esac
  }
  export -f npm
  run npm__is_managed "$_bin"
  assert_success
}

@test "npm__is_managed returns true for symlink resolving into node_modules" {
  export _NPM_TEST_PREFIX="${BATS_TEST_TMPDIR}/npm-prefix2"
  mkdir -p "${_NPM_TEST_PREFIX}/bin" "${_NPM_TEST_PREFIX}/lib/node_modules/myapp/bin"
  local _target="${_NPM_TEST_PREFIX}/lib/node_modules/myapp/bin/myapp"
  touch "$_target"
  local _bin="${BATS_TEST_TMPDIR}/myapp-link"
  ln -sf "$_target" "$_bin"

  npm() {
    case "$*" in
      "prefix -g") printf '%s\n' "${_NPM_TEST_PREFIX}" ;;
      "root -g") printf '%s\n' "${_NPM_TEST_PREFIX}/lib/node_modules" ;;
    esac
  }
  export -f npm
  run npm__is_managed "$_bin"
  assert_success
}

@test "npm__is_managed returns false for binary outside npm prefix" {
  export _NPM_TEST_PREFIX="${BATS_TEST_TMPDIR}/npm-prefix3"
  mkdir -p "${_NPM_TEST_PREFIX}/bin" "${_NPM_TEST_PREFIX}/lib/node_modules"
  local _bin="${BATS_TEST_TMPDIR}/unmanaged-bin"
  touch "$_bin"

  npm() {
    case "$*" in
      "prefix -g") printf '%s\n' "${_NPM_TEST_PREFIX}" ;;
      "root -g") printf '%s\n' "${_NPM_TEST_PREFIX}/lib/node_modules" ;;
    esac
  }
  export -f npm
  run npm__is_managed "$_bin"
  assert_failure
}

# ---------------------------------------------------------------------------
# npm__is_bundled
# ---------------------------------------------------------------------------

@test "npm__is_bundled returns false for empty path" {
  run npm__is_bundled ""
  assert_failure
}

@test "npm__is_bundled returns false for nonexistent path" {
  run npm__is_bundled "/no/such/binary"
  assert_failure
}

@test "npm__is_bundled returns true for wrapper with all layout markers present" {
  local _prefix="${BATS_TEST_TMPDIR}/bundled-prefix"
  mkdir -p "${_prefix}/bin" "${_prefix}/node/current/bin" "${_prefix}/pkg/current" "${_prefix}/.metadata"
  local _bin="${_prefix}/bin/mycli"
  printf '#!/bin/sh\nexec node "$@"\n' > "$_bin"
  chmod +x "$_bin"
  printf '5.4.5\n' > "${_prefix}/.metadata/installed-version"
  printf '#!/bin/sh\nprintf "v20.0.0\\n"\n' > "${_prefix}/node/current/bin/node"
  chmod +x "${_prefix}/node/current/bin/node"

  run npm__is_bundled "$_bin"
  assert_success
}

@test "npm__is_bundled returns false when node marker is missing" {
  local _prefix="${BATS_TEST_TMPDIR}/bundled-no-node"
  mkdir -p "${_prefix}/bin" "${_prefix}/pkg/current" "${_prefix}/.metadata"
  local _bin="${_prefix}/bin/mycli"
  touch "$_bin"
  printf '5.4.5\n' > "${_prefix}/.metadata/installed-version"

  run npm__is_bundled "$_bin"
  assert_failure
}

@test "npm__is_bundled returns false when pkg/current is missing" {
  local _prefix="${BATS_TEST_TMPDIR}/bundled-no-pkg"
  mkdir -p "${_prefix}/bin" "${_prefix}/node/current/bin" "${_prefix}/.metadata"
  local _bin="${_prefix}/bin/mycli"
  touch "$_bin"
  printf '#!/bin/sh\nprintf "v20.0.0\\n"\n' > "${_prefix}/node/current/bin/node"
  chmod +x "${_prefix}/node/current/bin/node"
  printf '5.4.5\n' > "${_prefix}/.metadata/installed-version"

  run npm__is_bundled "$_bin"
  assert_failure
}

@test "npm__is_bundled returns false when .metadata/installed-version is missing" {
  local _prefix="${BATS_TEST_TMPDIR}/bundled-no-meta"
  mkdir -p "${_prefix}/bin" "${_prefix}/node/current/bin" "${_prefix}/pkg/current"
  local _bin="${_prefix}/bin/mycli"
  touch "$_bin"
  printf '#!/bin/sh\nprintf "v20.0.0\\n"\n' > "${_prefix}/node/current/bin/node"
  chmod +x "${_prefix}/node/current/bin/node"

  run npm__is_bundled "$_bin"
  assert_failure
}

@test "npm__is_bundled returns true for a symlink pointing to a wrapper" {
  local _prefix="${BATS_TEST_TMPDIR}/bundled-symlink"
  mkdir -p "${_prefix}/bin" "${_prefix}/node/current/bin" "${_prefix}/pkg/current" "${_prefix}/.metadata"
  local _wrapper="${_prefix}/bin/mycli"
  printf '#!/bin/sh\nexec node "$@"\n' > "$_wrapper"
  chmod +x "$_wrapper"
  printf '5.4.5\n' > "${_prefix}/.metadata/installed-version"
  printf '#!/bin/sh\nprintf "v20.0.0\\n"\n' > "${_prefix}/node/current/bin/node"
  chmod +x "${_prefix}/node/current/bin/node"
  local _link="${BATS_TEST_TMPDIR}/mycli-link"
  ln -sf "$_wrapper" "$_link"

  run npm__is_bundled "$_link"
  assert_success
}

# ---------------------------------------------------------------------------
# npm__node_platform
# ---------------------------------------------------------------------------

@test "npm__node_platform returns linux-x64 for x86_64 linux" {
  os__release_kernel() { printf 'linux\n'; }
  os__release_arch() { printf 'x64\n'; }
  export -f os__release_kernel os__release_arch
  run npm__node_platform "x86_64"
  assert_success
  assert_output "linux-x64"
}

@test "npm__node_platform returns darwin-arm64 for aarch64 darwin" {
  os__release_kernel() { printf 'darwin\n'; }
  os__release_arch() { printf 'arm64\n'; }
  export -f os__release_kernel os__release_arch
  run npm__node_platform "aarch64"
  assert_success
  assert_output "darwin-arm64"
}

@test "npm__node_platform uses os__arch when no arg given" {
  os__arch() { printf 'x86_64\n'; }
  os__release_kernel() { printf 'linux\n'; }
  os__release_arch() { printf 'x64\n'; }
  export -f os__arch os__release_kernel os__release_arch
  run npm__node_platform
  assert_success
  assert_output "linux-x64"
}

@test "npm__node_platform fails when os__release_kernel fails" {
  os__release_kernel() { return 1; }
  export -f os__release_kernel
  run npm__node_platform "x86_64"
  assert_failure
}

@test "npm__node_platform fails when os__release_arch fails" {
  os__release_kernel() { printf 'linux\n'; }
  os__release_arch() { return 1; }
  export -f os__release_kernel os__release_arch
  run npm__node_platform "mips"
  assert_failure
  assert_output --partial "unsupported architecture"
}

# ---------------------------------------------------------------------------
# npm__resolve_node_version
# ---------------------------------------------------------------------------

@test "npm__resolve_node_version resolves lts using --index-file" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v22.1.0","lts":"Jod"},{"version":"v20.19.2","lts":"Iron"},{"version":"v23.0.0","lts":false}]\n' > "$_index_file"
  run npm__resolve_node_version lts --index-file "$_index_file"
  assert_success
  assert_output "v22.1.0"
}

@test "npm__resolve_node_version resolves lts/* using --index-file" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v22.1.0","lts":"Jod"},{"version":"v20.19.2","lts":"Iron"},{"version":"v23.0.0","lts":false}]\n' > "$_index_file"
  run npm__resolve_node_version "lts/*" --index-file "$_index_file"
  assert_success
  assert_output "v22.1.0"
}

@test "npm__resolve_node_version resolves latest using --index-file" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v23.0.0","lts":false},{"version":"v22.1.0","lts":"Jod"}]\n' > "$_index_file"
  run npm__resolve_node_version latest --index-file "$_index_file"
  assert_success
  assert_output "v23.0.0"
}

@test "npm__resolve_node_version resolves major 20 using --index-file" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v22.1.0","lts":"Jod"},{"version":"v20.19.2","lts":"Iron"},{"version":"v20.18.0","lts":"Iron"}]\n' > "$_index_file"
  run npm__resolve_node_version 20 --index-file "$_index_file"
  assert_success
  assert_output "v20.19.2"
}

@test "npm__resolve_node_version resolves exact vX.Y.Z using --index-file" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v20.19.2","lts":"Iron"},{"version":"v20.18.0","lts":"Iron"}]\n' > "$_index_file"
  run npm__resolve_node_version "v20.19.2" --index-file "$_index_file"
  assert_success
  assert_output "v20.19.2"
}

@test "npm__resolve_node_version resolves exact X.Y.Z (no v) using --index-file" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v20.19.2","lts":"Iron"}]\n' > "$_index_file"
  run npm__resolve_node_version "20.19.2" --index-file "$_index_file"
  assert_success
  assert_output "v20.19.2"
}

@test "npm__resolve_node_version fails on unknown spec" {
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v20.19.2","lts":"Iron"}]\n' > "$_index_file"
  run npm__resolve_node_version "iron" --index-file "$_index_file"
  assert_failure
  assert_output --partial "unsupported version spec"
}

@test "npm__resolve_node_version fails when spec is empty" {
  run npm__resolve_node_version "" --index-file "/dev/null"
  assert_failure
  assert_output --partial "version spec is required"
}

@test "npm__resolve_node_version rejects unknown option" {
  run npm__resolve_node_version lts --bogus value
  assert_failure
  assert_output --partial "unknown option"
}

@test "npm__resolve_node_version fetches from network when no --index-file" {
  net__fetch_url_stdout() {
    printf '[{"version":"v20.19.2","lts":"Iron"}]\n'
  }
  export -f net__fetch_url_stdout
  run npm__resolve_node_version lts
  assert_success
  assert_output "v20.19.2"
}

# ---------------------------------------------------------------------------
# npm__install_bundled
# ---------------------------------------------------------------------------

@test "npm__install_bundled fails when --package is missing" {
  run npm__install_bundled --version "1.0.0"
  assert_failure
  assert_output --partial "--package is required"
}

@test "npm__install_bundled rejects unknown option" {
  run npm__install_bundled --package "myapp" --bogus
  assert_failure
  assert_output --partial "unknown option"
}

@test "npm__install_bundled installs package with bundled node" {
  [[ "$(os__platform)" == "alpine" ]] && skip "pre-built Node.js not supported on Alpine (musl)"
  # Set up fake pkg tarball dir in a tmpdir
  local _index_file="${BATS_TEST_TMPDIR}/index.json"
  printf '[{"version":"v20.19.2","lts":"Iron"}]\n' > "$_index_file"

  # Stub version resolution
  npm__resolve_version() { printf '1.0.0\n'; }
  npm__resolve_node_version() { printf 'v20.19.2\n'; }
  npm__node_platform() { printf 'linux-x64\n'; }
  export -f npm__resolve_version npm__resolve_node_version npm__node_platform

  # Stub _npm__bundled__pkg_tarball_url
  _npm__bundled__pkg_tarball_url() { printf 'http://example.com/pkg.tgz\n'; }
  export -f _npm__bundled__pkg_tarball_url

  # Stub _npm__bundled__entry_point
  _npm__bundled__entry_point() { printf 'index.js\n'; }
  export -f _npm__bundled__entry_point

  local _prefix="${BATS_TEST_TMPDIR}/install-test"

  # Pre-create node binary + pkg/package dir so network downloads are skipped
  mkdir -p "${_prefix}/node/v20.19.2/bin"
  printf '#!/bin/sh\nprintf "v20.19.2\\n"\n' > "${_prefix}/node/v20.19.2/bin/node"
  chmod +x "${_prefix}/node/v20.19.2/bin/node"
  mkdir -p "${_prefix}/pkg/1.0.0/package"

  run npm__install_bundled \
    --package "myapp" \
    --version "1.0.0" \
    --cmd "myapp" \
    --prefix "$_prefix" \
    --node-version "lts"
  assert_success

  # Wrapper should exist and be executable
  [ -x "${_prefix}/bin/myapp" ]
  # Wrapper should resolve entry point at runtime (not baked at install time)
  grep -q 'PKG_JSON=' "${_prefix}/bin/myapp"
  grep -q 'process.argv' "${_prefix}/bin/myapp"
  ! grep -q "index.js" "${_prefix}/bin/myapp"
  # Metadata should be written
  [ -f "${_prefix}/.metadata/installed-version" ]
  assert_equal "$(cat "${_prefix}/.metadata/installed-version")" "1.0.0"
  assert_equal "$(cat "${_prefix}/.metadata/node-version")" "v20.19.2"
}

@test "npm__install_bundled --update fails when no existing installation" {
  run npm__install_bundled \
    --package "myapp" \
    --prefix "${BATS_TEST_TMPDIR}/no-such-dir" \
    --update
  assert_failure
  assert_output --partial "--update requires an existing installation"
}

@test "npm__install_bundled --update succeeds and updates metadata" {
  [[ "$(os__platform)" == "alpine" ]] && skip "pre-built Node.js not supported on Alpine (musl)"
  npm__resolve_version() { printf '2.0.0\n'; }
  npm__resolve_node_version() { printf 'v22.0.0\n'; }
  npm__node_platform() { printf 'linux-x64\n'; }
  _npm__bundled__pkg_tarball_url() { printf 'http://example.com/pkg.tgz\n'; }
  _npm__bundled__entry_point() { printf 'index.js\n'; }
  export -f npm__resolve_version npm__resolve_node_version npm__node_platform
  export -f _npm__bundled__pkg_tarball_url _npm__bundled__entry_point

  local _prefix="${BATS_TEST_TMPDIR}/update-test"

  # Simulate existing v1.0.0 / Node v20 installation
  mkdir -p "${_prefix}/.metadata"
  printf '1.0.0\n' > "${_prefix}/.metadata/installed-version"
  printf 'v20.19.2\n' > "${_prefix}/.metadata/node-version"
  mkdir -p "${_prefix}/node/v22.0.0/bin"
  printf '#!/bin/sh\nprintf "v22.0.0\\n"\n' > "${_prefix}/node/v22.0.0/bin/node"
  chmod +x "${_prefix}/node/v22.0.0/bin/node"
  mkdir -p "${_prefix}/pkg/2.0.0/package"

  run npm__install_bundled \
    --package "myapp" \
    --version "2.0.0" \
    --cmd "myapp" \
    --prefix "$_prefix" \
    --node-version "lts" \
    --update
  assert_success

  assert_equal "$(cat "${_prefix}/.metadata/installed-version")" "2.0.0"
  assert_equal "$(cat "${_prefix}/.metadata/node-version")" "v22.0.0"
}

@test "npm__install_bundled --update logs 'already at' when version unchanged" {
  [[ "$(os__platform)" == "alpine" ]] && skip "pre-built Node.js not supported on Alpine (musl)"
  npm__resolve_version() { printf '1.0.0\n'; }
  npm__resolve_node_version() { printf 'v20.19.2\n'; }
  npm__node_platform() { printf 'linux-x64\n'; }
  _npm__bundled__pkg_tarball_url() { printf 'http://example.com/pkg.tgz\n'; }
  _npm__bundled__entry_point() { printf 'index.js\n'; }
  export -f npm__resolve_version npm__resolve_node_version npm__node_platform
  export -f _npm__bundled__pkg_tarball_url _npm__bundled__entry_point

  local _prefix="${BATS_TEST_TMPDIR}/update-noop-test"

  mkdir -p "${_prefix}/.metadata"
  printf '1.0.0\n' > "${_prefix}/.metadata/installed-version"
  printf 'v20.19.2\n' > "${_prefix}/.metadata/node-version"
  mkdir -p "${_prefix}/node/v20.19.2/bin"
  printf '#!/bin/sh\nprintf "v20.19.2\\n"\n' > "${_prefix}/node/v20.19.2/bin/node"
  chmod +x "${_prefix}/node/v20.19.2/bin/node"
  mkdir -p "${_prefix}/pkg/1.0.0/package"

  run npm__install_bundled \
    --package "myapp" \
    --version "1.0.0" \
    --cmd "myapp" \
    --prefix "$_prefix" \
    --node-version "lts" \
    --update
  assert_success
  assert_output --partial "already at 1.0.0"
  assert_output --partial "already at v20.19.2"
}

@test "npm__install_bundled --update logs transition when version changes" {
  [[ "$(os__platform)" == "alpine" ]] && skip "pre-built Node.js not supported on Alpine (musl)"
  npm__resolve_version() { printf '2.0.0\n'; }
  npm__resolve_node_version() { printf 'v22.0.0\n'; }
  npm__node_platform() { printf 'linux-x64\n'; }
  _npm__bundled__pkg_tarball_url() { printf 'http://example.com/pkg.tgz\n'; }
  _npm__bundled__entry_point() { printf 'index.js\n'; }
  export -f npm__resolve_version npm__resolve_node_version npm__node_platform
  export -f _npm__bundled__pkg_tarball_url _npm__bundled__entry_point

  local _prefix="${BATS_TEST_TMPDIR}/update-change-test"

  mkdir -p "${_prefix}/.metadata"
  printf '1.0.0\n' > "${_prefix}/.metadata/installed-version"
  printf 'v20.19.2\n' > "${_prefix}/.metadata/node-version"
  mkdir -p "${_prefix}/node/v22.0.0/bin"
  printf '#!/bin/sh\nprintf "v22.0.0\\n"\n' > "${_prefix}/node/v22.0.0/bin/node"
  chmod +x "${_prefix}/node/v22.0.0/bin/node"
  mkdir -p "${_prefix}/pkg/2.0.0/package"

  run npm__install_bundled \
    --package "myapp" \
    --version "2.0.0" \
    --cmd "myapp" \
    --prefix "$_prefix" \
    --node-version "lts" \
    --update
  assert_success
  assert_output --partial "1.0.0"
  assert_output --partial "2.0.0"
  assert_output --partial "v20.19.2"
  assert_output --partial "v22.0.0"
}

@test "npm__install_bundled --update prunes old version directories" {
  [[ "$(os__platform)" == "alpine" ]] && skip "pre-built Node.js not supported on Alpine (musl)"
  npm__resolve_version() { printf '2.0.0\n'; }
  npm__resolve_node_version() { printf 'v22.0.0\n'; }
  npm__node_platform() { printf 'linux-x64\n'; }
  _npm__bundled__pkg_tarball_url() { printf 'http://example.com/pkg.tgz\n'; }
  _npm__bundled__entry_point() { printf 'index.js\n'; }
  export -f npm__resolve_version npm__resolve_node_version npm__node_platform
  export -f _npm__bundled__pkg_tarball_url _npm__bundled__entry_point

  local _prefix="${BATS_TEST_TMPDIR}/prune-test"

  # Simulate existing v1.0.0 / Node v20 installation
  mkdir -p "${_prefix}/.metadata"
  printf '1.0.0\n' > "${_prefix}/.metadata/installed-version"
  printf 'v20.19.2\n' > "${_prefix}/.metadata/node-version"
  # Old version dirs (to be pruned)
  mkdir -p "${_prefix}/node/v20.19.2/bin"
  mkdir -p "${_prefix}/pkg/1.0.0/package"
  # New version dirs (pre-created to skip download)
  mkdir -p "${_prefix}/node/v22.0.0/bin"
  printf '#!/bin/sh\nprintf "v22.0.0\\n"\n' > "${_prefix}/node/v22.0.0/bin/node"
  chmod +x "${_prefix}/node/v22.0.0/bin/node"
  mkdir -p "${_prefix}/pkg/2.0.0/package"

  run npm__install_bundled \
    --package "myapp" \
    --version "2.0.0" \
    --cmd "myapp" \
    --prefix "$_prefix" \
    --node-version "lts" \
    --update
  assert_success

  # Old version dirs should be removed
  [ ! -d "${_prefix}/pkg/1.0.0" ]
  [ ! -d "${_prefix}/node/v20.19.2" ]
  # New version dirs should remain
  [ -d "${_prefix}/pkg/2.0.0" ]
  [ -d "${_prefix}/node/v22.0.0" ]
}

# ---------------------------------------------------------------------------
# npm__uninstall_bundled
# ---------------------------------------------------------------------------

# Create a minimal bundled npm layout under <prefix>.
_npm_test__make_bundled_prefix() {
  local _prefix="$1"
  mkdir -p "${_prefix}/node/current/bin" "${_prefix}/pkg/current" "${_prefix}/.metadata"
  printf '#!/bin/sh\n' > "${_prefix}/node/current/bin/node"
  chmod +x "${_prefix}/node/current/bin/node"
  printf '1.0.0\n' > "${_prefix}/.metadata/installed-version"
}

@test "npm__uninstall_bundled removes prefix dir" {
  local _prefix="${BATS_TEST_TMPDIR}/bundled-uninstall-prefix"
  _npm_test__make_bundled_prefix "$_prefix"
  run npm__uninstall_bundled --prefix "$_prefix"
  assert_success
  [ ! -d "$_prefix" ]
}

@test "npm__uninstall_bundled is no-op when prefix absent" {
  run npm__uninstall_bundled --prefix "${BATS_TEST_TMPDIR}/no-such-dir"
  assert_success
}

@test "npm__uninstall_bundled derives prefix from --package" {
  local _cmd="myapp"
  local _prefix="${HOME}/.local/share/${_cmd}"
  _npm_test__make_bundled_prefix "$_prefix"
  run npm__uninstall_bundled --package "$_cmd"
  assert_success
  [ ! -d "$_prefix" ]
}

@test "npm__uninstall_bundled derives prefix from --cmd" {
  local _cmd="mycli"
  local _prefix="${HOME}/.local/share/${_cmd}"
  _npm_test__make_bundled_prefix "$_prefix"
  run npm__uninstall_bundled --cmd "$_cmd"
  assert_success
  [ ! -d "$_prefix" ]
}

@test "npm__uninstall_bundled from --bin derives prefix and removes" {
  local _prefix="${BATS_TEST_TMPDIR}/bin-derived-prefix"
  _npm_test__make_bundled_prefix "$_prefix"
  mkdir -p "${_prefix}/bin"
  printf '#!/bin/sh\n' > "${_prefix}/bin/myapp"
  chmod +x "${_prefix}/bin/myapp"
  run npm__uninstall_bundled --bin "${_prefix}/bin/myapp"
  assert_success
  [ ! -d "$_prefix" ]
}

@test "npm__uninstall_bundled with --bin fails when not a bundled install" {
  local _bin="${BATS_TEST_TMPDIR}/some-random-binary"
  printf '#!/bin/sh\n' > "$_bin"
  chmod +x "$_bin"
  run npm__uninstall_bundled --bin "$_bin"
  assert_failure
  assert_output --partial "is not a bundled npm installation"
}

@test "npm__uninstall_bundled refuses non-bundled prefix dir" {
  local _prefix="${BATS_TEST_TMPDIR}/not-a-bundled-prefix"
  mkdir -p "$_prefix"
  run npm__uninstall_bundled --prefix "$_prefix"
  assert_failure
  assert_output --partial "does not look like a bundled npm installation"
}

@test "npm__uninstall_bundled fails when neither --prefix nor --package given" {
  run npm__uninstall_bundled
  assert_failure
  assert_output --partial "--prefix, --bin, --package, or --cmd is required"
}

@test "npm__uninstall_bundled rejects unknown option" {
  run npm__uninstall_bundled --bogus
  assert_failure
  assert_output --partial "unknown option"
}
