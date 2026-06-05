# Build System Tests

The Python build system (`proman`) has its own pytest test suite under `test/proman/`.

## Running

```bash
just test-py                  # run all proman tests
```

Tests run in the `test` pixi environment (activated automatically via `pixi run --environment test`).

## What's Covered

| Test file | What it tests |
|-----------|--------------|
| `test_metadata.py` | Feature metadata parsing and validation |
| `test_config.py` | Project config loading (`_main.yaml`, `ci.yaml`, `docs.yaml`) |
| `test_config_schema.py` | Config schema validation |
| `test_codegen.py` | `install.bash` code generation from templates |
| `test_install_script_codegen.py` | Generated install script structure and content |
| `test_argparse_manifest_schema.py` | Argparse manifest schema validation |
| `test_schema_bundle.py` | JSON schema bundling for docs publication |
| `test_feature_env.py` | Feature environment variable computation |
| `test_cicd_detect.py` | CI/CD change detection logic |
| `test_detect_releasable.py` | Release detection (features needing new GitHub Releases) |
| `test_run_install.py` | Test runner injection logic |
| `test_test_runner_injection.py` | Test script generation from `checks.yaml` |

## When to Add Tests

Add or update `test/proman/` tests when:

- Changing feature metadata parsing logic in `.dev/lib/proman/metadata.py`
- Changing code generation in `.dev/lib/proman/sync/install_script.py`
- Changing config loading in `.dev/lib/proman/config.py`
- Adding a new proman CLI command
- Changing schema validation or bundling logic
- Changing the test generation pipeline

## Running in CI

Python tests run in the `test-dev` workflow (`.github/workflows/test-dev.yaml`), triggered by changes to `.dev/lib/**`, `.config/proman/**`, or `test/proman/**`.
