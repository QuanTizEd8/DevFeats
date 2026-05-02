# DevOps Operations

Three workflow files form the pipeline:

- **`cicd.yaml`** — Orchestrator. Defines all event triggers (push, tag, PR, manual). Runs a `detect` job that computes changed-file flags, then calls `ci.yaml` (reusable CI) and conditionally `cd.yaml` (reusable CD) for releases.
- **`ci.yaml`** — Reusable CI. All lint, validation, unit, feature, and dist test jobs. Also callable standalone via `workflow_dispatch`.
- **`cd.yaml`** — Reusable CD. Publishes features to GHCR and creates a GitHub Release. Callable standalone via `workflow_dispatch` with a `tag` input.

`detect` in `cicd.yaml` maps changed paths to specific jobs:

| Changed path | Jobs triggered |
|---|---|
| `*.sh`, `*.bash`, `*.bats` | `lint` |
| `src/**/devcontainer-feature.json` | `validate` |
| `lib/**`, `test/unit/**` | `unit-native`, `unit-linux` |
| `src/<f>/` or `test/<f>/` | `test-features` (matrix), `test-macos` if macOS scenarios exist |
| `install-os-pkg` in changed list | `test-os-pkg` (6-distro matrix) |
| `features/install.sh`, `features/sysset.sh`, `scripts/build-artifacts.sh`, `src/**`, `lib/**`, `test/dist/**` | `test-dist-*` |

On `workflow_dispatch` or `v*` tag push, all jobs run. CD runs only when `is_release=true` AND CI passes.



- `.github/workflows/`:
  - `cicd.yaml` — Orchestrator: triggers, `detect` job, calls `ci.yaml` and conditionally `cd.yaml`
  - `ci.yaml` — Reusable CI (lint, validate, unit, feature scenarios, dist tests)
  - `cd.yaml` — Reusable CD (GHCR publish, GitHub Release)
  - `devcontainer-image.yaml` — Build/publish devcontainer image



## Workflow files

| Workflow | Role |
|----------|------|
| **`cicd.yaml`** | **Orchestrator.** The only file with event triggers (push to `main`, PRs, `workflow_dispatch`). Runs a `detect` job that analyses changed files and computes flags, then calls **`ci.yaml`** (reusable CI) and conditionally **`cd.yaml`** (reusable CD) when releasable features are detected. |
| **`ci.yaml`** | **Reusable CI.** Lint, metadata validation, unit tests, feature scenario tests, macOS tests, dist tests. Directly callable via `workflow_dispatch` for a standalone full-suite run. |
| **`cd.yaml`** | **Reusable CD.** Publishes features to GHCR and creates GitHub Releases. Directly callable via `workflow_dispatch` with `feature` + `version` inputs for a single-feature hotfix. |
| **`devcontainer.yaml`** | Builds and publishes the repository devcontainer image (multi-arch: amd64/arm64). |


## Feature Discoverability

By default, packages pushed to GHCR are **private**. Private packages incur
storage costs and are not visible to consumers who do not have credentials.
To stay within the free tier and allow anyone to use a feature, mark each
package as public:

1. Navigate to the package settings URL:
   ```
   https://github.com/users/|{{github_user}}|/packages/container/sysset%2F<feature-id>/settings
   ```
   For example, for `install-shell`:
   ```
   https://github.com/users/|{{github_user}}|/packages/container/sysset%2Finstall-shell/settings
   ```
2. Under **Danger Zone**, set the visibility to **Public**.

This must be done once per feature after its first publication.

---

## Feature Findability

To make features discoverable in tools such as VS Code Dev Containers and
GitHub Codespaces, submit a PR to the
[devcontainers/devcontainers.github.io](https://github.com/devcontainers/devcontainers.github.io)
repository to add an entry to the
[`_data/collection-index.yml`](https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml)
file.

The index entry registers the feature collection namespace
(`ghcr.io/|{{github_user}}|/sysset`) so that supporting tools can surface all
features from this repository in their dev container creation UI.

---

## Private Features

If a feature is kept private in GHCR, consumers using GitHub Codespaces must
grant the token additional permissions, because Codespaces uses repo-scoped
tokens that do not automatically include package read access.

Add a `customizations.codespaces.repositories` block to the consuming
`devcontainer.json`:

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/|{{github_user}}|/|{{github_repo}}|/install-shell:0": {}
  },
  "customizations": {
    "codespaces": {
      "repositories": {
        "|{{github_user}}|/sysset": {
          "permissions": {
            "packages": "read",
            "contents": "read"
          }
        }
      }
    }
  }
}
```

Most other implementing tools (e.g. VS Code Dev Containers, the devcontainer
CLI) use a broadly-scoped token and work without this configuration.

---