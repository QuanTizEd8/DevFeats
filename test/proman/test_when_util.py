"""Tests for when_util YAML serialization."""

from __future__ import annotations

from proman.when_util import (
    serialize_path_entries,
    serialize_sysreq_args,
    serialize_value_entries,
    serialize_when,
    serialize_when_flow,
)


def test_serialize_when_dotted_keys() -> None:
    """Dotted-key condition objects serialize to YAML."""
    out = serialize_when({"os.id": "ubuntu", "plat.pm": "apt"})
    assert "os.id" in out
    assert "plat.pm" in out


def test_serialize_when_operator_dict() -> None:
    """Ordering operator conditions serialize to YAML."""
    out = serialize_when({"feat.version": {"gte": "1.0", "lt": "2.0"}})
    assert "gte" in out
    assert "feat.version" in out


def test_serialize_when_empty() -> None:
    """Empty or None when blocks serialize to empty string."""
    assert serialize_when({}) == ""
    assert serialize_when(None) == ""


def test_serialize_when_flow_one_line() -> None:
    """Flow YAML serializer produces compact single-line output."""
    out = serialize_when_flow({"plat.kernel": "darwin"})
    assert "\n" not in out or "{" in out


def test_serialize_sysreq_args_yaml_blobs() -> None:
    """Each sysreq spec becomes a $'...'-quoted YAML blob."""
    specs = [{"plat.kernel": "linux"}, {"os.id": "ubuntu"}]
    out = serialize_sysreq_args(specs)
    assert out.startswith("$'")
    assert "plat.kernel" in out


def test_serialize_path_entries_tab_yaml() -> None:
    """Path entries with when conditions serialize with tab separator."""
    entries = [{"path": "bin/tool", "when": {"feat.version": {"lte": "2.0"}}}]
    out = serialize_path_entries(entries)
    assert "bin/tool\t" in out
    assert "feat.version" in out


def test_serialize_value_entries_tab_yaml() -> None:
    """Value entries with when conditions serialize with tab separator."""
    entries = [{"value": "GOTOOLCHAIN=auto", "when": {"plat.kernel": "linux"}}]
    out = serialize_value_entries(entries)
    assert "GOTOOLCHAIN=auto\t" in out
    assert "plat.kernel" in out


def test_serialize_when_or_groups_preserve_keys() -> None:
    """OR groups preserve key order in the serialized output."""
    out = serialize_when([{"plat.kernel": "linux"}, {"plat.pm": "apt"}])
    assert "plat.kernel" in out
    assert "plat.pm" in out
    assert out.index("plat.kernel") < out.index("plat.pm")
