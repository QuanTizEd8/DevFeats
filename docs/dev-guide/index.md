# Developer Guide





---

## Guide sections

| Section | Description |
|---------|-------------|
| [Repository structure](repo-structure.md) | Directory layout, synced files, tooling, dev container, CI |
| [CI](ci.md) | `cicd.yaml`, `ci.yaml`, `cd.yaml`, path-based jobs |
| [Writing features](writing-features.md) | Feature anatomy, bootstrap pattern, argument parsing, shared library |
| [Testing](testing.md) | Scenario tests, unit tests, running locally vs CI |
| [Publishing](publishing.md) | Versioning, GHCR, releases |

---

Install [just](https://github.com/casey/just), then from the repo root:

```bash
just --list
```

That prints every recipe, its `[group]`, and the comment text above it in the [`justfile`](../../justfile). Prefer this over maintaining a duplicate table here.


Direct equivalents still work (e.g. `python3 scripts/sync-src.py`) and are mentioned in the `justfile` comments where relevant.

## Releases (not wrapped by `just`)

Publishing to GHCR and GitHub Releases is done via GitHub Actions. See [Publishing](../dev-guide/publishing.md).




## Shared library quick reference

Every feature's `install.bash` has access to a shared bash library
(sourced from `_lib/`, a synced copy of `lib/`):

| Module | Key functions |
|--------|---------------|
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

Run **`just --list`** for the full recipe list. Typical workflow:

```sh
just sync                    # regenerate src/ (or: python3 scripts/sync-src.py)
just format && just lint     # format + shellcheck
just test-feature install-pixi
just test-unit
just watch-gha --commit HEAD # after push — stream CI logs
```

Release automation is documented in [Publishing](publishing.md), not as `just` tasks.

---

## Lefthook

[`lefthook.yml`](../lefthook.yml) is present for optional Git hooks. **Pre-commit commands that run `sync`, `format`, and `validate-metadata` are currently commented out**, so commits are not automatically reformatted or re-synced unless you re-enable those blocks.

The devcontainer **`postCreateCommand`** still runs **`lefthook install`**, so hook definitions are registered when you use that environment.

---

## References

- [Dev Containers — Feature authoring specification](https://containers.dev/implementors/features/)
- [Dev Containers — Feature distribution specification](https://containers.dev/implementors/features-distribution/)
- [devcontainers/cli — npm package](https://www.npmjs.com/package/@devcontainers/cli)
- [devcontainers/action — GitHub Action for CI and publishing](https://github.com/devcontainers/action)
- [containers.dev — public features index](https://containers.dev/features)
- [`dev-container-features-test-lib` — source](https://github.com/devcontainers/cli/blob/main/src/test/dev-container-features-test-lib)
