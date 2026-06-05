# Feature Quickstart

## Directory Layout

Each feature lives in `features/<feature-id>/`. The canonical `id` is the directory name.

```
features/<feature-id>/
├── metadata.yaml       ← Required: options, description, deps, version (source of truth)
├── install.bash        ← Required: body-only installer (bash ≥4; header auto-generated)
├── notes.md            ← Optional: user-facing supplemental documentation
├── dev-notes.md        ← Optional: developer notes (design, research, implementation)
├── tool-ref.md         ← Optional: tool installation methods reference for developers
└── files/              ← Optional: static files deployed alongside the installer
```

Files shared across all features (do not duplicate in per-feature directories):

- `features/install.sh` — POSIX bootstrap shim (source of truth; copied to `src/*/install.sh`)
- `features/install.tmpl.bash` — install script template (used by `proman-sync`)
- `features/metadata.shared.yaml` — options auto-injected into every feature
- `features/metadata.schema.json` — JSON Schema for `metadata.yaml`

## Quick-Start Checklist

1. **Read the library first.** Check {doc}`lib` before writing any logic. Functions for OS detection, package installation, GitHub releases, checksum verification, user management, and shell configuration are already there.

2. **Create `metadata.yaml`** following {doc}`metadata.yaml`. Validate against `features/metadata.schema.json` (VS Code auto-validates when the schema is registered, which the dev container does).

3. **Create `install.bash`** (body only — no shebang, no header). The header and template orchestration are generated. See {doc}`install.bash` for what hooks are available.

4. **Run `just sync-src`** to generate `src/<feature-id>/` and verify the output compiles cleanly.

5. **Run `just lint-sh-check`** to catch shellcheck issues in the assembled `src/<feature-id>/install.bash`.

6. **Create `test/features/<feature-id>/scenarios.yaml`** and `test/features/<feature-id>/checks.yaml`. See {doc}`/dev-guide/tests/features` for the format.

7. **Run `just sync-tests <feature-id>`** to generate the test `*.sh` scripts from `checks.yaml`.

8. **Run `just test-feats <feature-id>`** to execute the scenarios (requires Docker).

9. **Bump `version`** in `metadata.yaml` for any change that affects behavior. See {doc}`/dev-guide/devops/ci` for the version-bump discipline enforced in CI.

## The Sync Pipeline

`just sync-src` runs `proman-sync`, which reads every `features/*/metadata.yaml` and produces a complete `src/<feature-id>/` directory:

```
metadata.yaml        →  src/*/devcontainer-feature.json   (OCI-compliant feature spec)
metadata.yaml        →  src/*/dependencies/*.yaml          (OS package manifests)
install.tmpl.bash
  + install.bash     →  src/*/install.bash                 (header + body)
features/install.sh  →  src/*/install.sh                   (POSIX bootstrap)
lib/                 →  src/*/lib/                          (library copy per feature)
files/               →  src/*/files/                        (static files)
```

The sync is idempotent. `just sync-src-check` verifies that `src/` is current without writing (used by CI).

## Key Conventions

- **`install.bash` is body-only** — no shebang, no argument parsing, no library sourcing. The template in `features/install.tmpl.bash` provides all boilerplate; `install.bash` only defines hooks that override template defaults. See {doc}`install.bash` for the full hook list and dispatch order.
- **`metadata.yaml` drives code generation** — options become CLI flags and env vars, dependencies become package manifests, and the shared options from `features/metadata.shared.yaml` are auto-injected (do not redeclare `log_level`, `log_file`, etc.). See {doc}`metadata.yaml` for the full reference.
- **`lib/` first** — before writing any logic, check {doc}`lib`. OS detection, package installation, GitHub releases, checksums, user management, and shell configuration are all covered.
- **Always `sync-src` before linting or testing** — shellcheck runs on the assembled `src/*/install.bash`, not the raw body file.

## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/action — GitHub Action for CI and publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [`dev-container-features-test-lib` — source](https://github.com/devcontainers/cli/blob/main/src/test/dev-container-features-test-lib)
