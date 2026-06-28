# Repository Layout

## Directory Tree

```
devfeats/
├── features/                ← Feature source definitions (source of truth)
│   ├── <feature-id>/
│   │   ├── metadata.yaml    ← Options, description, deps, version
│   │   ├── install.bash     ← Body-only installer (bash ≥4; header auto-generated)
│   │   ├── notes.md         ← User-facing supplemental documentation (optional)
│   │   ├── dev-notes.md     ← Developer notes (design decisions, research) (optional)
│   │   ├── tool-ref.md      ← Tool installation reference (optional)
│   │   └── files/           ← Static files deployed by the feature (optional)
│   ├── install.sh           ← POSIX shim (source of truth; copied to src/*/install.sh)
│   ├── install.tmpl.bash    ← Install script template used by proman-sync
│   ├── metadata.shared.yaml ← Options injected into every feature at sync time
│   ├── metadata.schema.json ← JSON Schema for metadata.yaml files
│   ├── checks.schema.json   ← JSON Schema for test checks.yaml files
│   └── install-os-pkg-bundle/ ← Package bundle manifests for install-os-pkg (not standalone features)
│       └── bundles/<bundle-id>/
│           ├── metadata.yaml  ← Bundle metadata (descriptions, URLs)
│           └── packages.yaml    ← ospkg manifest for the bundle
│
├── lib/                     ← Shared bash library modules (source of truth)
│   ├── __init__.bash        ← Master loader; sources all modules in dependency order
│   ├── logging.sh           ← POSIX logging dispatcher used before bash is available
│   ├── posix.sh             ← POSIX bootstrap helpers shared with install.sh
│   ├── logging.bash         ← Structured bash logging backend
│   ├── os.bash              ← OS/hardware detection
│   ├── ospkg.bash           ← Cross-distro package manager abstraction
│   ├── github.bash          ← GitHub API helpers
│   ├── net.bash             ← Network fetch, retry, checksum
│   ├── git.bash             ← Git operations
│   ├── shell.bash           ← Shell detection, startup file management
│   ├── users.bash           ← User/group management
│   ├── ver.bash             ← Version parsing and comparison
│   ├── install.bash         ← Installation state management, asset extraction
│   ├── *.bash               ← Additional bash-only modules (oci.bash, json.bash, etc.)
│   └── argparse-manifest.schema.json ← JSON Schema for argparse manifests
│
├── test/                    ← Test suite
│   ├── environments.yaml    ← Central registry of Docker images for tests
│   ├── features/
│   │   └── <feature-id>/
│   │       ├── scenarios.yaml  ← Test matrix (envs, modes, options)
│   │       ├── checks.yaml     ← Test assertions (source of truth for *.sh scripts)
│   │       └── tests/
│   │           └── *.sh        ← Auto-generated test scripts (DO NOT EDIT)
│   ├── lib/
│   │   ├── *.bats              ← BATS unit tests (one file per lib module)
│   │   ├── scenarios.yaml      ← BATS test environment matrix
│   │   ├── helpers/            ← reload_lib(), stubs helpers
│   │   └── bats/               ← Git submodules (bats-core, bats-assert, etc.)
│   └── proman/                 ← Python unit tests for the build system
│       └── test_*.py
│
├── docs/                    ← Documentation
│   ├── conf.py              ← Sphinx configuration
│   ├── toc.yaml             ← Navigation tree
│   └── source/              ← Content (Markdown, MyST)
│       ├── dev-guide/       ← This guide
│       ├── features/        ← Auto-generated feature reference pages
│       └── library/         ← Auto-generated library API reference pages
│
├── src/                     ← GENERATED — never edit (git-ignored)
│   └── <feature-id>/        ← Per-feature compiled output
│       ├── devcontainer-feature.json
│       ├── install.sh
│       ├── install.bash
│       ├── lib/
│       └── files/
│
├── .dev/                    ← Development tooling
│   ├── lib/proman/          ← Python build system (proman CLI entry points)
│   └── scripts/             ← Bash scripts for Docker, bats, GHA log streaming
│
├── .devcontainer/           ← Dev container configurations
│   ├── .dev/                ← Main development container (EDIT HERE)
│   ├── .src -> ../src       ← Symlink — lets test-* containers reference local src/
│   ├── test-*/              ← Auto-generated; install from local src/ — for developer testing
│   └── try-*/               ← Auto-generated; install from published OCI image — for user demos
│
├── .github/                 ← GitHub configuration
│   ├── workflows/           ← CI/CD pipelines
│   ├── instructions/        ← Copilot/AI context files
│   └── agents/              ← AI agent definitions
│
├── .config/
│   ├── proman/              ← Project configuration read by proman
│   │   ├── _main.yaml       ← Repo metadata, paths, file names
│   │   ├── ci.yaml          ← CI image config, artifact names, trigger paths
│   │   └── docs.yaml        ← Sphinx settings, JSON schema publish list
│   ├── lefthook.yml         ← Git hook definitions (pre-commit: format-sh; lint-py + format-py)
│   ├── ruff.toml            ← Python linter/formatter config
│   └── pytest.ini           ← pytest config
│
├── .local/                  ← Git-ignored scratch space (logs, build artifacts)
├── justfile                 ← Developer task runner (entry point for all tasks)
└── pixi.toml                ← Conda environments and pixi task definitions
```

## Read-Only Paths

:::{admonition} Never edit these paths
:class: danger

| Path | Reason |
|------|--------|
| `src/` | Fully auto-generated by `just sync-src`; overwritten on every run |
| `test/features/*/tests/*.sh` | Auto-generated from `checks.yaml` by `just sync-tests`; overwritten on every run |
| `.devcontainer/test-*/` | Auto-generated developer test containers; reference local `src/` via `.devcontainer/.src` symlink |
| `.devcontainer/try-*/` | Auto-generated user demo containers; reference published OCI image |
| `.devcontainer/.src` | Symlink to `../src`; do not remove or retarget |
| `docs/source/features/` | Auto-generated by `just build-docs` from feature metadata |
| `docs/source/library/` | Auto-generated by `just build-docs` from `lib/*.bash` / `lib/*.sh` annotations |
| `test/lib/bats/` | Git submodules (bats-core, bats-support, bats-assert, bats-file) |
:::

## Configuration Hierarchy

Project-wide settings are split across three files in `.config/proman/`:

- **`_main.yaml`** — repo metadata (owner, name, namespace, OCI base, file name conventions, feature lifecycle hook keys)
- **`ci.yaml`** — CI image config, artifact retention, Docker registry, change-trigger path globs
- **`docs.yaml`** — Sphinx extension list, theme options, JSON schema publish targets

All three are loaded by `proman` at runtime. Values use `${{ key }}$` interpolation and `#{{ python }}#` for computed fields.
