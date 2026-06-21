"""Tests for when_util YAML serialization."""

from __future__ import annotations

from proman.when_util import (
    serialize_binary_src,
    serialize_sysreq_args,
    serialize_when,
    serialize_when_flow,
)


def test_serialize_when_dotted_keys() -> None:
    out = serialize_when({"os.id": "ubuntu", "plat.pm": "apt"})
    assert "os.id" in out
    assert "plat.pm" in out


def test_serialize_when_operator_dict() -> None:
    out = serialize_when({"feat.version": {"gte": "1.0", "lt": "2.0"}})
    assert "gte" in out
    assert "feat.version" in out


def test_serialize_when_empty() -> None:
    assert serialize_when({}) == ""
    assert serialize_when(None) == ""


def test_serialize_when_flow_one_line() -> None:
    out = serialize_when_flow({"plat.kernel": "darwin"})
    assert "\n" not in out or "{" in out


def test_serialize_sysreq_args_yaml_blobs() -> None:
    specs = [{"plat.kernel": "linux"}, {"os.id": "ubuntu"}]
    out = serialize_sysreq_args(specs)
    assert out.startswith("$'")
    assert "plat.kernel" in out


def test_serialize_binary_src_tab_yaml() -> None:
    entries = [{"path": "/bin/foo", "when": {"feat.version": {"lte": "2.0"}}}]
    out = serialize_binary_src(entries)
    assert "/bin/foo\t" in out
    assert "feat.version" in out


def test_serialize_when_or_groups_preserve_keys() -> None:
    out = serialize_when([{"plat.kernel": "linux"}, {"plat.pm": "apt"}])
    assert "plat.kernel" in out
    assert "plat.pm" in out
    assert out.index("plat.kernel") < out.index("plat.pm")
