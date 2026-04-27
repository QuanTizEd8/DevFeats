# Developer Guide

This guide covers everything needed to contribute to SysSet: setting up the development environment, understanding the repository layout, writing features, testing, CI/CD, and publishing releases.

---

## Development environment

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

## Common commands

Run `just --list` for the full recipe list with descriptions. Key workflows:

```sh
# Regenerate src/ from features/ + lib/ + bootstrap.sh
just sync

# Format shell files in-place, then run shellcheck
just format && just lint

# Format-check only (CI-style, no writes) + lint
just format-check && just lint

# Validate metadata files and check src/ is up-to-date
just sync-check

# Run feature scenario tests for one feature (requires Docker + devcontainer CLI)
just test-feature install-pixi

# Run shared library unit tests (no Docker needed)
just test-unit

# Build the docs website locally (requires sysset-website conda env)
just build-website

# Serve docs with live reload
just build-website-live

# Watch GitHub Actions logs after a push
just watch-gha --commit HEAD
```

Preview what the next CD run will do without pushing:

```sh
just detect-releasable           # print features_to_release JSON
just compute-bundle-tag          # print the next bundle version decision
just compute-bundle-tag notes    # print the release notes markdown
just compute-bundle-tag manifest # print the bundle manifest YAML
```

Publishing to GHCR and GitHub Releases is done via GitHub Actions — see {doc}`publishing`.

---

## Lefthook

[`lefthook.yml`](../../lefthook.yml) is present for optional Git hooks. **Pre-commit commands that run `sync`, `shfmt`, and `shellcheck` are currently commented out**, so commits are not automatically reformatted or re-synced unless you re-enable those blocks.

The dev container runs `lefthook install` on create, so hook definitions are registered and ready to enable.

---

## Guide sections

| Section | What you'll find |
|---------|-----------------|
| {doc}`repo-structure` | Directory layout, the sync mechanism, code style |
| {doc}`writing-features` | Feature anatomy, metadata schema, install scripts, and the full shared library API |
| {doc}`testing` | Unit tests, scenario tests, macOS native tests, and CI test jobs |
| {doc}`ci` | GitHub Actions workflows, change detection, and manual triggers |
| {doc}`publishing` | Versioning, GHCR, GitHub Releases, and the containers.dev index |

---

## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/cli — npm package](https://www.npmjs.com/package/@devcontainers/cli)
- [devcontainers/action — GitHub Action for CI and publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
