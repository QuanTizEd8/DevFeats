# DevOps

This section covers the development infrastructure, CI/CD pipelines, and operational practices for the project.

::::{grid} 1
:gutter: 3

:::{grid-item-card} Task Architecture
:class-title: sd-text-center
:link: devops/dev
:link-type: doc

The four-tier task system (`just` → `pixi` → `proman` → `.dev/scripts`), naming conventions, and the complete task reference.
:::

:::{grid-item-card} CI/CD Pipelines
:class-title: sd-text-center
:link: devops/ci
:link-type: doc

GitHub Actions workflows, change-detection logic, version-bump discipline, and the deployment pipeline (GHCR + GitHub Releases).
:::

:::{grid-item-card} Operations
:class-title: sd-text-center
:link: devops/ops
:link-type: doc

Post-deployment operations: making packages public on GHCR, registering the feature collection on containers.dev, and managing private features in Codespaces.
:::

:::{grid-item-card} AI Agents
:class-title: sd-text-center
:link: devops/ai
:link-type: doc

The GitHub Copilot customizations and AI agent definitions used for feature development and code review.
:::

::::
