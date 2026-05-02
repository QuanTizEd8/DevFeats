# Workspace

The workspace is a git repository with the following key files and directories:

:`.dev/`:
    [Development workflows](/dev-guide/devops/dev) — local libraries and scripts for build, sync, validation, and other development routines.

:`.devcontainer/`:
    Dev Container configuration files for the project's [development environment](/dev-guide/environment), as well as auto-generated Dev Container configuration files for [live testing](/dev-guide/tests/live) local and released features.

:`.github/`:
    GitHub configuration files, including GitHub Actions [CI/CD pipelines](/dev-guide/devops/ops), and GitHub [Copilot customizations](/dev-guide/devops/ai).

:`.local/`:
    Git-ignored directory for temporary files like logs, build and test artifacts, scratch files, etc. Used for short-term storage during local development.

:`docs/`:
    Project [documentation](/dev-guide/docs) source files and website configuration.

:`features/`:
    [Feature](/dev-guide/features) source files, including metadata, installation scripts, and feature-specific user and developer documentation.

:`lib/`:
    [Shared library](/dev-guide/features/lib) source files, containing helper functions used by feature scripts.

:`test/`:
    [Tests](/dev-guide/tests) for features, the shared library, and local development workflows.

:`justfile`:
    Developer recipes — run `just --list` to see available tasks for common development routines.

:`.editorconfig`:
    shfmt style config (2-space, case-indent, etc.).

:`.shellcheckrc`:
    shellcheck defaults (shell=bash, external-sources=true).

:`lefthook.yml`:
    Lefthook configuration.


:::{admonition} Read-only directories
:class: danger

The following files and directories should **never be edited**; they are either fully auto-generated, git-ignored, symbolic links, or external dependencies:

:`.devcontainer/**/!(.dev)/**`:
    Other than the `.devcontainer/.dev/` directory, all files in `.devcontainer/` are either fully auto-generated (`.devcontainer/try-*/**` and `.devcontainer/test-*/**`) or symlinks (`.devcontainer/.src/`) for [live testing](/dev-guide/tests/live) of features in dev containers.

:`docs/source/features/`:
    Auto-generated directory for [feature documentation](/dev-guide/docs/features) generated from `features/` metadata and notes. The source of truth for feature documentation is the `metadata.yaml` and `NOTES.md` files in each `features/<id>/` directory.

:`docs/source/library/`:
    Auto-generated directory for [library documentation](/dev-guide/docs/library) generated from `lib/` source files. The source of truth for library documentation is the docstrings in the source code.

:`src/`:
    [Feature Output](/dev-guide/features/src) — publication-ready feature scripts generated from `features/` and `lib/`.

:`test/unit/bats/`:
    [Bats Testing Framework](/dev-guide/tests/unit) — Git submodule containing the Bats testing framework for unit tests.

:::
