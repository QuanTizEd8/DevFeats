"""Tests for migrate_ctx_metadata codemod."""

from __future__ import annotations

from proman.migrate_ctx_metadata import dedupe_qualified_keys, migrate_text


def test_migrate_conditional_pattern_tokens() -> None:
    raw = (
        'asset_uri: "{OS==linux?{LIBC==musl?-musl:}:}/bin"\n'
        "when: {arch: amd64, id: ubuntu}\n"
    )
    out = migrate_text(raw)
    assert "{plat.kernel==linux" in out
    assert "{plat.libc==musl" in out
    assert "plat.machine_release: amd64" in out
    assert "os.id: ubuntu" in out
    assert "{OS" not in out
    assert "{ARCH" not in out


def test_migrate_version_input_and_prefix() -> None:
    raw = (
        "repos:\n"
        "  - https://example/apt/{VERSION_INPUT==latest?latest:stable}\n"
        'snippet: "{PREFIX}/bin/tool"\n'
    )
    out = migrate_text(raw)
    assert "{feat.version_input==latest" in out
    assert "{feat.prefix}/bin/tool" in out


def test_migrate_does_not_double_qualify_keys() -> None:
    raw = "when: {plat.kernel: linux, os.id: ubuntu}\n"
    assert migrate_text(raw) == raw


def test_dedupe_repair_double_prefix() -> None:
    raw = "when: {plat.plat.kernel: linux, os.os.id: ubuntu}\n"
    assert dedupe_qualified_keys(raw) == "when: {plat.kernel: linux, os.id: ubuntu}\n"
