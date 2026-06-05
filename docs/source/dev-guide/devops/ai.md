# AI Agents & Copilot

The repository includes structured AI customizations for GitHub Copilot and autonomous AI agents.

## Copilot Instructions

`.github/copilot-instructions.md` provides project-wide context to GitHub Copilot Chat. It describes the project structure, conventions, and key file relationships so that Copilot suggestions are aligned with project patterns.

## Instruction Files (`.github/instructions/`)

Per-topic instruction files provide focused context for specific areas of the codebase. Each file has an `applyTo` glob that tells Copilot when to apply the instructions:

| File | `applyTo` glob | Content |
|------|----------------|---------|
| `features.instructions.md` | `features/**/*` | Feature metadata and install script conventions |
| `lib.instructions.md` | `lib/**/*` | Library module conventions and documentation format |
| `test.instructions.md` | `test/**/*` | Test scenarios, checks, BATS test patterns |
| `src.instructions.md` | `src/**/*` | Generated `src/` — not to be edited directly |
| `docs.instructions.md` | `docs/**/*` | Documentation structure, MyST, auto-generated sections |
| `dev.instructions.md` | `.dev/**/*` | Development infrastructure, proman, task architecture |
| `devcontainer.instructions.md` | `.devcontainer/**/*` | Dev container configuration |
| `github.instructions.md` | `.github/**/*` | CI/CD workflows and GitHub Actions |
| `config.instructions.md` | `.config/**/*` | Project configuration files |

These files are read automatically by Copilot when the active file matches the `applyTo` pattern.

## AI Agents (`.github/agents/`)

The repository includes agent definition files for specialized AI-driven workflows. These agents are invoked via Copilot Workspace or compatible tools:

| Agent | Purpose |
|-------|---------|
| `feature-designer.agent.md` | Design a new feature: research the tool, plan options, dependencies, and install methods |
| `feature-researcher.agent.md` | Research a tool's installation methods, versioning, and platform support |
| `feature-research-reviewer.agent.md` | Review and validate feature research outputs |
| `feature-developer.agent.md` | Implement a feature from a design: write `metadata.yaml`, `install.bash`, notes, and tests |
| `feature-reviewer.agent.md` | Review a feature implementation for correctness, conventions, and completeness |
| `feature-manager.agent.md` | Oversee the feature lifecycle: coordinate designer, researcher, developer, and reviewer agents |
| `final-reviewer.agent.md` | Final QA review before merging: checks conventions, tests, docs, and version bumps |

## Updating AI Context

When adding a new file type, directory, or significant convention:

1. Update the relevant `.github/instructions/*.md` file with the new pattern or convention.
2. If the change requires a new focused context scope, add a new instructions file with an appropriate `applyTo` glob.
3. Update `copilot-instructions.md` if the overall project structure changes.
