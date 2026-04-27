# Publishing Features

This guide covers how to version, publish, and make features discoverable
once they are ready for release.


## Versioning

Each feature is versioned **independently** via the `version` field in its `metadata.yaml` (which is also copied to its generated `devcontainer-feature.json`). Versions follow [semver](https://semver.org) format (`X.Y.Z`). When making a change to a feature, bump the version according to the nature of the change:
- **Patch** (`X.Y.Z+1`) — backwards-compatible bug fixes and minor corrections with no behaviour change.
- **Minor** (`X.Y+1.0`) — backwards-compatible new options or capabilities.
- **Major** (`X+1.0.0`) — breaking changes to option names, defaults, or behaviour.

### Version-bump discipline (CI guard)

Because `lib/` is embedded into every feature tarball as `_lib/`, a change
in `lib/` semantically affects every feature's payload. A CI lint enforces
the following rule on pull requests:

> Any PR that touches `lib/`, `features/bootstrap.sh`, or a `features/<id>/`
> directory must bump the `version` in the corresponding `metadata.yaml`
> file(s). For `lib/` and `features/bootstrap.sh` changes, **every** feature
> that embeds the changed file must be bumped (in practice: all of them).

The guard is implemented in
[`.github/workflows/scripts/cicd_detect.py`](../../.github/workflows/scripts/cicd_detect.py)
and runs as part of the `detect` job in `cicd.yaml`. A failed check names
the features that need a bump.


## Release identity

Each feature has its own release identity:

- **Tag scheme:** `<feature-id>/<X.Y.Z>` (e.g. `install-pixi/1.2.3`).
- **GitHub Release** per tag, shipping exactly one asset:
  `sysset-<feature-id>.tar.gz`.
- **GHCR tag** per version:
  `ghcr.io/|{{github_user}}|/|{{github_repo}}|/<feature-id>:<major>`, `:<major.minor>`, and
  `:<major.minor.patch>`.

Each CD run also produces an **accumulator-tagged bundle release**
(`v<X.Y.Z>`) whose assets are:

- `sysset-all.tar.gz` — every feature's tarball, flat layout.
- `manifest.yaml` — a machine-readable map of the feature versions
  contained in this bundle (consumed by `install.bash` for bundle pinning when
  `SYSSET_VERSION` or a `v*.*.*` suffix in a devcontainer `name` is used).

The bundle's global semver is derived from the highest per-feature bump in
the run; see [Bundle accumulator](#bundle-accumulator) below.


## Publishing via GitHub Actions

Publication is driven by pushes to `main`. The
[`cicd.yaml`](../../.github/workflows/cicd.yaml) orchestrator runs the
[`detect`](../../.github/workflows/scripts/cicd_detect.py) step which calls
[`scripts/detect-releasable.py`](../../scripts/detect-releasable.py):

1. For every `features/<id>/metadata.yaml`, read `.version`.
2. Query GitHub for an existing release with `tag_name == "<id>/<version>"`.
3. If absent, the feature joins the `features_to_release` output.

If the list is non-empty, [`cd.yaml`](../../.github/workflows/cd.yaml)
runs with three jobs:

1. **`publish-ghcr`** — calls
   [`devcontainers/action`](https://github.com/devcontainers/action) with
   `publish-features: "true"` and `disable-repo-tagging: "true"`. The
   action pushes the OCI artefact to GHCR for every feature whose
   `metadata.yaml` version has not yet been published, idempotently
   skipping already-published versions. It no longer creates Git tags —
   our `publish-gh-release` job owns tagging.
2. **`publish-gh-release`** — matrix over `features_to_release`. For each
   entry:
   - Creates an annotated Git tag `<feature>/<X.Y.Z>` on `github.sha`.
   - Runs `gh release create "<feature>/<X.Y.Z>" sysset-<feature>.tar.gz
     --title "<feature> <X.Y.Z>" --generate-notes`.
3. **`publish-bundle`** (`needs: [publish-ghcr, publish-gh-release]`) —
   runs [`scripts/compute-bundle-tag.py`](../../scripts/compute-bundle-tag.py)
   to compute the next `v<X.Y.Z>`, produce `notes.md`, and emit
   `manifest.yaml`. Creates the tag, then
   `gh release create "v<X.Y.Z>" sysset-all.tar.gz manifest.yaml
   --latest --notes-file notes.md`. Skips cleanly when the aggregate bump
   is `none` (idempotent re-runs).

The per-feature and bundle artefacts all come from the same `sysset-dist`
CI artefact built once in `ci.yaml`'s `prepare` step — no `gh release
download` round-trip. The
[version-bump guard](#version-bump-discipline-ci-guard) guarantees that a
feature whose `metadata.yaml` version is unchanged on this commit has
identical payload to its already-published release, so the bundle's
`sysset-all.tar.gz` is always a faithful snapshot of what is published.


### Manual single-feature publish (`workflow_dispatch`)

For hotfixes or a re-deploy after manual verification, trigger `cicd.yaml`
with the `feature` + `version` inputs:

```bash
gh workflow run "CI/CD" --field feature=install-pixi --field version=1.2.3
```

This bypasses `detect-releasable.py` and queues exactly one feature for
release. CI still runs first; CD publishes only if the tests pass. The
bundle job then runs as usual (recomputing the next bundle tag from the
single bump).

Or open the **Actions** tab in GitHub, select **CI/CD**, and click **Run
workflow**.


### Local preview

Before pushing, preview what the next CD run will do:

```bash
just detect-releasable            # prints the features_to_release JSON
just compute-bundle-tag           # prints the JSON decision record
just compute-bundle-tag notes     # prints the release-notes markdown
just compute-bundle-tag manifest  # prints the bundle manifest YAML
```


## Bundle accumulator

The global `v<X.Y.Z>` tag is computed by
[`scripts/compute-bundle-tag.py`](../../scripts/compute-bundle-tag.py):

1. **Prior tag** — highest tag matching `^v\d+\.\d+\.\d+$`, semver-sorted.
   On the first CD run this is absent → baseline `v0.0.0`.
2. **Per-feature bump classification** (vs. the latest already-published
   `<feature>/<X.Y.Z>` tag):
   - new feature (no prior release) → `minor`.
   - removed feature (has a published tag but no `features/<id>/` dir) →
     `major`.
   - existing feature: compare component-by-component (`major` > `minor`
     > `patch` > `none`). A downgrade aborts the run.
3. **Aggregate** = `max(classifications)`. If `none`, the bundle release is
   **skipped**.
4. **Next tag** = `apply_bump(prior_tag, aggregate)` using standard semver
   reset rules (`major`: `X+1.0.0`; `minor`: `X.Y+1.0`; `patch`: `X.Y.Z+1`).

Because the accumulator owns the `v*` namespace exclusively, no marker or
body-gating is needed to distinguish "real" bundle tags from historical
ones.

The resulting `manifest.yaml` is the canonical per-feature version map for
the bundle:

```yaml
bundle: v1.2.0
commit: 3f7a…
features:
  install-fonts: 0.1.0
  install-pixi: 1.3.0
  install-shell: 0.2.0
```

This is what `install.bash` downloads in bundle-pinned mode
(`SYSSET_VERSION=v1.2.0`) to resolve each requested feature to its version
inside that bundle.


## Making GHCR packages public

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

## Adding features to the containers.dev index

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

## Using private features in Codespaces

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

## References

- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/action — GitHub Action for publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [devcontainers/devcontainers.github.io — collection-index.yml](https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml)
- [Dev Containers — Feature versioning](https://containers.dev/implementors/features/#versioning)
- [GitHub Container Registry — managing package visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)
