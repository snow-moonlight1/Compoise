import ast
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
POWERSHELL = shutil.which("pwsh") or shutil.which("powershell")


class ScriptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not POWERSHELL:
            raise AssertionError("PowerShell is required for WP28-R3 script contracts")

    def _run(self, script: Path, extra=None, timeout=30):
        command = [POWERSHELL, "-NoProfile", "-File", str(script)]
        if extra:
            command.extend(extra)
        return subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout)

    def _ast(self, script: Path):
        command = [
            POWERSHELL, "-NoProfile", "-Command",
            "$err=$null; $tok=$null; "
            "[void][System.Management.Automation.Language.Parser]::ParseFile('%s', [ref]$tok, [ref]$err); "
            "if ($err) { $err | ForEach-Object { $_.Message }; exit 1 }; exit 0" % str(script).replace("'", "''"),
        ]
        result = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_powershell_ast_parses_r2_and_r3_scripts(self):
        for name in (
            "wp28_r2_build_diagnostic.ps1",
            "wp28_r2_windows_gates.ps1",
            "wp28_u2_windows_harness.ps1",
            "wp28_r3_desktop_probe.ps1",
            "wp28_r3_windows_ci.ps1",
        ):
            with self.subTest(name=name):
                self._ast(SCRIPTS / name)

    def test_scripts_block_without_run_and_do_not_create_evidence(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-block-") as raw:
            evidence = Path(raw) / "evidence"
            for name, marker in (
                ("wp28_r3_windows_ci.ps1", "WP28-R3 native CI matrix requires -Run"),
                ("wp28_r3_desktop_probe.ps1", "WP28-R3 desktop probe requires -Run"),
                ("wp28_r2_build_diagnostic.ps1", "R2 diagnostic build requires -Run"),
                ("wp28_r2_windows_gates.ps1", "R2 gate acceptance requires -Run"),
                ("wp28_u2_windows_harness.ps1", "pass -Run for synthetic private-desktop acceptance"),
            ):
                with self.subTest(name=name):
                    result = self._run(SCRIPTS / name, ["-EvidenceDirectory", str(evidence)])
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertIn("Blocked:", result.stdout)
                    self.assertIn(marker, result.stdout)
                    self.assertFalse(evidence.exists())

    def test_r2_scripts_accept_ci_sdk_timeout_and_evidence_parameters(self):
        diagnostic = (SCRIPTS / "wp28_r2_build_diagnostic.ps1").read_text(encoding="utf-8")
        gates = (SCRIPTS / "wp28_r2_windows_gates.ps1").read_text(encoding="utf-8")
        harness = (SCRIPTS / "wp28_u2_windows_harness.ps1").read_text(encoding="utf-8")
        self.assertIn("[string]$EvidenceDirectory", diagnostic)
        self.assertIn("[string]$Flutter", diagnostic)
        self.assertIn("[string]$EvidenceDirectory", gates)
        self.assertIn("[int]$TimeoutMs", gates)
        self.assertIn("[string]$DiagnosticProof", harness)
        self.assertIn("[int]$ReportTimeoutMs", harness)
        self.assertIn("[int]$ExitTimeoutMs", harness)
        self.assertIn("$script:ReportTimeoutMs", harness)

    def test_python_modules_parse(self):
        for name in ("wp28_r3_report.py", "wp28_r3_workflow.py"):
            ast.parse((SCRIPTS / name).read_text(encoding="utf-8"), filename=name)


if __name__ == "__main__":
    unittest.main()
