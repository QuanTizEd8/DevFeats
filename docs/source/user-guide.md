# User Guide

This guide provides general instructions for installing and using features. For a complete list of available features and detailed documentation on each, see the [Features](features.md).

## Quickstart Guide

Create a `devcontainer.json` file and add the features you want to use in the `features` property, for example:

```jsonc
{
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-os-pkg": {},
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-user": {},
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/setup-shell": {},
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-git": {},
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-gh": {},
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-pixi": {},
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-just": {}
  },
  // other properties...
}
```

You can then use any [Dev Container supporting tool](https://containers.dev/supporting) such as [VS Code](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers), or [Dev Container CLI](https://github.com/devcontainers/cli) to build and start your container, which will automatically install the specified features. Outside of a Dev Container context, you can use [SysSet](https://github.com/repodynamics/sysset) or download and install features manually from their release artifacts. For detailed instructions on different installation contexts, see the [Installation Guide](user-guide/installation.md).

## Learn More

<br>

::::{grid} 1
:gutter: 3

:::{grid-item-card} Installation Guide
:class-title: sd-text-center
:link: user-guide/installation
:link-type: doc

Learn how to install features in different contexts: dev containers, virtual machines, and personal computers.
:::

:::{grid-item-card} Feature Options
:class-title: sd-text-center
:link: user-guide/options
:link-type: doc

Learn how to customize features with options in different installation contexts.
:::

:::{grid-item-card} Versioning
:class-title: sd-text-center
:link: user-guide/versioning
:link-type: doc

Learn about feature versioning and how to pin versions for stability, reproducibility, and security.
:::

:::{grid-item-card} Technical Details
:class-title: sd-text-center
:link: user-guide/technical
:link-type: doc

Learn about the technical details of how features are built, released, and installed.
:::

::::
