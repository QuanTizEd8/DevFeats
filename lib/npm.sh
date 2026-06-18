# shellcheck shell=bash
# npm Registry API: fetch package metadata, resolve versions, and install npm packages.
#
# Fetches package metadata via the npm registry API, resolves version specs
# (including semver prefixes, dist-tags, "stable", and "latest"), and installs
# packages via the npm CLI.
# Respects `NPM_TOKEN` (falls back to `NODE_AUTH_TOKEN`) for all registry calls.

npm__fetch_package_json() {
  # @brief npm__fetch_package_json <package> [--version <ver>] [--registry <base>] [--dest <file>] — Fetch npm registry JSON for a package.
  #
  # Without `--version`: fetches the full package document from
  # `<registry>/<package>` (includes all versions and dist-tags).
  # With `--version`: fetches the version-specific document from
  # `<registry>/<package>/<version>`.
  # Respects `NPM_TOKEN` or `NODE_AUTH_TOKEN` (sets `Authorization: Bearer`
  # automatically).
  #
  # Args:
  #   <package>            npm package name (e.g. `typescript`, `@devcontainers/cli`).
  #   --version <ver>      Specific version to fetch (optional; fetches full doc by default).
  #   --registry <base>    Registry base URL (default: https://registry.npmjs.org).
  #   --dest <file>        Write JSON to this file instead of stdout (optional).
  #
  # Stdout: package JSON (suppressed when `--dest` is given).
  #
  # Returns: 0 on success, 1 on HTTP error or missing tool.
  local _package="$1"
  shift
  local _version="" _dest="" _registry=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --version)
        shift
        _version="$1"
        shift
        ;;
      --registry)
        shift
        _registry="$1"
        shift
        ;;
      --dest)
        shift
        _dest="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _base="${_registry:-https://registry.npmjs.org}"
  local _url
  if [ -n "$_version" ]; then
    _url="$(_npm__registry_url "$_base" "$_package" "$_version")"
  else
    _url="$(_npm__registry_url "$_base" "$_package")"
  fi

  logging__download "Fetching npm package JSON for '${_package}'${_version:+@${_version}} from '${_base}'."
  _npm__registry_get "$_url" "$_dest"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to fetch '${_package}'${_version:+@${_version}} from '${_url}'."
    return "$_rc"
  }
  return 0
}

npm__dist_tags() {
  # @brief npm__dist_tags <package> [--registry <base>] — Print dist-tags for an npm package, one per line.
  #
  # Fetches `<registry>/-/package/<package>/dist-tags` and prints each tag as
  # `name=version` (e.g. `latest=1.2.3`, `next=2.0.0-beta.1`).
  # Prefers jq; falls back to grep for environments without jq.
  #
  # Args:
  #   <package>          npm package name.
  #   --registry <base>  Registry base URL (default: https://registry.npmjs.org).
  #
  # Stdout: one `name=version` pair per line.
  #
  # Returns: 0 on success, 1 on network or parse error.
  local _package="$1"
  shift
  local _registry=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --registry)
        shift
        _registry="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done
  local _base="${_registry:-https://registry.npmjs.org}"
  local _json
  logging__download "Fetching dist-tags for npm package '${_package}' from '${_base}'."
  _json="$(_npm__registry_get "$(_npm__registry_url "$_base" "-/package" "$_package" "dist-tags")")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to fetch dist-tags for '${_package}'."
    return "$_rc"
  }
  [ -n "$_json" ] || {
    logging__error "empty dist-tags response for '${_package}'."
    return 1
  }

  local _out=""
  if bootstrap__jq 2> /dev/null; then
    _out="$(printf '%s\n' "$_json" |
      json__query -r 'to_entries[] | "\(.key)=\(.value)"' 2> /dev/null)" || _out=""
  fi
  if [ -z "$_out" ]; then
    # grep fallback: flat JSON object {"key":"value",...}
    _out="$(printf '%s\n' "$_json" |
      grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*"[^"]+"' |
      sed 's/^"//; s/"[[:space:]]*:[[:space:]]*"/=/; s/"$//')" || _out=""
  fi
  [ -n "$_out" ] || {
    logging__error "could not parse dist-tags for '${_package}'."
    return 1
  }
  printf '%s\n' "$_out"
}

npm__latest_version() {
  # @brief npm__latest_version <package> [--registry <base>] — Print the version pointed to by the `latest` dist-tag.
  #
  # Uses the lightweight dist-tags endpoint; does not fetch the full package document.
  #
  # Args:
  #   <package>          npm package name.
  #   --registry <base>  Registry base URL (default: https://registry.npmjs.org).
  #
  # Stdout: bare version string (e.g. `1.2.3`).
  #
  # Returns: 0 on success, 1 on network or parse error.
  local _package="$1"
  shift
  local _registry=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --registry)
        shift
        _registry="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done
  local -a _args=("$_package")
  [ -n "$_registry" ] && _args+=(--registry "$_registry")
  local _tags _ver
  _tags="$(npm__dist_tags "${_args[@]}")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "could not fetch dist-tags for '${_package}'."
    return "$_rc"
  }
  _ver="$(printf '%s\n' "$_tags" | grep '^latest=' | sed 's/^latest=//')"
  [ -n "$_ver" ] || {
    logging__error "no 'latest' dist-tag found for '${_package}'."
    return 1
  }
  printf '%s\n' "$_ver"
}

npm__versions() {
  # @brief npm__versions <package> [--all] [--registry <base>] — Print published versions newest-first.
  #
  # Fetches the full package document and extracts version strings from the
  # `versions` object. Requires jq.
  # Without `--all`: only stable (non-prerelease) versions are printed.
  # With `--all`: all published versions are included.
  #
  # Args:
  #   <package>          npm package name.
  #   --all              Include prerelease versions (default: stable only).
  #   --registry <base>  Registry base URL (default: https://registry.npmjs.org).
  #
  # Stdout: one version string per line, sorted newest-first.
  #
  # Returns: 0 on success, 1 on network, parse, or jq error.
  local _package="$1"
  shift
  local _all=false _registry=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all)
        _all=true
        shift
        ;;
      --registry)
        shift
        _registry="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  local _base="${_registry:-https://registry.npmjs.org}"
  local _json
  _json="$(_npm__registry_get "$(_npm__registry_url "$_base" "$_package")")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to fetch package metadata for '${_package}'."
    return "$_rc"
  }
  [ -n "$_json" ] || {
    logging__error "empty package metadata for '${_package}'."
    return 1
  }

  bootstrap__jq
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "jq is required to list versions."
    return "$_rc"
  }

  local _versions
  _versions="$(printf '%s\n' "$_json" | json__object_keys_stdin versions)" || {
    logging__error "could not extract versions for '${_package}'."
    return 1
  }
  [ -n "$_versions" ] || {
    logging__error "no versions found for '${_package}'."
    return 1
  }

  if [ "$_all" = "true" ]; then
    printf '%s\n' "$_versions" | sort -rV
  else
    local _v
    while IFS= read -r _v; do
      ver__semver_is_final "$_v" && printf '%s\n' "$_v"
    done < <(printf '%s\n' "$_versions" | sort -rV)
  fi
}

npm__resolve_version_uri() {
  # @brief npm__resolve_version_uri <uri> [<spec>] — Resolve a version spec using the full package document at <uri>.
  #
  # Fetches the full npm package document JSON from <uri> (any URI scheme
  # supported by net__fetch_url_stdout; typically the package root endpoint
  # https://registry.npmjs.org/<package> or an equivalent for a custom registry).
  # Applies all resolution logic without any path construction.
  #
  # Version specs:
  #   "stable" / ""  Stable version: the `stable` dist-tag if the package defines
  #                  one, otherwise falls back to the `latest` dist-tag (npm
  #                  convention for the stable release).
  #   "latest"       Most recently published version, including pre-releases.
  #   starts with a digit (e.g. "1", "1.2", "1.2.3", "1.2.3-rc1")
  #                  Newest stable published version whose version matches the
  #                  prefix followed by ".", "-", or end-of-string.
  #   anything else (e.g. "next", "beta", "canary")
  #                  Interpreted as a dist-tag name; resolved to its version.
  #
  # Args:
  #   <uri>    Full URI of the npm package document (required).
  #   [<spec>] Version spec string (default: "stable").
  #
  # Stdout: exact bare version string (e.g. `1.2.3`).
  #
  # Returns: 0 on success, 1 if no matching version found or on API error.
  local _uri="$1"
  local _spec="${2:-stable}"

  [ -n "$_uri" ] || {
    logging__error "uri is required."
    return 1
  }

  local _json
  _json="$(_npm__registry_get "$_uri")"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to fetch package document from '${_uri}'."
    return "$_rc"
  }
  [ -n "$_json" ] || {
    logging__error "empty response from '${_uri}'."
    return 1
  }

  local _version=""

  case "$_spec" in
    stable | "")
      # Prefer an explicit 'stable' dist-tag when the package defines one (e.g.
      # @anthropic-ai/claude-code); fall back to 'latest' (npm convention for the
      # stable release on packages that don't maintain a separate 'stable' tag).
      if bootstrap__jq 2> /dev/null; then
        _version="$(printf '%s\n' "$_json" | json__query -r '.["dist-tags"].stable // .["dist-tags"].latest // empty' 2> /dev/null)" || _version=""
        [ "$_version" = "null" ] && _version=""
      fi
      if [ -z "$_version" ]; then
        _version="$(printf '%s\n' "$_json" |
          grep -oE '"stable"[[:space:]]*:[[:space:]]*"[^"]+"' |
          head -1 | sed 's/^"stable"[^"]*"//; s/"$//')" || _version=""
      fi
      if [ -z "$_version" ]; then
        _version="$(printf '%s\n' "$_json" |
          grep -oE '"latest"[[:space:]]*:[[:space:]]*"[^"]+"' |
          head -1 | sed 's/^"latest"[^"]*"//; s/"$//')" || _version=""
      fi
      [ -n "$_version" ] || {
        logging__error "no 'stable' or 'latest' dist-tag found at '${_uri}'."
        return 1
      }
      ;;
    latest)
      # Most recently published, including pre-releases.
      bootstrap__jq
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "jq is required to resolve 'latest' spec."
        return "$_rc"
      }
      local _all_vers
      _all_vers="$(printf '%s\n' "$_json" | json__object_keys_stdin versions)" || _all_vers=""
      [ -n "$_all_vers" ] || {
        logging__error "no 'versions' field in package document at '${_uri}'."
        return 1
      }
      _version="$(printf '%s\n' "$_all_vers" | sort -rV | head -1)"
      ;;
    [0-9]*)
      # Numeric prefix: find newest stable published version matching the prefix.
      bootstrap__jq
      local _rc=$?
      [[ $_rc == 0 ]] || {
        logging__error "jq is required to resolve numeric spec '${_spec}'."
        return "$_rc"
      }
      local _norm
      _norm="$(ver__extract_version --keep-suffix "$_spec")"
      [ -n "$_norm" ] || {
        logging__error "spec '${_spec}' contains no numeric version content."
        return 1
      }
      local _stable_vers="" _v
      while IFS= read -r _v; do
        ver__semver_is_final "$_v" && _stable_vers+="${_stable_vers:+$'\n'}${_v}"
      done < <(printf '%s\n' "$_json" | json__object_keys_stdin versions | sort -rV)
      [ -n "$_stable_vers" ] || {
        logging__error "no stable versions found at '${_uri}'."
        return 1
      }
      _version="$(printf '%s\n' "$_stable_vers" | ver__first_matching_prefix "$_norm")" || _version=""
      [ -n "$_version" ] || {
        logging__error "no stable version matching '${_spec}' at '${_uri}'."
        return 1
      }
      ;;
    *)
      # Symbolic dist-tag name (e.g. "next", "beta", "canary").
      if bootstrap__jq 2> /dev/null; then
        # shellcheck disable=SC2016  # $t is a jq variable, not a shell variable
        _version="$(printf '%s\n' "$_json" | json__query -r --arg t "$_spec" '.["dist-tags"][$t] // empty' 2> /dev/null)" || _version=""
        [ "$_version" = "null" ] && _version=""
      fi
      if [ -z "$_version" ]; then
        _version="$(printf '%s\n' "$_json" |
          grep -oE "\"${_spec}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" |
          head -1 | sed 's/^"[^"]*"[^"]*"//; s/"$//')" || _version=""
      fi
      [ -n "$_version" ] || {
        logging__error "dist-tag '${_spec}' not found at '${_uri}'."
        return 1
      }
      ;;
  esac

  printf '%s\n' "$_version"
  return 0
}

npm__resolve_version() {
  # @brief npm__resolve_version <package> [<version-spec>] [--registry <base>] — Resolve a version spec to an exact published version.
  #
  # Thin wrapper around npm__resolve_version_uri. Constructs the full package
  # document URI from <package> and optional registry base, then delegates.
  #
  # Version specs: same as npm__resolve_version_uri.
  #
  # Args:
  #   <package>            npm package name.
  #   [<version-spec>]     Version spec string (default: "stable").
  #   --registry <base>    Registry base URL (default: https://registry.npmjs.org).
  #
  # Stdout: exact bare version string (e.g. `1.2.3`).
  #
  # Returns: 0 on success, 1 if no matching version found or on API error.
  local _package="$1"
  shift
  local _spec="stable" _spec_set=false _registry=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --registry)
        shift
        _registry="$1"
        shift
        ;;
      --*)
        logging__error "unknown option: '$1'"
        return 1
        ;;
      *)
        if [ "$_spec_set" = "false" ]; then
          _spec="$1"
          _spec_set=true
          shift
        else
          logging__error "unexpected positional argument: '$1'"
          return 1
        fi
        ;;
    esac
  done

  local _base="${_registry:-https://registry.npmjs.org}"
  npm__resolve_version_uri "$(_npm__registry_url "$_base" "$_package")" "$_spec"
}

npm__install_package() {
  # @brief npm__install_package OPTIONS — Ensure npm is available, then install a package globally.
  #
  # Installs an npm package globally (or under a given prefix). Ensures the npm
  # CLI is available before proceeding, installing Node.js + npm via the OS
  # package manager if necessary.
  #
  # Args:
  #   --package <name>   Package name to install (required).
  #   --version <ver>    Exact version to install (optional; omit for npm's default).
  #   --prefix <dir>     Pass `--prefix <dir>` to npm (optional).
  #
  # Returns: 0 on success, 1 on failure.
  local _package="" _version="" _prefix=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --package)
        shift
        _package="$1"
        shift
        ;;
      --version)
        shift
        _version="$1"
        shift
        ;;
      --prefix)
        shift
        _prefix="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  [ -n "$_package" ] || {
    logging__error "--package is required."
    return 1
  }

  logging__install "Ensuring npm is available for package install."
  bootstrap__npm
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "npm is required but could not be found or installed."
    return "$_rc"
  }

  local -a _args=(-g)
  [ -n "$_prefix" ] && _args+=(--prefix "$_prefix")
  local _pkg_spec="$_package"
  [ -n "$_version" ] && _pkg_spec="${_package}@${_version}"
  npm "${_args[@]}" install "$_pkg_spec"
}

npm__uninstall_package() {
  # @brief npm__uninstall_package OPTIONS — Uninstall a globally installed npm package.
  #
  # Ensures npm is available, then removes the named package from the global
  # (or prefixed) npm install tree.
  #
  # Args:
  #   --package <name>   Package name to uninstall (required).
  #   --prefix <dir>     Pass `--prefix <dir>` to npm (optional).
  #
  # Returns: 0 on success, 1 on failure.
  local _package="" _prefix=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --package)
        shift
        _package="$1"
        shift
        ;;
      --prefix)
        shift
        _prefix="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  [ -n "$_package" ] || {
    logging__error "--package is required."
    return 1
  }

  logging__install "Ensuring npm is available for package uninstall."
  bootstrap__npm
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "npm is required but could not be found or installed."
    return "$_rc"
  }

  local -a _args=(-g)
  [ -n "$_prefix" ] && _args+=(--prefix "$_prefix")
  npm "${_args[@]}" uninstall "$_package"
}

npm__is_managed() {
  # @brief npm__is_managed <bin_path> — Return 0 if <bin_path> is owned by npm's global package manager.
  #
  # Gets the global npm prefix (`npm prefix -g`) and the global modules root
  # (`npm root -g`), then checks whether <bin_path> or its resolved symlink target
  # resides under either npm's global `bin/` directory or its global
  # `node_modules/` tree.
  #
  # Note: this detects packages installed by `npm install -g` (or
  # `npm__install_package`). Packages installed by `npm__install_bundled` use a
  # separate prefix and are NOT reported as npm-managed by this function.
  #
  # Args:
  #   <bin_path>  Absolute path to the binary to check (may be empty).
  #
  # Returns: 0 if managed by npm global install, 1 otherwise (including empty or
  #          nonexistent paths, or when npm is not available).
  local _bin="${1-}"
  [[ -n "$_bin" && -e "$_bin" ]] || return 1
  command -v npm > /dev/null 2>&1 || return 1

  local _npm_prefix _npm_root
  _npm_prefix="$(npm prefix -g 2> /dev/null)" || {
    logging__error "failed to determine global npm prefix."
    return 1
  }
  _npm_root="$(npm root -g 2> /dev/null)" || {
    logging__error "failed to determine global npm root."
    return 1
  }
  [[ -n "$_npm_prefix" && -n "$_npm_root" ]] || {
    logging__error "global npm prefix or root is empty."
    return 1
  }

  # Canonicalize prefix/root so macOS /tmp → /private/tmp expansion is consistent
  # with the file__canonical_path-resolved _real path used in the comparison below.
  _npm_prefix="$(file__canonical_path "$_npm_prefix")"
  _npm_root="$(file__canonical_path "$_npm_root")"

  local _real
  _real="$(file__canonical_path "$_bin")"
  [[ "$_real" == /* ]] || _real="$(dirname "$_bin")/${_real}"

  # Binary lives in npm's global bin dir, or its target is inside the node_modules tree
  [[ "$_bin" == "${_npm_prefix}/bin/"* ]] ||
    [[ "$_real" == "${_npm_prefix}/bin/"* ]] ||
    [[ "$_real" == "${_npm_root}/"* ]]
}

npm__is_bundled() {
  # @brief npm__is_bundled <bin_path> — Return 0 if <bin_path> is a wrapper installed by npm__install_bundled.
  #
  # Resolves <bin_path> (following symlinks), then walks up one level to the
  # parent of the `bin/` directory. Checks for the three layout markers written
  # by `npm__install_bundled`:
  #   node/current/bin/node         — bundled Node.js runtime
  #   pkg/current/node_modules/     — npm-managed package tree
  #   .metadata/installed-version   — version record
  #
  # This does NOT detect packages installed by `npm install -g` or
  # `npm__install_package`; use `npm__is_managed` for those.
  #
  # Args:
  #   <bin_path>  Absolute path to the binary to check (may be empty).
  #
  # Returns: 0 if installed by npm__install_bundled, 1 otherwise (including empty
  #          or nonexistent paths).
  local _bin="${1-}"
  [[ -n "$_bin" && -e "$_bin" ]] || return 1

  local _real
  _real="$(file__canonical_path "$_bin")"
  [[ "$_real" == /* ]] || _real="$(dirname "$_bin")/${_real}"

  # The wrapper lives at <prefix>/bin/<cmd>; walk up two levels to get the prefix.
  local _prefix
  _prefix="$(cd "$(dirname "$_real")/.." 2> /dev/null && pwd)" || {
    logging__error "failed to resolve bundled npm install prefix for '${_bin}'."
    return 1
  }

  [[ -x "${_prefix}/node/current/bin/node" ]] &&
    [[ -d "${_prefix}/pkg/current/node_modules" ]] &&
    [[ -f "${_prefix}/.metadata/installed-version" ]]
}

npm__node_platform() {
  # @brief npm__node_platform [<arch>] — Print the nodejs.org platform string for the current (or given) architecture.
  #
  # Maps the kernel + architecture to the platform token used in nodejs.org
  # binary tarball filenames (e.g. `linux-x64`, `darwin-arm64`, `linux-armv7l`).
  #
  # Args:
  #   [<arch>]  Raw arch string (e.g. `x86_64`, `aarch64`). Defaults to `os__arch`.
  #
  # Stdout: platform string (e.g. `linux-x64`).
  #
  # Returns: 0 on success, 1 if the kernel or arch is unsupported.
  local _arch="${1:-$(os__arch)}"
  local _os _arch_token
  _os="$(os__release_kernel)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "unsupported kernel."
    return "$_rc"
  }
  _arch_token="$(os__release_arch "$_arch" --flavor node)"
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "unsupported architecture '${_arch}' for Node.js."
    return "$_rc"
  }
  printf '%s\n' "${_os}-${_arch_token}"
}

npm__resolve_node_version() {
  # @brief npm__resolve_node_version <spec> [--index-file <path>] — Resolve a Node.js version spec to an exact `vX.Y.Z`.
  #
  # Reads the nodejs.org dist index.json (fetched from the network or from a
  # pre-downloaded file given with `--index-file`) and resolves the spec using
  # `json__nodejs_index_version_stdin`. Supported specs:
  #   `lts` / `lts/*`      Latest stable LTS release.
  #   `latest` / `node`    Most recent release (may be non-LTS).
  #   `<major>`            Latest release for that major (e.g. `20`, `22`).
  #   `vX.Y.Z` / `X.Y.Z`  Exact version; validated against the index.
  #
  # Args:
  #   <spec>              Version spec string (required).
  #   --index-file <path> Use a pre-downloaded index.json file instead of fetching.
  #
  # Stdout: exact version string with leading `v` (e.g. `v20.19.2`).
  #
  # Returns: 0 on success, 1 on resolution failure or network error.
  local _spec="$1"
  shift
  local _index_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --index-file)
        shift
        _index_file="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  [ -n "$_spec" ] || {
    logging__error "version spec is required."
    return 1
  }

  local _index_json
  if [ -n "$_index_file" ]; then
    _index_json="$(cat "$_index_file")" || {
      logging__error "could not read index file '${_index_file}'."
      return 1
    }
  else
    _index_json="$(net__fetch_url_stdout "https://nodejs.org/dist/index.json")"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to fetch nodejs.org/dist/index.json."
      return "$_rc"
    }
  fi

  [ -n "$_index_json" ] || {
    logging__error "nodejs.org/dist/index.json was empty."
    return 1
  }

  # Normalise "lts" alias → "lts/*"
  [ "$_spec" = "lts" ] && _spec="lts/*"

  local _resolved=""
  case "$_spec" in
    "lts/*")
      _resolved="$(printf '%s\n' "$_index_json" | json__nodejs_index_version_stdin lts-first)" || _resolved=""
      ;;
    "latest" | "node")
      _resolved="$(printf '%s\n' "$_index_json" | json__nodejs_index_version_stdin head)" || _resolved=""
      ;;
    v[0-9]*"."*"."[0-9]*)
      # Exact semver with leading v — validate it exists in the index
      if printf '%s\n' "$_index_json" | json__nodejs_index_version_stdin exact "$_spec" > /dev/null 2>&1; then
        _resolved="$_spec"
      else
        logging__error "version '${_spec}' not found in nodejs.org/dist/index.json."
        return 1
      fi
      ;;
    [0-9]*"."*"."[0-9]*)
      # Exact semver without leading v — must come before [0-9]* (major) to avoid false match
      if printf '%s\n' "$_index_json" | json__nodejs_index_version_stdin exact "v${_spec}" > /dev/null 2>&1; then
        _resolved="v${_spec}"
      else
        logging__error "version '${_spec}' not found in nodejs.org/dist/index.json."
        return 1
      fi
      ;;
    [0-9]*)
      _resolved="$(printf '%s\n' "$_index_json" | json__nodejs_index_version_stdin major "$_spec")" || _resolved=""
      ;;
    *)
      logging__error "unsupported version spec '${_spec}'."
      logging__info "Supported: lts, lts/*, latest, node, a major number (e.g. 22), or an exact semver."
      return 1
      ;;
  esac

  [ -n "$_resolved" ] || {
    logging__error "could not resolve '${_spec}' from index.json."
    return 1
  }

  printf '%s\n' "$_resolved"
}

_npm__registry_url() {
  # _npm__registry_url <base> <segment> [<segment> ...]  (internal)
  #
  # Joins a registry base URL with path segments. Strips trailing slashes from
  # <base> and leading slashes from each segment so callers may pass
  # `https://example.com/` without producing `//` in the result.
  local _base="$1"
  shift
  while [[ "$_base" == */ ]]; do
    _base="${_base%/}"
  done
  local _url="$_base" _seg
  for _seg in "$@"; do
    _seg="${_seg#/}"
    _url="${_url}/${_seg}"
  done
  printf '%s\n' "$_url"
}

_npm__registry_get() {
  # _npm__registry_get <url> [<dest_file>]  (internal)
  #
  # Performs an npm registry GET with optional Authorization header from
  # NPM_TOKEN (falling back to NODE_AUTH_TOKEN). Suppresses xtrace around
  # the authenticated call to prevent token leaking in CI logs.
  # Passes output to stdout or to <dest_file> when provided.
  local _url="$1"
  local _dest="${2:-}"
  local _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null

  local _token="${NPM_TOKEN:-${NODE_AUTH_TOKEN:-}}"
  # Use set -- to accumulate --header args (POSIX alternative to arrays).
  set -- --header "Accept: application/json" --header "User-Agent: devfeats"
  [ -n "$_token" ] && set -- "$@" --header "Authorization: Bearer ${_token}"

  local _ec=0
  if [ -n "$_dest" ]; then
    net__fetch_url_file "$_url" "$_dest" "$@" || _ec=$?
  else
    net__fetch_url_stdout "$_url" "$@" || _ec=$?
  fi
  [ "$_xt" = "true" ] && { set -x; } 2> /dev/null
  return "$_ec"
}

npm__install_bundled() {
  # @brief npm__install_bundled OPTIONS — Install an npm package with a bundled Node.js runtime.
  #
  # Downloads a self-contained Node.js binary and then uses the bundled npm to
  # install the package (including optional platform-specific dependencies).
  # Creates a portable `bin/<cmd>` wrapper that invokes the bundled Node.js via
  # the `.bin/<cmd>` symlink written by npm.
  #
  # Layout under <prefix>:
  #   node/<node-version>/   Node.js binary tree (extracted tarball)
  #   node/current           Symlink → <node-version>
  #   pkg/<pkg-version>/     npm-managed package tree (node_modules/ + .bin/)
  #   pkg/current            Symlink → <pkg-version>
  #   bin/<cmd>              Shell wrapper: exec \$NODE_BIN pkg/current/node_modules/.bin/\$cmd "\$@"
  #   .metadata/installed-version
  #   .metadata/node-version
  #
  # Args:
  #   --package <name>         npm package name (required; scoped names like @scope/pkg are OK).
  #   --version <spec>         Package version spec (default: stable).
  #   --cmd <name>             Wrapper command name (default: basename of package after last /).
  #   --prefix <dir>           Installation prefix (default: \$HOME/.local/share/<cmd>).
  #   --node-version <spec>    Node.js version spec (default: lts); passed to npm__resolve_node_version.
  #   --update                 Update an existing installation. Requires an existing prefix; errors if
  #                            absent (run without --update for a fresh install). Resolves versions
  #                            fresh according to --version and --node-version specs (any spec accepted;
  #                            no restriction to 'latest'); skips component downloads when the resolved
  #                            version is already installed; always regenerates the wrapper. Prunes
  #                            the previous version directory (node/<old> and pkg/<old>) when the
  #                            version changes.
  #
  # Returns: 0 on success, 1 on failure.
  local _package="" _version="" _cmd="" _prefix="" _node_spec="lts" _update=false _registry=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --package)
        shift
        _package="$1"
        shift
        ;;
      --version)
        shift
        _version="$1"
        shift
        ;;
      --cmd)
        shift
        _cmd="$1"
        shift
        ;;
      --prefix)
        shift
        _prefix="$1"
        shift
        ;;
      --node-version)
        shift
        _node_spec="$1"
        shift
        ;;
      --registry)
        shift
        _registry="$1"
        shift
        ;;
      --update)
        _update=true
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  [ -n "$_package" ] || {
    logging__error "--package is required."
    return 1
  }

  # Default cmd = last path segment, stripping any leading @
  if [ -z "$_cmd" ]; then
    _cmd="${_package##*/}"
    _cmd="${_cmd##@}"
  fi

  # Default prefix
  [ -n "$_prefix" ] || _prefix="${HOME}/.local/share/${_cmd}"

  # Guard: --update requires an existing installation
  if [ "$_update" = "true" ]; then
    [ -f "${_prefix}/.metadata/installed-version" ] || {
      logging__error "--update requires an existing installation at '${_prefix}'. Run without --update for a fresh install."
      return 1
    }
  fi

  # Resolve package version
  if [ -z "$_version" ] || [ "$_version" = "stable" ] || [ "$_version" = "latest" ]; then
    logging__info "Resolving ${_package} version..."
    _version="$(npm__resolve_version "$_package" "${_version:-stable}" ${_registry:+--registry "$_registry"})"
  fi
  logging__info "${_package} package version: ${_version}"

  # Resolve Node.js version
  logging__info "Resolving Node.js (${_node_spec}) version..."
  local _node_version
  _node_version="$(npm__resolve_node_version "$_node_spec")"
  logging__info "Node.js version: ${_node_version}"

  # In update mode, report what is changing relative to the current installation
  if [ "$_update" = "true" ]; then
    local _current_version="" _current_node=""
    _current_version="$(cat "${_prefix}/.metadata/installed-version" 2> /dev/null || printf '')"
    _current_node="$(cat "${_prefix}/.metadata/node-version" 2> /dev/null || printf '')"
    if [ "$_version" = "$_current_version" ]; then
      logging__info "${_package}: already at ${_version}; download will be skipped."
    else
      logging__info "${_package}: ${_current_version:-unknown} → ${_version}."
    fi
    if [ "$_node_version" = "$_current_node" ]; then
      logging__info "Node.js: already at ${_node_version}; download will be skipped."
    else
      logging__info "Node.js: ${_current_node:-unknown} → ${_node_version}."
    fi
  fi

  # Resolve platform
  local _platform
  logging__info "Resolving Node.js binary platform triple."
  _platform="$(npm__node_platform)"

  # Node.js binaries from nodejs.org are glibc-linked; they will not run on Alpine (musl)
  if [ "$(os__platform)" = "alpine" ]; then
    logging__error "pre-built Node.js binaries are not supported on Alpine Linux (glibc-only)."
    logging__info "On Alpine, install Node.js via the OS package manager and use npm__install_package instead."
    return 1
  fi

  local _node_dir="${_prefix}/node"
  local _node_version_dir="${_node_dir}/${_node_version}"
  local _pkg_dir="${_prefix}/pkg"
  local _pkg_version_dir="${_pkg_dir}/${_version}"
  local _bin_dir="${_prefix}/bin"
  local _meta_dir="${_prefix}/.metadata"

  # Download + extract Node.js tarball if not already present
  if [ ! -x "${_node_version_dir}/bin/node" ]; then
    logging__info "Downloading Node.js ${_node_version} (${_platform})..."
    local _node_tarball="node-${_node_version}-${_platform}.tar.xz"
    local _node_url="https://nodejs.org/dist/${_node_version}/${_node_tarball}"
    local _node_tmp
    _node_tmp="$(file__mktmpdir "npm-bundled-node")"
    net__fetch_url_file "$_node_url" "${_node_tmp}/${_node_tarball}"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to download Node.js from '${_node_url}'."
      return "$_rc"
    }
    logging__info "Extracting Node.js ${_node_version}..."
    file__mkdir "${_node_version_dir}"
    file__extract_archive "${_node_tmp}/${_node_tarball}" "${_node_version_dir}" --strip 1
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "failed to extract Node.js tarball."
      return "$_rc"
    }
  else
    logging__info "Node.js ${_node_version} already present; skipping download."
  fi

  # Update current symlink for Node.js
  file__ln -sfn "${_node_version}" "${_node_dir}/current"

  # Verify the bundled Node.js binary executes correctly before using it
  local _node_bin="${_node_dir}/current/bin/node"
  "${_node_bin}" --version > /dev/null 2>&1 || {
    logging__error "installed Node.js binary '${_node_bin}' does not execute. The tarball may be corrupt or incompatible with this system."
    return 1
  }

  # Install package via bundled npm (automatically resolves optional platform deps)
  local _npm_cli="${_node_dir}/current/lib/node_modules/npm/bin/npm-cli.js"
  if [ ! -d "${_pkg_version_dir}/node_modules" ]; then
    logging__info "Installing ${_package}@${_version} via bundled npm..."
    file__mkdir "${_pkg_version_dir}"
    local -a _npm_args=(
      --prefix "${_pkg_version_dir}"
      --no-save
      --no-audit
      --no-fund
      --no-package-lock
      --loglevel=warn
    )
    [ -n "${_registry:-}" ] && _npm_args+=(--registry "$_registry")
    # Prepend node's bin/ to PATH for lifecycle scripts; --scripts-prepend-node-path was removed in npm v10.
    PATH="${_node_dir}/current/bin:${PATH}" "${_node_bin}" "$_npm_cli" install \
      "${_npm_args[@]}" \
      "${_package}@${_version}"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "npm install failed for '${_package}@${_version}'."
      file__rm -rf "${_pkg_version_dir}"
      return "$_rc"
    }
  else
    logging__info "${_package}@${_version} already installed; skipping."
  fi

  # Update current symlink for package
  file__ln -sfn "${_version}" "${_pkg_dir}/current"

  # Validate .bin/<cmd> symlink written by npm install
  local _bin_entry="${_pkg_version_dir}/node_modules/.bin/${_cmd}"
  [ -e "${_bin_entry}" ] || {
    logging__error "npm installed '${_package}@${_version}' but '.bin/${_cmd}' not found; check the package's 'bin' field."
    return 1
  }

  # Write shell wrapper
  file__mkdir "$_bin_dir"
  local _wrapper="${_bin_dir}/${_cmd}"
  file__tee "$_wrapper" << 'WRAPPER_EOF'
#!/bin/sh
# Generated by npm__install_bundled (devfeats) — do not edit by hand
SCRIPT_PATH="$0"
[ -L "$SCRIPT_PATH" ] && SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || readlink "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"
INSTALL_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
CMD="$(basename "$SCRIPT_PATH")"
NODE_BIN_DIR="$INSTALL_DIR/node/current/bin"
BIN_ENTRY="$INSTALL_DIR/pkg/current/node_modules/.bin/$CMD"
[ -d "$NODE_BIN_DIR" ] || { printf 'error: Node.js not found at %s\n' "$NODE_BIN_DIR" >&2; exit 1; }
[ -e "$BIN_ENTRY" ] || { printf 'error: package entry not found at %s\n' "$BIN_ENTRY" >&2; exit 1; }
export PATH="$NODE_BIN_DIR:$PATH"
exec "$BIN_ENTRY" "$@"
WRAPPER_EOF
  file__chmod +x "$_wrapper"

  # Write metadata
  file__mkdir "$_meta_dir"
  printf '%s\n' "$_version" | file__tee "${_meta_dir}/installed-version"
  printf '%s\n' "$_node_version" | file__tee "${_meta_dir}/node-version"

  # Prune stale version directories superseded by this update
  if [ "$_update" = "true" ]; then
    if [ -n "${_current_version:-}" ] && [ "$_current_version" != "$_version" ]; then
      local _old_pkg_dir="${_pkg_dir}/${_current_version}"
      [ -d "$_old_pkg_dir" ] && {
        file__rm -rf "$_old_pkg_dir"
        logging__info "Pruned old ${_package} version: ${_current_version}."
      }
    fi
    if [ -n "${_current_node:-}" ] && [ "$_current_node" != "$_node_version" ]; then
      local _old_node_dir="${_node_dir}/${_current_node}"
      [ -d "$_old_node_dir" ] && {
        file__rm -rf "$_old_node_dir"
        logging__info "Pruned old Node.js version: ${_current_node}."
      }
    fi
  fi

  logging__success "${_cmd} installed at '${_wrapper}'."
  logging__info "Add '${_bin_dir}' to PATH to use '${_cmd}'."
}

npm__uninstall_bundled() {
  # @brief npm__uninstall_bundled OPTIONS — Remove a bundled npm package installation.
  #
  # Removes the entire prefix directory created by `npm__install_bundled`.
  # Succeeds silently (no-op) when the prefix does not exist. Errors if the
  # resolved prefix does not carry the expected bundled layout markers
  # (node/current/bin/node, pkg/current/node_modules/, .metadata/installed-version)
  # to prevent accidental removal of unrelated directories.
  #
  # Args:
  #   --bin <path>       Path to the installed wrapper binary. The prefix is
  #                      derived automatically via `npm__is_bundled` (use instead
  #                      of --prefix when you have the binary path).
  #   --package <name>   npm package name; used to derive the default prefix when
  #                      neither --bin nor --prefix is given (optional).
  #   --cmd <name>       Wrapper command name; overrides the default derived from
  #                      `--package` when computing the prefix (optional).
  #   --prefix <dir>     Installation prefix to remove. If omitted, derived from
  #                      `--cmd` or `--package` as `${HOME}/.local/share/<cmd>`.
  #
  # Returns: 0 on success, 1 on error.
  local _package="" _cmd="" _prefix="" _bin=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bin)
        shift
        _bin="$1"
        shift
        ;;
      --package)
        shift
        _package="$1"
        shift
        ;;
      --cmd)
        shift
        _cmd="$1"
        shift
        ;;
      --prefix)
        shift
        _prefix="$1"
        shift
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done

  # Derive prefix from --bin (also validates the layout via npm__is_bundled)
  if [ -n "$_bin" ]; then
    npm__is_bundled "$_bin"
    local _rc=$?
    [[ $_rc == 0 ]] || {
      logging__error "'${_bin}' is not a bundled npm installation."
      return "$_rc"
    }
    local _real
    _real="$(file__canonical_path "$_bin")"
    case "$_real" in
      /*) : ;;
      *) _real="$(dirname "$_bin")/${_real}" ;;
    esac
    _prefix="$(cd "$(dirname "$_real")/.." && pwd)" || {
      logging__error "could not resolve prefix from '${_bin}'."
      return 1
    }
  fi

  # Derive cmd and prefix (mirrors npm__install_bundled defaults)
  if [ -z "$_cmd" ] && [ -n "$_package" ]; then
    _cmd="${_package##*/}"
    _cmd="${_cmd##@}"
  fi
  if [ -z "$_prefix" ]; then
    [ -n "$_cmd" ] || {
      logging__error "--prefix, --bin, --package, or --cmd is required."
      return 1
    }
    _prefix="${HOME}/.local/share/${_cmd}"
  fi

  if [ -d "$_prefix" ]; then
    # Guard against removing an unrelated directory
    if [ ! -x "${_prefix}/node/current/bin/node" ] ||
      [ ! -d "${_prefix}/pkg/current/node_modules" ] ||
      [ ! -f "${_prefix}/.metadata/installed-version" ]; then
      logging__error "'${_prefix}' does not look like a bundled npm installation; refusing to remove."
      return 1
    fi
    file__rm -rf "$_prefix"
    logging__success "removed '${_prefix}'."
  else
    logging__info "nothing to uninstall at '${_prefix}'."
  fi
}
