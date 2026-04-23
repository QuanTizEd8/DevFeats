# Introduction

Features are distributed in two forms:

| Form | Use case |
|---|---|
| **Dev Container features** (GHCR) | `devcontainer.json`-driven container builds |
| **Standalone installers** (GitHub Releases) | VMs, CI runners, WSL2, physical machines |


## As Dev Container features

Add any feature to `.devcontainer/devcontainer.json`:

```jsonc
{
  "image": "ubuntu:24.04",
  "features": {
    "ghcr.io/quantized8/sysset/setup-user:0": {
      "username": "dev"
    },
    "ghcr.io/quantized8/sysset/install-shell:0": {
      "ohmyzsh_theme": "romkatv/powerlevel10k",
      "set_user_shells": "zsh"
    },
    "ghcr.io/quantized8/sysset/install-pixi:0": {}
  }
}
```

The major version tag (`:0`, `:1`, …) pins the feature API while still receiving patch updates. For a fully pinned build use the full semver tag (`:1.2.3`).

See the individual feature reference pages for all available options.

---

## As standalone installers

The entry point is `get.sh`, a POSIX sh bootstrap that lives in the repository. It finds or installs bash ≥ 4, downloads `get.bash` (the full implementation), and hands off execution. All arguments are forwarded verbatim.

### Requirements

- `curl` or `wget`
- bash ≥ 4 (installed automatically if absent, using the system package manager)
- Root or `sudo` access (required by most features)

### Single feature — inline (pipe)

The fastest way to install one feature: pipe `get.sh` directly into the shell.

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh | \
  sh -s -- install-pixi
```

Pass feature options after `--`:

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh | \
  sh -s -- install-pixi --version 0.66.0

curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh | \
  sh -s -- install-shell --set_user_shells zsh --ohmyzsh_theme romkatv/powerlevel10k

curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh | \
  sh -s -- install-fonts --nerd_fonts Meslo,FiraCode
```

### Single feature — downloaded script

Download `get.sh` once and run it repeatedly:

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh -o get.sh

sh get.sh install-pixi --version 0.66.0
sh get.sh install-shell --set_user_shells zsh
sh get.sh setup-user --username dev
```

### Pinning a feature version

Every feature is versioned and released independently. By default, `get.sh` installs each feature's latest published release. To pin a specific feature to a specific version, append `@<version>` to the feature name. Partial semver is supported: `@1` resolves to the latest `1.x.x`, `@1.2` resolves to the latest `1.2.x`.

```sh
# Pin install-pixi to the latest 1.x release
sh get.sh install-pixi@1

# Pin install-pixi to the latest 1.2.x release
sh get.sh install-pixi@1.2

# Pin install-pixi to an exact release
sh get.sh install-pixi@1.2.3

# Pin install-pixi AND pass --version to its installer
sh get.sh install-pixi@1.2 --version 0.66.0
```

The `@version` pin only affects which sysset tarball is downloaded for that feature. Feature options (like `--version 0.66.0` above) are passed through to the installer unchanged. Other features installed in the same run are resolved independently.

Under the hood, per-feature releases are published with the Git tag scheme `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`). Each release ships exactly one asset, `sysset-<feature-id>.tar.gz`.

### Pinning the bundle version

Every CD run also publishes an accumulator-tagged **bundle release** — a single `v<X.Y.Z>` tag whose version is derived from the highest per-feature bump in that run. Each bundle release contains:

- `sysset-all.tar.gz` — every feature's tarball, flat layout.
- `manifest.yaml` — a machine-readable map of the feature versions contained in this bundle (used by `get.bash` for pin resolution).

Set `SYSSET_VERSION` to pin every feature installed in a run to the versions listed in that bundle's `manifest.yaml`:

```sh
# Pin every feature to the versions shipped in bundle v1.2.0
SYSSET_VERSION=v1.2.0 sh get.sh install-pixi install-shell

# Partial specs and 'latest' also work — resolved against v* bundle tags
SYSSET_VERSION=v1.2  sh get.sh install-pixi
SYSSET_VERSION=v1    sh get.sh install-pixi
SYSSET_VERSION=latest sh get.sh install-pixi
```

Or inside a manifest via a top-level `version:` key (see [Manifest-driven installation](#manifest-driven-installation)):

```yaml
version: v1.2.0       # pin all features to the bundle's manifest
features:
  - id: install-pixi
  - id: install-shell
```

A per-feature `@<version>` override always wins over a bundle pin — useful to take a point-fix on a single feature without giving up the pinned set for the others:

```sh
# Pin everything to v1.2.0, except install-pixi which rolls to its latest 1.4.x
SYSSET_VERSION=v1.2.0 sh get.sh install-pixi@1.4 install-shell
```

**When to use which:**

| Mode | Use when |
|---|---|
| Rolling (no pin) | Dev loops; always want the latest of each feature. |
| Per-feature `@spec` | Reproduce a specific feature version (hotfix, bisect). |
| Bundle `SYSSET_VERSION` | Reproducible multi-feature snapshot; offline/air-gapped setups. |

### Running a single feature tarball directly

Every per-feature release ships a self-contained tarball. Download and extract it to run entirely offline, or to inspect its contents before running:

```sh
# Exact per-feature release (tag scheme: <feature>/<X.Y.Z>)
curl -fsSL https://github.com/quantized8/sysset/releases/download/install-pixi/1.2.3/sysset-install-pixi.tar.gz \
  | tar xz -C /tmp/pixi
sh /tmp/pixi/install.sh --version 0.66.0
```

To fetch the latest of a single feature without knowing the version up-front, use the bundle's `manifest.yaml` as an index (see [Offline / air-gapped use](#offline--air-gapped-use)) or let `get.sh` do the resolution:

```sh
sh get.sh install-pixi
```

The tarball contains:
- `install.sh` — POSIX sh bootstrap (handles bash ≥ 4 on any platform)
- `install.bash` — real bash ≥ 4 installer
- `_lib/` — full copy of the shared library (no network access needed)
- `dependencies/` — OS package manifest (when the feature has one)
- `files/` — supplementary files (when the feature has them)

---

## Manifest-driven installation

To install multiple features in one invocation, pass a manifest file to `get.sh`. The manifest lists features and their options; `get.sh` resolves and installs them in [canonical order](#canonical-install-order).

### Manifest format

**JSON:**

```jsonc
{
  "version": "v1.2.0",               // optional — pin all features to bundle v1.2.0's manifest
  "override_install_order": false,   // true to keep manifest order instead of canonical order
  "features": [
    { "id": "setup-user",        "options": { "username": "dev" } },
    { "id": "install-homebrew",  "options": { "update": true } },
    { "id": "install-shell",     "options": { "set_user_shells": "zsh", "ohmyzsh_theme": "romkatv/powerlevel10k" } },
    { "id": "install-miniforge", "options": { "version": "latest" } },
    { "id": "install-pixi",      "version": "1.2", "options": { "version": "0.66.0" } },
    { "id": "install-fonts",     "options": { "nerd_fonts": "Meslo", "p10k_fonts": true } }
  ]
}
```

**YAML** (requires `yq`; auto-installed if absent):

```yaml
version: v1.2.0           # optional — bundle pin (applies to every feature by default)
override_install_order: false
features:
  - id: setup-user
    options:
      username: dev
  - id: install-shell
    options:
      set_user_shells: zsh
      ohmyzsh_theme: romkatv/powerlevel10k
  - id: install-pixi
    version: "1.4"         # per-feature override (takes precedence over the bundle pin)
    options:
      version: "0.66.0"    # pixi version (passed to the installer)
```

**Version priority (highest to lowest):** per-feature `"version"` (a `<feature>/<X.Y.Z>` spec — rolling mode) → manifest top-level `"version"` (a bundle `v<X.Y.Z>` spec) → `SYSSET_VERSION` env var (also a bundle spec) → each feature's latest per-feature release.

### Running a manifest

```sh
# Download get.sh once
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh -o get.sh

# Run against a local manifest
sudo sh get.sh my-setup.json
sudo sh get.sh my-setup.yaml
```

Or inline:

```sh
curl -fsSL https://raw.githubusercontent.com/quantized8/sysset/main/get.sh | \
  sudo sh -s -- my-setup.json
```

`get.sh` prints a pass/fail summary after all features have been processed. A non-zero exit code is returned if any feature fails, but remaining features are still attempted.

---

## Canonical install order

When `override_install_order` is `false` (the default), features are always installed in a dependency-safe order regardless of their order in the manifest:

```
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
```

Features not in this list are appended at the end in the order they appear in the manifest. Set `"override_install_order": true` to disable sorting and use manifest order verbatim.

---

## Options reference

| Option | Default | Description |
|---|---|---|
| `--logfile <path>` | — | Append full log output to this file on exit |
| `--debug` | off | Enable `bash -x` trace for the installer |
| `--help`, `-h` | — | Print usage and exit |

---

## Environment variables

| Variable | Description |
|---|---|
| `SYSSET_RAW_BASE` | Raw GitHub base URL. Default: `https://raw.githubusercontent.com/quantized8/sysset/main`. Override to use a fork or local mirror. |
| `SYSSET_BASE_URL` | GitHub Releases base URL for feature tarballs. Default: `https://github.com/quantized8/sysset/releases/download`. URLs are constructed as `<base>/<feature>/<X.Y.Z>/sysset-<feature>.tar.gz` for per-feature releases and `<base>/v<X.Y.Z>/manifest.yaml` for bundle manifests. Override for offline use (see below). |
| `SYSSET_VERSION` | Pin every feature installed in this run to the versions listed in the given bundle release (e.g. `v1.2.0`, `v1.2`, `v1`, or `latest`). Equivalent to a top-level `version:` key in a manifest. Per-feature `@<spec>` overrides still win. |
| `SYSSET_FETCH_TOOL` | Force `curl` or `wget`. Auto-detected when unset. |

---

## Offline / air-gapped use

Each CD run publishes an accumulator-tagged **bundle release** (`v<X.Y.Z>`) whose assets are `sysset-all.tar.gz` (every feature's tarball, flat layout) and `manifest.yaml` (the canonical per-feature version map for that bundle). Pick the bundle you want to freeze against — or use the latest:

```sh
# Pick a bundle and fetch its two assets
VERSION=v1.2.0
curl -fsSL "https://github.com/quantized8/sysset/releases/download/${VERSION}/sysset-all.tar.gz" \
  | tar xz -C /opt/sysset
curl -fsSL "https://github.com/quantized8/sysset/releases/download/${VERSION}/manifest.yaml" \
  -o /opt/sysset/manifest.yaml

# Run an individual feature tarball directly
tar xz -C /tmp/pixi < /opt/sysset/sysset-install-pixi.tar.gz
sh /tmp/pixi/install.sh --version 0.66.0
```

For manifest-driven offline installs, build a local mirror that mirrors the GitHub Releases URL layout (`<base>/<feature>/<X.Y.Z>/sysset-<feature>.tar.gz` for per-feature assets and `<base>/v<X.Y.Z>/manifest.yaml` for the bundle manifest), then point `SYSSET_BASE_URL` at it:

```sh
VERSION=v1.2.0

# Build the mirror layout from the extracted bundle + manifest.yaml.
mkdir -p /opt/sysset-mirror/${VERSION}
cp /opt/sysset/manifest.yaml /opt/sysset-mirror/${VERSION}/

# Stage each per-feature tarball under <feature>/<X.Y.Z>/.
python3 - <<'PY'
import pathlib, shutil, yaml
m = yaml.safe_load(pathlib.Path("/opt/sysset/manifest.yaml").read_text())
root = pathlib.Path("/opt/sysset-mirror")
src  = pathlib.Path("/opt/sysset")
for feat, ver in m["features"].items():
    dst = root / feat / ver
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / f"sysset-{feat}.tar.gz", dst / f"sysset-{feat}.tar.gz")
PY

# Use get.sh with the local mirror, pinned to the bundle.
SYSSET_BASE_URL="file:///opt/sysset-mirror" \
SYSSET_VERSION="${VERSION}" \
  sh get.sh my-setup.json
```

With `SYSSET_VERSION` set, `get.sh` first fetches `manifest.yaml` from the mirror, then resolves each feature's version from it before downloading `<feature>/<X.Y.Z>/sysset-<feature>.tar.gz`. This keeps the install fully reproducible.

`get.sh` itself still downloads `get.bash` and `lib/*.sh` from `SYSSET_RAW_BASE` (raw GitHub). For a fully air-gapped environment, also override that:

```sh
# Serve the repo locally, then:
SYSSET_RAW_BASE="http://my-mirror.internal/sysset" \
SYSSET_BASE_URL="file:///opt/sysset-mirror" \
SYSSET_VERSION="v1.2.0" \
  sh get.sh my-setup.json
```

