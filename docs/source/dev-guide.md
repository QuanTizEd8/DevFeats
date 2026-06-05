# Developer Guide

This guide covers everything needed to contribute to |{{project_name}}|: setting up the development environment, understanding the repository layout, writing and testing features, maintaining documentation, and DevOps practices.


::::{grid} 1
:gutter: 3

:::{grid-item-card} Quickstart Guide
:class-title: sd-text-center
:link: dev-guide/quickstart
:link-type: doc

**New here?** Start with the quickstart guide — it gets you from zero to a working contribution in one page.
:::


:::{grid-item-card} Environment & Workspace
:class-title: sd-text-center

- {doc}`dev-guide/environment` — Set up the dev container and get tools installed.
- {doc}`dev-guide/workspace` — Annotated directory tree, read-only paths, naming conventions.
- {doc}`dev-guide/workflow` — `just` tasks, code style, and day-to-day commands.
:::


:::{grid-item-card} Features
:class-title: sd-text-center
:link: dev-guide/features
:link-type: doc

How to write and maintain features: directory layout, `metadata.yaml`, `install.bash`, the shared library, and how `src/` is generated.
:::


:::{grid-item-card} Testing
:class-title: sd-text-center
:link: dev-guide/tests
:link-type: doc

Feature scenario tests (`scenarios.yaml` + `checks.yaml`), library unit tests (BATS), development infrastructure tests, and running tests locally or in CI.
:::


:::{grid-item-card} Documentation
:class-title: sd-text-center
:link: dev-guide/docs
:link-type: doc

How the docs site is structured, how to build it locally, and how to write feature notes and library annotations.
:::


:::{grid-item-card} DevOps
:class-title: sd-text-center
:link: dev-guide/devops
:link-type: doc

Development infrastructure, task architecture (`just` → `pixi` → `proman`), GitHub Actions workflows, deployment to GHCR and GitHub Releases, and operations.
:::

::::
