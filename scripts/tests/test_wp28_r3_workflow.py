import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location(
    "wp28_r3_workflow", ROOT / "scripts" / "wp28_r3_workflow.py"
)
workflow = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(workflow)


class WorkflowYamlTests(unittest.TestCase):
    def test_parser_reads_triggers_jobs_and_literals(self):
        text = """
name: sample
on:
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  example:
    timeout-minutes: 180
    steps:
      - name: Script
        if: always()
        run: |
          echo one
          echo two
"""
        doc = workflow.parse_yaml(text)
        self.assertEqual(doc["name"], "sample")
        self.assertIn("pull_request", doc["on"])
        self.assertIsNone(doc["on"]["pull_request"])
        self.assertEqual(doc["jobs"]["example"]["timeout-minutes"], 180)
        step = doc["jobs"]["example"]["steps"][0]
        self.assertEqual(step["if"], "always()")
        self.assertEqual(step["run"], "echo one\necho two\n")

    def test_wp28_native_workflow_contract(self):
        doc, text = workflow.load_workflow()
        errors = workflow.lint_workflow(doc, text)
        self.assertEqual(errors, [])
        job = doc["jobs"]["windows-native-matrix"]
        self.assertEqual(job["runs-on"], "windows-2022")
        self.assertGreaterEqual(job["timeout-minutes"], 120)
        self.assertEqual(doc["on"]["workflow_dispatch"], None)
        self.assertEqual(doc["permissions"]["contents"], "read")
        self.assertEqual(doc["permissions"], {"contents": "read"})
        self.assertTrue(doc["concurrency"]["cancel-in-progress"])
        upload = [step for step in job["steps"] if str(step.get("uses", "")).startswith("actions/upload-artifact@")][0]
        self.assertEqual(upload["if"], "always()")
        self.assertEqual(upload["with"]["if-no-files-found"], "error")
        self.assertIn("WP28_R3_EVIDENCE", upload["with"]["path"])
        runs = "\n".join(step["run"] for step in job["steps"] if isinstance(step.get("run"), str))
        self.assertIn("wp28_r3_windows_ci.ps1", runs)
        self.assertIn("-Run", runs)
        self.assertIn("-EvidenceDirectory", runs)
        self.assertIn("-ReportTimeoutMs", runs)
        self.assertIn("-GateTimeoutMs", runs)
        self.assertIn("flutter pub get --enforce-lockfile", runs)
        self.assertNotIn("secrets.", text)
        self.assertNotIn("contents: write", text)

    def test_lint_rejects_skip_success_and_missing_upload_guard(self):
        doc, text = workflow.load_workflow()
        broken = text.replace("if: always()", "if: success()").replace("if-no-files-found: error", "if-no-files-found: ignore")
        errors = workflow.lint_workflow(workflow.parse_yaml(broken), broken)
        self.assertTrue(any("skip-style if" in item for item in errors))
        self.assertTrue(any("if-no-files-found" in item for item in errors))

    def test_cli_fails_on_a_workflow_without_windows_job(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "empty.yml"
            path.write_text("name: other\non:\n  push:\njobs:\n  lint:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n", encoding="utf-8")
            self.assertEqual(workflow.main(["--file", str(path)]), 1)


if __name__ == "__main__":
    unittest.main()
