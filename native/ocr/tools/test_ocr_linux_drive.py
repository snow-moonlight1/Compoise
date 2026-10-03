"""Driver regressions; device acceptance remains separately opt-in."""
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from drive_official_import import Linux
from drive_linux_reopen import execute, validate_report


class LinuxDriveTest(unittest.TestCase):
    def test_disappearing_gtk_children_do_not_abort_directory_navigation(self):
        class Gone(Exception):
            pass

        desktop, app, dead, cell = (Mock() for _ in range(4))
        desktop.get_child_count.return_value = 1
        desktop.get_child_at_index.return_value = app
        app.get_process_id.return_value = 44
        app.get_child_count.return_value = 3
        app.get_child_at_index.side_effect = [None, dead, cell]
        dead.get_role_name.side_effect = Gone()
        cell.get_child_count.return_value = 0
        gi = SimpleNamespace(require_version=Mock())
        repository = SimpleNamespace(Atspi=SimpleNamespace(get_desktop=lambda _: desktop),
                                     GLib=SimpleNamespace(GError=Gone))
        with patch.dict("sys.modules", {"gi": gi, "gi.repository": repository}):
            self.assertEqual(Linux.nodes(44), [app, cell])
            self.assertFalse(Linux.matches(dead, "table cell", ("file.png",)))

    def test_real_picker_refuses_unowned_display_before_ui_access(self):
        with patch.dict(os.environ, {"DISPLAY": ":0"}, clear=True), patch("drive_official_import.run") as run:
            with self.assertRaisesRegex(RuntimeError, "private Xvfb"):
                Linux(Path("unused-fixtures")).choose(False)
            run.assert_not_called()

    def test_explicit_i6_file_entry_never_operates_a_display(self):
        with patch("drive_official_import.run") as run:
            Linux(Path("/unused"), file_entry=True).choose(False)
            run.assert_not_called()

    def test_location_ui_only_receives_a_directory_and_selection_uses_real_rows(self):
        with tempfile.TemporaryDirectory(prefix="wp17i7-driver-test-") as root:
            fixtures = Path(root) / "fixtures"
            fixtures.mkdir()
            for index in range(5):
                (fixtures / f"{index}.png").write_bytes(b"fixture")
            picker = Linux(fixtures)
            names = [f"{index}.png" for index in range(5)]
            picker.select_files = Mock(return_value=names)
            picker.confirm = Mock(return_value="OK")
            picker.snapshot = Mock()
            results = [Mock(returncode=0, stdout="123\n"), Mock(returncode=1, stdout="")]
            with patch.dict(os.environ, {"DISPLAY": ":77", "WP17_LINUX_PRIVATE_DISPLAY": ":77"}), \
                 patch("drive_official_import.subprocess.run", side_effect=results), \
                 patch("drive_official_import.run", return_value="42\n") as run, \
                 patch("drive_official_import.time.sleep"):
                picker.choose(False)
            picker.select_files.assert_called_once_with(42, names)
            picker.confirm.assert_called_once_with(42)
            commands = [c.args[0] for c in run.call_args_list]
            self.assertIn(["xdotool", "key", "--clearmodifiers", "ctrl+l", "ctrl+a"], commands)
            typed = [command[-1] for command in commands if "type" in command]
            self.assertEqual(typed, [str(fixtures.resolve()) + "/"])

    def test_extra_or_missing_gtk_selected_rows_cannot_be_confirmed(self):
        picker = Linux(Path("/unused"))
        cell = Mock()
        selection = cell.get_parent.return_value.get_parent.return_value.get_selection_iface.return_value
        selection.select_all.return_value = True
        selection.get_n_selected_children.return_value = 1
        selection.get_selected_child.return_value.get_child_at_index.return_value.get_name.return_value = "wrong.png"
        picker.cell = Mock(return_value=cell)
        with self.assertRaisesRegex(RuntimeError, "selected rows differ"):
            picker.select_files(1, ["expected.png"])

    def test_report_cannot_claim_injected_picker_or_in_memory_reopen(self):
        for report, phase in (({"real_picker": False, "real_ocr": True}, "import"),
                              ({"real_picker": True, "real_ocr": False}, "import"),
                              ({"independent_disk_reopen": False}, "reopen")):
            with self.assertRaises(RuntimeError):
                validate_report(dict(report, passed=True, phase=phase, pid=1), phase, 1)
        with self.assertRaises(RuntimeError):
            validate_report({"passed": True, "phase": "reopen", "pid": 2, "independent_disk_reopen": True}, "reopen", 1)

    @unittest.skipIf(os.name == "nt", "POSIX application waitpid/process groups")
    def test_actual_exit_failure_is_retained_even_with_success_report(self):
        with tempfile.TemporaryDirectory(prefix="wp17i7-exit-test-") as root:
            directory = Path(root)
            executable = directory / "application"
            executable.write_text("#!/usr/bin/env python3\n"
                "import json, os\n"
                "from pathlib import Path\n"
                "Path(os.environ['WP17_I7_REPORT']).write_text(json.dumps({"
                "'passed':True,'phase':'reopen','pid':os.getpid(),'independent_disk_reopen':True}))\n"
                "raise SystemExit(7)\n")
            executable.chmod(0o700)
            with self.assertRaisesRegex(RuntimeError, "Application failed"):
                execute(executable, directory, directory, "reopen", dict(os.environ), Mock())
            evidence = json.loads((directory / "process-reopen.json").read_text())
            self.assertEqual(evidence["exit"], 7)
            self.assertFalse(evidence["normal_exit"])
            self.assertTrue((directory / "flow-reopen.json").exists())


if __name__ == "__main__":
    unittest.main()
