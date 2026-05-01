# Development Environment



### Using the dev container (recommended)

The repository ships a ready-to-use dev container at `.devcontainer/devcontainer.json`. It installs Node.js, Docker-in-Docker, Python dev tools, the devcontainer CLI, `shfmt`, `shellcheck`, `just`, and `lefthook` automatically on create.

Open the repository in VS Code and choose **Reopen in Container**, or run:

```sh
devcontainer up --workspace-folder .
```

The dev container also has `_src → ../src` symlink under `.devcontainer/` so the devcontainer CLI can reference locally-built features during development. See {doc}`testing` for details.

### Host setup

To work directly on macOS or Linux:

1. Run `just install-dev` from the repo root. This executes `.devcontainer/setup-dev.sh`, which installs pinned versions of `shfmt`, `shellcheck`, `just`, `PyYAML`, `jsonschema`, `@devcontainers/cli`, and `lefthook` depending on your OS and the `--tools` flags.
2. Initialize bats submodules for unit tests:
   ```sh
   git submodule update --init --recursive
   ```
3. (Optional) Create the Sphinx docs environment:
   ```sh
   # Requires conda or mamba
   conda env create -f docs/environment.yaml
   ```

**Requirements:**
- Bash ≥ 4 (macOS ships with 3.2; install via `brew install bash`)
- Docker — running and accessible for feature integration tests
- Node.js / npm — needed for the devcontainer CLI (`npm install -g @devcontainers/cli`)

---


### `_src` symlink

`_src` → `../src` lets the devcontainer CLI resolve locally built features under `.devcontainer/` while real output lives in repo-root `src/`. See `docs/dev-guide/repo-structure.md` (section on `_src`).





`.devcontainer/` contains configuration for the **repository's own dev
container** — the container you use when working on this repo. It does not
contain feature source code.

```
.devcontainer/
├── devcontainer.json           ← Main dev container (Node.js + Docker-in-Docker)
├── _src                       → ../src  (symlink — see below)
├── install-shell/
│   └── devcontainer.json       ← Dev container for testing install-shell locally
├── install-miniforge/
│   └── devcontainer.json
└── install-podman/
    └── devcontainer.json
```



- **Bash** ≥ 4.0
- **Docker** — running and accessible for feature integration tests (local scenario runs).
- **Git** with submodules — initialize `test/unit/bats/` for unit tests (`git submodule update --init --recursive`).

**On the host (recommended bootstrap)**

- Run **`just install-dev`** once from the repo root. It executes [`.devcontainer/setup-dev.sh`](../.devcontainer/setup-dev.sh), which can install pinned **shfmt**, **shellcheck**, **just**, **PyYAML**, **jsonschema**, **@devcontainers/cli**, and **lefthook** (depending on OS and flags). See the script header for `--tools`.
- **Node.js / npm** — needed if you install the devcontainer CLI yourself. The repo devcontainer installs globals in `devcontainer.json` (`updateContentCommand`).

**Using the dev container**

- Open the folder in a dev container (see [`.devcontainer/README.md`](../.devcontainer/README.md)). The image installs Python packages, dev CLI tools, Docker-in-Docker, and runs `lefthook install` after create.

**Docs site (optional)**

- Building the Sphinx site (`just docs`, `just docs-serve`) uses the Conda environment defined in [`docs/environment.yaml`](../docs/environment.yaml) (`sysset-website`). Create it per that file if you work on docs.

**Reference**

- **Commands:** run `just --list` from the repo root (see [`justfile`](../../justfile)); non-`just` release steps are in [`docs/snippets/key-commands.md`](../snippets/key-commands.md).
- High-level layout: [`docs/snippets/repo-layout.md`](../snippets/repo-layout.md)
- Shell style: [`docs/snippets/code-style.md`](../snippets/code-style.md)
