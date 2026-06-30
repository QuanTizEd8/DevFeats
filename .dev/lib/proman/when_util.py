r"""Utilities for serializing `when` condition blocks.

Shared by the install-script generator (install_script.py) and the
metadata template filler (metadata.py / metadata.shared.yaml).

Serialization emits **YAML** blobs consumed by ``ctx__match_when`` / ``ctx__match_spec``
in ``lib/ctx.bash`` (evaluated via ``ctx-match.jq``).

When keys are validated by ``features/metadata.schema.json`` (``WhenSpec`` /
``WhenConditionObject.propertyNames``); this module only serializes already-valid
metadata.
"""

from __future__ import annotations

import yaml


def _dump_when_yaml(data: object, *, flow: bool) -> str:
    """Dump a when dict or OR-list to YAML."""
    if not data:
        return ""
    if isinstance(data, dict):
        payload: object = dict(data)
    elif isinstance(data, list):
        payload = [dict(g) for g in data if g]
        if not payload:
            return ""
    else:
        return ""

    dumped = yaml.dump(
        payload,
        default_flow_style=flow,
        sort_keys=False,
        width=10_000 if flow else None,
        allow_unicode=True,
    )
    return dumped.strip() if flow else dumped.rstrip("\n")


def serialize_when(when: object) -> str:
    """Serialize a ``when`` block to multi-line YAML."""
    return _dump_when_yaml(when, flow=False)


def serialize_when_flow(when: dict | list) -> str:
    """Serialize a ``when`` block to single-line YAML."""
    return _dump_when_yaml(when, flow=True)


def serialize_sysreq_args(specs: list[dict]) -> str:
    """Build sys_req__require_platform argument list (one YAML blob per OR group)."""
    parts: list[str] = []
    for spec in specs:
        blob = serialize_when(spec)
        if not blob:
            continue
        escaped = blob.replace("\\", "\\\\").replace("'", "'\\''")
        parts.append(f"$'{escaped}'")
    return " ".join(parts)


def _serialize_value_when_entries(
    entries: list | None,
    *,
    value_key: str,
) -> str:
    """Serialize ``[{value_key, when}]`` metadata entries to option default lines."""
    if not entries:
        return ""
    lines: list[str] = []
    for entry in entries:
        if isinstance(entry, str):
            lines.append(entry)
            continue
        if isinstance(entry, dict):
            value = entry.get(value_key, "")
            when = entry.get("when")
            if when:
                yaml_when = serialize_when_flow(when)
                lines.append(f"{value}\t{yaml_when}" if yaml_when else value)
            else:
                lines.append(str(value))
            continue
        lines.append(str(entry))
    return "\n".join(lines)


def serialize_path_entries(entries: list | None) -> str:
    """Serialize a list of ``{path, when?}`` entries to tab-delimited defaults."""
    return _serialize_value_when_entries(entries, value_key="path")


def serialize_value_entries(entries: list | None) -> str:
    """Serialize a list of ``{value, when?}`` entries to tab-delimited defaults."""
    return _serialize_value_when_entries(entries, value_key="value")
