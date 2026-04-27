# SysSet

**Declarative System Setup for Containers, Virtual Machines, and Host Environments**

**SysSet** is a tool for installing software and configuring environments in a consistent, reproducible way across containers, virtual machines, and physical computers running macOS or any major Linux distribution. It enables users to declare a platform-agnostic recipe in a single configuration file, and use it on any machine to set up the same environment with a single command.
SysSet consists of a collection of ***features*** — modular, specialized software installers and setup scripts with a rich options surface to customize their behavior and configuration. Each feature is published as a self-contained tarball available through two channels:

1. [GitHub Release Artifacts](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) that can be downloaded and executed with a single command on any system, with no requirements other than a POSIX-compliant shell.
2. [Dev Container Features](https://containers.dev/implementors/features/) that can be referenced from a [`devcontainer.json`](https://containers.dev/implementors/json_reference/) file and installed automatically when the container is built by VS Code, GitHub Codespaces, or any other spec-compliant tool.

SysSet's installer can also take a `devcontainer.json` file and execute the whole installation process directly on the running machine without any container involved, allowing the same configuration file to be used for both containerized and non-containerized setups.

---

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} User Guide
:class-title: sd-text-center
:link: manual/index
:link-type: doc

Quickstart guide, installation methods, manifests, versioning, and other general user documentation.
:::

:::{grid-item-card} Feature Reference
:class-title: sd-text-center
:link: features/index
:link-type: doc

Feature descriptions, options, defaults, examples, and other details.
:::

:::{grid-item-card} Background Knowledge
:class-title: sd-text-center
:link: learn/index
:link-type: doc

Dev Containers, configuration files, shell profiles, environment variables, and other background knowledge.
:::

:::{grid-item-card} Contribution Guide
:class-title: sd-text-center
:link: dev/index
:link-type: doc

Feedback, bug report, feature request, developer guide, donation.
:::

::::
