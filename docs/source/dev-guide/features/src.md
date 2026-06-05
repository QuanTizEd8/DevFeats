# Generated `src/`

`src/` is fully auto-generated and **git-ignored**. Never edit files here — they are overwritten on every `just sync-src`.

## Layout

```
src/<feature-id>/
├── devcontainer-feature.json   ← Generated from metadata.yaml
├── install.sh                  ← Copied from features/install.sh (POSIX bootstrap)
├── install.bash                ← Generated: template header + features/*/install.bash body
├── lib/                       ← Copy of lib/ (all modules + __init__.bash)
├── dependencies/
│   └── run/
│       └── base.yaml           ← Generated from metadata.yaml _dependencies.run.base
└── files/                      ← Copied from features/<feature-id>/files/ (if present)
```

## What Each File Does

**`devcontainer-feature.json`** — the OCI-compliant feature manifest consumed by the devcontainer CLI and published to GHCR. It is generated from `metadata.yaml` fields plus derived fields (id, documentationURL, licenseURL, OCI ref) injected from project config.

**`install.sh`** — the POSIX bootstrap. See {doc}`install.sh`.

**`install.bash`** — the assembled installer. The template from `features/install.tmpl.bash` provides the framework; the feature body from `features/<feature-id>/install.bash` is appended after. See {doc}`install.bash`.

**`lib/`** — a full copy of `lib/`. Sourced at runtime via `lib/__init__.bash`. Each feature gets its own copy so that feature tarballs are self-contained.

**`dependencies/<lifecycle>/<name>.yaml`** — ospkg manifests generated from `_dependencies.<lifecycle>.<name>` in `metadata.yaml`. The devcontainer CLI installs `dependencies/run/*.yaml` manifests before invoking `install.sh`.

## Sync Command

```bash
just sync-src           # regenerate src/ (run after any edit to features/ or lib/)
just sync-src-check     # verify src/ is current (exits non-zero if stale; used by CI)
```

`just sync-src` runs `proman-sync` (Python), which:
1. Validates every `features/*/metadata.yaml` against `features/metadata.schema.json`.
2. Generates `devcontainer-feature.json`, `dependencies/<lifecycle>/*.yaml`, and `install.bash` for each feature.
3. Copies `features/install.sh` and `lib/` into each feature's output directory.
4. Copies any `features/<id>/files/` content.

Feature discovery is automatic — any directory under `features/` that contains a `metadata.yaml` is treated as a feature.

## Why `src/` Is Ignored

- Files are exact copies or derivatives of source; committing them creates noisy diffs every time `lib/` is touched.
- CI regenerates `src/` at the start of every job to guarantee a clean, consistent working tree.
- The `.gitignore` makes it immediately obvious when someone accidentally edits a generated file (changes disappear on the next sync).
