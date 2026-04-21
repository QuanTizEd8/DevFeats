# Intro


## Quick Start

Every release publishes to two registries simultaneously:

| Artifact | Location |
|---|---|
| Dev Container features | `ghcr.io/quantized8/sysset/<feature>:<version>` |
| `get.sh` | GitHub Releases → `get.sh` |
| Per-feature tarballs | GitHub Releases → `sysset-<feature>.tar.gz` |
| All-in-one bundle | GitHub Releases → `sysset-all.tar.gz` |

```sh
# Install from GHCR (devcontainer.json)
ghcr.io/quantized8/sysset/install-pixi:0

# Install standalone (latest release)
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/get.sh | \
  sh -s -- install-pixi --version 0.66.0
```

---



### As Dev Container features

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

### As standalone installers — single feature

Download and run any feature in one line (requires `curl` or `wget`):

```sh
# Install a specific feature from the latest release
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/get.sh | \
  sh -s -- install-pixi --version 0.66.0

# Pin to a specific release
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/get.sh | \
  sh -s -- install-pixi --tag v1.0.0 --version 0.66.0
```

Or download the tarball and run offline:

```sh
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/sysset-install-pixi.tar.gz \
  | tar xz -C /tmp/sysset-pixi
bash /tmp/sysset-pixi/install.sh --version 0.66.0
```

### As standalone installers — manifest-driven

Download the all-in-one bundle and drive multiple features from a single manifest:

```sh
curl -fsSL https://github.com/quantized8/sysset/releases/latest/download/sysset-all.tar.gz \
  | tar xz -C /opt/sysset
sudo bash /opt/sysset/scripts/sysset.sh my-setup.json
```

**`my-setup.json`:**

```jsonc
{
  "features": [
    { "id": "setup-user",       "options": { "username": "dev" } },
    { "id": "install-shell",    "options": { "ohmyzsh_theme": "romkatv/powerlevel10k", "set_user_shells": "zsh" } },
    { "id": "install-miniforge","options": { "version": "latest" } },
    { "id": "install-pixi",     "options": { "version": "0.66.0" } }
  ]
}
```

Features are always installed in a safe [canonical order](#canonical-install-order) regardless of how they appear in the manifest.



## Standalone Distribution

Every feature is also available as a self-contained tarball, with no Docker or devcontainer tooling required. Perfect for provisioning VMs, CI runners, WSL2, or physical machines.

### `get.sh` — single feature

```sh
# Usage
get.sh <feature> [--tag <release-tag>] [<feature-options>...]

# Examples
sh get.sh install-shell --set_user_shells zsh
sh get.sh install-pixi --version 0.66.0
sh get.sh install-fonts --nerd_fonts Meslo,FiraCode --p10k_fonts true
sh get.sh install-miniforge --version latest --bin_dir /opt/conda
```

`get.sh` is version-stamped at build time and always downloads from the same release it was bundled with. Use `--tag` to override.

### `sysset.sh` — manifest-driven

```sh
# Usage (from an extracted sysset-all.tar.gz)
sudo bash scripts/sysset.sh <manifest.json|.yaml> [OPTIONS]

Options:
  --tag <tag>       Override the release tag for all downloads
  --logfile <path>  Tee output to a file
  --debug           Enable set -x trace
```

**JSON manifest:**

```jsonc
{
  "tag": "v1.0.0",                   // optional — pin to a specific release
  "override_install_order": false,   // true to keep manifest order
  "features": [
    { "id": "setup-user",        "options": { "username": "dev" } },
    { "id": "install-homebrew",  "options": { "update": true } },
    { "id": "install-shell",     "options": { "ohmyzsh_theme": "romkatv/powerlevel10k", "set_user_shells": "zsh" } },
    { "id": "install-miniforge", "options": { "version": "latest" } },
    { "id": "install-pixi",      "options": { "version": "0.66.0" } },
    { "id": "install-fonts",     "options": { "nerd_fonts": "Meslo", "p10k_fonts": true } }
  ]
}
```

**YAML manifest** (requires `yq`; auto-installed):

```yaml
features:
  - id: setup-user
    options:
      username: dev
  - id: install-shell
    options:
      ohmyzsh_theme: romkatv/powerlevel10k
      set_user_shells: zsh
  - id: install-pixi
    options:
      version: "0.66.0"
```

### Canonical install order

Features are always installed in dependency-safe order unless `override_install_order: true`:

```
setup-user → install-homebrew → install-os-pkg → install-shell
→ install-miniforge → install-conda-env → install-pixi
→ install-podman → install-fonts → setup-shim
```

Unknown feature IDs (not in the list above) are appended at the end in manifest order.

### Offline / air-gapped use

Extract `sysset-all.tar.gz` — it contains all per-feature tarballs alongside `scripts/sysset.sh`. The orchestrator automatically prefers co-located tarballs over network downloads:

```sh
tar xzf sysset-all.tar.gz -C /opt/sysset
sudo bash /opt/sysset/scripts/sysset.sh my-setup.json  # fully offline
```

---
