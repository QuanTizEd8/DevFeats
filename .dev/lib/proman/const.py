"""Shared constants for the proman project management library."""


def project_slug(owner: str, repo: str) -> str:
    """Return ``<owner>-<repo>`` (same value as ``@@PROJECT_SLUG@@`` in metadata)."""
    return f"{owner}-{repo}"


def lifecycle_command_entry_prefix(feature_id: str, owner: str, repo: str) -> str:
    """Return ``<owner>-<repo>--<feature_id>--`` for namespacing lifecycle hook IDs."""
    return f"{project_slug(owner, repo)}--{feature_id}--"


def feat_share_dir(feature_id: str, owner: str, repo: str) -> str:
    """Return the canonical ``/usr/local/share/`` path for a feature's artefacts.

    Formula: ``/usr/local/share/<owner>/<repo>/<feature_id>``.

    This is the single authoritative definition used both when generating the
    bash header (``_FEAT_SHARE_DIR`` variable) and when substituting
    ``@@_FEAT_SHARE_DIR@@`` tokens in ``metadata.yaml`` values.
    """
    return f"/usr/local/share/{owner}/{repo}/{feature_id}"


def export_profile_d(feature_id: str, owner: str, repo: str) -> str:
    """Return the canonical ``/etc/profile.d/`` drop-in filename for a feature.

    Formula: ``<owner>-<repo>-<feature_id>-export-path.sh``.

    This is the single authoritative definition used both when generating the
    bash header (``_EXPORT_PROFILE_D`` variable) and when substituting
    ``@@_EXPORT_PROFILE_D@@`` tokens in ``metadata.yaml`` values.
    """
    return f"{project_slug(owner, repo)}-{feature_id}-export-path.sh"


def activation_profile_d(feature_id: str, owner: str, repo: str) -> str:
    """Return the profile.d filename for a feature's default activation snippet.

    Formula: ``<owner>-<repo>-<feature_id>-prefix-activation.sh``.

    Covers the unnamed (stem="prefix") prefix group.  Used when generating the
    ``_ACTIVATION_PROFILE_D`` test-runner variable.
    """
    return f"{project_slug(owner, repo)}-{feature_id}-prefix-activation.sh"


LIFECYCLE_COMMAND_KEYS: tuple[str, ...] = (
    "onCreateCommand",
    "updateContentCommand",
    "postCreateCommand",
    "postStartCommand",
    "postAttachCommand",
)
