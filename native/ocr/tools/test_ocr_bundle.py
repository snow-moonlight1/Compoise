"""Failure and read-only contracts for optional official app asset staging."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import stage_official_bundle as bundle


class OfficialBundleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wp17i6-bundle-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source, self.out = self.root / "source", self.root / "out"
        self.lock = {"files": {}, "attachments": {}, "conversion": {"byte_identical": True}}
        self.report = {"modelSource": "official", "models": {}, "attachments": {},
                       "inputs": {}, "onnx": {}, "conversion": self.lock["conversion"]}
        for name in bundle.MODEL_NAMES + [bundle.DICT_NAME]:
            path = self.source / "ncnn" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.report["models"][name] = {"bytes": path.stat().st_size, "sha256": digest}
            if name == bundle.DICT_NAME:
                patcher = patch.object(bundle, "DICT_SHA", digest)
                patcher.start()
                self.addCleanup(patcher.stop)
            else:
                self.lock["files"]["ncnn-official/" + name] = {"sha256": digest}
        for name in ("licenses/licence.txt", "licenses/THIRD_PARTY_OCR_NOTICES.md"):
            path = self.source / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(b"synthetic licence")
            entry = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}
            self.report["attachments"][name] = entry
            if name.endswith("licence.txt"):
                self.lock["attachments"][name] = entry
        self.write_report()

    def write_report(self):
        (self.source / "deployed.json").write_text(json.dumps(self.report))

    def snapshot(self, root):
        return {str(p.relative_to(root)): (p.read_bytes(), p.stat().st_mtime_ns)
                for p in root.rglob("*") if p.is_file()}

    def test_check_preserves_source_destination_bytes_and_times(self):
        bundle.stage(self.source, self.out, self.lock)
        before = self.snapshot(self.root)
        bundle.stage(self.source, self.out, self.lock, check=True)
        self.assertEqual(self.snapshot(self.root), before)

    def test_legacy_or_stale_provenance_cannot_replace_official_bundle(self):
        bundle.stage(self.source, self.out, self.lock)
        before = self.snapshot(self.out)
        self.report["modelSource"] = "nihui"
        self.write_report()
        with self.assertRaisesRegex(bundle.PreparationError, "provenance"):
            bundle.stage(self.source, self.out, self.lock)
        self.assertEqual(self.snapshot(self.out), before)

    def test_bad_last_licence_keeps_complete_previous_bundle(self):
        bundle.stage(self.source, self.out, self.lock)
        before = self.snapshot(self.out)
        (self.source / "licenses/licence.txt").write_bytes(b"changed licence")
        with self.assertRaises(bundle.PreparationError):
            bundle.stage(self.source, self.out, self.lock)
        self.assertEqual(self.snapshot(self.out), before)

    def test_changed_graph_refused_without_touching_destination(self):
        bundle.stage(self.source, self.out, self.lock)
        before = self.snapshot(self.out)
        (self.source / "ncnn" / bundle.MODEL_NAMES[0]).write_bytes(b"unreviewed graph")
        with self.assertRaises(bundle.PreparationError):
            bundle.stage(self.source, self.out, self.lock)
        self.assertEqual(self.snapshot(self.out), before)

    def test_overlapping_destination_refused(self):
        with self.assertRaises(bundle.PreparationError) as caught:
            bundle.stage(self.source, self.source / "data", self.lock)
        self.assertEqual(caught.exception.exit_code, 2)


if __name__ == "__main__":
    unittest.main()
