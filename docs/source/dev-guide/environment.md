# Development Environment

## Dev Container

The project ships a fully-configured Dev Container at `.devcontainer/.dev/`. Opening the repository in this container gives you every tool needed for development, testing, and documentation — with consistent versions across machines.

**Supporting tools:** [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers), [GitHub Codespaces](https://docs.github.com/en/codespaces), or any [spec-compliant client](https://containers.dev/supporting) that adheres to the [Development Container Specification](https://containers.dev/implementors/spec/).

### What's Installed

The dev container installs the following features at container creation time:

| Category | Tools |
|----------|-------|
| Core | `setup-user`, `install-git`, `install-gh`, `install-jq`, `install-just`, `install-yq` |
| Shell | `install-zsh`, `setup-shell` (bash + zsh env setup), `install-shfmt`, `install-shellcheck` |
| Python / envs | `install-miniforge`, `install-pixi` |
| Packaging | `install-devcontainer-cli`, `install-oras` |
| AI tooling | `install-claude`, `install-codex`, `install-copilot`, `install-cursor` |
| CI infra | Docker-in-Docker (`devcontainers/features/docker-in-docker`) |

### Post-Start Setup

Three commands run automatically on every container start (`postStartCommand` in `.devcontainer/.dev/devcontainer.json`):

```bash
git submodule update --init --recursive   # init BATS test framework submodules
pixi install --all                        # install all pixi environments
just sync-src                             # generate src/ from features/ + lib/
```

These are idempotent — safe to re-run at any time. Running on every start ensures the environment is always consistent after container restarts.

### VS Code Customizations

The dev container configures VS Code automatically:

- **Extensions:** Bash IDE, EditorConfig, YAML support, Even Better TOML, Python (Pylance), Ruff, Docker, Markdown, Claude Code, PDF viewer, Copilot, Copilot Chat
- **YAML schema:** `features/metadata.schema.json` is registered for `features/*/metadata.yaml` files, enabling validation and autocompletion in the editor
- **JSON schema:** `devcontainer-feature.json` schema is registered for generated feature output files
- **Search/watcher excludes:** `.git/`, `__pycache__/`, `.pixi/` are excluded to keep VS Code responsive

## Rebuilding the Container

When `.devcontainer/.dev/devcontainer.json` or the feature definitions it uses change, rebuild the container via VS Code's **Dev Containers: Rebuild Container** command or from Codespaces settings.

The CI devcontainer image is a pre-built multi-arch (amd64/arm64) image published to GHCR and used as the CI execution environment. See {doc}`/dev-guide/devops/ci` for how and when it is rebuilt.
