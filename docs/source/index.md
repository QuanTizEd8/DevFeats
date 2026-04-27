# SysSet

**Declarative System Setup for Containers, Virtual Machines, and Host Environments**

**SysSet** is a tool for installing software and configuring environments in a consistent, reproducible way across containers, virtual machines, and physical computers running macOS or any major Linux distribution. It enables users to declare a single recipe and use it on any platform to set up the same environment.
SysSet consists of a collection of ***features*** — modular, specialized software installers and setup scripts with a rich options surface to customize their behavior and configuration. Features are published as self-contained tarballs compliant with the [Development Container Features Specification](https://containers.dev/implementors/features/), and can be downloaded and executed with a single command on any system, with no requirements other than a POSIX-compliant shell. They can also be referenced from a [`devcontainer.json`](https://containers.dev/implementors/json_reference/) file and installed automatically when the container is built by VS Code, GitHub Codespaces, or any other spec-compliant tool. Additionally, SysSet provides an installer that can take any `devcontainer.json` file and execute the entire installation process directly on the running machine, allowing the same configuration to be used for both containerized and non-containerized setups.

---

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} User Guide
:class-title: sd-text-center
:link: manual/index
:link-type: doc

Read more about how to use SysSet: quickstart guide, installation methods and options, recipes, version pinning, and other general user documentation.
:::

:::{grid-item-card} Feature Reference
:class-title: sd-text-center
:link: features/index
:link-type: doc

Navigate all available features and their documentation: options, examples, defaults, and other per-feature details.
:::

:::{grid-item-card} Background Knowledge
:class-title: sd-text-center
:link: learn/index
:link-type: doc

Learn about the concepts and tools that SysSet builds on: POSIX shells, package managers, Dev Containers, configuration files, shell profiles, environment variables, and other background knowledge.
:::

:::{grid-item-card} Contribution Guide
:class-title: sd-text-center
:link: dev/index
:link-type: doc

Find out how to contribute to SysSet: feedback, bug report, feature request, developer guide, donations, and other ways to get involved.
:::

::::
