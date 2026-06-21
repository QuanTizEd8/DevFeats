r"""Utilities for serializing `when` condition blocks.

Shared by the install-script generator (install_script.py) and the
metadata template filler (metadata.py / metadata.shared.yaml).

Serialization emits **YAML** blobs consumed by ``ctx__match_when`` / ``ctx__match_spec``
in ``lib/ctx.sh`` (evaluated via ``ctx-match.jq``).

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
    """Serialize a ``when`` block to multi-line YAML for bash ``ctx__match_*`` evaluators."""
    return _dump_when_yaml(when, flow=False)


def serialize_when_flow(when: dict) -> str:
    """Compact one-line YAML for embedding in PREFIX platform override lines."""
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


def serialize_binary_src(entries: list | None) -> str:
    """Serialize ``method.binary.binary_src`` metadata to option default lines."""
    if not entries:
        return ""
    lines: list[str] = []
    for entry in entries:
        if isinstance(entry, str):
            lines.append(entry)
            continue
        if isinstance(entry, dict):
            path = entry.get("path", "")
            when = entry.get("when")
            if when:
                yaml_when = serialize_when(when)
                lines.append(f"{path}\t{yaml_when}" if yaml_when else path)
            else:
                lines.append(str(path))
            continue
        lines.append(str(entry))
    return "\n".join(lines)
