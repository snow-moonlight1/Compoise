"""Host contracts only. No ADB/device/model download or OCR result injection."""
from copy import deepcopy
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch

import a1_android as a1


def device(**changes):
    return {"serial": "a1-dedicated", "state": "device", "abi": "arm64-v8a,armeabi-v7a",
            "sdk": "23", "fingerprint": "test/fixed/build", "packages": [], **changes}


def enrollment(**changes):
    return {"schema": 1, "scope": "WP17-A1", "kind": "dedicated-test-device",
            "serial": "a1-dedicated", "fingerprint": "test/fixed/build", **changes}


def flows():
    common = {"passed": True, "exit_intent": 0, "failures": [], "identity": a1.PACKAGE,
              "snapshot": {"tasks": [{"id": "parent", "notes": "date text",
                                       "subtasks": [{"id": "child", "completed": True}]}]}}
    first = {**deepcopy(common), "phase": "import", "pid": 111, "real_picker": True,
             "real_ocr": True, "temporary_pngs": 0, "cases": [
                 {"case": "picker-cancel", "store_writer_calls": 0},
                 {"case": "review-cancel", "images": 10, "store_writer_calls": 0,
                  "unconfirmed_submit_disabled": True, "failed_images": 1},
                 {"case": "active-cancel-recovery", "store_writer_calls": 0, "cancelled": True},
                 {"case": "failed-save-retry", "images": 10, "successful_pointers": 1,
                  "items": 24, "roots": 18, "completed": 6, "retry_stable_ids": True,
                  "failed_save_preserved_review": True, "date_text_only_in_notes": True}],
             "measurements": [{"case": "native-cold-first-call"}, {"case": "native-hot-recovery"},
                              {"case": "missing-dictionary-bad-png-recovery", "passed": True}]}
    return first, {**deepcopy(common), "phase": "reopen", "pid": 222, "independent_disk_reopen": True}


class Arm64DriverTest(unittest.TestCase):
    def test_default_and_unenabled_accept_never_touch_device_or_disk(self):
        for args in ([], ["build"], ["accept", "--root", "invalid"]):
            with self.subTest(args=args), patch("sys.argv", ["a1_android.py", *args]), \
                    patch.object(a1, "Commands") as commands, patch.object(a1, "private_root") as root:
                self.assertEqual(a1.main(), 0)
                commands.assert_not_called()
                root.assert_not_called()

    def test_read_only_inventory_never_queries_offline_device(self):
        class ReadOnly:
            def __init__(self, root):
                self.root, self.calls = root, []
            def run(self, args):
                self.calls.append(args)
                return "List of devices attached\nemulator-5562 offline transport_id:1\n"
        with tempfile.TemporaryDirectory() as temporary:
            command = ReadOnly(Path(temporary))
            result = a1.inventory(command, Path("adb"))
            self.assertEqual(command.calls, [[Path("adb"), "devices", "-l"]])
            self.assertIsNone(result[0]["abi"])
            self.assertIsNone(result[0]["packages"])

    def test_actual_device_enrollment_and_api_are_required(self):
        a1.authorize(device(), enrollment())
        for dev, permit in ((device(state="offline"), enrollment()),
                            (device(abi="x86_64"), enrollment()),
                            (device(sdk="22"), enrollment()),
                            (device(), enrollment(fingerprint="old/build")),
                            (device(), enrollment(kind="personal-phone")),
                            (device(), enrollment(serial="somebody-else")),
                            (device(packages=["package:" + a1.PACKAGE]), enrollment())):
            with self.subTest(device=dev, permit=permit), self.assertRaises(ValueError):
                a1.authorize(dev, permit)

    def test_normal_package_is_read_only_and_not_an_install_target(self):
        a1.authorize(device(packages=["package:com.matrixflow.app"]), enrollment())
        self.assertEqual(a1.PACKAGE, "com.matrixflow.app.wp17i6")

    def test_meminfo_api23_pss_and_process_rss_have_separate_units(self):
        raw = " Native Heap 123 0 0 0 456 78\n Dalvik Heap 50 0 0\n Dalvik Other 7 0 0\n TOTAL 210 0 0\n"
        memory = a1.parse_memory(raw, "VmRSS:\t350 kB\nVmHWM:\t400 kB\n")
        self.assertEqual(memory["native_heap_pss_kib"], 123)
        self.assertEqual(memory["java_heap_pss_kib"], 57)
        self.assertEqual(memory["process_pss_kib"], 210)
        self.assertEqual(memory["process_rss_kib"], 350)
        self.assertEqual(memory["process_hwm_kib"], 400)
        self.assertIsNone(memory["java_heap_rss_kib"])

    def test_modern_meminfo_zero_and_missing_are_not_fabricated(self):
        raw = "App Summary\n Pss(KB) Rss(KB)\n Java Heap: 80 120\n Native Heap: 90 140\n TOTAL PSS: 0 TOTAL RSS: 300\n"
        memory = a1.parse_memory(raw, "permission denied")
        self.assertEqual(memory["process_pss_kib"], 0)
        self.assertEqual(memory["java_heap_rss_kib"], 120)
        self.assertEqual(memory["native_heap_rss_kib"], 140)
        self.assertIsNone(memory["process_rss_kib"])
        peaks = a1.memory_peaks([memory, {"sampling_error": "denied"}])
        self.assertEqual(peaks["process_pss_kib"], 0)
        self.assertIsNone(peaks["process_rss_kib"])

    def test_full_flow_requires_second_pid_and_deep_snapshot(self):
        first, second = flows()
        a1.validate_flow(first, second)
        second["snapshot"]["tasks"][0]["subtasks"][0]["completed"] = False
        with self.assertRaisesRegex(ValueError, "snapshot"):
            a1.validate_flow(first, second)
        first, second = flows()
        second["pid"] = first["pid"]
        with self.assertRaisesRegex(ValueError, "independent"):
            a1.validate_flow(first, second)

    def test_failure_injection_skip_or_old_five_image_run_cannot_pass(self):
        for field, value in (("passed", False), ("exit_intent", 1), ("real_picker", False),
                             ("real_ocr", False), ("temporary_pngs", 1), ("failures", ["teardown failed"])):
            first, second = flows()
            first[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                a1.validate_flow(first, second)
        first, second = flows()
        first["cases"][1]["images"] = 5
        with self.assertRaisesRegex(ValueError, "Ten-image"):
            a1.validate_flow(first, second)
        first, second = flows()
        first["cases"][0]["store_writer_calls"] = 1
        with self.assertRaisesRegex(ValueError, "zero Store"):
            a1.validate_flow(first, second)

    def test_bad_retry_date_or_missing_boundary_evidence_cannot_pass(self):
        for field, value in (("successful_pointers", 2), ("retry_stable_ids", False),
                             ("date_text_only_in_notes", False), ("items", 25)):
            first, second = flows()
            first["cases"][-1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                a1.validate_flow(first, second)
        first, second = flows()
        first["measurements"].pop()
        with self.assertRaisesRegex(ValueError, "boundary"):
            a1.validate_flow(first, second)

    def test_elf_architecture_refuses_x86_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "lib.so"
            header = bytearray(64)
            header[:6] = b"\x7fELF\x02\x01"
            header[18:20] = (62).to_bytes(2, "little")
            binary.write_bytes(header)
            with self.assertRaisesRegex(ValueError, "AArch64"):
                a1.elf_facts(binary)
            header[18:20] = (183).to_bytes(2, "little")
            binary.write_bytes(header)
            self.assertEqual(a1.elf_facts(binary)["machine"], "AArch64")

    def test_forced_crashed_or_report_failure_completion_cannot_pass(self):
        a1.assert_unforced_completion("10-03 19:00:00.100 111 112 I flutter: completed", 111)
        for line in ("10-03 19:00:00.100 111 112 F libc: Fatal signal 9",
                     "10-03 19:00:00.100 111 112 E AndroidRuntime: FATAL EXCEPTION",
                     "ActivityManager: Killing 111:com.matrixflow.app.wp17i6/u0a42",
                     "ActivityManager: Force stopping " + a1.PACKAGE,
                     "10-03 19:00:00.100 111 112 I flutter: WP17_A1_REPORT_FAILED=full disk"):
            with self.subTest(line=line), self.assertRaises(ValueError):
                a1.assert_unforced_completion(line, 111)

    def test_remote_smoke_exit_sentinel_rejects_kill_and_partial_output(self):
        for raw in ('{"summary":{"images":1,"succeeded":1}}\nA1_RC=137\n',
                    '{"summary":{"images":1,"succeeded":1}}\n',
                    '{"summary":{"images":1,"succeeded":1}}\nA1_RC=0\n'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                a1.parse_smoke(raw, ["zh_light_base"], 0, [None])

    def test_smoke_r2_comparison_accepts_original_and_rejects_changed_text(self):
        reference = json.loads((a1.REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json").read_text(encoding="utf-8"))["images"]
        image = deepcopy(next(item for item in reference if "zh_light_base.png" in item["path"]))
        summary = {"summary": {"images": 1, "succeeded": 1}}
        raw = json.dumps(image) + "\n" + json.dumps(summary) + "\nA1_RC=0\n"
        self.assertEqual(a1.parse_smoke(raw, ["zh_light_base"], 0, [None])["exit"], 0)
        image["lines"][0]["text"] += "altered"
        raw = json.dumps(image) + "\n" + json.dumps(summary) + "\nA1_RC=0\n"
        with self.assertRaisesRegex(ValueError, "text/geometry"):
            a1.parse_smoke(raw, ["zh_light_base"], 0, [None])


if __name__ == "__main__":
    unittest.main()
