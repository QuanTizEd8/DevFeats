
| Task | Command |
|------|---------|
| Sync auto-generated files | `bash scripts/sync-lib.sh` |
| Verify auto-generated files are up to date | `bash scripts/sync-lib.sh --check` |
| Format all shell files | `make format` |
| Check formatting (CI-style, no writes) | `make format-check` |
| Lint all shell files | `make lint` |
| Test one feature (scenarios + fail cases) | `bash test/run.sh feature <feature>` |
| Run lib/ unit tests (all) | `make test-unit` |
| Run lib/ unit tests (one module) | `bash test/run-unit.sh --module <name>` (e.g. `os`, `shell`, `ospkg`) |
| Release to GHCR + GitHub Release | Push a `v*` tag, or `workflow_dispatch` on `cicd.yaml` with a `tag` input |
| Publish only (skip tests) | `workflow_dispatch` on `cd.yaml` with a `tag` input |
