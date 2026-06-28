# Documentation Quickstart

## Building Locally

```bash
just build-docs           # build HTML to .local/build/docs/
just build-docs-live      # live-reload server at http://localhost:8000
```

Both commands run `proman-gen-docs-data` first to regenerate the auto-generated `features/` and `library/` sections from source. Output goes to `.local/build/docs/` (git-ignored).

The docs environment requires Python packages listed in the `docs` pixi environment (`pixi.toml`). Running `pixi install --all` (done automatically in the dev container) installs these.

## Content Organization

```
docs/
├── conf.py                        ← Sphinx configuration (loaded from .config/proman/docs.yaml)
├── toc.yaml                       ← Navigation tree (sphinx-external-toc)
└── source/
    ├── index.md                   ← Home page
    ├── intro.md + background/     ← Project introduction and conceptual background
    ├── user-guide/                ← User guide (installation, options, versioning)
    ├── dev-guide/                 ← This developer guide
    ├── features/                  ← AUTO-GENERATED (do not edit)
    └── library/                   ← AUTO-GENERATED (do not edit)
```

Navigation is controlled exclusively by `docs/toc.yaml` (`sphinx-external-toc`). Adding a new page requires:
1. Creating the `.md` file under `docs/source/`.
2. Adding the path (without `.md` extension) to `docs/toc.yaml` under the appropriate parent.

## Writing Feature Notes

Each feature can include a `notes.md` file at `features/<feature-id>/notes.md` with additional user-facing documentation. This content is appended to the auto-generated feature page. The filename is configured in `.config/proman/_main.yaml` (`filename.feature_notes`; currently `notes.md`).

**Rules:**
- Use only level-2 (`##`) and deeper headings — no `#` (H1).
- Do not repeat information already in `metadata.yaml` (options, descriptions, examples auto-generated from there).
- Focus on usage notes, gotchas, platform quirks, and troubleshooting that can't be expressed in YAML.

The following sections are automatically generated from `metadata.yaml` and must not be included in `notes.md`:
- Example Usage
- Options
- Lifecycle Commands
- Installation Order
- VS Code Extensions

## Writing Library API Annotations

Library module functions are documented via structured `# @brief` comments. The generator (`proman-gen-docs-data`) reads `lib/*.bash` and the small POSIX `lib/*.sh` subset, then produces API reference pages under `docs/source/library/`. See {doc}`/dev-guide/features/lib` for the full annotation format reference (module header, `@brief` syntax, block types, and section labels).

## JSON Schemas

JSON schemas listed in `.config/proman/docs.yaml` under `json_schemas_publish` are published to the docs site under `/schema/<stem>.json`. Currently published:

- `/schema/ospkg-manifest.json` — OS package dependency manifest schema
- `/schema/argparse-manifest.json` — Argparse manifest schema

To publish a new schema, add its repo-relative path to the `json_schemas_publish` list in `.config/proman/docs.yaml`. In schema files under `features/`, use relative `$ref` paths (e.g. `../lib/ospkg-manifest.schema.json`) so editor YAML language servers can resolve them locally.
