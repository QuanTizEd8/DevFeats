"""Tests for proman.release.detect."""

import pathlib
import tempfile
from unittest import mock

import pytest
import yaml
from proman.release.detect import _release_exists, detect_releasable
from pylinks.exception.api import WebAPIPersistentStatusCodeError


def _make_status_error(status_code: int) -> WebAPIPersistentStatusCodeError:
    """Build a WebAPIPersistentStatusCodeError with the given status code."""
    response = mock.Mock()
    response.status_code = status_code
    exc = WebAPIPersistentStatusCodeError.__new__(WebAPIPersistentStatusCodeError)
    exc.response = response
    return exc


def _make_repo(
    *,
    side_effect: WebAPIPersistentStatusCodeError | None = None,
    return_value: dict | None = None,
) -> mock.Mock:
    """Build a mock repo with _rest_query configured."""
    repo = mock.Mock()
    if side_effect is not None:
        repo._rest_query.side_effect = side_effect
    else:
        repo._rest_query.return_value = return_value
    return repo


def test_200_means_release_exists() -> None:
    """Verify _release_exists returns True for a 200 response."""
    repo = _make_repo(return_value={"tag_name": "foo/1.0.0"})
    assert _release_exists(repo, "foo/1.0.0")


def test_404_means_release_missing() -> None:
    """Verify _release_exists returns False for a 404 response."""
    repo = _make_repo(side_effect=_make_status_error(404))
    assert not _release_exists(repo, "foo/1.0.0")


def test_other_http_status_raises() -> None:
    """Verify _release_exists raises RuntimeError for non-404 HTTP errors."""
    repo = _make_repo(side_effect=_make_status_error(500))
    with pytest.raises(RuntimeError, match=r"foo/1\.0\.0"):
        _release_exists(repo, "foo/1.0.0")


def test_tag_is_url_encoded() -> None:
    """Verify release tag slashes are URL-encoded in the query path."""
    repo = _make_repo(return_value={})
    _release_exists(repo, "install-pixi/1.2.3")
    call_args = repo._rest_query.call_args[0][0]
    assert "install-pixi%2F1.2.3" in call_args


def _write_metadata(
    features_dir: pathlib.Path, feature_id: str, version: str,
) -> None:
    """Write a minimal metadata.yaml for a feature under features_dir."""
    d = features_dir / feature_id
    d.mkdir()
    (d / "metadata.yaml").write_text(yaml.dump({"version": version}), encoding="utf-8")


def test_returns_features_without_release() -> None:
    """Verify detect_releasable returns features whose release tag is missing."""
    with tempfile.TemporaryDirectory() as tmp:
        features_dir = pathlib.Path(tmp)
        _write_metadata(features_dir, "feat-a", "1.0.0")
        _write_metadata(features_dir, "feat-b", "2.0.0")

        with mock.patch("proman.release.detect.GitHub") as mock_gh:
            repo = mock.Mock()
            mock_gh.return_value.user.return_value.repo.return_value = repo

            def side_effect(path: str) -> None:
                if "feat-a" in path:
                    raise _make_status_error(404)

            repo._rest_query.side_effect = side_effect
            result = detect_releasable("owner/name", features_dir)

    assert result == [{"feature": "feat-a", "version": "1.0.0", "tag": "feat-a/1.0.0"}]


def test_skips_features_without_version() -> None:
    """Verify detect_releasable skips features that have no version field."""
    with tempfile.TemporaryDirectory() as tmp:
        features_dir = pathlib.Path(tmp)
        d = features_dir / "no-version"
        d.mkdir()
        (d / "metadata.yaml").write_text(yaml.dump({"name": "test"}), encoding="utf-8")

        with mock.patch("proman.release.detect.GitHub") as mock_gh:
            repo = mock.Mock()
            mock_gh.return_value.user.return_value.repo.return_value = repo
            result = detect_releasable("owner/name", features_dir)

    assert result == []
    repo._rest_query.assert_not_called()
