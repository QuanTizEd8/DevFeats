"""Unit tests for .github/workflows/scripts/cicd_detect.py.

Focuses on regression-prone helpers that drive CI job decisions:
- glob-style decision-group matching used by ``any_match``
- macOS-capable feature discovery derived from ``find`` output

Run with:

    python3 -m unittest test.scripts.test_cicd_detect
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCRIPT_PATH = REPO_ROOT / ".github" / "workflows" / "scripts" / "cicd_detect.py"


def _load_module():
    """Import cicd_detect.py under a valid identifier name."""
    spec = importlib.util.spec_from_file_location("cicd_detect", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("cicd_detect", mod)
    spec.loader.exec_module(mod)
    return mod


CD = _load_module()


class AnyMatchTest(unittest.TestCase):
    """Decision-group path matching semantics."""

    def test_recursive_double_star_matches_nested_paths(self):
        changed = [
            "lib/foo/bar.baz",
            "test/unit/subsuite/example.bats",
            ".devcontainer/.dev/nested/config.json",
        ]
        self.assertTrue(CD.any_match(changed, ["lib/**"]))
        self.assertTrue(CD.any_match(changed, ["test/unit/**"]))
        self.assertTrue(CD.any_match(changed, [".devcontainer/.dev/**"]))

    def test_no_pattern_match_returns_false(self):
        changed = ["docs/source/index.md", "README.md"]
        self.assertFalse(CD.any_match(changed, ["lib/**", "test/unit/**"]))


class DiscoverMacosCapableTest(unittest.TestCase):
    """Parity with shell `find ... -path "*/macos/*"` behavior."""

    def test_accepts_both_single_and_two_segment_feature_paths(self):
        find_output = "\n".join(
            [
                "test/install-git/macos/package_default.sh",
                "test/vendor/install-homebrew/macos/default.sh",
                "test/dist/scenarios/macos/build.sh",
                "test/install-gh/linux/default.sh",
            ]
        )
        with mock.patch.object(CD, "sh", return_value=find_output):
            got = CD.discover_macos_capable()

        # `dist/scenarios` is intentionally included because the original shell
        # implementation includes every `*/macos/*.sh` candidate under test/.
        self.assertEqual(got, ["dist/scenarios", "install-git", "vendor/install-homebrew"])

    def test_empty_find_output_returns_empty_list(self):
        with mock.patch.object(CD, "sh", return_value=""):
            self.assertEqual(CD.discover_macos_capable(), [])


if __name__ == "__main__":
    unittest.main()
