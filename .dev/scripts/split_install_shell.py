#!/usr/bin/env python3
"""
Phase 1 mechanical split for install-shell refactoring.
Run from repo root. All line numbers are 1-indexed, inclusive.
No line appears in more than one feature's cut.
"""
import shutil
from pathlib import Path

FEATURES_DIR = Path("features")
SRC = FEATURES_DIR / "install-shell"

# ---------------------------------------------------------------------------
# install.bash cuts: {feature: [(label, start, end), ...]}
#
# All line numbers reference the ORIGINAL install-shell/install.bash (849 lines).
# configure_user() inner-block offsets: original = current-after-first-run + 214
# (214 = lines removed by cutting the 5 top-level functions in the first attempt).
# ---------------------------------------------------------------------------
BASH_CUTS = {
    "install-ohmyzsh": [
        # Global var used only by this feature
        ("_OHMYZSH_REPO_URL global var", 8, 8),
        # Top-level function
        ("install_ohmyzsh() + blank", 12, 70),
        # Helpers used only by OMZ and OMB configure_user blocks
        ("_resolve_custom_dir() and _link_custom_items() helpers + blanks", 226, 277),
        # Top-level step
        ("Step 2: Install Oh My Zsh + blank", 663, 675),
        # configure_user() OMZ block
        ("configure_user: OMZ zsh block + trailing blank", 371, 461),
    ],
    "install-ohmybash": [
        ("_OHMYBASH_REPO_URL global var", 9, 9),
        ("install_ohmybash() + blank", 71, 127),
        ("Step 3: Install Oh My Bash + blank", 676, 684),
        ("configure_user: OMB bash block + trailing blank", 519, 578),
    ],
    "install-fzf": [
        ("install_fzf() + blank", 128, 178),
        ("fzf sub-block of Step 2.5 + blank", 659, 662),
        ("configure_user: fzf zsh hook + trailing blank", 468, 473),
        ("configure_user: fzf bash hook + trailing blank", 585, 590),
    ],
    "install-zsh-completion": [
        # Feature-specific global vars (line 1 _GITHUB_BASE_URL stays in install-shell)
        ("zsh-completions global vars (lines 2–7)", 2, 7),
        ("install_zsh_completions() + blank", 179, 199),
        ("zsh-completions sub-block of Step 2.5 + blank", 649, 653),
        ("Step 5.5 inner block (fpath wiring)", 765, 788),
    ],
    "install-starship": [
        ("_STARSHIP_INSTALLER_URL global var", 10, 10),
        ("install_starship() + blank", 200, 225),
        ("Step 4: Install Starship + blank", 685, 691),
        ("configure_user: Starship zsh hook + trailing blank", 474, 482),
        ("configure_user: Starship bash hook + trailing blank", 591, 599),
    ],
    "install-bash-completion": [
        ("Step 2.5 header + bash-completion sub-block + blank", 641, 648),
        ("configure_user: bash-completion Homebrew hook + trailing blank", 506, 518),
    ],
    "install-direnv": [
        ("direnv sub-block of Step 2.5 + blank", 654, 658),
        ("configure_user: direnv zsh hook + trailing blank", 462, 467),
        ("configure_user: direnv bash hook + trailing blank", 579, 584),
    ],
}

# ---------------------------------------------------------------------------
# metadata.yaml cuts: {feature: {section: [(start, end), ...]}}
# sections: "options", "gh_repo", "prefix_groups"
# ---------------------------------------------------------------------------
YAML_CUTS = {
    "install-ohmyzsh": {
        "options":       [(22,25),(48,56),(66,79),(87,92),(97,102),(147,153)],
        "gh_repo":       [(208,210)],
        "prefix_groups": [],
    },
    "install-ohmybash": {
        "options":       [(26,29),(57,65),(80,86),(93,96),(103,106),(154,160)],
        "gh_repo":       [(211,213)],
        "prefix_groups": [],
    },
    "install-starship": {
        "options":       [(30,33),(34,47)],
        "gh_repo":       [],
        "prefix_groups": [(242,246)],
    },
    "install-bash-completion": {
        "options":       [(172,177)],
        "gh_repo":       [],
        "prefix_groups": [],
    },
    "install-zsh-completion": {
        "options":       [(178,189)],
        "gh_repo":       [(214,216)],
        "prefix_groups": [],
    },
    "install-direnv": {
        "options":       [(190,196)],
        "gh_repo":       [],
        "prefix_groups": [],
    },
    "install-fzf": {
        "options":       [(197,202)],
        "gh_repo":       [(205,207)],
        "prefix_groups": [(247,251)],
    },
}


def get_lines(all_lines, ranges):
    result = []
    for s, e in ranges:
        result.extend(all_lines[s - 1 : e])
    return result


def remove_lines(all_lines, flat_ranges):
    to_remove = set()
    for s, e in flat_ranges:
        to_remove.update(range(s, e + 1))
    return [ln for i, ln in enumerate(all_lines, 1) if i not in to_remove]


def write_bash(feature, cuts, src_lines):
    dest = FEATURES_DIR / feature
    dest.mkdir(parents=True, exist_ok=True)
    out = [
        "# Phase 1 skeleton — mechanically extracted from install-shell/install.bash\n",
        f"# Feature: {feature}\n",
        "# Not yet functional. Wired up in this feature's own semantic phase.\n",
        "# shellcheck shell=bash\n\n",
    ]
    for label, s, e in cuts:
        out.append(f"# --- {label} (original lines {s}–{e}) ---\n")
        out.extend(src_lines[s - 1 : e])
        out.append("\n")
    (dest / "install.bash").write_text("".join(out))
    print(f"  wrote {dest}/install.bash")


def write_yaml(feature, sections, src_lines):
    dest = FEATURES_DIR / feature
    dest.mkdir(parents=True, exist_ok=True)
    out = [
        "# Phase 1 skeleton — mechanically extracted from install-shell/metadata.yaml\n",
        f"# Feature: {feature}\n",
        "# Add version/name/description/dependencies in the semantic phase.\n\n",
    ]
    opts = sections.get("options", [])
    ghr  = sections.get("gh_repo", [])
    pfx  = sections.get("prefix_groups", [])
    if opts:
        out.append("options:\n")
        out.extend(get_lines(src_lines, opts))
    if ghr:
        out.append("_options:\n  gh_repo:\n")
        out.extend(get_lines(src_lines, ghr))
    if pfx:
        out.append("_prefix_groups:\n")
        out.extend(get_lines(src_lines, pfx))
    (dest / "metadata.yaml").write_text("".join(out))
    print(f"  wrote {dest}/metadata.yaml")


def main():
    bash_src = (SRC / "install.bash").read_text().splitlines(keepends=True)
    yaml_src = (SRC / "metadata.yaml").read_text().splitlines(keepends=True)

    # Sanity check: verify expected source file sizes
    assert len(bash_src) == 849, f"install.bash: expected 849 lines, got {len(bash_src)}"
    assert len(yaml_src) == 251, f"metadata.yaml: expected 251 lines, got {len(yaml_src)}"

    # Sanity check: no line appears in more than one feature's bash cut
    bash_seen = {}
    for feat, cuts in BASH_CUTS.items():
        for _, s, e in cuts:
            for n in range(s, e + 1):
                if n in bash_seen:
                    raise ValueError(f"Line {n} of install.bash assigned to both {bash_seen[n]} and {feat}")
                bash_seen[n] = feat

    # Sanity check: no line appears in more than one feature's yaml cut
    yaml_seen = {}
    for feat, secs in YAML_CUTS.items():
        for k in ("options", "gh_repo", "prefix_groups"):
            for s, e in secs.get(k, []):
                for n in range(s, e + 1):
                    if n in yaml_seen:
                        raise ValueError(f"Line {n} of metadata.yaml assigned to both {yaml_seen[n]} and {feat}")
                    yaml_seen[n] = feat

    print("=== install.bash ===")
    bash_flat = []
    for feat, cuts in BASH_CUTS.items():
        write_bash(feat, cuts, bash_src)
        bash_flat.extend((s, e) for _, s, e in cuts)
    updated = remove_lines(bash_src, bash_flat)
    (SRC / "install.bash").write_text("".join(updated))
    print(f"  install-shell/install.bash: {len(bash_src)} → {len(updated)} lines")

    print("\n=== metadata.yaml ===")
    yaml_flat = []
    for feat, secs in YAML_CUTS.items():
        write_yaml(feat, secs, yaml_src)
        for k in ("options", "gh_repo", "prefix_groups"):
            yaml_flat.extend(secs.get(k, []))
    updated = remove_lines(yaml_src, yaml_flat)
    (SRC / "metadata.yaml").write_text("".join(updated))
    print(f"  install-shell/metadata.yaml: {len(yaml_src)} → {len(updated)} lines")

    print("\n=== files/ ===")
    src_p10k = SRC / "files" / "skel" / "p10k.zsh"
    dst_p10k = FEATURES_DIR / "install-ohmyzsh" / "files" / "skel" / "p10k.zsh"
    dst_p10k.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_p10k, dst_p10k)
    src_p10k.unlink()
    print("  moved p10k.zsh → install-ohmyzsh/files/skel/p10k.zsh")

    print("\n=== Done. Verify and commit. ===")


if __name__ == "__main__":
    main()
