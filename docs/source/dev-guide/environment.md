# Environment

The project ships a ready-to-use Dev Container at `.devcontainer/.dev/`, which encapsulates the full development environment for the project. It installs all necessary tools for development, testing, and documentation, ensuring a consistent setup across different machines and operating systems. You can use this Dev Container in [VS Code](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers), or any other [supporting tool](https://containers.dev/supporting) that adheres to the [Development Container Specification](https://containers.dev/implementors/spec/); simply open your local clone of the repository in the Dev Container to get started.


## Git Hooks

The project uses [Lefthook](https://github.com/evilmartians/lefthook) to manage Git hooks;

The dev container runs `lefthook install` on create, so hook definitions are registered and ready to enable.
[`lefthook.yml`](../lefthook.yml) is present for optional Git hooks.



## Task Runner

The project uses [just](https://github.com/casey/just) as its task runner; all routine project tasks (e.g. format, lint, test, build) are implemented as `just` recipes.


Run `just --list` to see all available commands and their descriptions in the `justfile`. Recipes are grouped by category (e.g. testing, CI, publishing) and include comments with additional details.

