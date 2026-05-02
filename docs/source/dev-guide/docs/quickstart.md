# Quickstart Guide

```
docs/
├── dev-guide/      ← This guide (development workflow, testing, publishing, CI)
│   ├── index.md
│   ├── repo-structure.md   ← This document
│   ├── ci.md
│   ├── writing-features.md
│   ├── testing.md
│   └── publishing.md
├── snippets/       ← Short reusable fragments (commands, layout, code style)
├── intro/          ← User-facing introduction and background
└── features/       ← Sphinx-generated feature pages (build-time)
```

Per-feature **developer** references for implementers live next to the feature: `features/<id>/dev-notes/feature.md` and `implementation.md` where present. User-facing notes: `features/<id>/NOTES.md`.

- `docs/`: Documentation.
  - `docs/snippets/`: Short, reusable fragments (commands, layout summary, code style) linked from the dev guide and agent instructions.
  - `docs/dev-guide/`: Developer guide
    - `docs/dev-guide/writing-features.md` — feature anatomy, options, scripts, full library reference
    - `docs/dev-guide/testing.md` — test structure, writing scenarios, running locally
    - `docs/dev-guide/repo-structure.md` — annotated directory tree, sync mechanism
    - `docs/dev-guide/ci.md` — GitHub Actions orchestration (`cicd.yaml`, `ci.yaml`, `cd.yaml`)
    - `docs/dev-guide/publishing.md` — versioning, release, GHCR, containers.dev index
