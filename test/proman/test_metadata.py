"""Tests for proman.metadata — the central feature metadata module."""

from __future__ import annotations

from pathlib import Path

import proman.config as cfg
import pytest
import yaml
from proman.metadata import MetadataLoader

_MINIMAL_SHARED = """\
_lifecycle_key_prefix: myowner-test--
_env_vars:
  _FEAT_SHARE_DIR_ROOT: /usr/local/share/myowner/test/${{ id }}$
options:
  shared_opt:
    type: string
    default: hello
    description: Injected shared option.
  locked_opt:
    type: string
    default: from-shared
    description: Shared option that must not be overridden.
"""


def _minimal_feature_metadata(**overrides: object) -> dict:
    """Return metadata.yaml content that passes schema validation."""
    base = {
        "version": "1.0.0",
        "name": "Test Feature",
        "description": "Short description.",
        "_long_description": "Longer description for docs.",
        "keywords": ["test"],
        "options": {},
    }
    base.update(overrides)
    return base


@pytest.fixture(autouse=True)
def _reset_config_singleton() -> None:
    """Ensure isolated tests do not leave a patched config pointing at tmp_path."""
    yield
    cfg.clear_cache()


_MINIMAL_MAIN = """\
name: Test
name_slug: test
owner: myowner
owner_slug: myowner
namespace: myowner/test
repo_url: https://github.com/myowner/test
oci_base: ghcr.io/myowner/test
path:
  features: features
  library: lib
  shared_metadata: features/metadata.shared.yaml
  metadata_schema: features/metadata.schema.json
filename:
  feature_metadata: metadata.yaml
features:
  lifecycle_hook_keys:
    - onCreateCommand
"""


@pytest.fixture
def repo_root() -> Path:
    """Return the repository root path."""
    return Path(__file__).resolve().parents[2]


@pytest.fixture
def features_dir(repo_root: Path) -> Path:
    """Return the path to the features/ directory."""
    return repo_root / "features"


def _write_test_repo(
    tmp_path: Path,
    *,
    feature_metadata: dict | None = None,
    shared_yaml: str = _MINIMAL_SHARED,
) -> Path:
    """Create a minimal repo layout under *tmp_path* for MetadataLoader tests."""
    proman_dir = tmp_path / ".config" / "proman"
    proman_dir.mkdir(parents=True)
    (proman_dir / "_main.yaml").write_text(_MINIMAL_MAIN, encoding="utf-8")

    features = tmp_path / "features"
    features.mkdir()
    (features / "metadata.shared.yaml").write_text(shared_yaml, encoding="utf-8")

    schema_src = (
        Path(__file__).resolve().parents[2] / "features" / "metadata.schema.json"
    )
    (features / "metadata.schema.json").write_text(
        schema_src.read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    if feature_metadata is not None:
        feat_dir = features / "test-feature"
        feat_dir.mkdir()
        (feat_dir / "metadata.yaml").write_text(
            yaml.dump(feature_metadata),
            encoding="utf-8",
        )
    return tmp_path


def _loader_for(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> MetadataLoader:
    monkeypatch.setattr("proman.config.git_repo_root", lambda: tmp_path)
    cfg.clear_cache()
    return MetadataLoader()


# ── load (integration against real repo) ─────────────────────────────────────


def test_load_sets_id_and_oci_ref(features_dir: Path) -> None:
    """MetadataLoader sets ``id`` and ``_oci_ref`` on loaded features."""
    candidates = sorted(features_dir.glob("*/metadata.yaml"))
    assert candidates, "No real features found — check features/ directory."
    feat_id = candidates[0].parent.name
    result = MetadataLoader().load(feat_id)[feat_id]
    assert result["id"] == feat_id
    assert result["_oci_ref"].startswith("ghcr.io/")
    assert feat_id in result["_oci_ref"]


def test_load_returns_all_valid_features() -> None:
    """MetadataLoader.load() returns a non-empty dict keyed by feature IDs."""
    all_meta = MetadataLoader().load()
    assert len(all_meta) > 0
    for feat_id, meta in all_meta.items():
        assert meta["id"] == feat_id
        assert "_oci_ref" in meta


def test_load_injects_shared_options() -> None:
    """Shared options from metadata.shared.yaml appear in feature options."""
    meta = MetadataLoader().load("install-git")["install-git"]
    assert "log_level" in meta["options"]


# ── load (isolated tmp_path repo) ─────────────────────────────────────────────


def test_load_missing_metadata_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Missing metadata.yaml raises ValueError."""
    _write_test_repo(tmp_path)
    loader = _loader_for(tmp_path, monkeypatch)
    with pytest.raises(ValueError, match="Metadata file not found"):
        loader.load("ghost")


def test_load_invalid_yaml_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Malformed YAML raises ValueError."""
    root = _write_test_repo(tmp_path)
    feat_dir = root / "features" / "bad-yaml"
    feat_dir.mkdir()
    (feat_dir / "metadata.yaml").write_text("key: [\n  invalid", encoding="utf-8")
    loader = _loader_for(tmp_path, monkeypatch)
    with pytest.raises(ValueError, match="Error reading metadata"):
        loader.load("bad-yaml")


def test_load_not_a_mapping_raises(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """YAML that parses to a non-dict raises ValueError."""
    root = _write_test_repo(
        tmp_path,
        feature_metadata=["not", "a", "dict"],  # type: ignore[arg-type]
    )
    loader = _loader_for(root, monkeypatch)
    with pytest.raises(ValueError, match="not a YAML mapping"):
        loader.load("test-feature")


def test_load_merges_shared_options(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Shared options are merged into the feature's options dict."""
    root = _write_test_repo(tmp_path, feature_metadata=_minimal_feature_metadata())
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert "shared_opt" in result["options"]


def test_load_feature_options_override_shared(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Feature-defined options take precedence over shared metadata defaults."""
    metadata = _minimal_feature_metadata(
        options={
            "locked_opt": {"type": "string", "default": "oops", "description": "x"},
        },
    )
    root = _write_test_repo(tmp_path, feature_metadata=metadata)
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    assert result["options"]["locked_opt"]["default"] == "oops"


def test_load_applies_shared_option_conditions() -> None:
    """Shared options with ``_apply_when`` are injected only when condition holds."""
    with_fetch = MetadataLoader().load("install-pixi")["install-pixi"]
    without_fetch = MetadataLoader().load("install-git")["install-git"]
    assert "fetch_headers" in with_fetch["options"]
    assert "fetch_headers" not in without_fetch["options"]


def test_load_substitutes_template_variables(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """${{ _project }} and ${{ _env_vars }} templates are expanded."""
    metadata = _minimal_feature_metadata(
        description="Test ${{ _project.name_slug }}$.",
        entrypoint={
            "command": (
                "${{ _env_vars._FEAT_SHARE_DIR_ROOT }}$/entrypoint.sh "
                "${containerWorkspaceFolder}"
            ),
        },
        onCreateCommand={
            "run": {
                "command": (
                    "sh ${{ _env_vars._FEAT_SHARE_DIR_ROOT }}$/on-create.sh || true"
                ),
                "description": "Run on-create hook.",
            },
        },
    )
    root = _write_test_repo(tmp_path, feature_metadata=metadata)
    result = _loader_for(root, monkeypatch).load("test-feature")["test-feature"]
    expected_share = "/usr/local/share/myowner/test/test-feature"
    assert result["entrypoint"] == {
        "command": f"{expected_share}/entrypoint.sh ${{containerWorkspaceFolder}}",
    }
    expected_lc_key = "myowner-test--run"
    assert list(result["onCreateCommand"].keys()) == [expected_lc_key]
    assert result["onCreateCommand"][expected_lc_key]["command"] == (
        f"sh {expected_share}/on-create.sh || true"
    )
    assert result["description"] == "Test test."
