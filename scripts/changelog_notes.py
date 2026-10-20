#!/usr/bin/env python3
"""Check CHANGELOG.md and turn one version's entry into the release's What's new.

Every released version has a section

    ## [X.Y.Z] - YYYY-MM-DD

with its subsections in Chinese first (`### 新增`, `### 变更`, ...) and then in
English (`### Added`, `### Changed`, ...). Each subsection lists at least one
bullet. The GitHub release notes start with this section, so a release cannot
go out with a missing or half-written entry.

Usage:
  changelog_notes.py check            the entry for the pubspec.yaml version
  changelog_notes.py check --tag TAG  the entry for a release tag, which also
                                      requires an empty Unreleased section
  changelog_notes.py notes --tag TAG  print the What's new block for TAG

Test tags (`vX.Y.Z-ci.N`) are never refused: `notes` prints the entry for
X.Y.Z, or the Unreleased changes, or nothing.
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_URL = "https://github.com/snow-moonlight1/Compoise"
VERSION_LINE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$", re.MULTILINE)
FORMAL_TAG = re.compile(r"^v(\d+\.\d+\.\d+)(\+\d+)?$")
CI_TAG = re.compile(r"^v(\d+\.\d+\.\d+)-ci\.\d+$")
SECTION = re.compile(r"^## \[([^\]]+)\](.*)$")
DATED = re.compile(r"^ - (\d{4}-\d{2}-\d{2})$")
SUBSECTION = re.compile(r"^### (.+?)\s*$")
LINK_REF = re.compile(r"^\[[^\]]+\]:\s*\S+")
BULLET = re.compile(r"^\s*[-*] \S")
CJK = re.compile(r"[\u3400-\u9fff]")


class ChangelogError(Exception):
    pass


@dataclass
class Subsection:
    heading: str
    lines: list[str] = field(default_factory=list)

    @property
    def chinese(self) -> bool:
        return bool(CJK.search(self.heading))

    @property
    def bullets(self) -> int:
        return sum(1 for line in self.lines if BULLET.match(line))


@dataclass
class Section:
    name: str
    rest: str
    lines: list[str] = field(default_factory=list)

    @property
    def body(self) -> str:
        return "\n".join(self.lines).strip()

    @property
    def subsections(self) -> list[Subsection]:
        result: list[Subsection] = []
        for line in self.lines:
            match = SUBSECTION.match(line)
            if match:
                result.append(Subsection(match.group(1)))
            elif result:
                result[-1].lines.append(line)
        return result

    @property
    def bullets(self) -> int:
        return sum(1 for line in self.lines if BULLET.match(line))


@dataclass
class Changelog:
    sections: list[Section]
    link_refs: dict[str, str]

    def section(self, name: str) -> Section | None:
        for section in self.sections:
            if section.name == name:
                return section
        return None

    @property
    def versions(self) -> list[Section]:
        return [s for s in self.sections if s.name != "Unreleased"]


def parse(text: str) -> Changelog:
    sections: list[Section] = []
    link_refs: dict[str, str] = {}
    for line in text.splitlines():
        if LINK_REF.match(line):
            name, _, url = line.partition("]:")
            link_refs[name[1:]] = url.strip()
            continue
        match = SECTION.match(line)
        if match:
            sections.append(Section(match.group(1), match.group(2)))
        elif sections:
            sections[-1].lines.append(line)
    return Changelog(sections, link_refs)


def pubspec_version(text: str) -> str:
    match = VERSION_LINE.search(text)
    if not match:
        raise ChangelogError("pubspec.yaml must declare version X.Y.Z+N")
    return match.group(1)


def check_entry(log: Changelog, version: str, *, release: bool) -> Section:
    """Return the entry for `version`, or raise with every problem found."""
    problems: list[str] = []
    entry = log.section(version)
    if entry is None:
        raise ChangelogError(
            f"CHANGELOG.md has no '## [{version}] - YYYY-MM-DD' entry. "
            "Move the Unreleased changes into it before releasing."
        )
    date = DATED.match(entry.rest)
    if not date:
        problems.append(f"the [{version}] heading needs ' - YYYY-MM-DD' after it")
    else:
        try:
            datetime.date.fromisoformat(date.group(1))
        except ValueError:
            problems.append(f"[{version}] has an invalid date {date.group(1)}")
    versions = log.versions
    if not versions or versions[0].name != version:
        problems.append(f"[{version}] must be the newest version entry")
    subsections = entry.subsections
    chinese = [i for i, sub in enumerate(subsections) if sub.chinese]
    english = [i for i, sub in enumerate(subsections) if not sub.chinese]
    if not chinese:
        problems.append(f"[{version}] needs Chinese subsections (### 新增, ### 变更, ...)")
    if not english:
        problems.append(f"[{version}] needs English subsections (### Added, ### Changed, ...)")
    if chinese and english and english[0] < chinese[-1]:
        problems.append(f"[{version}] must list the Chinese subsections before the English ones")
    for sub in subsections:
        if sub.bullets == 0:
            problems.append(f"[{version}] '### {sub.heading}' has no bullet")
    want = f"{REPO_URL}/releases/tag/v{version}"
    if log.link_refs.get(version) != want:
        problems.append(f"missing link reference '[{version}]: {want}'")
    want = f"{REPO_URL}/compare/v{version}...HEAD"
    if log.link_refs.get("Unreleased") != want:
        problems.append(f"missing link reference '[Unreleased]: {want}'")
    if release:
        unreleased = log.section("Unreleased")
        if unreleased is None:
            problems.append("keep an empty '## [Unreleased]' section at the top")
        elif unreleased.bullets:
            problems.append(
                "Unreleased still lists changes: move them into "
                f"[{version}] or leave them for the next version"
            )
    if problems:
        raise ChangelogError("CHANGELOG.md: " + "; ".join(problems) + ".")
    return entry


def whats_new(log: Changelog, tag: str) -> str:
    """The block that opens the release notes for `tag`; may be empty."""
    formal = FORMAL_TAG.match(tag)
    if formal:
        version = formal.group(1)
        entry = check_entry(log, version, release=True)
        return _block(f"v{version} 更新 / What's new", entry.body)
    test = CI_TAG.match(tag)
    if not test:
        raise ChangelogError(f"not a release tag: {tag}")
    entry = log.section(test.group(1))
    if entry is not None and entry.body:
        return _block(f"v{test.group(1)} 更新 / What's new", entry.body)
    unreleased = log.section("Unreleased")
    if unreleased is not None and unreleased.bullets:
        return _block("未发布的更新 / Unreleased changes", unreleased.body)
    return ""


def _block(title: str, body: str) -> str:
    return (
        f"## {title}\n\n{body}\n\n"
        f"完整更新日志 / Full changelog: [CHANGELOG.md]({REPO_URL}/blob/main/CHANGELOG.md)\n\n"
        "---\n\n"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["check", "notes"])
    parser.add_argument("--tag", help="release tag, for example v1.2.0")
    parser.add_argument("--repo", default=".", help="repository root")
    args = parser.parse_args(argv)
    repo = Path(args.repo)
    try:
        log = parse((repo / "CHANGELOG.md").read_text(encoding="utf-8"))
        if args.command == "notes":
            if not args.tag:
                raise ChangelogError("notes needs --tag")
            sys.stdout.write(whats_new(log, args.tag))
            return 0
        if args.tag:
            formal = FORMAL_TAG.match(args.tag)
            if not formal:
                print(f"{args.tag} is not a formal release tag; nothing to check.")
                return 0
            version, release = formal.group(1), True
        else:
            pubspec = (repo / "pubspec.yaml").read_text(encoding="utf-8")
            version, release = pubspec_version(pubspec), False
        check_entry(log, version, release=release)
    except (ChangelogError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f"CHANGELOG.md has a complete entry for {version}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
