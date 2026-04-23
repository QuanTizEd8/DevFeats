"""Unit tests for scripts/detect-releasable.py.

Covers the retry-aware ``_github_request`` helper (including the URLError
path that previously crashed the script) and the ``_release_exists``
branching on HTTP status. Run with:

    python3 -m unittest test.scripts.test_detect_releasable

or:

    just test-scripts
"""

from __future__ import annotations

import importlib.util
import io
import pathlib
import sys
import unittest
import urllib.error
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCRIPT_PATH = REPO_ROOT / "scripts" / "detect-releasable.py"


def _load_module():
    """Import detect-releasable.py under a valid identifier name."""
    spec = importlib.util.spec_from_file_location("detect_releasable", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("detect_releasable", mod)
    spec.loader.exec_module(mod)
    return mod


DR = _load_module()


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
    return urllib.error.HTTPError(
        url=url, code=code, msg="simulated", hdrs=None, fp=io.BytesIO(body)
    )


class GithubRequestRetryTest(unittest.TestCase):
    """Retry + URLError behaviour of ``_github_request``."""

    def setUp(self):
        # Eliminate real back-off sleeps during tests.
        self._sleep_patch = mock.patch.object(DR.time, "sleep", lambda *_: None)
        self._sleep_patch.start()
        self.addCleanup(self._sleep_patch.stop)

    def _patch_urlopen(self, side_effect):
        return mock.patch.object(DR.urllib.request, "urlopen", side_effect=side_effect)

    def test_success_first_try(self):
        with self._patch_urlopen([_FakeResponse(200, b"ok")]):
            status, body = DR._github_request("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"ok")

    def test_retries_transient_http_then_succeeds(self):
        seq = [
            _make_http_error("https://api.github.com/x", 503),
            _make_http_error("https://api.github.com/x", 502),
            _FakeResponse(200, b"ok"),
        ]
        with self._patch_urlopen(seq) as mock_urlopen:
            status, body = DR._github_request("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"ok")
        self.assertEqual(mock_urlopen.call_count, 3)

    def test_404_returned_immediately(self):
        """404 is non-transient — must not be retried."""
        with self._patch_urlopen([_make_http_error("https://api.github.com/x", 404)]) as m:
            status, _ = DR._github_request("https://api.github.com/x", None)
        self.assertEqual(status, 404)
        self.assertEqual(m.call_count, 1)

    def test_urlerror_retried_then_raises_runtime_error(self):
        """Regression for the original bug: URLError was uncaught and crashed
        the script. Must now be retried and surface as ``RuntimeError``."""
        err = urllib.error.URLError("Temporary failure in name resolution")
        with self._patch_urlopen([err, err, err]) as m:
            with self.assertRaises(RuntimeError) as cm:
                DR._github_request("https://api.github.com/x", None)
        self.assertEqual(m.call_count, DR._MAX_ATTEMPTS)
        self.assertIn("network error", str(cm.exception))

    def test_urlerror_then_success(self):
        err = urllib.error.URLError("Connection reset by peer")
        with self._patch_urlopen([err, _FakeResponse(200, b"ok")]):
            status, body = DR._github_request("https://api.github.com/x", None)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"ok")

    def test_timeout_urlerror_is_retried(self):
        import socket

        err = urllib.error.URLError(socket.timeout("timed out"))
        with self._patch_urlopen([err, _FakeResponse(200, b"ok")]):
            status, _ = DR._github_request("https://api.github.com/x", None)
        self.assertEqual(status, 200)


class ReleaseExistsTest(unittest.TestCase):
    """Branching of ``_release_exists`` on HTTP status."""

    def _patch_request(self, return_value=None, side_effect=None):
        return mock.patch.object(
            DR, "_github_request", return_value=return_value, side_effect=side_effect
        )

    def test_200_means_release_exists(self):
        with self._patch_request(return_value=(200, b"{}")):
            self.assertTrue(DR._release_exists("owner/repo", "foo/1.0.0", None))

    def test_404_means_release_missing(self):
        with self._patch_request(return_value=(404, b"")):
            self.assertFalse(DR._release_exists("owner/repo", "foo/1.0.0", None))

    def test_tag_is_url_encoded(self):
        captured_url: list[str] = []

        def _stub(url, token):  # noqa: ARG001
            captured_url.append(url)
            return 404, b""

        with self._patch_request(side_effect=_stub):
            DR._release_exists("owner/repo", "install-pixi/1.2.3", None)
        # The "/" in the tag must be encoded so GitHub doesn't interpret
        # it as a path separator (otherwise we'd get a 404 for a valid tag).
        self.assertEqual(len(captured_url), 1)
        self.assertIn("install-pixi%2F1.2.3", captured_url[0])

    def test_other_http_status_raises(self):
        """A 500 (or 401/403/etc) must raise so the CI run stops rather than
        silently emitting a spurious release entry."""
        with self._patch_request(return_value=(500, b"boom")):
            with self.assertRaises(RuntimeError) as cm:
                DR._release_exists("owner/repo", "foo/1.0.0", None)
        self.assertIn("HTTP 500", str(cm.exception))

    def test_runtime_error_from_request_propagates(self):
        """If ``_github_request`` gives up on URLError, the RuntimeError must
        propagate unchanged so ``main()`` can convert it to exit 1."""
        with self._patch_request(side_effect=RuntimeError("unreachable")):
            with self.assertRaises(RuntimeError):
                DR._release_exists("owner/repo", "foo/1.0.0", None)


if __name__ == "__main__":
    unittest.main()
