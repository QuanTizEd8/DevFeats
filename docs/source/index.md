# SysSet

**Declarative System Setup for Containers, Virtual Machines, and Host Environments**

**SysSet** is a tool for installing software and configuring environments in a consistent, repeatable way across containers, virtual machines, and physical computers running macOS or any major Linux distribution. It enables users to declare a platform-agnostic system state in a single configuration file, and use it on any machine to set up a complete environment with a single command.

SysSet consists of a collection of ***features*** — modular, specialized software installers and setup scripts with a rich options surface to customize their behavior and configuration. All features are available through **two** channels:

1. Self-contained files that can be downloaded from [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) and executed directly on any supported platform, with no requirements other than a POSIX-compliant shell. This method can be used universally on host machines (e.g. set up a new laptop, update a PC), virtual machines (e.g. CI runner, Cloud VM, WSL2 distro), and containers (e.g. RUN instruction in a Dockerfile, executing inside a running container).
2. [Dev Container Features](https://containers.dev/implementors/features/) that can be referenced in a [`devcontainer.json`](https://containers.dev/implementors/json_reference/) file and automatically installed when the container is built or started by a supporting tool (e.g. VS Code, GitHub Codespaces, JetBrains Projector).

In addition, SysSet provides an ***orchestrator*** — a single downloadable script that can take a `devcontainer.json` file as input and execute the same installation process as a Dev Container supporting tool, but directly on the running machine without any requirements. This means that you can use the same configuration file to set up your environment whether you're working in a container, on a VM, or directly on your computer.
