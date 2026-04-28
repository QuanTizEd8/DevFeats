#!/usr/bin/env python3
"""Merge default GitHub auth into devcontainer feature scenario JSON.

The devcontainers CLI does not apply shared defaults to each scenario; image-only
scenarios omit ``build.args``, so feature install scripts never see
``GITHUB_TOKEN`` during ``docker build`` and unauthenticated GitHub API calls hit
rate limits. CI sets ``GITHUB_TOKEN`` (``secrets.GITHUB_TOKEN``); this tool ensures
every scenario passes it via:

    "build": { "args": { "GITHUB_TOKEN": "${localEnv:GITHUB_TOKEN}" } }

which devcontainers substitutes from the host environment.

Used by ``test/run.sh feature`` on a temporary copy of ``test/`` so tracked
``scenarios.json`` files stay unchanged.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

TOKEN_REF = "${localEnv:GITHUB_TOKEN}"


def merge_github_token_into_scenario(scenario: object) -> bool:
    """Ensure scenario has build.args.GITHUB_TOKEN set to TOKEN_REF.

    Does not overwrite an existing GITHUB_TOKEN value. Returns True if the
    scenario dict was modified.
    """
    if not isinstance(scenario, dict):
        return False

    build = scenario.get("build")
    if build is None:
        scenario["build"] = {"args": {"GITHUB_TOKEN": TOKEN_REF}}
        return True
    if not isinstance(build, dict):
        print(
            f"warning: skipping scenario with non-object 'build': {type(build).__name__}",
            file=sys.stderr,
        )
        return False

    args = build.get("args")
    if args is None:
        build["args"] = {"GITHUB_TOKEN": TOKEN_REF}
        return True
    if not isinstance(args, dict):
        print(
            "warning: skipping scenario with non-object 'build.args': "
            f"{type(args).__name__}",
            file=sys.stderr,
        )
        return False
    if "GITHUB_TOKEN" in args:
        return False
    args["GITHUB_TOKEN"] = TOKEN_REF
    return True


def merge_scenarios_object(data: object) -> bool:
    """Merge TOKEN_REF into each top-level scenario. Returns True if any changed."""
    if not isinstance(data, dict):
        return False
    modified = False
    for _name, scenario in data.items():
        if merge_github_token_into_scenario(scenario):
            modified = True
    return modified


def merge_file(path: pathlib.Path) -> bool:
    """Load JSON, merge tokens, write back if modified. Returns True if written."""
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)
    if not merge_scenarios_object(data):
        return False
    path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
    return True


def merge_all_under_test_root(test_root: pathlib.Path) -> int:
    """Merge every ``test/<feature>/scenarios.json`` under *test_root*."""
    if not test_root.is_dir():
        print(f"error: not a directory: {test_root}", file=sys.stderr)
        return 1
    count = 0
    for path in sorted(test_root.glob("*/scenarios.json")):
        if merge_file(path):
            count += 1
            print(f"merged GITHUB_TOKEN into {path.relative_to(test_root)}")
    if count:
        print(f"updated {count} scenarios.json file(s) under {test_root}")
    else:
        print(f"no scenarios needed merging under {test_root}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "test_root",
        type=pathlib.Path,
        help="Path to the test/ directory (or a copy used as devcontainer project-folder)",
    )
    args = parser.parse_args(argv)
    return merge_all_under_test_root(args.test_root.expanduser().resolve())


if __name__ == "__main__":
    raise SystemExit(main())
