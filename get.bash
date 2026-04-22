#!/usr/bin/env bash
# get.bash — Full bash >=4 implementation of the sysset installer.
#
# Invoked by get.sh after bash >=4 is confirmed. Downloads lib/*.sh from the
# repo, then operates in one of two modes:
#
#   Feature mode:   install a single feature (optionally version-pinned via @)
#   Manifest mode:  install multiple features from a JSON/YAML manifest
#
# Usage:
#   get.bash <feature>[@<sysset-version>] [feature-opts...]
#   get.bash <manifest.json|.yaml|.yml>
#
# Options (consumed by get.bash; not forwarded to feature installers):
#   --logfile <path>  Append captured output to this file on exit.
#   --debug           Enable bash -x trace.
#   --help, -h        Show this help.
#
# Environment overrides:
#   SYSSET_BASE_URL   GitHub Releases base URL  (default: github.com releases)
#   SYSSET_RAW_BASE   Raw GitHub base URL       (default: main branch)
#   SYSSET_FETCH_TOOL curl|wget                 (set by get.sh; auto-detected here if unset)
set -euo pipefail

SYSSET_REPO="quantized8/sysset"
SYSSET_RELEASE_BASE="${SYSSET_BASE_URL:-https://github.com/${SYSSET_REPO}/releases/download}"
SYSSET_RAW_BASE="${SYSSET_RAW_BASE:-https://raw.githubusercontent.com/${SYSSET_REPO}/main}"

# ── Lib bootstrap ─────────────────────────────────────────────────────────────
# Download lib/*.sh before anything else. SYSSET_FETCH_TOOL is set by get.sh;
# fall back to curl detection here in case get.bash is invoked directly.

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
for _f in net.sh os.sh json.sh github.sh ospkg.sh logging.sh checksum.sh; do
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

logging__setup
trap 'rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT

echo "↪️  Script entry: sysset installer" >&2

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
  Feature mode:   get.sh <feature>[@<sysset-version>] [feature-opts...]
  Manifest mode:  get.sh <manifest.json|.yaml|.yml>

Arguments:
  <feature>           Feature to install (e.g. install-pixi, install-shell)
  @<sysset-version>   Pin the sysset release version for this feature
                      (e.g. @1.2, @v1.2.3; supports partial semver)
  <manifest>          Path to a JSON or YAML installation manifest

Options:
  --logfile <path>    Append log output to this file on exit.
  --debug             Enable bash -x trace output.
  --help, -h          Show this help.

Examples:
  get.sh install-pixi                           # latest sysset, latest pixi
  get.sh install-pixi --version 0.66.0          # pixi v0.66.0 (forwarded to installer)
  get.sh install-pixi@1.2 --version 0.66.0      # sysset v1.2.x, pixi v0.66.0
  get.sh manifest.json                          # manifest (version from manifest or latest)

Manifest format (JSON):
  {
    "version": "1",
    "override_install_order": false,
    "features": [
      { "id": "install-pixi", "version": "1.2", "options": { "version": "0.66.0" } },
      { "id": "install-shell",                   "options": { "shell": "zsh" } }
    ]
  }

Version priority (highest to lowest):
  per-feature "version" in manifest > top-level "version" in manifest > latest

Canonical install order:
EOF
  for _f in "${_CANONICAL_ORDER[@]}"; do
    echo "  $_f" >&2
  done
  echo "  <unknown features in manifest order>" >&2
  exit "${1:-0}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
LOGFILE=""
_debug=false
_mode_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logfile)
      shift
      if [[ $# -eq 0 ]]; then
        echo "⛔ --logfile requires a value." >&2
        exit 1
      fi
      LOGFILE="$1"
      echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
      shift
      ;;
    --debug)
      _debug=true
      echo "📩 Read argument 'debug': 'true'" >&2
      shift
      ;;
    --help | -h) __usage__ ;;
    --*)
      echo "⛔ Unknown option: '${1}'" >&2
      exit 1
      ;;
    *)
      _mode_arg="$1"
      shift
      break # Everything remaining belongs to the feature installer.
      ;;
  esac
done

[[ "$_debug" == true ]] && set -x

if [[ -z "$_mode_arg" ]]; then
  echo "⛔ No feature or manifest specified." >&2
  __usage__ 1
fi

# ── Mode detection ────────────────────────────────────────────────────────────
_mode=""
case "$_mode_arg" in
  *.json | *.yaml | *.yml) _mode="manifest" ;;
  *) _mode="feature" ;;
esac

# ── jq/yq helpers (required for manifest mode; installed on demand) ───────────

_install_jq() {
  echo "ℹ️  jq not found — installing via package manager." >&2
  ospkg__install jq
}

_install_yq() {
  local _os _arch _url
  _os="$(os__kernel | tr '[:upper:]' '[:lower:]')"
  _arch="$(os__arch)"
  case "$_arch" in
    x86_64) _arch="amd64" ;;
    aarch64 | arm64) _arch="arm64" ;;
    *)
      echo "⛔ Unsupported architecture for yq: ${_arch}" >&2
      return 1
      ;;
  esac
  _url="$(github__release_asset_urls mikefarah/yq \
    --filter "yq_${_os}_${_arch}$" | head -1)"
  if [[ -z "$_url" ]]; then
    echo "⛔ Could not find yq release asset for ${_os}/${_arch}." >&2
    return 1
  fi
  echo "ℹ️  Downloading yq from: ${_url}" >&2
  net__fetch_url_file "$_url" /usr/local/bin/yq
  chmod +rx /usr/local/bin/yq
  echo "✅ yq installed to /usr/local/bin/yq" >&2
  return 0
}

# ── Feature mode ──────────────────────────────────────────────────────────────
if [[ "$_mode" == "feature" ]]; then
  # Parse optional @sysset-version from the feature name.
  case "$_mode_arg" in
    *@*)
      _feature="${_mode_arg%%@*}"
      _feat_version_spec="${_mode_arg#*@}"
      ;;
    *)
      _feature="$_mode_arg"
      _feat_version_spec=""
      ;;
  esac

  _effective_spec="${_feat_version_spec:-}"
  echo "ℹ️  Resolving sysset version for feature '${_feature}' (spec: '${_effective_spec:-latest}')..." >&2
  _RESOLVED="$(github__resolve_version "${SYSSET_REPO}" "$_effective_spec")"
  echo "ℹ️  Resolved sysset version: '${_RESOLVED}'" >&2

  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_lib_tmpdir" "$_tmpdir"; logging__cleanup' EXIT

  echo "↪️  Downloading sysset-${_feature} @ ${_RESOLVED} ..." >&2
  _fetch_and_verify_tarball "${_feature}" "${_RESOLVED}" "${_tmpdir}/feature.tar.gz"

  tar -xzf "$_tmpdir/feature.tar.gz" -C "$_tmpdir"

  # The tarball contains a POSIX sh bootstrap (install.sh) → install.bash.
  sh "$_tmpdir/install.sh" "$@"
  echo "↩️  Script exit: sysset installer" >&2
  exit 0
fi

# ── Manifest mode ─────────────────────────────────────────────────────────────

_MANIFEST="$_mode_arg"

if [[ ! -f "$_MANIFEST" ]]; then
  echo "⛔ Manifest not found: '${_MANIFEST}'" >&2
  exit 1
fi

# Preconditions
os__require_root

# Detect manifest format.
_ext="${_MANIFEST##*.}"
_is_yaml=false
case "$_ext" in
  yaml | yml) _is_yaml=true ;;
  json) _is_yaml=false ;;
  *)
    echo "⛔ Unrecognised manifest extension '.${_ext}'. Use .json, .yaml, or .yml." >&2
    exit 1
    ;;
esac

# Auto-install parser dependencies.
if ! command -v jq > /dev/null 2>&1; then
  _install_jq
fi

if [[ "$_is_yaml" == true ]] && ! command -v yq > /dev/null 2>&1; then
  echo "ℹ️  yq not found — fetching from GitHub Releases." >&2
  _install_yq
fi

# Normalise manifest to JSON (yq for YAML, jq handles JSON directly).
_PARSER="jq"
echo "ℹ️  Using parser: ${_PARSER}" >&2

if [[ "$_is_yaml" == true ]]; then
  _json_manifest="$(mktemp)"
  # shellcheck disable=SC2064
  trap 'rm -f "$_json_manifest"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
  echo "ℹ️  Converting YAML manifest to JSON via yq..." >&2
  yq -o=json '.' "$_MANIFEST" > "$_json_manifest"
  _MANIFEST="$_json_manifest"
fi

# Parse top-level fields.
_override_order="$("$_PARSER" -r '.override_install_order // false' "$_MANIFEST")"

# Version priority: per-feature (resolved later) > manifest top-level > latest
_manifest_version="$("$_PARSER" -r '.version // ""' "$_MANIFEST")"

# Resolve the global sysset version once (used for features without a per-feature version).
echo "ℹ️  Resolving global sysset version (spec: '${_manifest_version:-latest}')..." >&2
_GLOBAL_VERSION="$(github__resolve_version "${SYSSET_REPO}" "$_manifest_version")"
echo "ℹ️  Global sysset version: '${_GLOBAL_VERSION}'" >&2
echo "ℹ️  override_install_order: '${_override_order}'" >&2

# Read feature IDs in manifest order.
# SC2016: $feat is a jq variable bound by --arg, not a bash variable.
mapfile -t _manifest_features < <("$_PARSER" -r '.features[].id' "$_MANIFEST")

if [[ ${#_manifest_features[@]} -eq 0 ]]; then
  echo "⛔ No features found in manifest." >&2
  exit 1
fi

echo "ℹ️  Manifest features (${#_manifest_features[@]}): ${_manifest_features[*]}" >&2

# ── Determine execution order ─────────────────────────────────────────────────
_sorted_features=()

_sort_features() {
  local _feat _known _found

  for _known in "${_CANONICAL_ORDER[@]}"; do
    for _feat in "${_manifest_features[@]}"; do
      if [[ "$_feat" == "$_known" ]]; then
        _sorted_features+=("$_feat")
        break
      fi
    done
  done

  for _feat in "${_manifest_features[@]}"; do
    _found=false
    for _known in "${_CANONICAL_ORDER[@]}"; do
      [[ "$_feat" == "$_known" ]] && {
        _found=true
        break
      }
    done
    [[ "$_found" == false ]] && _sorted_features+=("$_feat")
  done
  return 0
}

if [[ "$_override_order" == "true" ]]; then
  _sorted_features=("${_manifest_features[@]}")
  echo "ℹ️  Using manifest order (override_install_order: true)" >&2
else
  _sort_features
  echo "ℹ️  Using canonical install order" >&2
fi

echo "ℹ️  Execution order: ${_sorted_features[*]}" >&2

# ── Shared tarball fetch + verify ────────────────────────────────────────────
# Downloads sysset-<feature>.tar.gz for the given resolved version tag, then
# verifies its SHA-256 against the digest field from the GitHub Releases API.
# Best-effort: warns when the API omits the digest; fails on a mismatch.
_fetch_and_verify_tarball() {
  local _feature="$1" _resolved="$2" _dest="$3"
  local _asset_name="sysset-${_feature}.tar.gz"
  local _url="${SYSSET_RELEASE_BASE}/${_resolved}/${_asset_name}"

  # Fetch release JSON to obtain the asset digest.
  local _rel_json _digest
  _rel_json="$(mktemp)"
  if github__fetch_release_json "${SYSSET_REPO}" --tag "${_resolved}" --dest "${_rel_json}" 2> /dev/null; then
    _digest="$(github__release_json_digest_for_asset "${_rel_json}" "${_asset_name}")" || _digest=""
  else
    _digest=""
  fi
  rm -f "${_rel_json}"

  net__fetch_url_file "${_url}" "${_dest}" || return 1

  if [[ -n "${_digest}" ]]; then
    echo "ℹ️  Verifying checksum for '${_asset_name}'..." >&2
    checksum__verify_sha256 "${_dest}" "${_digest}" || return 1
  else
    echo "⚠️  No digest in release metadata for '${_asset_name}' — skipping verification." >&2
  fi
  return 0
}

# ── Feature runner ────────────────────────────────────────────────────────────
_run_feature() {
  local _feature="$1"
  local _resolved_version="$2"
  shift 2
  local _opts=("$@")

  local _tmpdir
  _tmpdir="$(mktemp -d)"

  echo "ℹ️  [${_feature}] Downloading @ ${_resolved_version} ..." >&2
  if ! _fetch_and_verify_tarball "${_feature}" "${_resolved_version}" "${_tmpdir}/feature.tar.gz"; then
    rm -rf "$_tmpdir"
    echo "⛔ [${_feature}] Failed to download or verify tarball." >&2
    return 1
  fi

  tar -xzf "$_tmpdir/feature.tar.gz" -C "$_tmpdir"
  local _exit=0
  sh "$_tmpdir/install.sh" "${_opts[@]+"${_opts[@]}"}" || _exit=$?
  rm -rf "$_tmpdir"
  return "$_exit"
}

# ── Main install loop ─────────────────────────────────────────────────────────
_passed=()
_failed=()

for _feature in "${_sorted_features[@]}"; do
  # Per-feature version: manifest "version" key > global resolved version.
  # shellcheck disable=SC2016
  _feat_version_spec="$("$_PARSER" -r \
    --arg feat "$_feature" \
    '.features[] | select(.id == $feat) | .version // ""' \
    "$_MANIFEST")"

  if [[ -n "$_feat_version_spec" ]]; then
    echo "ℹ️  [${_feature}] Resolving per-feature version (spec: '${_feat_version_spec}')..." >&2
    _feat_resolved="$(github__resolve_version "${SYSSET_REPO}" "$_feat_version_spec")"
  else
    _feat_resolved="$_GLOBAL_VERSION"
  fi

  # Extract feature options as CLI arguments.
  # shellcheck disable=SC2016
  mapfile -t _opts < <(
    "$_PARSER" -r \
      --arg feat "$_feature" \
      '.features[] | select(.id == $feat) | .options // {} | to_entries[] | "--\(.key)", "\(.value | tostring)"' \
      "$_MANIFEST"
  )

  echo "" >&2
  echo "▶️  [${_feature}] Installing @ ${_feat_resolved}..." >&2
  if _run_feature "$_feature" "$_feat_resolved" "${_opts[@]+"${_opts[@]}"}"; then
    _passed+=("$_feature")
    echo "✅ [${_feature}] Done" >&2
  else
    _failed+=("$_feature")
    echo "⛔ [${_feature}] FAILED" >&2
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
_total=$(("${#_passed[@]}" + "${#_failed[@]}"))
echo "" >&2
echo "── Summary (${_total} features) ─────────────────────────────────────────" >&2
for _f in "${_passed[@]+"${_passed[@]}"}"; do echo "  ✅ ${_f}" >&2; done
for _f in "${_failed[@]+"${_failed[@]}"}"; do echo "  ⛔ ${_f}" >&2; done
echo "" >&2

if [[ "${#_failed[@]}" -gt 0 ]]; then
  echo "⛔ ${#_failed[@]} feature(s) failed." >&2
  exit 1
fi

echo "↩️  Script exit: sysset installer" >&2
