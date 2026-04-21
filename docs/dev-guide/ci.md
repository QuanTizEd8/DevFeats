# CI

| Workflow | Trigger | Purpose |
|---|---|---|
| `test.yaml` | Push/PR to `main` | Integration tests for changed features |
| `test-unit.yaml` | Push/PR touching `lib/**` | bats unit tests on `ubuntu-latest` + `macos-latest` |
| `lint.yaml` | Every push/PR | shfmt + shellcheck |
| `validate.yml` | PR | JSON schema validation of `devcontainer-feature.json` |
| `release.yaml` | Push `v*` tag / `workflow_dispatch` | Publish to GHCR + GitHub Releases |
