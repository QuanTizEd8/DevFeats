# Installation Guide

Features are packaged as self-contained tarballs compliant with the [Dev Container Features Specification](https://containers.dev/implementors/features/), versioned according to Semantic Versioning, and [released](releases.md) as immutable artifacts to both [GitHub Container Registry](https://github.com/|{{github_user}}|?tab=packages&repo_name=|{{github_repo}}|) (GHCR) and [GitHub Releases](https://github.com/|{{github_user}}|/|{{github_repo}}|/releases). They can be downloaded and installed in any POSIX-compliant environment, including physical machines (e.g. to set up a new laptop or update a PC), virtual machines (e.g. to set up a cloud VM such as a GitHub Actions runner), containers (e.g. as a RUN instruction in a Dockerfile or executed inside a running container), and Dev Containers — with the same behavior across all platforms and installation methods.

## Dev Container Installation

To install features in a Dev Container, simply add their OCI registry references to the `features` object in your [`devcontainer.json`](https://containers.dev/implementors/json_reference/) file (with optional [version tag](versioning.md) and [options](options.md)). Features are published to GHCR under `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>`, with tags for major, minor, and patch versions (and a rolling `latest` tag). For example:

```jsonc
// devcontainer.json
{
  "features": {

    // latest version (no tag) with default options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user": {},

    // latest version ('latest' tag) with overridden options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell:latest": {
      "ohmyzsh_theme":   "romkatv/powerlevel10k",
      "set_user_shells": "zsh"
    },

    // specific major version with default options
     "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git:0": {},

    // specific minor version with overridden options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1": {
      "version": "2.89.0"
    },

    // specific patch version with default options
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-miniforge:0.1.0": {}
  },
  // other properties...
}
```

Features are then downloaded, [ordered](installation-order.md), and installed automatically when the container is built by [VS Code](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers), [`@devcontainers/cli`](https://github.com/devcontainers/cli), or any other [supporting tools](https://containers.dev/supporting).


## Universal Installation

Outside Dev Containers, features can be installed either using SysSet, or directly from their release artifacts.
**Re-runs are idempotent** — installers check for already-done work and skip it, so you can rerun after fixing an environment issue without uninstalling first.


### SysSet Installation

This is the recommended method for installing features outside Dev Containers. SysSet is a Dev Container supporting tool that can install any Dev Container Feature on any compatible platform, with the same behavior as if it were running inside a container. It provides a convenient CLI interface, handles all the plumbing around downloading and invoking features, and correctly handles all Dev Container specific configurations such as dependency resolution, installation order, and lifecycle hooks. It can be used to install features one at a time:

```sh
sysset feat install ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1 --version 2.89.0
```

or even whole environments defined by `devcontainer.json` files:

```sh
sysset env install /path/to/devcontainer.json
```

### Direct Installation

Features can also be installed directly from their release artifacts, without using SysSet. This involves:

1. download the corresponding asset from GHCR or GitHub Releases,
2. extract the tarball,
3. execute the included script with the desired feature options.

For example, the same installation process for the following `devcontainer.json` entry

```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0": {
      "version": "2.89.0"
    }
  }
}
```

can be performed directly on the command line using:

```sh
TMP_DIR=$(mktemp -d) && \
oras pull \
  ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0 \
  --output install-gh.tar.gz && \
tar -xzf install-gh.tar.gz -C $TMP_DIR && \
sudo sh $TMP_DIR/install.sh --version 2.89.0 && \
rm -rf $TMP_DIR install-gh.tar.gz
```

When building the container, the Dev Container supporting tool effectively performs the same process under the hood — downloading the feature's tarball from GHCR, extracting it, and running the same `install.sh` with the options specified in the corresponding `devcontainer.json` entry. However, there are two aspects where the Dev Container experience differs:

1. **Installation order.** Some features are better installed before others (e.g. a feature that sets up a user should generally run before a feature that installs packages for that user). Dev Container features can declare hard and soft dependencies on other features, which are used by supporting tools to determine the correct installation order. When installing features directly from their artifacts, you need to ensure that you install them in the correct order yourself. You can check the documentation of each feature for any hard or soft dependencies it may have.
2. **Dev Container specific configurations.** Dev Container features can declare specific settings in their [`devcontainer-feature.json`](https://containers.dev/implementors/features/#devcontainer-feature-json-properties) metadata file, which are used by supporting tools to configure different aspects of the container (e.g. adding mount points, setting privileges, or running commands at specific points during the container lifecycle). When installing features directly from their artifacts, these settings are ignored, so some features may not work as expected or may require additional manual configuration to work correctly. However, this is a minor concern for most features, as the majority of their functionality is implemented in the installer script and does not rely on Dev Container specific configurations. Additionally, most Dev Container specific configurations are irrelevant outside of containers. You can check the documentation of each feature for any special considerations when installing outside of a Dev Container.


#### Download

##### From GHCR

Features are published to GHCR under `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>`, with tags for major, minor, and patch versions (and a rolling `latest` tag). To download a feature from GHCR, the best way is to use a networking tool that recognizes the [OCI Artifact Distribution Specification](https://github.com/opencontainers/distribution-spec), such as [`oras`](https://github.com/oras-project/oras). For example:

```sh
# Download 'install-gh' version '0.1.0' and save as 'install-gh.tar.gz'
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh:0.1.0 --output install-gh.tar.gz

# Download latest 'install-git' and save as 'install-git.tar.gz'
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git:latest --output install-git.tar.gz

# Download latest 0.1.x version of 'install-miniforge' and save as 'install-miniforge.tar.gz'
oras pull ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-miniforge:0.1 --output install-miniforge.tar.gz
```

##### From GitHub Releases

Features are published to GitHub Releases under `<base>/<feature-id>/<version>/sysset-<feature-id>-<version>.tar.gz`, where `<base>` is `https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download`. To download a feature from GitHub Releases, you can use any networking tool (e.g. `curl` or `wget`) to download the corresponding asset. For example:

```sh
# Use curl to download 'install-gh' version '0.1.0' and save as 'install-gh.tar.gz'
ID=install-gh VERSION=0.1.0 curl -fsSL \
  https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/$ID/$VERSION/sysset-$ID-$VERSION.tar.gz \
  -o install-gh.tar.gz

# Use wget to download 'install-git' version '0.1.0' and save as 'install-git.tar.gz'
ID=install-git VERSION=0.1.0 wget -qO- \
  https://github.com/|{{github_user}}|/|{{github_repo}}|/releases/download/$ID/$VERSION/sysset-$ID-$VERSION.tar.gz \
  -O install-git.tar.gz
```

Note that GitHub Releases only supports a single tag per release, so you can only download a specific version (e.g. `0.1.0`), while GHCR supports multiple tags per release, allowing you to download the latest version of a major or minor release (e.g. `0.1` or `latest`).

#### Extract

After downloading the feature's tarball, you need to extract it with a tarball extraction tool (e.g. `tar`):

```sh
tar -xzf install-gh.tar.gz -C /path/to/extract
```

#### Execute

After extracting the tarball, you can navigate to the extracted directory and use a POSIX-compliant shell (e.g. `sh` or `bash`) to run the included `install.sh` script with the desired options passed as [CLI flags](options.md):

```sh
sudo sh /path/to/extract/install.sh --version 2.89.0
```

:::{note}

`sudo` is required when a feature writes to system directories (almost all of them do). Dev container tooling already runs feature installs as root; with `install.sh` you need to supply the privilege yourself.
:::
