#!/usr/bin/env bash
# get.bash — Full bash >=4 implementation of the sysset installer.
#
# Invoked by get.sh after bash >=4 is confirmed. Downloads lib/*.sh from the
# repo, then operates in one of two modes:
#
#   Feature mode:   install a single feature (optionally version-pinned via @)
#   Manifest mode:  install multiple features from a JSON/YAML manifest
#
# Version resolution modes (per-feature releases are independent; the bundle
# tag `v<X.Y.Z>` is an accumulator over per-feature versions):
#
#   Rolling (default):       each feature resolves to the latest
#                            `<feature>/<X.Y.Z>` release tag independently.
#   Bundle-pinned:           `SYSSET_VERSION` (env) or `.version` (manifest)
#                            resolves to a bundle tag (`v<X.Y.Z>`); each
#                            feature's version is read from that bundle's
#                            `manifest.yaml`. Per-feature overrides (`@spec`
#                            or features[].version) still take precedence.
#
# Usage:
#   get.bash <feature>[@<feature-version>] [feature-opts...]
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
#   SYSSET_VERSION    Pin the bundle version; feature versions are read from
#                     that bundle's manifest.yaml. Accepts any spec understood
#                     by github__resolve_version ("", "latest", "1", "1.2",
#                     "v1.2.3", "1.2.3"). Per-feature overrides still win.
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
  Feature mode:   get.sh <feature>[@<feature-version>] [feature-opts...]
  Manifest mode:  get.sh <manifest.json|.yaml|.yml>

Arguments:
  <feature>              Feature to install (e.g. install-pixi, install-shell)
  @<feature-version>     Pin this feature's version (e.g. @1.2, @1.2.3).
                         Resolves against <feature>/<X.Y.Z> release tags.
  <manifest>             Path to a JSON or YAML installation manifest

Options:
  --logfile <path>       Append log output to this file on exit.
  --debug                Enable bash -x trace output.
  --help, -h             Show this help.

Examples:
  get.sh install-pixi                           # rolling: latest pixi feature release
  get.sh install-pixi --version 0.66.0          # pixi v0.66.0 (forwarded to installer)
  get.sh install-pixi@1.2                       # feature install-pixi @ 1.2.x
  get.sh manifest.json                          # manifest-driven install

Manifest format (JSON):
  {
    "version": "1",                             # bundle version (optional)
    "override_install_order": false,
    "features": [
      { "id": "install-pixi", "version": "1.2", "options": { "version": "0.66.0" } },
      { "id": "install-shell",                   "options": { "shell": "zsh" } }
    ]
  }

Version priority (highest to lowest):
  per-feature "version" in manifest or @spec  >  SYSSET_VERSION / manifest ".version" (bundle)  >  latest per-feature

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

# ── Bundle manifest: fetch + parse ──────────────────────────────────────────
# Bundle-pinned mode fetches <bundle>/manifest.yaml once and caches it on disk.
# The manifest records {<feature>: <X.Y.Z>} per feature at bundle-cut time.
_BUNDLE_TAG=""          # Resolved bundle tag (e.g. v1.2.3); "" in rolling mode.
_BUNDLE_MANIFEST_FILE="" # Path to downloaded bundle manifest.yaml; "" if N/A.

# _resolve_bundle_tag <spec> — Resolve a bundle-version spec to its v<X.Y.Z> tag.
_resolve_bundle_tag() {
  local _spec="${1:-}"
  github__resolve_version "${SYSSET_REPO}" "$_spec" --prefix "v" --all
}

# _fetch_bundle_manifest <bundle-tag> <dest-file> — Download manifest.yaml from
# the bundle release.
_fetch_bundle_manifest() {
  local _tag="$1" _dest="$2"
  local _url="${SYSSET_RELEASE_BASE}/${_tag}/manifest.yaml"
  net__fetch_url_file "${_url}" "${_dest}" || return 1
  return 0
}

# _lookup_bundle_feature_version <manifest.yaml> <feature> — Print the feature's
# X.Y.Z version from the bundle manifest. Exits 1 if the feature is absent.
_lookup_bundle_feature_version() {
  local _manifest="$1" _feature="$2" _version=""
  if command -v yq > /dev/null 2>&1; then
    _version="$(yq -r --arg f "$_feature" '.features[$f] // ""' "$_manifest" 2> /dev/null)" || _version=""
  fi
  if [[ -z "${_version}" || "${_version}" == "null" ]] && command -v python3 > /dev/null 2>&1; then
    _version="$(python3 -c '
import sys
path, feat = sys.argv[1], sys.argv[2]
try:
    import yaml  # type: ignore
    with open(path, encoding="utf-8") as fp:
        data = yaml.safe_load(fp) or {}
except ImportError:
    data = {}
    current = None
    in_features = False
    with open(path, encoding="utf-8") as fp:
        for raw in fp:
            line = raw.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            if line.startswith("features:"):
                in_features = True
                continue
            if in_features:
                if line and not line[0].isspace():
                    in_features = False
                    continue
                stripped = line.strip()
                if ":" in stripped:
                    k, v = stripped.split(":", 1)
                    data.setdefault("features", {})[k.strip()] = v.strip().strip("\"\x27")
feats = (data or {}).get("features") or {}
v = feats.get(feat, "")
if isinstance(v, str):
    print(v)
' "$_manifest" "$_feature" 2> /dev/null)" || _version=""
  fi
  if [[ -z "${_version}" || "${_version}" == "null" ]]; then
    return 1
  fi
  printf '%s\n' "$_version"
}

# ── Shared tarball fetch + verify ────────────────────────────────────────────
# Downloads sysset-<feature>.tar.gz for a feature's <feature>/<X.Y.Z> tag and
# verifies its SHA-256 against the digest field from the GitHub Releases API.
# Best-effort: warns when the API omits the digest; fails on a mismatch.
_fetch_and_verify_tarball() {
  # $1 = feature id, $2 = resolved tag (<feature>/<X.Y.Z>), $3 = destination file
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
    echo "ℹ️  [${_feature}] Resolving per-feature version (spec: '${_spec}')..." >&2
    _resolve_feature_tag "$_feature" "$_spec"
    return $?
  fi
  if [[ -n "$_BUNDLE_TAG" ]]; then
    _version="$(_lookup_bundle_feature_version "$_BUNDLE_MANIFEST_FILE" "$_feature")" || {
      echo "⛔ [${_feature}] Feature not listed in bundle '${_BUNDLE_TAG}' manifest." >&2
      return 1
    }
    echo "ℹ️  [${_feature}] Using bundle ${_BUNDLE_TAG} → version '${_version}'." >&2
    printf '%s/%s\n' "$_feature" "$_version"
    return 0
  fi
  echo "ℹ️  [${_feature}] Resolving latest per-feature release..." >&2
  _resolve_feature_tag "$_feature" ""
}

# ── Feature mode ──────────────────────────────────────────────────────────────
if [[ "$_mode" == "feature" ]]; then
  # Parse optional @feature-version from the feature name.
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

  # Bundle-pinned mode (when no per-feature @spec was provided):
  # SYSSET_VERSION → resolve bundle tag, fetch manifest.yaml.
  if [[ -z "$_feat_version_spec" && -n "${SYSSET_VERSION:-}" ]]; then
    echo "ℹ️  Resolving bundle version (SYSSET_VERSION='${SYSSET_VERSION}')..." >&2
    if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${SYSSET_VERSION}")" || [[ -z "$_BUNDLE_TAG" ]]; then
      echo "⛔ Failed to resolve bundle version (SYSSET_VERSION='${SYSSET_VERSION}'). Is the v<X.Y.Z> release published?" >&2
      exit 1
    fi
    echo "ℹ️  Resolved bundle tag: '${_BUNDLE_TAG}'" >&2
    _BUNDLE_MANIFEST_FILE="$(mktemp)"
    trap 'rm -f "$_BUNDLE_MANIFEST_FILE"; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
    echo "ℹ️  Fetching bundle manifest ${_BUNDLE_TAG}/manifest.yaml..." >&2
    if ! _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE"; then
      echo "⛔ Failed to fetch bundle manifest for '${_BUNDLE_TAG}'. Check network connectivity and that the release asset exists." >&2
      exit 1
    fi
  fi

  if ! _RESOLVED="$(_resolve_install_tag "$_feature" "$_feat_version_spec")" || [[ -z "$_RESOLVED" ]]; then
    echo "⛔ [${_feature}] Failed to resolve install tag (spec: '${_feat_version_spec:-<bundle/latest>}')." >&2
    exit 1
  fi
  echo "ℹ️  [${_feature}] Resolved tag: '${_RESOLVED}'" >&2

  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_lib_tmpdir" "$_tmpdir" ${_BUNDLE_MANIFEST_FILE:+"$_BUNDLE_MANIFEST_FILE"}; logging__cleanup' EXIT

  echo "↪️  Downloading sysset-${_feature} @ ${_RESOLVED} ..." >&2
  if ! _fetch_and_verify_tarball "${_feature}" "${_RESOLVED}" "${_tmpdir}/feature.tar.gz"; then
    echo "⛔ [${_feature}] Failed to download or verify tarball for '${_RESOLVED}'." >&2
    exit 1
  fi

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

# Version priority: per-feature (resolved later) > manifest top-level / SYSSET_VERSION > rolling latest
_manifest_version="$("$_PARSER" -r '.version // ""' "$_MANIFEST")"

# Resolve bundle version once (env wins over manifest top-level).
_bundle_spec=""
if [[ -n "${SYSSET_VERSION:-}" ]]; then
  _bundle_spec="${SYSSET_VERSION}"
  echo "ℹ️  Bundle version spec from SYSSET_VERSION: '${_bundle_spec}'" >&2
elif [[ -n "${_manifest_version}" ]]; then
  _bundle_spec="${_manifest_version}"
  echo "ℹ️  Bundle version spec from manifest .version: '${_bundle_spec}'" >&2
fi

if [[ -n "${_bundle_spec}" ]]; then
  echo "ℹ️  Resolving bundle tag (spec: '${_bundle_spec}')..." >&2
  if ! _BUNDLE_TAG="$(_resolve_bundle_tag "${_bundle_spec}")" || [[ -z "$_BUNDLE_TAG" ]]; then
    echo "⛔ Failed to resolve bundle version (spec: '${_bundle_spec}'). Is the v<X.Y.Z> release published?" >&2
    exit 1
  fi
  echo "ℹ️  Resolved bundle tag: '${_BUNDLE_TAG}'" >&2
  _BUNDLE_MANIFEST_FILE="$(mktemp)"
  # shellcheck disable=SC2064
  trap 'rm -f "$_BUNDLE_MANIFEST_FILE" ${_json_manifest:+"$_json_manifest"}; rm -rf "$_lib_tmpdir"; logging__cleanup' EXIT
  echo "ℹ️  Fetching bundle manifest ${_BUNDLE_TAG}/manifest.yaml..." >&2
  if ! _fetch_bundle_manifest "$_BUNDLE_TAG" "$_BUNDLE_MANIFEST_FILE"; then
    echo "⛔ Failed to fetch bundle manifest for '${_BUNDLE_TAG}'. Check network connectivity and that the release asset exists." >&2
    exit 1
  fi
else
  echo "ℹ️  No bundle pin — rolling per-feature resolution." >&2
fi

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

# ── Feature runner ────────────────────────────────────────────────────────────
_run_feature() {
  local _feature="$1"
  local _resolved_tag="$2"
  shift 2
  local _opts=("$@")

  local _tmpdir
  _tmpdir="$(mktemp -d)"

  echo "ℹ️  [${_feature}] Downloading @ ${_resolved_tag} ..." >&2
  if ! _fetch_and_verify_tarball "${_feature}" "${_resolved_tag}" "${_tmpdir}/feature.tar.gz"; then
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
  # Per-feature version spec (if any) overrides the bundle pin.
  # shellcheck disable=SC2016
  _feat_version_spec="$("$_PARSER" -r \
    --arg feat "$_feature" \
    '.features[] | select(.id == $feat) | .version // ""' \
    "$_MANIFEST")"

  _feat_resolved=""
  if ! _feat_resolved="$(_resolve_install_tag "$_feature" "$_feat_version_spec")"; then
    echo "⛔ [${_feature}] Failed to resolve tag (spec: '${_feat_version_spec:-<bundle/latest>}')." >&2
    _failed+=("$_feature")
    continue
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
