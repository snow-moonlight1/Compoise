#!/usr/bin/env python3
"""Refuse a formal release whose version or build number does not increase.

Android only installs an update over an existing app when its versionCode
(the `+N` in pubspec.yaml) is strictly greater. The release workflow already
checks that the tag matches pubspec.yaml; this script also compares against
every earlier formal `vX.Y.Z` tag in the repository.

Usage: check_build_number.py [--repo DIR] [--tag vX.Y.Z]

`--tag` is the tag being released. It is excluded from the comparison so that
moving a tag that has not been published yet (re-running the same release)
still works. Test tags (`-ci.N`) are never compared.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

VERSION_LINE = re.compile(
    r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", re.MULTILINE
)
FORMAL_TAG = re.compile(r"^v\d+\.\d+\.\d+(\+\d+)?$")


class VersionError(Exception):
    pass


def parse_pubspec(text: str) -> tuple[tuple[int, int, int], int]:
    match = VERSION_LINE.search(text)
    if not match:
        raise VersionError("pubspec.yaml must declare version X.Y.Z+N")
    major, minor, patch, build = (int(part) for part in match.groups())
    return (major, minor, patch), build


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def previous_releases(repo: Path, current_tag: str | None):
    """Yield (tag, version, build) for every earlier formal tag."""
    for tag in _git(repo, "tag", "--list", "v*").split():
        if tag == current_tag or not FORMAL_TAG.match(tag):
            continue
        try:
            text = _git(repo, "show", f"{tag}:pubspec.yaml")
            version, build = parse_pubspec(text)
        except (subprocess.CalledProcessError, VersionError):
            # Tags from before the X.Y.Z+N rule cannot be compared.
            continue
        yield tag, version, build


def check(repo: Path, current_tag: str | None) -> list[str]:
    text = (repo / "pubspec.yaml").read_text(encoding="utf-8")
    version, build = parse_pubspec(text)
    label = "%d.%d.%d+%d" % (*version, build)
    problems = []
    for tag, old_version, old_build in previous_releases(repo, current_tag):
        old_label = "%d.%d.%d+%d" % (*old_version, old_build)
        if build <= old_build:
            problems.append(
                f"build number {build} in pubspec.yaml ({label}) must be greater "
                f"than {old_build} from {tag} ({old_label}); Android will not "
                "install an update with the same or a lower versionCode."
            )
        if version <= old_version:
            problems.append(
                f"version {label} must be newer than {old_label} from {tag}."
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--tag", default=None)
    args = parser.parse_args(argv)
    try:
        problems = check(args.repo, args.tag)
    except VersionError as error:
        print(error, file=sys.stderr)
        return 1
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(
            "Bump `version:` in pubspec.yaml (see docs/release-process.md).",
            file=sys.stderr,
        )
        return 1
    print("Version and build number are newer than every earlier release tag.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
