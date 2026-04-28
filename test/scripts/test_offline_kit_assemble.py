"""Tests for ``scripts/offline_kit_assemble.py`` helpers (no dist/tar I/O)."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCRIPT_PATH = REPO_ROOT / "scripts" / "offline_kit_assemble.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("offline_kit_assemble", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("offline_kit_assemble", mod)
    spec.loader.exec_module(mod)
    return mod


OKA = _load_module()


class ManifestVersionCheckTest(unittest.TestCase):
    def test_ok(self):
        self.assertIsNone(
            OKA._check_manifest_version_matches_tag(
                {"version": "v1.0.0"}, "v1.0.0"
            )
        )

    def test_mismatch(self):
        self.assertIn(
            "does not match",
            OKA._check_manifest_version_matches_tag(
                {"version": "v1.0.0"}, "v1.0.1"
            )
            or "",
        )

    def test_empty_manifest_version(self):
        self.assertIn(
            "version",
            OKA._check_manifest_version_matches_tag({}, "v1.0.0") or "",
        )

    def test_empty_tag(self):
        self.assertIn(
            "non-empty",
            OKA._check_manifest_version_matches_tag({"version": "v1.0.0"}, "") or "",
        )


if __name__ == "__main__":
    unittest.main()
