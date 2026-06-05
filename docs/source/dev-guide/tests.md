# Tests

The test suite has three layers, each targeting a different scope:

| Layer | Directory | Framework | Docker needed |
|-------|-----------|-----------|---------------|
| Library unit tests | `test/lib/` | BATS (Bash Automated Testing System) | No |
| Feature scenario tests | `test/features/<id>/` | devcontainer CLI + plain Docker | Yes (Linux) |
| Build system tests | `test/proman/` | pytest | No |

::::{grid} 1
:gutter: 3

:::{grid-item-card} Quickstart
:class-title: sd-text-center
:link: tests/quickstart
:link-type: doc

Test directory layout, which test to add for which change, and the most common run commands.
:::

:::{grid-item-card} Feature Tests
:class-title: sd-text-center
:link: tests/features
:link-type: doc

`scenarios.yaml` and `checks.yaml` formats, how test scripts are generated, running modes (devcontainer / standalone / macOS), and writing effective assertions.
:::

:::{grid-item-card} Library Unit Tests
:class-title: sd-text-center
:link: tests/lib
:link-type: doc

BATS test anatomy, `reload_lib`, stubs, subprocess isolation, and common pitfalls.
:::

:::{grid-item-card} Live Testing
:class-title: sd-text-center
:link: tests/live
:link-type: doc

Running features interactively in a dev container for manual verification.
:::

:::{grid-item-card} Build System Tests
:class-title: sd-text-center
:link: tests/dev
:link-type: doc

pytest tests for `proman` — the Python build system.
:::

::::
