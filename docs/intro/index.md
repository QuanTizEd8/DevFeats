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

### Pinning the sysset release version

By default, `get.sh` downloads the latest sysset release. To pin to a specific release, append `@<version>` to the feature name. Partial semver is supported: `@1` resolves to the latest `v1.x.x`, `@1.2` resolves to the latest `v1.2.x`.

```sh
# Pin to the latest v1.x release
sh get.sh install-pixi@1

# Pin to the latest v1.2.x release
sh get.sh install-pixi@1.2

# Pin to an exact release
sh get.sh install-pixi@1.2.3

# Pin the sysset release AND pass --version to the pixi installer
sh get.sh install-pixi@1.2 --version 0.66.0
```

The `@version` pin applies only to which sysset release tarball is downloaded. Feature options (like `--version 0.66.0` above) are passed through to the installer unchanged.

### Running a single feature tarball directly

Every release publishes a self-contained tarball per feature. Download and extract it to run entirely offline, or to inspect its contents before running:

```sh
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/sysset-install-pixi.tar.gz \
  | tar xz -C /tmp/pixi
sh /tmp/pixi/install.sh --version 0.66.0
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
  "version": "1",                    // optional — pin all features to sysset v1.x
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
version: "1"
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
    version: "1.2"       # per-feature sysset version pin
    options:
      version: "0.66.0"  # pixi version (passed to the installer)
```

**Version priority (highest to lowest):** per-feature `"version"` key → manifest top-level `"version"` key → latest release.

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
| `SYSSET_BASE_URL` | GitHub Releases base URL for feature tarballs. Default: `https://github.com/quantized8/sysset/releases/download`. Override for offline use (see below). |
| `SYSSET_FETCH_TOOL` | Force `curl` or `wget`. Auto-detected when unset. |

---

## Offline / air-gapped use

Download the all-in-one bundle from the release you want to use. It contains all per-feature tarballs in a flat layout.

```sh
# Download and extract the bundle
VERSION=v1.2.3
curl -fsSL "https://github.com/quantized8/sysset/releases/download/${VERSION}/sysset-all.tar.gz" \
  | tar xz -C /opt/sysset

# Run individual tarballs directly (fully offline)
sh /opt/sysset/sysset-install-pixi.tar.gz      # won't work — extract first
tar xz -C /tmp/pixi < /opt/sysset/sysset-install-pixi.tar.gz
sh /tmp/pixi/install.sh --version 0.66.0
```

For manifest-driven offline installs, point `SYSSET_BASE_URL` at a directory tree structured as `<base>/<tag>/sysset-<feature>.tar.gz`. Create that layout from the extracted bundle:

```sh
VERSION=v1.2.3
mkdir -p /opt/sysset-mirror/${VERSION}
cp /opt/sysset/sysset-*.tar.gz /opt/sysset-mirror/${VERSION}/

# Now use get.sh with the local mirror
SYSSET_BASE_URL="file:///opt/sysset-mirror" \
  sh get.sh my-setup.json
```

`get.sh` itself still downloads `get.bash` and `lib/*.sh` from `SYSSET_RAW_BASE` (raw GitHub). For a fully air-gapped environment, also override that:

```sh
# Serve the repo locally, then:
SYSSET_RAW_BASE="http://my-mirror.internal/sysset" \
SYSSET_BASE_URL="file:///opt/sysset-mirror" \
  sh get.sh my-setup.json
```

