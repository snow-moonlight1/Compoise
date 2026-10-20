"""Regression tests for scripts/changelog_notes.py."""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import changelog_notes as notes  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
URL = notes.REPO_URL

ENTRY = """\
## [1.3.0] - 2026-11-20

### 新增

- 月视图。

### 修复

- 提醒不再重复。

### Added

- Month view.

### Fixed

- Reminders no longer repeat.
"""

OLDER = """\
## [1.2.0] - 2026-10-20

### 新增

- 可选同步。

### Added

- Optional sync.
"""


def changelog(entry: str = ENTRY, unreleased: str = "", refs: str | None = None) -> str:
    if refs is None:
        refs = (
            f"[Unreleased]: {URL}/compare/v1.3.0...HEAD\n"
            f"[1.3.0]: {URL}/releases/tag/v1.3.0\n"
            f"[1.2.0]: {URL}/releases/tag/v1.2.0\n"
        )
    return (
        "# Changelog\n\nIntro.\n\n## [Unreleased]\n\n"
        + unreleased
        + ("\n" if unreleased else "")
        + entry
        + "\n"
        + OLDER
        + "\n"
        + refs
    )


def check(text: str, version: str = "1.3.0", release: bool = True) -> None:
    notes.check_entry(notes.parse(text), version, release=release)


class CheckEntryTest(unittest.TestCase):
    def assertRefused(self, text: str, fragment: str, **kwargs) -> None:
        with self.assertRaises(notes.ChangelogError) as caught:
            check(text, **kwargs)
        self.assertIn(fragment, str(caught.exception))

    def test_a_complete_bilingual_entry_passes(self) -> None:
        entry = notes.check_entry(notes.parse(changelog()), "1.3.0", release=True)
        self.assertIn("### 新增", entry.body)
        self.assertNotIn("[1.3.0]:", entry.body)

    def test_a_missing_entry_is_refused(self) -> None:
        self.assertRefused(changelog(), "no '## [1.4.0] - YYYY-MM-DD' entry", version="1.4.0")

    def test_the_entry_needs_a_valid_date(self) -> None:
        self.assertRefused(
            changelog(ENTRY.replace(" - 2026-11-20", "")), "needs ' - YYYY-MM-DD'"
        )
        self.assertRefused(
            changelog(ENTRY.replace("2026-11-20", "2026-13-01")), "invalid date 2026-13-01"
        )

    def test_the_entry_must_be_the_newest(self) -> None:
        self.assertRefused(changelog(), "must be the newest", version="1.2.0", release=False)

    def test_both_languages_are_required_chinese_first(self) -> None:
        english_only = "## [1.3.0] - 2026-11-20\n\n### Added\n\n- Month view.\n"
        self.assertRefused(changelog(english_only), "needs Chinese subsections")
        chinese_only = "## [1.3.0] - 2026-11-20\n\n### 新增\n\n- 月视图。\n"
        self.assertRefused(changelog(chinese_only), "needs English subsections")
        swapped = (
            "## [1.3.0] - 2026-11-20\n\n### Added\n\n- Month view.\n\n"
            "### 新增\n\n- 月视图。\n"
        )
        self.assertRefused(changelog(swapped), "Chinese subsections before the English")

    def test_every_subsection_needs_a_bullet(self) -> None:
        empty = ENTRY.replace("- Reminders no longer repeat.\n", "")
        self.assertRefused(changelog(empty), "'### Fixed' has no bullet")

    def test_link_references_are_required(self) -> None:
        refs = f"[Unreleased]: {URL}/compare/v1.2.0...HEAD\n[1.2.0]: {URL}/releases/tag/v1.2.0\n"
        with self.assertRaises(notes.ChangelogError) as caught:
            check(changelog(refs=refs))
        self.assertIn(f"'[1.3.0]: {URL}/releases/tag/v1.3.0'", str(caught.exception))
        self.assertIn(f"'[Unreleased]: {URL}/compare/v1.3.0...HEAD'", str(caught.exception))

    def test_a_release_refuses_leftover_unreleased_changes(self) -> None:
        text = changelog(unreleased="### Added\n\n- Something new.\n")
        self.assertRefused(text, "Unreleased still lists changes")
        check(text, release=False)


class WhatsNewTest(unittest.TestCase):
    def test_a_formal_tag_opens_with_its_entry(self) -> None:
        block = notes.whats_new(notes.parse(changelog()), "v1.3.0")
        self.assertTrue(block.startswith("## v1.3.0 更新 / What's new\n\n### 新增\n"))
        self.assertIn("- Reminders no longer repeat.", block)
        self.assertIn(f"[CHANGELOG.md]({URL}/blob/main/CHANGELOG.md)", block)
        self.assertNotIn("1.2.0", block)
        self.assertEqual(notes.whats_new(notes.parse(changelog()), "v1.3.0+5"), block)

    def test_a_formal_tag_without_a_complete_entry_fails(self) -> None:
        with self.assertRaises(notes.ChangelogError):
            notes.whats_new(notes.parse(changelog()), "v1.4.0")

    def test_a_test_tag_never_fails(self) -> None:
        log = notes.parse(changelog())
        self.assertIn("## v1.3.0 更新", notes.whats_new(log, "v1.3.0-ci.2"))
        self.assertEqual(notes.whats_new(log, "v1.4.0-ci.1"), "")
        pending = notes.parse(changelog(unreleased="### Added\n\n- Something new.\n"))
        block = notes.whats_new(pending, "v1.4.0-ci.1")
        self.assertTrue(block.startswith("## 未发布的更新 / Unreleased changes"))
        self.assertIn("- Something new.", block)

    def test_other_refs_are_not_release_tags(self) -> None:
        with self.assertRaises(notes.ChangelogError):
            notes.whats_new(notes.parse(changelog()), "main")


class CommandLineTest(unittest.TestCase):
    def run_main(self, repo: Path, *args: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = notes.main([*args, "--repo", str(repo)])
        return code, out.getvalue(), err.getvalue()

    def test_check_follows_the_pubspec_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / "CHANGELOG.md").write_text(changelog(), encoding="utf-8")
            (repo / "pubspec.yaml").write_text("name: x\nversion: 1.3.0+5\n", encoding="utf-8")
            self.assertEqual(self.run_main(repo, "check")[0], 0)
            (repo / "pubspec.yaml").write_text("name: x\nversion: 1.4.0+6\n", encoding="utf-8")
            code, _, err = self.run_main(repo, "check")
            self.assertEqual(code, 1)
            self.assertIn("no '## [1.4.0]", err)
            self.assertEqual(self.run_main(repo, "check", "--tag", "v1.4.0-ci.1")[0], 0)
            code, out, _ = self.run_main(repo, "notes", "--tag", "v1.3.0")
            self.assertEqual(code, 0)
            self.assertTrue(out.startswith("## v1.3.0 更新"))

    def test_the_repository_changelog_covers_the_pubspec_version(self) -> None:
        log = notes.parse((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"))
        version = notes.pubspec_version((ROOT / "pubspec.yaml").read_text(encoding="utf-8"))
        notes.check_entry(log, version, release=False)


if __name__ == "__main__":
    unittest.main()
