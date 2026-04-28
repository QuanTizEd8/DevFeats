#!/usr/bin/env bash
# shellcheck disable=SC2016
# (jq filter bodies use $foo for jq-side bindings; shellcheck flags single-quoted jq.)
# install.bash — Full bash >=4 implementation of the sysset installer.
#
# Invoked by install.sh after bash >=4 is confirmed. Downloads lib/*.sh from the
# repo, then operates in one of two modes:
#
#   Feature mode:   install a single feature (optionally version-pinned via :)
#   Manifest mode:  install multiple features from a devcontainer.json[.jsonc] manifest
#
# Version resolution modes (per-feature releases are independent; the bundle
# tag `v<X.Y.Z>` is an accumulator over per-feature versions):
#
#   Rolling (default):       each feature resolves to the latest
#                            `<feature>/<X.Y.Z>` release tag independently.
#   Bundle-pinned:           `SYSSET_VERSION` (env) or `.version` (manifest)
#                            resolves to a bundle tag (`v<X.Y.Z>`); each
#                            feature's version is read from that bundle's
#                            embedded ``manifest.json`` (offline kit) or the
#                            kit tarball on the release. Per-feature overrides
#                            (`feature:version` or features[].version) still win.
#
# Usage:
#   install.bash <feature>[:<feature-version>] [feature-opts...]
#   install.bash <devcontainer.json|.jsonc>
#
# Options (consumed by install.bash; not forwarded to feature installers in manifest mode):
#   --log_file <path>  Append captured output to this file on exit.
#   --log_level <level>  Log verbosity: silent|error|warn|info|debug|trace.
#   --help, -h        Show this help.
#   --workspace-folder <path>  Default cwd for init/lifecycle (manifest); feature mode default CWD.
#   --no-initialize-command    Skip devcontainer "initializeCommand" (manifest only).
#   --initialize-command-dir <path>  CWD for initializeCommand.
#   --lifecycle-command-dir <path>  CWD for all lifecycle commands.
#   --no-feature-lifecycle-command <path>  Repeat. Disable feature lifecycle (grammar: all, feature, phase, ...).
#   --no-container-lifecycle-command <path>  Repeat. Disable devcontainer.json lifecycle entries.
#   --compatible-prefix <oci-prefix>  Repeat. Default: ghcr.io/quantized8/sysset/
#   --no-lifecycle   Feature mode: skip the installed feature's lifecycle hooks.
#   --local-registry <path>  Registry root (manifest.json + features/). Default: directory of this install.bash, or SYSSET_LOCAL_REGISTRY.
#   --download-only   Fetch into the local registry and update manifest.json; do not run installers (see plan).
#   --report-file <path>  With --download-only: JSON summary of partial failures.
#
# Environment overrides:
#   SYSSET_BASE_URL   GitHub Releases base URL  (default: github.com releases)
#   SYSSET_RAW_BASE   Raw GitHub base URL       (default: main branch)
#   SYSSET_FETCH_TOOL curl|wget                 (set by install.sh; auto-detected here if unset)
#   SYSSET_GHCR_NAMESPACE  GHCR namespace path for oci__ refs (default: quantized8/sysset)
#   SYSSET_LOCAL_REGISTRY  Optional directory override for the local registry root.
#   SYSSET_VERSION    Pin the bundle version; feature versions are read from
#                     that bundle's manifest.json. Accepts any spec understood
#                     by github__resolve_version ("", "latest", "1", "1.2",
#                     "v1.2.3", "1.2.3"). Per-feature overrides still win.
set -euo pipefail

SYSSET_REPO="quantized8/sysset"
SYSSET_RELEASE_BASE="${SYSSET_BASE_URL:-https://github.com/${SYSSET_REPO}/releases/download}"
SYSSET_RAW_BASE="${SYSSET_RAW_BASE:-https://raw.githubusercontent.com/${SYSSET_REPO}/main}"
SYSSET_GHCR_NAMESPACE="${SYSSET_GHCR_NAMESPACE:-quantized8/sysset}"

# ── Lib bootstrap ─────────────────────────────────────────────────────────────
# Download lib/*.sh before anything else. SYSSET_FETCH_TOOL is set by install.sh;
# fall back to curl detection here in case install.bash is invoked directly.

if [[ -z "${SYSSET_FETCH_TOOL:-}" ]]; then
  if command -v curl > /dev/null 2>&1; then
    SYSSET_FETCH_TOOL="curl"
  elif command -v wget > /dev/null 2>&1; then
    SYSSET_FETCH_TOOL="wget"
  else
    echo "⛔ Neither curl nor wget found. Install one and retry." >&2
    exit 1
  fi
fi

_lib_tmpdir="$(mktemp -d)"
_lib_dir="${_lib_tmpdir}/_lib"
mkdir "$_lib_dir"

# Tiny fetch helper used only for the initial lib download (net.sh not yet sourced).
_bootstrap_fetch() {
  # $1=url $2=dest
  if [[ "${SYSSET_FETCH_TOOL}" == "wget" ]]; then
    wget -qO "$2" --tries=3 --waitretry=5 "$1"
  else
    curl -fsSL --retry 3 --retry-delay 5 "$1" -o "$2"
  fi
}

echo "ℹ️  Downloading sysset lib files..." >&2
for _f in net.sh os.sh str.sh json.sh github.sh ospkg.sh logging.sh checksum.sh oci.sh lock.sh graph.sh proc.sh devcontainer.sh jsonc.py users.sh; do
  _bootstrap_fetch "${SYSSET_RAW_BASE}/lib/${_f}" "${_lib_dir}/${_f}"
done
unset -f _bootstrap_fetch

# _SYSSET_LIB_DIR is read by github.sh when it loads json.sh.
_SYSSET_LIB_DIR="$_lib_dir"

# shellcheck source=lib/ospkg.sh
. "${_lib_dir}/ospkg.sh" # also sources os.sh and net.sh
# shellcheck source=lib/logging.sh
. "${_lib_dir}/logging.sh"
# shellcheck source=lib/github.sh
. "${_lib_dir}/github.sh"
# shellcheck source=lib/checksum.sh
. "${_lib_dir}/checksum.sh"
# shellcheck source=lib/oci.sh
. "${_lib_dir}/oci.sh"
# shellcheck source=lib/lock.sh
. "${_lib_dir}/lock.sh"
# shellcheck source=lib/str.sh
. "${_lib_dir}/str.sh"
# shellcheck source=lib/graph.sh
. "${_lib_dir}/graph.sh"
# shellcheck source=lib/proc.sh
. "${_lib_dir}/proc.sh"
# shellcheck source=lib/devcontainer.sh
. "${_lib_dir}/devcontainer.sh"
# shellcheck source=lib/users.sh
. "${_lib_dir}/users.sh"

logging__setup
trap 'rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

logging__entry "sysset installer"

# ── Canonical install order ───────────────────────────────────────────────────
_CANONICAL_ORDER=(
  setup-user
  install-homebrew
  install-os-pkg
  install-git
  install-gh
  install-shell
  install-miniforge
  install-conda-env
  install-pixi
  install-node
  install-podman
  install-fonts
  setup-shim
)

# ── Usage ─────────────────────────────────────────────────────────────────────
__usage__() {
  cat >&2 << 'EOF'
Usage:
  Feature mode:   install.sh <feature>[:<feature-version>] [feature-opts...]
  Devcontainer:    install.sh <devcontainer.json[.jsonc]>

Options (see also header comment in install.bash):
  --log_file, --log_level, --help
  --workspace-folder, --no-initialize-command, --initialize-command-dir, --lifecycle-command-dir
  --no-feature-lifecycle-command, --no-container-lifecycle-command, --compatible-prefix
  --no-lifecycle (feature mode: skip that feature's post-install hooks)
  --local-registry <path>   Registry root: manifest.json + features/ (overrides SYSSET_LOCAL_REGISTRY)
  --download-only           Stage tarballs and update registry only; do not run installers
  --report-file <path>      With --download-only: write JSON ok/failures (manifest mode)

Version priority: per OCI :tag  >  SYSSET_VERSION  >  name vX.Y.Z suffix  >  latest
  (Use ``feature:version`` — ``@`` is not supported.)
EOF
  exit "${1:-0}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-}"
LOG_LEVEL="${LOG_LEVEL:-info}"
_mode_arg=""
_WORKSPACE_CUSTOM=""
_NO_INIT_CMD=false
_INIT_CMD_DIR=""
_LIFE_CMD_DIR=""
_NO_FE_LIFE=()
_NO_CO_LIFE=()
_COMPAT_PREFIX=("ghcr.io/quantized8/sysset/")
_FEATURE_SKIP_LIFECYCLE=false
_DOWNLOAD_ONLY=false
_REPORT_FILE=""
_SYSSET_REGISTRY_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log_file)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--log_file requires a value."
        exit 1
      }
      LOG_FILE="$1"
      shift
      ;;
    --log_level)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--log_level requires a value."
        exit 1
      }
      LOG_LEVEL="$1"
      shift
      ;;
    --help | -h) __usage__ ;;
    --workspace-folder)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--workspace-folder needs a value."
        exit 1
      }
      _WORKSPACE_CUSTOM="$1"
      shift
      ;;
    --no-initialize-command)
      _NO_INIT_CMD=true
      shift
      ;;
    --initialize-command-dir)
      shift
      _INIT_CMD_DIR="${1-}"
      shift
      ;;
    --lifecycle-command-dir)
      shift
      _LIFE_CMD_DIR="${1-}"
      shift
      ;;
    --no-feature-lifecycle-command)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--no-feature-lifecycle-command needs a value."
        exit 1
      }
      _NO_FE_LIFE+=("$1")
      shift
      ;;
    --no-container-lifecycle-command)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--no-container-lifecycle-command needs a value."
        exit 1
      }
      _NO_CO_LIFE+=("$1")
      shift
      ;;
    --compatible-prefix)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--compatible-prefix needs a value."
        exit 1
      }
      _COMPAT_PREFIX+=("$1")
      shift
      ;;
    --no-lifecycle)
      _FEATURE_SKIP_LIFECYCLE=true
      shift
      ;;
    --local-registry)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--local-registry needs a path."
        exit 1
      }
      _SYSSET_REGISTRY_ROOT="$(cd "$1" && pwd -P)"
      shift
      ;;
    --download-only)
      _DOWNLOAD_ONLY=true
      shift
      ;;
    --report-file)
      shift
      [[ $# -eq 0 ]] && {
        logging__error "--report-file needs a path."
        exit 1
      }
      _REPORT_FILE="$1"
      shift
      ;;
    --*)
      logging__error "Unknown option: '${1}'"
      exit 1
      ;;
    *)
      _mode_arg="$1"
      shift
      break
      ;;
  esac
done

if [[ -z "$_SYSSET_REGISTRY_ROOT" ]]; then
  if [[ -n "${SYSSET_LOCAL_REGISTRY:-}" ]]; then
    _SYSSET_REGISTRY_ROOT="$(cd "${SYSSET_LOCAL_REGISTRY}" && pwd -P)"
  else
    _SYSSET_REGISTRY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  fi
fi

logging__set_level

if [[ "$_DOWNLOAD_ONLY" == true ]]; then
  _json__ensure_jq || {
    logging__error "--download-only requires jq (json.sh could not install it)."
    exit 1
  }
fi

if [[ -z "$_mode_arg" ]]; then
  logging__error "No feature or manifest specified."
  __usage__ 1
fi

# ── Mode detection ────────────────────────────────────────────────────────────
_mode=""
case "$_mode_arg" in
  *.json | *.jsonc) _mode="manifest" ;;
  *) _mode="feature" ;;
esac

# ── Per-feature version resolution ──────────────────────────────────────────
# Resolves a feature-scoped version to its exact `<feature>/<X.Y.Z>` release
# tag. Supports partial/empty specs via github__resolve_version with
# --prefix '<feature>/' and --all (release tags fan out across all features,
# so per_page=100 is not enough).
_resolve_feature_tag() {
  # $1 = feature id, $2 = version spec (may be empty → latest)
  local _feature="$1" _spec="${2:-}"
  github__resolve_version "${SYSSET_REPO}" "$_spec" \
    --prefix "${_feature}/" --all
}

# ── Offline kit / local registry (installer-only) ─────────────────────────────
_sysset_bundle_kit_tarball_name() {
  local _tag="${1-}"
  [[ "$_tag" == v* ]] || _tag="v${_tag}"
  printf 'sysset-%s.tar.gz\n' "$_tag"
}

_sysset_default_oci_ref() {
  oci__ghcr_image_ref "${SYSSET_GHCR_NAMESPACE}" "${1,,}" "${2-}"
}

_sysset_verify_digest_checksums() {
  local _root="${1%/}" _dkey="${2-}" _mf="${3-}" _rp _ent _path _sum _expect
  _json__ensure_jq || return 1
  _rp="$(json__query -r --arg d "$_dkey" '.digests[$d].relativePath // empty' "$_mf" 2> /dev/null)" || _rp=""
  [[ -n "$_rp" && "$_rp" != "null" ]] || return 1
  while IFS=$'\t' read -r _ent _expect; do
    [[ -z "$_ent" || "$_ent" == "null" ]] && continue
    _path="${_root}/${_rp%/}/${_ent}"
    [[ -f "$_path" ]] || {
      logging__error "local registry: missing payload file ${_path}"
      return 1
    }
    _sum="$(checksum__sha256_file "$_path")" || return 1
    if [[ "${_sum}" != "${_expect}" ]]; then
      logging__error "local registry: checksum mismatch for ${_ent}"
      return 1
    fi
  done < <(json__query -r --arg d "$_dkey" '.digests[$d].checksums // {} | to_entries[] | "\(.key)\t\(.value)"' "$_mf" 2> /dev/null)
  return 0
}

_sysset_pack_digest_payload_to_tarball() {
  local _root="${1%/}" _dkey="${2-}" _mf="${3-}" _dest="${4-}" _rp _d
  _json__ensure_jq || return 1
  _rp="$(json__query -r --arg d "$_dkey" '.digests[$d].relativePath // empty' "$_mf" 2> /dev/null)" || _rp=""
  [[ -n "$_rp" && "$_rp" != "null" ]] || return 1
  _d="${_root}/${_rp}"
  [[ -d "$_d" ]] || return 1
  tar -czf "$_dest" -C "$_d" .
  return 0
}

# shellcheck disable=SC2329 # called from _sysset_manifest_registry_append_unlocked (dynamic analysis misses eval chain)
_sysset_checksums_json_for_payload_dir() {
  local _d="${1-}" _j="{}"
  local _f _h
  _json__ensure_jq || return 1
  for _f in install.sh install.bash devcontainer-feature.json; do
    [[ -f "${_d}/${_f}" ]] || continue
    _h="$(checksum__sha256_file "${_d}/${_f}")" || return 1
    _j="$(json__query -n --argjson cur "$_j" --arg k "$_f" --arg v "$_h" '$cur + {($k): $v}')"
  done
  printf '%s\n' "$_j"
}

_sysset_manifest_registry_append() {
  local _root="${1%/}" _feat="$2" _ver="$3" _tb="$4"
  local _mf="${_root}/manifest.json"
  [[ -f "$_mf" ]] || return 1
  [[ -f "$_tb" ]] || return 1
  lock__run_with_lockfile "${_mf}.lock" "$(printf '_sysset_manifest_registry_append_unlocked %q %q %q %q' "$_root" "$_feat" "$_ver" "$_tb")"
}

# shellcheck disable=SC2329 # invoked via eval from lock__run_with_lockfile (see _sysset_manifest_registry_append)
_sysset_manifest_registry_append_unlocked() {
  local _root="${1%/}" _feat="$2" _ver="$3" _tb="$4"
  local _mf="${_root}/manifest.json"
  local _hex _dkey _rel _dest _ref _now _chk _tmp
  _hex="$(checksum__sha256_file "$_tb")" || return 1
  _dkey="sha256:${_hex}"
  # Match offline kit layout: OCI path segment is lowercased (see offline_kit_assemble.py).
  _rel="features/ghcr.io/${SYSSET_GHCR_NAMESPACE}/${_feat,,}/sha256/${_hex}/"
  _dest="${_root}/${_rel}"
  _ref="$(_sysset_default_oci_ref "$_feat" "$_ver")"
  _ref="${_ref,,}"
  _now="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2> /dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
  [[ -d "$_dest" ]] && rm -rf "$_dest"
  mkdir -p "$_dest"
  tar -xzf "$_tb" -C "$_dest" || return 1
  _chk="$(_sysset_checksums_json_for_payload_dir "$_dest")" || return 1
  _tmp="${_mf}.tmp.$$"
  if ! json__query \
    --arg ref "$_ref" \
    --arg dig "$_dkey" \
    --arg rp "$_rel" \
    --arg fa "$_now" \
    --arg fv "$_feat" \
    --arg vs "$_ver" \
    --argjson chk "$_chk" \
    --argjson digestsprev "$(json__query -c '.digests // {}' "$_mf" 2> /dev/null || echo '{}')" \
    '
    .refs[$ref] = $dig
    | .digests[$dig] = (
        {
          relativePath: $rp,
          fetchedAt: $fa,
          sourceRefs: (
            ( ($digestsprev[$dig].sourceRefs // []) + [$ref] ) | unique
          ),
          checksums: $chk
        }
      )
    | .features[$fv] = $vs
    ' "$_mf" > "$_tmp"
  then
    rm -rf "$_dest"
    rm -f "$_tmp"
    return 1
  fi
  mv "$_tmp" "$_mf" || {
    rm -rf "$_dest"
    rm -f "$_tmp"
    return 1
  }
  return 0
}

# ── Bundle manifest: fetch + parse ──────────────────────────────────────────
# Bundle-pinned mode fetches <bundle>/sysset-vX.Y.Z.tar.gz (manifest.json) or uses a local manifest.json.
# The manifest records {<feature>: <X.Y.Z>} per feature at bundle-cut time.
_BUNDLE_TAG=""           # Resolved bundle tag (e.g. v1.2.3); "" in rolling mode.
_BUNDLE_MANIFEST_FILE="" # Path to downloaded bundle manifest.json; "" if N/A.

# _resolve_bundle_tag <spec> — Resolve a bundle-version spec to its v<X.Y.Z> tag.
_resolve_bundle_tag() {
  local _spec="${1:-}"
  github__resolve_version "${SYSSET_REPO}" "$_spec" --prefix "v" --all
}

# _fetch_bundle_manifest <bundle-tag> <dest-file> — Obtain manifest.json from
# local registry (matching .version) or from the bundle kit tarball on the release.
_fetch_bundle_manifest() {
  local _tag="$1" _dest="$2"
  local _local_mf="${_SYSSET_REGISTRY_ROOT}/manifest.json"
  if [[ -f "$_local_mf" ]]; then
    local _lv=""
    _lv="$(json__query -r '.version // empty' "$_local_mf" 2> /dev/null)" || _lv=""
    if [[ "$_lv" == "$_tag" ]]; then
      cp "$_local_mf" "$_dest"
      return 0
    fi
  fi
  local _kit _url _tmp _td
  _kit="$(_sysset_bundle_kit_tarball_name "$_tag")"
  _url="${SYSSET_RELEASE_BASE}/${_tag}/${_kit}"
  _tmp="$(mktemp)"
  if ! net__fetch_url_file "${_url}" "${_tmp}"; then
    rm -f "$_tmp"
    return 1
  fi
  _td="$(mktemp -d)"
  if ! tar -xzf "$_tmp" -C "$_td" manifest.json 2> /dev/null; then
    rm -rf "$_td" "$_tmp"
    return 1
  fi
  cp "$_td/manifest.json" "$_dest"
  rm -rf "$_td" "$_tmp"
  return 0
}

# _lookup_bundle_feature_version <manifest.json> <feature> — Print semver from .features.
_lookup_bundle_feature_version() {
  local _mf="${1-}" _feat="${2-}" _v=""
  _v="$(json__query -r --arg f "$_feat" '.features[$f] // empty' "$_mf" 2> /dev/null)" || _v=""
  [[ -n "$_v" && "$_v" != "null" ]] || return 1
  printf '%s\n' "$_v"
}

# ── Shared tarball fetch + verify ────────────────────────────────────────────
# Downloads sysset-<feature>.tar.gz for a feature's <feature>/<X.Y.Z> tag and
# verifies its SHA-256 against the digest field from the GitHub Releases API.
# Best-effort: warns when the API omits the digest; fails on a mismatch.
_fetch_and_verify_tarball() {
  # $1 = feature id, $2 = resolved tag (<feature>/<X.Y.Z>), $3 = destination file
  local _feature="$1" _resolved="$2" _dest="$3"
  local _ver="${_resolved##*/}"
  local _ref _norm _mf _dkey
  _mf="${_SYSSET_REGISTRY_ROOT}/manifest.json"
  _ref="$(_sysset_default_oci_ref "$_feature" "$_ver")"
  _norm="${_ref,,}"
  if [[ -f "$_mf" ]]; then
    _dkey="$(json__query -r --arg r "$_norm" '.refs[$r] // empty' "$_mf" 2> /dev/null)" || _dkey=""
    if [[ -n "$_dkey" && "$_dkey" != "null" ]]; then
      if _sysset_verify_digest_checksums "$_SYSSET_REGISTRY_ROOT" "$_dkey" "$_mf" &&
        _sysset_pack_digest_payload_to_tarball "$_SYSSET_REGISTRY_ROOT" "$_dkey" "$_mf" "$_dest"; then
        logging__info "[${_feature}] using local registry (${_dkey})."
        return 0
      fi
      logging__warn "[${_feature}] local registry digest failed verification — refetching."
    fi
  fi
  local _asset_name="sysset-${_feature}.tar.gz"
  if ! github__fetch_release_asset_tarball "${SYSSET_REPO}" "${_resolved}" "${_asset_name}" "${_dest}"; then
    return 1
  fi
  if [[ -f "$_mf" && -w "$_mf" ]]; then
    _sysset_manifest_registry_append "$_SYSSET_REGISTRY_ROOT" "$_feature" "$_ver" "$_dest" || {
      logging__warn "[${_feature}] could not update local manifest.json."
    }
  fi
  return 0
}

# ── Resolve (feature, spec) → tag ──────────────────────────────────────────
# Applies the priority rules:
#
#   1. If <spec> is non-empty, resolve <feature>/<spec> directly
#      (per-feature override; wins in every mode).
#   2. Else if bundle mode is active, look up the feature's version in the
#      bundle manifest; return <feature>/<version>.
#   3. Else (rolling mode), resolve the latest <feature>/<X.Y.Z> release.
#
# Stdout: the resolved <feature>/<X.Y.Z> tag.
_resolve_install_tag() {
  local _feature="$1" _spec="${2:-}" _version=""
  if [[ -n "$_spec" ]]; then
    logging__info "[${_feature}] Resolving per-feature version (spec: '${_spec}')..."
    _resolve_feature_tag "$_feature" "$_spec"
    return $?
  fi
  if [[ -n "$_BUNDLE_TAG" ]]; then
    _version="$(_lookup_bundle_feature_version "$_BUNDLE_MANIFEST_FILE" "$_feature")" || {
      logging__error "[${_feature}] Feature not listed in bundle '${_BUNDLE_TAG}' manifest."
      return 1
    }
    logging__info "[${_feature}] Using bundle ${_BUNDLE_TAG} -> version '${_version}'."
    printf '%s/%s\n' "$_feature" "$_version"
    return 0
  fi
  logging__info "[${_feature}] Resolving latest per-feature release..."
  _resolve_feature_tag "$_feature" ""
}

# _sysset_options_to_env — apply options JSON (stdin) as exported env vars in current shell.
# Newlines inside string values are preserved via bash %q quoting (in devcontainer__feature_env_exports).
_sysset_options_to_env() {
  local _exports
  _exports="$(devcontainer__feature_env_exports)" || return 1
  [[ -n "$_exports" ]] && eval "$_exports"
  return 0
}

# _sysset_disabled_fe <entry...>,<fid>,<phase>,<cmdname> — scan _NO_FE_LIFE for feature-scope skip.
_sysset_disabled_fe() {
  local _fid="$1" _ph="$2" _cn="${3-}" _e
  for _e in "${_NO_FE_LIFE[@]+"${_NO_FE_LIFE[@]}"}"; do
    devcontainer__lifecycle_disabled "$_e" feature "$_fid" "$_ph" "$_cn" && return 0
  done
  return 1
}

# _sysset_disabled_co <phase> <cmdname> — scan _NO_CO_LIFE for container-scope skip.
_sysset_disabled_co() {
  local _ph="$1" _cn="${2-}" _e
  for _e in "${_NO_CO_LIFE[@]+"${_NO_CO_LIFE[@]}"}"; do
    devcontainer__lifecycle_disabled "$_e" container "_container_" "$_ph" "$_cn" && return 0
  done
  return 1
}

# _sysset_warn_unknown_fe_scope <fid> — warn about feature-scope disable entries whose
# feature id does not match the single installed feature (feature-mode only).
_sysset_warn_unknown_fe_scope() {
  local _fid="$1" _e _head
  for _e in "${_NO_FE_LIFE[@]+"${_NO_FE_LIFE[@]}"}"; do
    [[ -z "$_e" || "$_e" == "all" ]] && continue
    _head="${_e%%:*}"
    local _isphase=0 _p
    for _p in "${_DEVCONTAINER_LIFECYCLE_PHASES[@]}"; do
      [[ "$_head" == "$_p" ]] && _isphase=1
    done
    ((_isphase)) && continue
    [[ "$_head" == "$_fid" ]] && continue
    logging__warn "--no-feature-lifecycle-command '$_e' references a different feature (installed: '$_fid'); ignoring."
  done
}

# _sysset_run_feature_lifecycle <staged-root> <fid> <cwd>
_sysset_run_feature_lifecycle() {
  local _root="${1-}" _fid="${2-}" _w="${3:-$PWD}" _ph _line _scope _sid _cmd
  local _df="${_root}/devcontainer-feature.json"
  [[ -f "$_df" ]] || {
    logging__info "No devcontainer-feature.json; skipping feature lifecycle"
    return 0
  }
  _sysset_warn_unknown_fe_scope "$_fid"
  local _stage_root
  _stage_root="$(dirname "$_root")"
  local _stage_name
  _stage_name="$(basename "$_root")"
  if [[ ! -d "${_stage_root}/${_fid}" ]]; then
    _stage_root="$_root"
    _stage_name=""
  fi
  for _ph in "${_DEVCONTAINER_LIFECYCLE_PHASES[@]}"; do
    while IFS=$'\t' read -r _scope _sid _cmd; do
      [[ "$_scope" == feature ]] || continue
      if _sysset_disabled_fe "$_sid" "$_ph" ""; then
        logging__info "[${_sid}] skip feature ${_ph} (disabled)"
        continue
      fi
      printf '%s' "$_cmd" | proc__run_command_form --cwd "$_w" || return 1
    done < <(
      if [[ -n "$_stage_name" ]]; then
        devcontainer__lifecycle_iter --staged-root "$_stage_root" --phase "$_ph" -- "$_stage_name" 2> /dev/null
      else
        local _tmpd
        _tmpd="$(mktemp -d)"
        mkdir -p "${_tmpd}/${_fid}"
        cp "$_df" "${_tmpd}/${_fid}/devcontainer-feature.json"
        devcontainer__lifecycle_iter --staged-root "$_tmpd" --phase "$_ph" -- "$_fid" 2> /dev/null
        rm -rf "$_tmpd"
      fi
    )
  done
  return 0
}

# ── Feature mode ─────────────────────────────────────────────────────────────
if [[ "$_mode" == "feature" ]]; then
  [[ "$_mode_arg" == *@* ]] && {
    logging__error "Use 'feature:version' instead of 'feature@version'."
    exit 1
  }
  case "$_mode_arg" in
    ./* | ../* | /* | ~/*)
      _feature="$_mode_arg"
      _feat_version_spec=""
      ;;
    *:*)
      _feature="${_mode_arg%%:*}"
      _feat_version_spec="${_mode_arg#*:}"
      ;;
    *)
      _feature="$_mode_arg"
      _feat_version_spec=""
      ;;
  esac

  if [[ "$_DOWNLOAD_ONLY" == true ]]; then
    case "$_mode_arg" in
      ./* | ../* | /*)
        logging__error "--download-only cannot be used with a single local feature path."
        exit 1
        ;;
    esac
  fi

  if [[ -z "$_feat_version_spec" && -n "${SYSSET_VERSION:-}" ]]; then
    if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${SYSSET_VERSION}")" || [[ -z "$_BUNDLE_TAG" ]]; then
      logging__error "Bad SYSSET_VERSION"
      exit 1
    fi
    _BUNDLE_MANIFEST_FILE="$(mktemp)"
    trap 'rm -f "$_BUNDLE_MANIFEST_FILE"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
    _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE" || exit 1
  fi

  if ! _RESOLVED="$(_resolve_install_tag "$_feature" "$_feat_version_spec")" || [[ -z "$_RESOLVED" ]]; then
    exit 1
  fi
  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_lib_tmpdir" "$_tmpdir" ${_BUNDLE_MANIFEST_FILE:+"$_BUNDLE_MANIFEST_FILE"}; logging__cleanup' EXIT
  if ! _fetch_and_verify_tarball "$_feature" "$_RESOLVED" "${_tmpdir}/feature.tar.gz"; then
    exit 1
  fi
  if [[ "$_DOWNLOAD_ONLY" == true ]]; then
    logging__info "[${_feature}] --download-only: fetched ${_RESOLVED}."
    [[ -n "$_REPORT_FILE" ]] && printf '%s\n' "{\"ok\":[\"${_feature}\"]}" > "$_REPORT_FILE"
    logging__fn_exit "sysset installer"
    exit 0
  fi
  tar -xzf "${_tmpdir}/feature.tar.gz" -C "$_tmpdir"
  sh "${_tmpdir}/install.sh" "$@"
  _wf="${_WORKSPACE_CUSTOM:-$PWD}"
  if [[ "$_FEATURE_SKIP_LIFECYCLE" != true ]]; then
    _lf="${_LIFE_CMD_DIR:-$_wf}"
    _sysset_run_feature_lifecycle "$_tmpdir" "$_feature" "$_lf" || exit 1
  fi
  logging__fn_exit "sysset installer"
  exit 0
fi

# ══ Devcontainer manifest mode ══════════════════════════════════════════
if [[ ! -f "$_mode_arg" ]]; then
  logging__error "Not found: $_mode_arg"
  exit 1
fi

_DCJ="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -f "$_DCJ"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
devcontainer__parse_config "$_mode_arg" > "$_DCJ" || exit 1

_WORK_ROOT="$(devcontainer__workspace_folder "$_mode_arg")"
[[ -n "$_WORKSPACE_CUSTOM" ]] && _WORK_ROOT="$_WORKSPACE_CUSTOM"

if [[ "$_DOWNLOAD_ONLY" == true ]]; then
  _BUNDLE_NAME_VER="$(devcontainer__name_version_suffix "$(json__query -r '.name // ""' "$_DCJ" 2> /dev/null || true)")"
  _bspec=""
  if [[ -n "${SYSSET_VERSION:-}" ]]; then
    _bspec="${SYSSET_VERSION}"
  elif [[ -n "$_BUNDLE_NAME_VER" ]]; then
    _bspec="${_BUNDLE_NAME_VER}"
  fi
  if [[ -n "$_bspec" ]]; then
    if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${_bspec}")" || [[ -z "$_BUNDLE_TAG" ]]; then
      logging__error "Bundle tag not found for '$_bspec'"
      exit 1
    fi
    _BUNDLE_MANIFEST_FILE="$(mktemp)"
    _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE" || exit 1
  fi
  declare -A _D_K=() _D_T=()
  _D_IDS=()
  while IFS=$'\t' read -r _id _k _tt; do
    [[ -z "$_id" ]] && continue
    if [[ "$_k" == ./* || "$_k" == ../* || "$_k" == /* ]]; then
      continue
    fi
    _D_IDS+=("$_id")
    _D_K["$_id"]="$_k"
    _D_T["$_id"]="$_tt"
  done < <(devcontainer__iter_features "$_DCJ" "$_WORK_ROOT" "${_COMPAT_PREFIX[@]}")
  declare -A _D_SEEN=()
  _D_QUEUE=("${_D_IDS[@]}")
  _D_FAIL=()
  _D_OK=()
  while ((${#_D_QUEUE[@]} > 0)); do
    _cur="${_D_QUEUE[0]}"
    _D_QUEUE=("${_D_QUEUE[@]:1}")
    [[ -n "${_D_SEEN[$_cur]:-}" ]] && continue
    _D_SEEN["$_cur"]=1
    if ! _rt="$(_resolve_install_tag "$_cur" "${_D_T[$_cur]}")" || [[ -z "$_rt" ]]; then
      _D_FAIL+=("$_cur")
      continue
    fi
    _wdir="$(mktemp -d)"
    if ! _fetch_and_verify_tarball "$_cur" "$_rt" "${_wdir}/a.tgz"; then
      _D_FAIL+=("$_cur")
      rm -rf "$_wdir"
      continue
    fi
    tar -xzf "${_wdir}/a.tgz" -C "$_wdir"
    _D_OK+=("$_cur")
    if [[ -f "${_wdir}/devcontainer-feature.json" ]]; then
      while IFS= read -r _dep; do
        [[ -z "$_dep" || "$_dep" == "null" ]] && continue
        [[ "$_dep" != *ghcr.io/quantized8/sysset/* ]] && continue
        _drest="${_dep##*/}"
        _did="${_drest%%:*}"
        [[ -n "${_D_SEEN[$_did]:-}" ]] && continue
        _D_QUEUE+=("$_did")
      done < <(json__query -r '.dependsOn[]? // empty' "${_wdir}/devcontainer-feature.json" 2> /dev/null)
    fi
    rm -rf "$_wdir"
  done
  if [[ -n "$_REPORT_FILE" ]]; then
    json__query -n \
      --argjson ok "$(json__query -n '$ARGS.positional' --args -- ${_D_OK[@]+"${_D_OK[@]}"})" \
      --argjson fail "$(json__query -n '$ARGS.positional' --args -- ${_D_FAIL[@]+"${_D_FAIL[@]}"})" \
      '{ok:$ok, failures:$fail}' > "$_REPORT_FILE" 2> /dev/null || true
  fi
  ((${#_D_FAIL[@]} > 0)) && exit 1
  logging__fn_exit "sysset installer"
  exit 0
fi

os__require_root
_SYSSET_BUILD_CONTEXT="install-bash"
export _SYSSET_BUILD_CONTEXT
_SYSSET_SESSION_TRACK_DIR="$(mktemp -d)"
export _SYSSET_SESSION_TRACK_DIR
_SYSSET_INITIAL_SNAPSHOT="$(mktemp)"
export _SYSSET_INITIAL_SNAPSHOT
ospkg__take_initial_snapshot "$_SYSSET_INITIAL_SNAPSHOT"

_STAGED="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'ospkg__cleanup_session_build_groups "false"; rm -rf "${_SYSSET_SESSION_TRACK_DIR:-}" "${_SYSSET_INITIAL_SNAPSHOT:-}" "$_STAGED" "$_DCJ"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

_BUNDLE_NAME_VER="$(devcontainer__name_version_suffix "$(json__query -r '.name // ""' "$_DCJ" 2> /dev/null || true)")"
_bspec=""
if [[ -n "${SYSSET_VERSION:-}" ]]; then
  _bspec="${SYSSET_VERSION}"
elif [[ -n "$_BUNDLE_NAME_VER" ]]; then
  _bspec="${_BUNDLE_NAME_VER}"
fi
if [[ -n "$_bspec" ]]; then
  if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${_bspec}")" || [[ -z "$_BUNDLE_TAG" ]]; then
    logging__error "Bundle tag not found for '$_bspec'"
    exit 1
  fi
  _BUNDLE_MANIFEST_FILE="$(mktemp)"
  _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE" || exit 1
fi

declare -A _KEY_OF=() _OPT_OF=() _TAG_OF=()
_IDS=()
while IFS=$'\t' read -r _id _k _tt; do
  [[ -z "$_id" ]] && continue
  _opt="$(json__query -c --arg k "$_k" '(.features // {})[$k] // {}' "$_DCJ")"
  _IDS+=("$_id")
  _KEY_OF["$_id"]="$_k"
  _OPT_OF["$_id"]="$_opt"
  _TAG_OF["$_id"]="$_tt"
done < <(devcontainer__iter_features "$_DCJ" "$_WORK_ROOT" "${_COMPAT_PREFIX[@]}")
((${#_IDS[@]})) || {
  logging__error "no features"
  exit 1
}

# Stage tarballs (skip and record failures; continue with remaining features)
_failed=()
_OK_IDS=()
for _id in "${_IDS[@]}"; do
  mkdir -p "${_STAGED}/${_id}"
  if ! _rt="$(_resolve_install_tag "$_id" "${_TAG_OF[$_id]}")" || [[ -z "$_rt" ]]; then
    _failed+=("$_id")
    continue
  fi
  if ! _fetch_and_verify_tarball "$_id" "$_rt" "${_STAGED}/${_id}/a.tgz"; then
    _failed+=("$_id")
    continue
  fi
  if ! tar -xzf "${_STAGED}/${_id}/a.tgz" -C "${_STAGED}/${_id}"; then
    _failed+=("$_id")
    continue
  fi
  if [[ ! -f "${_STAGED}/${_id}/devcontainer-feature.json" ]]; then
    logging__error "missing devcontainer-feature.json in $_id"
    _failed+=("$_id")
    continue
  fi
  _OK_IDS+=("$_id")
done
((${#_OK_IDS[@]})) || {
  logging__error "no features could be staged"
  exit 1
}
_IDS=("${_OK_IDS[@]}")
unset _OK_IDS

# Graph files
ht="${_STAGED}/h"
st="${_STAGED}/s"
pt="${_STAGED}/p"
devcontainer__build_ordering_inputs \
  --hard-edges-file "$ht" \
  --soft-edges-file "$st" \
  --priority-file "$pt" \
  --staged-root "$_STAGED" \
  --config-file "$_DCJ" \
  -- "${_IDS[@]}" || {
  logging__error "failed to build ordering inputs"
  exit 1
}

mapfile -t _ORDER < <(graph__round_order --hard-edges-file "$ht" --soft-edges-file "$st" --priority-file "$pt" -- "${_IDS[@]}" 2> /dev/null || true)
((${#_ORDER[@]})) || {
  _ORDER=()
  for _c in "${_CANONICAL_ORDER[@]}"; do
    for _i in "${_IDS[@]}"; do
      [[ "$_c" == "$_i" ]] && _ORDER+=("$_i")
    done
  done
  for _i in "${_IDS[@]}"; do
    _in=0
    for _o in "${_ORDER[@]}"; do
      [[ "$_o" == "$_i" ]] && _in=1
    done
    ((_in)) || _ORDER+=("$_i")
  done
}
logging__info "order: ${_ORDER[*]}"

if [[ "$_NO_INIT_CMD" != true ]]; then
  _iv="$(json__query -c 'if (has("initializeCommand")|not) then null else .initializeCommand end' "$_DCJ" 2> /dev/null || echo "null")"
  if [[ -n "$_iv" && "$_iv" != "null" ]]; then
    logging__warn "initializeCommand (host): trust this config"
    (cd "${_INIT_CMD_DIR:-$_WORK_ROOT}" && printf '%s' "$_iv" | proc__run_command_form --cwd "${_INIT_CMD_DIR:-$_WORK_ROOT}") || exit 1
  fi
fi

_RU="$(json__query -r '.remoteUser // ""' "$_DCJ" 2> /dev/null | head -1)"
_CU="$(json__query -r '.containerUser // ""' "$_DCJ" 2> /dev/null | head -1)"
_SELF_USER="$(users__get_current)"
_EFF_USER="${_RU:-${_CU:-$_SELF_USER}}"
_EFF_CUSER="${_CU:-$_SELF_USER}"
_RU_HOME="$(devcontainer__user_home "$_EFF_USER" 2> /dev/null || true)"
_CU_HOME="$(devcontainer__user_home "$_EFF_CUSER" 2> /dev/null || true)"
[[ -z "$_RU_HOME" ]] && _RU_HOME="${HOME:-}"
[[ -z "$_CU_HOME" ]] && _CU_HOME="${HOME:-}"

_passed=()
for _id in "${_ORDER[@]}"; do
  _r2="$(_resolve_install_tag "$_id" "${_TAG_OF[$_id]}")" || {
    _failed+=("$_id")
    continue
  }
  _wdir="$(mktemp -d)"
  if ! _fetch_and_verify_tarball "$_id" "$_r2" "${_wdir}/a.tgz"; then
    _failed+=("$_id")
    rm -rf "$_wdir"
    continue
  fi
  tar -xzf "${_wdir}/a.tgz" -C "$_wdir"
  (
    if ! _sysset_options_to_env <<< "${_OPT_OF[$_id]-}"; then
      exit 1
    fi
    export _REMOTE_USER="${_EFF_USER}"
    export _CONTAINER_USER="${_EFF_CUSER}"
    export _REMOTE_USER_HOME="${_RU_HOME}"
    export _CONTAINER_USER_HOME="${_CU_HOME}"
    export _SYSSET_BUILD_CONTEXT="feature::${_id}"
    cd "$_wdir" || exit 1
    logging__info "[${_id}] running install.sh"
    sh install.sh
  ) && _passed+=("$_id") || _failed+=("$_id")
  rm -rf "$_wdir"
done

_LCW="${_LIFE_CMD_DIR:-$_WORK_ROOT}"
_LIFE_USER="${_RU:-}"
for _ph in onCreateCommand updateContentCommand postCreateCommand postStartCommand postAttachCommand; do
  while IFS=$'\t' read -r _scope _sid _cmd; do
    [[ -z "$_scope" ]] && continue
    if [[ "$_scope" == feature ]]; then
      if _sysset_disabled_fe "$_sid" "$_ph" ""; then
        logging__info "[${_sid}] skip feature ${_ph} (disabled)"
        continue
      fi
    else
      if _sysset_disabled_co "$_ph" ""; then
        logging__info "skip container ${_ph} (disabled)"
        continue
      fi
    fi
    if [[ -n "$_LIFE_USER" ]]; then
      printf '%s' "$_cmd" | proc__run_command_form --cwd "$_LCW" --user "$_LIFE_USER" || exit 1
    else
      printf '%s' "$_cmd" | proc__run_command_form --cwd "$_LCW" || exit 1
    fi
  done < <(devcontainer__lifecycle_iter --config-file "$_DCJ" --staged-root "$_STAGED" --phase "$_ph" -- "${_ORDER[@]}")
done

((${#_failed[@]} > 0)) && {
  logging__error "failed: ${_failed[*]}"
  exit 1
}
logging__fn_exit "sysset installer"
exit 0
