import importlib.util
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

_spec = importlib.util.spec_from_file_location(
    "r2_audit", Path(__file__).resolve().parents[1] / "wp28_r2_candidate_audit.py"
)
audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(audit)


class R2AuditTests(unittest.TestCase):
    def test_utf8_bom_build_files_preserve_both_gate_rejections(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r2-audit-") as root:
            root = Path(root)
            config = root / "windows/flutter/ephemeral/generated_config.cmake"
            project = root / "build/windows/x64/runner/compoise.vcxproj"
            config.parent.mkdir(parents=True)
            project.parent.mkdir(parents=True)
            config.write_text("# 中文合成生成文件\n", encoding="utf-8-sig")
            project.write_text("<!-- 中文合成生成文件 -->\n", encoding="utf-8-sig")
            audit.inspect_normal_build_gates(root)
            config.write_text("# 中文\nV1AyOF9VMl9IQVJORVNTPXRydWU=", encoding="utf-8-sig")
            with self.assertRaisesRegex(ValueError, "Normal Dart build"):
                audit.inspect_normal_build_gates(root)
            config.write_text("# 中文\n", encoding="utf-8-sig")
            project.write_text("<!-- 中文 -->\n<PreprocessorDefinitions>WP28_U2_HARNESS</PreprocessorDefinitions>", encoding="utf-8-sig")
            with self.assertRaisesRegex(ValueError, "Normal native build"):
                audit.inspect_normal_build_gates(root)

    def test_failed_cli_invalidates_an_old_success_report(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r2-audit-") as root:
            output = Path(root) / "report.json"
            output.write_text('{"passed":true}')
            result = subprocess.run([
                sys.executable, audit.__file__, "--first", root, "--second", root,
                "--extracted-first", root, "--extracted-second", root,
                "--commit", "0" * 40, "--output", str(output),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("REJECTED", result.stderr)
            self.assertFalse(output.exists())

    def test_added_removed_and_changed_files_are_separate(self):
        a = [{"path": "same", "bytes": 1, "sha256": "a"},
             {"path": "changed", "bytes": 1, "sha256": "a"},
             {"path": "removed", "bytes": 1, "sha256": "a"}]
        b = [a[0], {"path": "changed", "bytes": 1, "sha256": "b"},
             {"path": "added", "bytes": 1, "sha256": "a"}]
        self.assertEqual(audit.compare_inventories(a, b), {
            "added": ["added"], "removed": ["removed"],
            "changed": ["changed"], "identicalFiles": 1})

    def test_extra_extracted_file_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r2-audit-") as root:
            path = Path(root) / "unexpected.txt"
            path.write_bytes(b"synthetic")
            with self.assertRaisesRegex(ValueError, "inventory differs"):
                audit.inspect_extracted(Path(root), [])

    def test_diagnostic_ascii_and_wide_markers_are_rejected(self):
        for encoding in ("utf-8", "utf-16-le"):
            with self.subTest(encoding=encoding), tempfile.TemporaryDirectory(prefix="wp28-r2-audit-") as root:
                path = Path(root) / "compoise.exe"
                path.write_bytes("WP28_U2_ROOT".encode(encoding))
                item = audit.gate.snapshot(path)
                inventory = [{"path": path.name, "bytes": item["bytes"], "sha256": item["sha256"]}]
                with self.assertRaisesRegex(ValueError, "diagnostic marker"):
                    audit.inspect_extracted(Path(root), inventory)

    def test_changed_extracted_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r2-audit-") as root:
            path = Path(root) / "data.txt"
            path.write_bytes(b"expected")
            item = audit.gate.snapshot(path)
            inventory = [{"path": path.name, "bytes": item["bytes"], "sha256": item["sha256"]}]
            self.assertEqual(audit.inspect_extracted(Path(root), inventory), inventory)
            path.write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "inventory differs"):
                audit.inspect_extracted(Path(root), inventory)


if __name__ == "__main__":
    unittest.main()
