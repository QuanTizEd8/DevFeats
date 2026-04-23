"""Unit tests for scripts/compute-bundle-tag.py.

Covers the pure helpers (semver parsing, bump classification, aggregate,
prior-tag discovery, feature-version discovery), the formatters, and the
retry-aware HTTP helper (``_github_get``) — all without hitting the
GitHub API. Run with:

    python3 -m unittest test.scripts.test_compute_bundle_tag

or:

    just test-scripts
"""

from __future__ import annotations

import importlib.util
import io
import pathlib
import sys
import textwrap
import tempfile
import unittest
import urllib.error
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCRIPT_PATH = REPO_ROOT / "scripts" / "compute-bundle-tag.py"


def _load_module():
    """Import compute-bundle-tag.py under a valid identifier name."""
    spec = importlib.util.spec_from_file_location("compute_bundle_tag", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("compute_bundle_tag", mod)
    spec.loader.exec_module(mod)
    return mod


CBT = _load_module()


class SemverHelpersTest(unittest.TestCase):
    def test_parse_semver_valid(self):
        self.assertEqual(CBT._parse_semver("0.0.0"), (0, 0, 0))
        self.assertEqual(CBT._parse_semver("1.2.3"), (1, 2, 3))
        self.assertEqual(CBT._parse_semver("10.20.30"), (10, 20, 30))

    def test_parse_semver_invalid(self):
        for bad in ("1.2", "1", "a.b.c", "", "1.2.3.4"):
            with self.subTest(spec=bad):
                with self.assertRaises(ValueError):
                    CBT._parse_semver(bad)

    def test_classify_bump(self):
        self.assertEqual(CBT._classify_bump((1, 2, 3), (1, 2, 3)), "none")
        self.assertEqual(CBT._classify_bump((1, 2, 3), (1, 2, 4)), "patch")
        self.assertEqual(CBT._classify_bump((1, 2, 3), (1, 3, 0)), "minor")
        self.assertEqual(CBT._classify_bump((1, 2, 3), (2, 0, 0)), "major")

    def test_classify_bump_downgrade_raises(self):
        with self.assertRaises(ValueError):
            CBT._classify_bump((1, 2, 3), (1, 2, 2))
        with self.assertRaises(ValueError):
            CBT._classify_bump((2, 0, 0), (1, 9, 9))

    def test_apply_bump(self):
        base = (1, 2, 3)
        self.assertEqual(CBT._apply_bump(base, "none"), (1, 2, 3))
        self.assertEqual(CBT._apply_bump(base, "patch"), (1, 2, 4))
        self.assertEqual(CBT._apply_bump(base, "minor"), (1, 3, 0))
        self.assertEqual(CBT._apply_bump(base, "major"), (2, 0, 0))

    def test_fmt_bundle(self):
        self.assertEqual(CBT._fmt_bundle((0, 0, 0)), "v0.0.0")
        self.assertEqual(CBT._fmt_bundle((1, 2, 3)), "v1.2.3")

    def test_max_bump(self):
        self.assertEqual(CBT._max_bump([]), "none")
        self.assertEqual(CBT._max_bump(["none", "none"]), "none")
        self.assertEqual(CBT._max_bump(["patch", "none"]), "patch")
        self.assertEqual(CBT._max_bump(["minor", "patch", "none"]), "minor")
        self.assertEqual(CBT._max_bump(["major", "minor", "patch"]), "major")


class PriorBundleTagTest(unittest.TestCase):
    def test_no_bundle_tags_returns_baseline(self):
        tags = ["install-pixi/0.1.0", "install-git/0.2.0"]
        self.assertEqual(CBT._prior_bundle_tag(tags, "v0.0.0"), "v0.0.0")

    def test_picks_highest_bundle_tag(self):
        tags = [
            "install-pixi/0.1.0",
            "v0.1.0",
            "v0.2.0",
            "v1.0.0",
            "v0.9.5",
            "install-git/1.0.0",
        ]
        self.assertEqual(CBT._prior_bundle_tag(tags, "v0.0.0"), "v1.0.0")

    def test_ignores_feature_like_bundle_tags(self):
        tags = ["v1.2.3-rc1", "v1.2.3"]
        self.assertEqual(CBT._prior_bundle_tag(tags, "v0.0.0"), "v1.2.3")

    def test_respects_custom_baseline(self):
        self.assertEqual(CBT._prior_bundle_tag([], "v9.9.9"), "v9.9.9")


class LatestFeatureVersionsTest(unittest.TestCase):
    def test_picks_highest_per_feature(self):
        tags = [
            "install-pixi/0.1.0",
            "install-pixi/0.2.0",
            "install-pixi/0.1.5",
            "install-git/1.0.0",
            "install-git/1.1.0",
            "v1.0.0",
            "something-else",
        ]
        result = CBT._latest_feature_versions(tags)
        self.assertEqual(result["install-pixi"], (0, 2, 0))
        self.assertEqual(result["install-git"], (1, 1, 0))
        self.assertNotIn("something-else", result)

    def test_returns_empty_for_no_feature_tags(self):
        tags = ["v1.0.0", "v2.0.0"]
        self.assertEqual(CBT._latest_feature_versions(tags), {})


class LoadFeaturesTest(unittest.TestCase):
    def test_reads_versions_from_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            features_dir = pathlib.Path(tmp)
            for fid, ver in (("install-pixi", "0.1.0"), ("install-git", "0.2.3")):
                fd = features_dir / fid
                fd.mkdir()
                (fd / "metadata.yaml").write_text(
                    textwrap.dedent(
                        f"""\
                        id: {fid}
                        version: {ver}
                        name: Install {fid}
                        """
                    ),
                    encoding="utf-8",
                )
            result = CBT._load_features(features_dir)
            self.assertEqual(result, {"install-pixi": "0.1.0", "install-git": "0.2.3"})

    def test_skips_missing_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            features_dir = pathlib.Path(tmp)
            fd = features_dir / "broken"
            fd.mkdir()
            (fd / "metadata.yaml").write_text("id: broken\n", encoding="utf-8")
            result = CBT._load_features(features_dir)
            self.assertEqual(result, {})


class ComputeTest(unittest.TestCase):
    """End-to-end _compute tests that stub out the GitHub tag discovery."""

    def setUp(self):
        self._orig = CBT._discover_tags

    def tearDown(self):
        CBT._discover_tags = self._orig

    def _stub_tags(self, tags):
        CBT._discover_tags = lambda repo, token: list(tags)

    def _make_features(self, features: dict[str, str]) -> pathlib.Path:
        tmp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(
            lambda: [p.unlink() for p in tmp.rglob("*") if p.is_file()]
            and [p.rmdir() for p in sorted(tmp.rglob("*"), reverse=True)]
            and tmp.rmdir()
        )
        for fid, ver in features.items():
            fd = tmp / fid
            fd.mkdir()
            (fd / "metadata.yaml").write_text(
                f"id: {fid}\nversion: {ver}\n", encoding="utf-8"
            )
        return tmp

    def test_fresh_repo_baseline_bump(self):
        """No bundle/per-feature tags yet → all features are 'new' (minor), → minor bundle bump."""
        self._stub_tags([])
        features_dir = self._make_features({"install-pixi": "0.1.0", "install-git": "0.2.0"})
        result = CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertEqual(result["prior_tag"], "v0.0.0")
        self.assertEqual(result["next_tag"], "v0.1.0")
        self.assertEqual(result["bump"], "minor")
        self.assertFalse(result["skip"])
        bumps = {item["id"]: item["bump"] for item in result["per_feature"]}
        self.assertEqual(bumps, {"install-pixi": "minor", "install-git": "minor"})

    def test_no_changes_skip(self):
        self._stub_tags(["v0.1.0", "install-pixi/0.1.0", "install-git/0.2.0"])
        features_dir = self._make_features(
            {"install-pixi": "0.1.0", "install-git": "0.2.0"}
        )
        result = CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertEqual(result["prior_tag"], "v0.1.0")
        self.assertEqual(result["next_tag"], "v0.1.0")
        self.assertEqual(result["bump"], "none")
        self.assertTrue(result["skip"])

    def test_patch_bump(self):
        self._stub_tags(["v1.0.0", "install-pixi/1.0.0", "install-git/1.0.0"])
        features_dir = self._make_features(
            {"install-pixi": "1.0.0", "install-git": "1.0.1"}
        )
        result = CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertEqual(result["prior_tag"], "v1.0.0")
        self.assertEqual(result["next_tag"], "v1.0.1")
        self.assertEqual(result["bump"], "patch")

    def test_minor_overrides_patch(self):
        self._stub_tags(["v1.0.0", "install-pixi/1.0.0", "install-git/1.0.0"])
        features_dir = self._make_features(
            {"install-pixi": "1.0.1", "install-git": "1.1.0"}
        )
        result = CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertEqual(result["bump"], "minor")
        self.assertEqual(result["next_tag"], "v1.1.0")

    def test_major_overrides_all(self):
        self._stub_tags(["v1.0.0", "install-pixi/1.0.0", "install-git/1.0.0"])
        features_dir = self._make_features(
            {"install-pixi": "2.0.0", "install-git": "1.1.0"}
        )
        result = CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertEqual(result["bump"], "major")
        self.assertEqual(result["next_tag"], "v2.0.0")

    def test_removed_feature_triggers_major(self):
        self._stub_tags(
            ["v1.0.0", "install-pixi/1.0.0", "install-git/1.0.0"]
        )
        # install-git removed from features/.
        features_dir = self._make_features({"install-pixi": "1.0.0"})
        result = CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertEqual(result["bump"], "major")
        self.assertEqual(result["next_tag"], "v2.0.0")
        removed = [
            item for item in result["per_feature"] if item.get("reason") == "removed"
        ]
        self.assertEqual(len(removed), 1)
        self.assertEqual(removed[0]["id"], "install-git")

    def test_downgrade_aborts(self):
        self._stub_tags(["v1.0.0", "install-pixi/1.2.0"])
        features_dir = self._make_features({"install-pixi": "1.1.0"})
        with self.assertRaises(SystemExit) as cm:
            CBT._compute("owner/repo", features_dir, "v0.0.0", None)
        self.assertIn("downgrade", str(cm.exception))


class FormattersTest(unittest.TestCase):
    def _make_record(self, **overrides):
        base = {
            "repo": "owner/repo",
            "prior_tag": "v0.1.0",
            "next_tag": "v0.2.0",
            "bump": "minor",
            "skip": False,
            "per_feature": [
                {"id": "install-pixi", "prev": "0.1.0", "curr": "0.2.0", "bump": "minor"},
                {"id": "install-git", "prev": "0.2.0", "curr": "0.2.0", "bump": "none"},
                {"id": "install-new", "prev": None, "curr": "0.1.0", "bump": "minor", "reason": "new"},
            ],
            "features_now": {
                "install-pixi": "0.2.0",
                "install-git": "0.2.0",
                "install-new": "0.1.0",
            },
        }
        base.update(overrides)
        return base

    def test_format_json_excludes_features_now(self):
        import json

        record = self._make_record()
        parsed = json.loads(CBT._format_json(record))
        self.assertNotIn("features_now", parsed)
        self.assertEqual(parsed["next_tag"], "v0.2.0")
        self.assertEqual(parsed["bump"], "minor")

    def test_format_notes_contains_tags_and_bumps(self):
        record = self._make_record()
        text = CBT._format_notes(record)
        self.assertIn("v0.2.0", text)
        self.assertIn("v0.1.0", text)
        self.assertIn("install-pixi", text)
        self.assertIn("install-new", text)
        self.assertIn("new", text)
        self.assertIn("minor", text)

    def test_format_manifest_yaml_has_features_map(self):
        import yaml

        record = self._make_record()
        text = CBT._format_manifest(record, commit="deadbeef")
        data = yaml.safe_load(text)
        self.assertEqual(data["bundle"], "v0.2.0")
        self.assertEqual(data["commit"], "deadbeef")
        self.assertEqual(
            data["features"],
            {"install-pixi": "0.2.0", "install-git": "0.2.0", "install-new": "0.1.0"},
        )


# ─── Retry-aware HTTP helper tests ─────────────────────────────────────────────


class _FakeResponse:
    """Minimal stand-in for ``urllib.request.urlopen`` context manager."""

    def __init__(self, status: int, body: bytes = b""):
        self.status = status
        self._body = body

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        return False

    def read(self) -> bytes:
        return self._body


def _make_http_error(url: str, code: int, body: bytes = b"") -> urllib.error.HTTPError:
    """Build an ``HTTPError`` whose ``read()`` returns ``body``."""
    return urllib.error.HTTPError(
        url=url, code=code, msg="simulated", hdrs=None, fp=io.BytesIO(body)
    )


class GithubGetRetryTest(unittest.TestCase):
    """Cover the retry / URLError behaviour of ``_github_get``."""

    def setUp(self):
        # Speed up the tests: no real back-off sleeps.
        self._sleep_patch = mock.patch.object(CBT.time, "sleep", lambda *_: None)
        self._sleep_patch.start()
        self.addCleanup(self._sleep_patch.stop)

    def _patch_urlopen(self, side_effect):
        return mock.patch.object(CBT.urllib.request, "urlopen", side_effect=side_effect)

    def test_success_first_try(self):
        with self._patch_urlopen([_FakeResponse(200, b"ok")]):
            status, body = CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"ok")

    def test_retries_transient_http_then_succeeds(self):
        seq = [
            _make_http_error("https://api.github.com/x", 503),
            _make_http_error("https://api.github.com/x", 502),
            _FakeResponse(200, b"ok-after-retries"),
        ]
        with self._patch_urlopen(seq) as mock_urlopen:
            status, body = CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"ok-after-retries")
        self.assertEqual(mock_urlopen.call_count, 3)

    def test_non_transient_http_returned_immediately(self):
        """404 (and similar) must be returned as-is, not retried."""
        seq = [_make_http_error("https://api.github.com/x", 404, b"not found")]
        with self._patch_urlopen(seq) as mock_urlopen:
            status, body = CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(status, 404)
        self.assertEqual(body, b"not found")
        self.assertEqual(mock_urlopen.call_count, 1)

    def test_urlerror_retried_then_raises_runtime_error(self):
        """URLError must be retried and raise RuntimeError after exhaustion.

        Regression: the old implementation only caught ``HTTPError`` so a
        genuine network failure (timeout, DNS, connection refused) would
        crash the script with an unhandled exception.
        """
        err = urllib.error.URLError("Temporary failure in name resolution")
        seq = [err, err, err]
        with self._patch_urlopen(seq) as mock_urlopen:
            with self.assertRaises(RuntimeError) as cm:
                CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(mock_urlopen.call_count, CBT._MAX_ATTEMPTS)
        self.assertIn("network error", str(cm.exception))

    def test_urlerror_then_success(self):
        err = urllib.error.URLError("Connection reset by peer")
        seq = [err, _FakeResponse(200, b"recovered")]
        with self._patch_urlopen(seq) as mock_urlopen:
            status, body = CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"recovered")
        self.assertEqual(mock_urlopen.call_count, 2)

    def test_timeout_urlerror_is_retried(self):
        """``socket.timeout`` surfaces as ``URLError`` — must be retried."""
        import socket

        err = urllib.error.URLError(socket.timeout("timed out"))
        seq = [err, _FakeResponse(200, b"ok")]
        with self._patch_urlopen(seq):
            status, body = CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"ok")

    def test_transient_http_exhausts_retries_returns_final_status(self):
        """After _MAX_ATTEMPTS transient HTTP responses, the final ``(status,
        body)`` is returned — callers decide whether it's fatal."""
        seq = [
            _make_http_error("https://api.github.com/x", 500, b"boom")
            for _ in range(CBT._MAX_ATTEMPTS)
        ]
        with self._patch_urlopen(seq) as mock_urlopen:
            status, body = CBT._github_get("https://api.github.com/x", None)
        self.assertEqual(status, 500)
        self.assertEqual(body, b"boom")
        self.assertEqual(mock_urlopen.call_count, CBT._MAX_ATTEMPTS)

    def test_authorization_header_sent_when_token_present(self):
        """Regression: the token must be forwarded as a Bearer header."""
        captured: dict[str, str] = {}

        def _fake_urlopen(req, timeout):  # noqa: ARG001
            # Store the headers so the test can assert on them.
            for k, v in req.header_items():
                captured[k] = v
            return _FakeResponse(200, b"ok")

        with mock.patch.object(CBT.urllib.request, "urlopen", side_effect=_fake_urlopen):
            CBT._github_get("https://api.github.com/x", "supersecret")
        # urllib normalises header names to Title-Case.
        self.assertEqual(captured.get("Authorization"), "Bearer supersecret")
        self.assertIn("sysset-compute-bundle-tag", captured.get("User-agent", ""))


if __name__ == "__main__":
    unittest.main()
