# SysSet — System Setup

**SysSet** is a project developing system setup tools (a.k.a features) that must work seamlessly on both macOS and various Linux distributions, both in containers and on bare-metal machines. These tools are distributed as both [**devcontainer features**](https://containers.dev/implementors/features/) (published to GHCR) and **standalone/bundled installers** (published to GitHub Releases). They provide users with a seamless experience for installing and configuring essential software in their environments, with rich configuration options that cater to a wide range of use cases and requirements. These tools must be robust, reliable, consistently designed, and thoroughly tested, with comprehensive documentation.

## Rules and Constraints

- When using conda, use `python` instead of `python3`; since `python3` is aliased to the system Python on some distros.

## Workspace Layout



## Key Commands

When asked to investigate failures in a CI run, use `make watch-gha` to stream logs from the run in question. See the target for details and examples.



Always run `bash scripts/sync-src.sh` before running feature tests locally.

## Features

To get a quick overview of all features, run the following command in the project root:

```bash
for f in features/*/metadata.yaml; do
  name=$(basename "$(dirname "$f")")
  desc=$(yq -r '.description' "$f")
  printf '%s: %s\n' "$name" "$desc"
done
```

To get all option names used across features (with counts of how many features use each option), run:

```bash
yq -r '.options // {} | keys[]' features/*/metadata.yaml \
  | sort \
  | uniq -c \
  | sort -nr \
  | awk '{printf "%s (%d)\n", $2, $1}'
```

## Shared Library (`lib/`)

**Always check `lib/` before implementing something from scratch.** The library covers the most common operations feature scripts need. Prefer calling a lib function over writing inline logic — this keeps scripts shorter, consistent, and testable.

When implementing a new feature or editing an existing one, abstract any reusable logic into `lib/` rather than copy-pasting it across scripts. A function belongs in `lib/` when it is (or could be) called from more than one feature, or when it encapsulates a non-trivial detail that is easy to get wrong (e.g. SHA-256 verification, GitHub API pagination, user deduplication).


## Code Style

All shell scripts are formatted with **shfmt** and linted with **shellcheck**.

- Style is defined in `.editorconfig`: 2-space indent, `switch_case_indent = true`, `function_next_line = false` (brace on same line), `space_redirects = true`.
- `.shellcheckrc` sets `shell=bash` and `external-sources=true` globally.
- Pre-commit hook checks formatting and lints staged files (no-op when tools absent from PATH).
- CI (`lint.yaml`) enforces both strictly on every push and PR.
- Run `make format` to auto-format; `make lint` to lint.
- `*.bats` files use `shell_variant = bats` in `.editorconfig` and are formatted by shfmt.
- `--apply-ignore` excludes generated `_lib/` copies and `install.sh` stubs automatically.
- `features/*/install.bash` are body-only (no header) and are **not linted in isolation** — lint targets the assembled `src/*/install.bash` files. Run `bash scripts/sync-src.sh` before `make lint`.


## Key References

- [devcontainer CLI Repository](https://github.com/devcontainers/cli)
- [devcontainer GitHub Organization](https://github.com/devcontainers)
