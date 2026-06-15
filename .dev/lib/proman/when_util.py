r"""Utilities for serializing `when` condition blocks.

Shared by the install-script generator (install_script.py) and the
metadata template filler (metadata.py / metadata.shared.yaml).

Serialization format (mirrors the ospkg manifest schema semantics):
  - Object form  : ``{arch: [amd64, arm64], kernel: linux}``
    → ``"arch=amd64|arm64 kernel=linux"``
  - Array form   : ``[{kernel: linux, arch: amd64}, {kernel: darwin}]``
    → ``"kernel=linux arch=amd64\\nkernel=darwin"``

The runtime evaluator is ``os__match_when`` in ``lib/os.sh``.
"""

from __future__ import annotations


def serialize_when(when: object) -> str:
    """Serialize a ``when`` condition block to the bash contract string format.

    Empty / null input returns an empty string (no constraint).
    """

    def _group(d: dict) -> str:
        parts = []
        for k, v in d.items():
            if isinstance(v, list):
                parts.append(f"{k}={'|'.join(str(x) for x in v)}")
            else:
                parts.append(f"{k}={v}")
        return " ".join(parts)

    if not when:
        return ""
    if isinstance(when, dict):
        return _group(when)
    if isinstance(when, list):
        return "\n".join(_group(g) for g in when if g)
    return ""
