# Developer Guide

SysSet is a collection of [dev container features](https://containers.dev/implementors/features/)
published to GitHub Container Registry. This guide covers everything needed
to work on the repository — understanding the structure, writing new features,
testing them, and publishing releases.

---

## Prerequisites

- Bash ≥ 4.0
- **Docker** — must be running and accessible for feature integration tests.
- **Node.js / npm** — required for the devcontainer CLI.
- **devcontainer CLI** — install once:
  ```bash
  npm install -g @devcontainers/cli
  ```
- **shfmt** — bash formatter ([mvdan/sh](https://github.com/mvdan/sh)):
  ```bash
  brew install shfmt
  ```
- [`shellcheck`](https://shellcheck.net/) — bash linter:
  ```bash
  brew install shellcheck
  ```
- **Lefthook** — runs `sync-lib.sh`, shfmt, and shellcheck automatically
  on commit:
  ```bash
  brew install lefthook
  lefthook install
  ```
- [devcontainer CLI](https://github.com/devcontainers/cli) (`npm install -g @devcontainers/cli`)
- [bats](https://github.com/bats-core/bats-core) (included as git submodule under `test/unit/bats/`)

---

## Guide sections

| Section | Description |
|---|---|
| [Repository structure](repo-structure.md) | Directory layout, synced files, code style tooling, dev container setup, CI workflows |
| [Writing features](writing-features.md) | Feature anatomy, bootstrap pattern, argument parsing, shared library reference |
| [Testing](testing.md) | Test framework, scenario scripts, running tests locally and in CI |
| [Publishing](publishing.md) | Versioning, GHCR publication, making packages public, adding to the index |

---

## Shared library quick reference

Every feature's `install.bash` has access to a shared bash library
(sourced from `_lib/`, a synced copy of `lib/`):

| Module | Key functions |
|---|---|
| `os.sh` | `os__require_root` |
| `logging.sh` | `logging__setup`, `logging__cleanup` |
| `net.sh` | `net__fetch_url_file`, `net__fetch_url_stdout`, `net__fetch_with_retry` |
| `ospkg.sh` | `ospkg__run`, `ospkg__install`, `ospkg__clean`, `ospkg__detect` |
| `shell.sh` | `shell__detect_bashrc`, `shell__detect_zshdir`, `shell__resolve_home` |
| `git.sh` | `git__clone` |

See [Writing features — Shared library reference](writing-features.md#shared-library-reference)
for the full API.

---


## Common commands

```sh
# Regenerate lib/ copies in each feature (run after editing lib/ or bootstrap.sh)
bash sync-lib.sh

# Format all shell scripts
make format

# Lint all shell scripts
make lint

# Build standalone distribution artifacts
make build-dist                      # tag = "dev"
make build-dist VERSION=v1.0.0       # tag = "v1.0.0"

# Run a feature's integration tests (scenarios + fail cases)
bash test/run.sh feature install-pixi

# Run all bats unit tests
make test-unit

# Run unit tests for a single lib module
bash test/run-unit.sh --module ospkg
```


## Feature reference documentation

Detailed per-feature documentation lives under `docs/ref/`:

- [install-os-pkg](../ref/install-os-pkg.md) — cross-distro OS package installer with manifest support
- [install-shell](../ref/install-shell.md) — Bash/Zsh, Oh My Zsh/Bash, Starship, Nerd Fonts
- [install-miniforge](../ref/install-miniforge.md) — Miniforge / conda
- [install-fonts](../ref/install-fonts.md) — Nerd Fonts
- [install-pixi](../ref/install-pixi.md) — Pixi package manager
- [install-podman](../ref/install-podman.md) — Podman container runtime
- [setup-shim](../ref/setup-shim.md) — command shims
- [setup-user](../ref/setup-user.md) — dev container user creation

---


## Pre-commit hooks

[lefthook](https://github.com/evilmartians/lefthook) runs automatically on commit:

- **shellcheck** — lint all staged shell files
- **shfmt** — format check all staged shell files
- **sync-lib** — regenerate `_lib/` copies when `lib/` or `bootstrap.sh` change



## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/cli — npm package](https://www.npmjs.com/package/@devcontainers/cli)
- [devcontainers/action — GitHub Action for CI and publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [`dev-container-features-test-lib` — source](https://github.com/devcontainers/cli/blob/main/src/test/dev-container-features-test-lib)
