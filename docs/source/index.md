# |{{project_name}}|

**Declarative System Setup Tools as Dev Container Features and Self-Contained Installers**

<p align="justify">
<strong>SysSet</strong> is a collection of <strong><em>features</em></strong> — modular, specialized scripts for installing software and configuring environments in a <strong>declarative</strong>, <strong>reproducible</strong>, and <strong>portable</strong> way across containers, virtual machines, and physical computers with different architectures and operating systems. Features are distributed as self-contained tarballs compliant with the <a href=https://containers.dev/implementors/features/>Development Container Features Specification</a>; they can be referenced from a <a href=https://containers.dev/implementors/json_reference/>devcontainer.json</a> file and installed automatically when the container is built by VS Code, GitHub Codespaces, or any other spec-compliant tool. They can also be downloaded and executed directly with a single command on any system running macOS or any major Linux distribution, with no requirements other than a POSIX-compliant shell. Features provide a rich options surface to customize their behavior and configuration. They are thoroughly documented and tested, with a consistent design and user experience across the board.
</p>

---

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} Introduction
:class-title: sd-text-center
:link: intro
:link-type: doc

Learn about the motivation and goals behind |{{project_name}}|, the problems it solves, and how it compares to other tools in the ecosystem.
:::


:::{grid-item-card} User Guide
:class-title: sd-text-center
:link: user-guide
:link-type: doc

Find out how to use |{{project_name}}|: installation guide, customization, versioning, examples, and other general usage details.
:::

:::{grid-item-card} Features
:class-title: sd-text-center
:link: features
:link-type: doc

Navigate all available features and their documentation: options, examples, defaults, and other per-feature details.
:::

:::{grid-item-card} Background Knowledge
:class-title: sd-text-center
:link: background
:link-type: doc

Learn about the concepts and tools that |{{project_name}}| builds on: shells, package managers, Dev Containers, environment variables, and other background knowledge.
:::

:::{grid-item-card} Developer Guide
:class-title: sd-text-center
:link: dev-guide
:link-type: doc

Find out how to contribute to |{{project_name}}|: feedback, bug report, feature request, developer guide, donations, and other ways to get involved.
:::

::::
