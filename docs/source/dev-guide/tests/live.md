# Dev Container Feature Live Tests

### `_src` symlink

`_src` → `../src` lets the devcontainer CLI resolve locally built features under `.devcontainer/` while real output lives in repo-root `src/`. See `docs/dev-guide/repo-structure.md` (section on `_src`).


The dev container also has `_src → ../src` symlink under `.devcontainer/` so the devcontainer CLI can reference locally-built features during development. See {doc}`testing` for details.


`.devcontainer/` contains configuration for the **repository's own dev
container** — the container you use when working on this repo. It does not
contain feature source code.


- `.devcontainer/`: Development environment definitions.
  - `.devcontainer/devcontainer.json`: Dev container configuration.
  - `.devcontainer/_src/`: Symlink to `src/` for local feature development inside the dev container.



## Live Testing

The `install-shell/`, `install-miniforge/`, and `install-podman/`
subdirectories each contain a `devcontainer.json` that references the local
feature via a relative path. These exist so you can open a VS Code window
scoped to a specific feature's dev container — useful for exercising the
feature interactively during development.

### The `_src` symlink

The devcontainer CLI enforces a constraint: locally-referenced features must
reside **inside** the `.devcontainer/` directory (it validates paths using
`path.relative('.devcontainer', child)` and rejects any path containing
`..`). Since `src/` lives at the repo root (not inside `.devcontainer/`), a
symlink is used to satisfy this constraint:

```
.devcontainer/_src  →  ../src
```

The symlink's apparent path (`.devcontainer/_src/install-shell`) passes the
CLI's check. At build time Node.js follows the symlink and reads the real
files from `src/`.

Per-feature `devcontainer.json` files reference features using this path:

```jsonc
{
  "features": {
    "../_src/install-shell": {}
  }
}
```

The `_` prefix signals that `_src` is infrastructure, not a real source
directory.
