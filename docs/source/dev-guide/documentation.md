# Documentation

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
