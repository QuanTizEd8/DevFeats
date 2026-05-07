"""Tests for proman.release.detect."""

import pathlib
import tempfile
from unittest import mock

import pytest
import yaml
from proman.release.detect import _release_exists, detect_releasable
from pylinks.exception.api import WebAPIPersistentStatusCodeError


def _make_status_error(status_code: int) -> WebAPIPersistentStatusCodeError:
    response = mock.Mock()
    response.status_code = status_code
    exc = WebAPIPersistentStatusCodeError.__new__(WebAPIPersistentStatusCodeError)
    exc.response = response
    return exc


def _make_repo(*, side_effect=None, return_value=None):
    repo = mock.Mock()
    if side_effect is not None:
        repo._rest_query.side_effect = side_effect
    else:
        repo._rest_query.return_value = return_value
    return repo


def test_200_means_release_exists():
    repo = _make_repo(return_value={"tag_name": "foo/1.0.0"})
    assert _release_exists(repo, "foo/1.0.0")


def test_404_means_release_missing():
    repo = _make_repo(side_effect=_make_status_error(404))
    assert not _release_exists(repo, "foo/1.0.0")


def test_other_http_status_raises():
    repo = _make_repo(side_effect=_make_status_error(500))
    with pytest.raises(RuntimeError, match="foo/1.0.0"):
        _release_exists(repo, "foo/1.0.0")


def test_tag_is_url_encoded():
    repo = _make_repo(return_value={})
    _release_exists(repo, "install-pixi/1.2.3")
    call_args = repo._rest_query.call_args[0][0]
    assert "install-pixi%2F1.2.3" in call_args


def _write_metadata(features_dir: pathlib.Path, feature_id: str, version: str) -> None:
    d = features_dir / feature_id
    d.mkdir()
    (d / "metadata.yaml").write_text(yaml.dump({"version": version}), encoding="utf-8")


def test_returns_features_without_release():
    with tempfile.TemporaryDirectory() as tmp:
        features_dir = pathlib.Path(tmp)
        _write_metadata(features_dir, "feat-a", "1.0.0")
        _write_metadata(features_dir, "feat-b", "2.0.0")

        with mock.patch("proman.release.detect.GitHub") as MockGH:
            repo = mock.Mock()
            MockGH.return_value.user.return_value.repo.return_value = repo

            def side_effect(path):
                if "feat-a" in path:
                    raise _make_status_error(404)

            repo._rest_query.side_effect = side_effect
            result = detect_releasable("owner/name", features_dir)

    assert result == [{"feature": "feat-a", "version": "1.0.0", "tag": "feat-a/1.0.0"}]


def test_skips_features_without_version():
    with tempfile.TemporaryDirectory() as tmp:
        features_dir = pathlib.Path(tmp)
        d = features_dir / "no-version"
        d.mkdir()
        (d / "metadata.yaml").write_text(yaml.dump({"name": "test"}), encoding="utf-8")

        with mock.patch("proman.release.detect.GitHub") as MockGH:
            repo = mock.Mock()
            MockGH.return_value.user.return_value.repo.return_value = repo
            result = detect_releasable("owner/name", features_dir)

    assert result == []
    repo._rest_query.assert_not_called()
