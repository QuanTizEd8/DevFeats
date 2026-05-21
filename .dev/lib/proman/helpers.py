"""Helper functions for proman."""

import sys


def log(msg: str) -> None:
    """Write a diagnostic message to stderr."""
    print(msg, file=sys.stderr)
