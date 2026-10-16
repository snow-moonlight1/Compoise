"""Regression tests for scripts/check_build_number.py."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_build_number as guard  # noqa: E402


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


class CheckBuildNumberTest(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.repo = Path(self._dir.name)
        _git(self.repo, "init", "-q")
        _git(self.repo, "config", "user.email", "ci@example.invalid")
        _git(self.repo, "config", "user.name", "CI")
        _git(self.repo, "config", "commit.gpgsign", "false")
        _git(self.repo, "config", "tag.gpgsign", "false")

    def tearDown(self) -> None:
        self._dir.cleanup()

    def _commit(self, version: str, tag: str | None = None) -> None:
        (self.repo / "pubspec.yaml").write_text(
            f"name: compoise\nversion: {version}\n", encoding="utf-8"
        )
        _git(self.repo, "add", "pubspec.yaml")
        _git(self.repo, "commit", "-q", "--allow-empty", "-m", version)
        if tag:
            _git(self.repo, "tag", tag)

    def test_first_release_has_nothing_to_compare(self) -> None:
        self._commit("1.0.0+1")
        self.assertEqual(guard.check(self.repo, "v1.0.0"), [])

    def test_increasing_version_and_build_pass(self) -> None:
        self._commit("1.0.0+1", "v1.0.0")
        self._commit("1.0.1+2")
        self.assertEqual(guard.check(self.repo, "v1.0.1"), [])

    def test_unchanged_build_number_fails(self) -> None:
        self._commit("1.0.0+1", "v1.0.0")
        self._commit("1.0.1+1")
        problems = guard.check(self.repo, "v1.0.1")
        self.assertEqual(len(problems), 1)
        self.assertIn("build number 1", problems[0])

    def test_unchanged_version_fails(self) -> None:
        self._commit("1.0.0+1", "v1.0.0")
        self._commit("1.0.0+2")
        problems = guard.check(self.repo, "v1.0.0+2")
        self.assertEqual(len(problems), 1)
        self.assertIn("must be newer", problems[0])

    def test_retagging_the_current_release_is_allowed(self) -> None:
        self._commit("1.0.0+1", "v1.0.0")
        self._commit("1.0.0+1")
        _git(self.repo, "tag", "-f", "v1.0.0")
        self.assertEqual(guard.check(self.repo, "v1.0.0"), [])

    def test_ci_tags_are_ignored(self) -> None:
        self._commit("1.0.1+2", "v1.0.1-ci.1")
        self._commit("1.0.1+2")
        self.assertEqual(guard.check(self.repo, "v1.0.1"), [])

    def test_malformed_pubspec_is_reported(self) -> None:
        (self.repo / "pubspec.yaml").write_text("version: 1.0\n", encoding="utf-8")
        with self.assertRaises(guard.VersionError):
            guard.check(self.repo, None)

    def test_main_returns_failure_exit_code(self) -> None:
        self._commit("1.0.0+1", "v1.0.0")
        self._commit("1.0.1+1")
        self.assertEqual(
            guard.main(["--repo", str(self.repo), "--tag", "v1.0.1"]), 1
        )


if __name__ == "__main__":
    unittest.main()
