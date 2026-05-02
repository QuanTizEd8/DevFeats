
### `_src` symlink

`_src` → `../src` lets the devcontainer CLI resolve locally built features under `.devcontainer/` while real output lives in repo-root `src/`. See `docs/dev-guide/repo-structure.md` (section on `_src`).


The dev container also has `_src → ../src` symlink under `.devcontainer/` so the devcontainer CLI can reference locally-built features during development. See {doc}`testing` for details.


`.devcontainer/` contains configuration for the **repository's own dev
container** — the container you use when working on this repo. It does not
contain feature source code.
