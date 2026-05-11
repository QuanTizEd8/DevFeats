# Development Infrastructure

## Task Architecture

Development tasks are split across four tiers with strict ownership rules. Each tier has exactly one job; the goal is that any new task has an obvious home.

| Tier | Tool | Rule |
|------|------|------|
| **Entry point** | `justfile` | Every developer command lives here. Zero inline logic — pure routing to a pixi task or a bash script. |
| **Python logic** | `proman` (`.dev/lib/`) | Anything that reads project metadata, feature manifests, or YAML config; multi-step orchestration; GitHub API calls. |
| **System ops** | `.dev/scripts/` | Docker socket management, bats orchestration, GHA log streaming. Operations that must run outside a managed Python environment. |
| **Environments** | `pixi.toml` | Python environment definitions plus tasks that use pixi-native features (`depends-on`, `cwd`, non-default environments). |

### Where does a new task go?

```
Does it read feature metadata, YAML config, or call an external API?
  → proman (new CLI entry point in .dev/lib/proman/cli/)

Does it require a specific Python environment, or use pixi's depends-on / cwd?
  → pixi task (add to the relevant [feature.X.tasks] block in pixi.toml)

Is it Docker/process management, bats, or a streaming shell operation?
  → .dev/scripts/CATEGORY/script.sh

Otherwise (justfile alias for any of the above)?
  → justfile recipe (routes to one of the three above)
```

---

## Invocation Patterns

Every `justfile` recipe uses exactly one of two patterns:

```bash
# Pattern 1 — pixi-managed tools (proman, ruff, sphinx, pytest)
pixi run [--environment ENV] <task-name>

# Pattern 2 — system-level bash ops (Docker, bats, streaming)
bash .dev/scripts/CATEGORY/SCRIPT.sh [args]
```

Proman entry points are **never** called directly from the justfile — always via `pixi run <task>`. This ensures the correct environment is activated and the binary is on PATH regardless of the shell context.

---

## Naming Convention

All task names follow `<type>-<domain>[-<modifier>]`.

### Types

| Type | Meaning |
|------|---------|
| `sync` | Assemble or reconcile derived files from sources |
| `build` | Produce a distributable artifact |
| `lint` | Static analysis |
| `format` | Reformat code |
| `test` | Run a test suite |
| `fetch` | Retrieve data from an external service |
| `show` | Print a human-readable inventory |
| `release` | Release lifecycle operations |
| `run` | One-shot internal execution wrapper (private tasks only) |

### Domains

| Domain | Covers |
|--------|--------|
| `sh` | Shell/bash files (`.sh`, `.bash`, `.bats`) |
| `py` | Python source (`proman/`) |
| `src` | Assembled `src/` tree |
| `feats` | Individual features (`features/`, `dist/`) |
| `lib` | `lib/` shell library |
| `docs` | Documentation (`docs/`, Sphinx, injected markers) |
| `gha` | GitHub Actions CI tooling |

### Modifiers

| Modifier | Meaning |
|----------|---------|
| `check` | Dry-run / verify-only (no writes, exits non-zero if changes needed) |
| `live` | Long-running with file-watching |
| `pkg` | Package/archive for distribution |
| `env` | Single-environment variant |
| `envs` | All-environments variant |
| `mod` | Single-module variant |
| `macos` | macOS-specific variant |

**`check` rule:** The bare name applies changes (`sync-src`, `format-sh`, `lint-py`). The `-check` suffix is always the verify-only variant (`sync-src-check`, `format-sh-check`, `lint-py-check`). Uniform across all types.

**`lint` specifics:** For tools that support auto-fix (ruff), the bare name applies fixes. For check-only tools (shellcheck), only the `-check` variant exists.

**Composites (no domain):** Only tasks that run every subdomain variant: `lint`, `format`, `format-check`, `test`.

---

## Current Task Reference

### justfile → pixi task → implementation

| justfile recipe | pixi task | Implementation |
|-----------------|-----------|----------------|
| `sync-src` | `sync-src` | `proman-sync` |
| `sync-src-check` | `sync-src-check` | `proman-sync --check` |
| `sync-docs` | `sync-docs` | `proman-gen-docs` |
| `sync-docs-check` | `sync-docs-check` | `proman-gen-docs --check` |
| `build-feats` | `build-feats` | `proman-build-feats` |
| `build-docs` | `build-docs` | Sphinx (depends on `_sync-docs-data`) |
| `build-docs-live` | `build-docs-live` | `sphinx-autobuild` |
| `build-docs-pkg` | `build-docs-pkg` | `proman-build-docs-pkg` |
| `release-detect` | `release-detect` | `proman-release-detect` |
| `show-feats` | `show-feats` | `proman-show-feats` |
| `show-feat-opts` | `show-feat-opts` | `proman-show-feat-opts` |
| `show-config` | — | `bash .dev/scripts/show/config.sh` |
| `lint-sh-check` | — | `shellcheck` (system tool) |
| `lint-py-check` | `lint-py-check` | `ruff check` |
| `lint-py` | `lint-py` | `ruff check --fix` |
| `format-sh` | — | `shfmt --write` (system tool) |
| `format-sh-check` | — | `shfmt --diff` |
| `format-py` | `format-py` | `ruff format` |
| `format-py-check` | `format-py-check` | `ruff format --check` |
| `test-lib` | — | `bash .dev/scripts/test/run-unit.sh` |
| `test-lib-mod` | — | `run-unit.sh --module` |
| `test-lib-env` | — | `run-unit-matrix.sh --env` |
| `test-lib-envs` | — | `run-unit-matrix.sh` |
| `test-py` | `test-py` | `pytest test/proman` |
| `test-feats` | `test-feats` | `proman-test-run` |
| `test-feats-macos` | `test-feats` | `proman-test-run --mode macos` |
| `fetch-gha` | — | `bash .dev/scripts/fetch/gha.sh` |
| `run-gha-dind` (private) | — | `bash .dev/scripts/ci/gha-dind.sh` |

### Sphinx docs build context

Sphinx loads `.local/data_transfer/docs_build_context.json` (repo owner/name, feature metadata, `lib/` summaries). That file is written by `proman-gen-docs-data` (`pixi run _sync-docs-data` in the default environment). The `build-docs` pixi task depends on `_sync-docs-data`; `build-docs-live` also runs it before each autobuild cycle. The path lives under `/.local/`, which is gitignored.

### pixi tasks called directly by CI

The following pixi tasks are invoked by GHA workflows via `pixi run <task>` and **must not be renamed without updating the corresponding workflow files**:

*(Currently CI calls `just <recipe>` which routes through pixi — but if CI ever bypasses justfile, these are the tasks it would call.)*

The remaining pixi tasks are only ever called by justfile recipes and may be renamed freely alongside their justfile counterparts.

---

## .dev/scripts/ Reference

| Script | Purpose | Called from |
|--------|---------|-------------|
| `git_helpers.sh` | Reusable git functions (sourced library) | Other scripts |
| `show/config.sh` | Print a field from `.config/*.yaml` via yq | `just show-config` |
| `ci/gha-dind.sh` | Docker-in-Docker setup for GHA | `just run-gha-dind` |
| `fetch/gha.sh` | Poll GHA workflow runs, stream logs | `just fetch-gha` |
| `test/run-unit.sh` | Execute bats unit tests for `lib/` | `just test-lib`, `just test-lib-mod` |
| `test/run-unit-matrix.sh` | Run `run-unit.sh` in container environments | `just test-lib-env`, `just test-lib-envs` |
| `test/run-in-container.sh` | Docker exec wrapper (mounts repo) | `run-unit-matrix.sh` |

**Adding a new script:** Only add to `.dev/scripts/` if the operation is inherently bash — Docker/process control, bats orchestration, or shell streaming. If it reads YAML config or makes decisions about project structure, it belongs in proman instead.
