"""Fault contracts for I8 packaging; synthetic resources, no downloads/devices."""
import json
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch
import zipfile
import i8_assets
import test_ocr_bundle
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
import wp17_i8_candidate as candidate


class Resources(test_ocr_bundle.OfficialBundleTest):
    def setUp(self):
        super().setUp()
        self.lock_path = self.root / "lock.json"
        self.lock_path.write_text(json.dumps(self.lock))
        for module, name, value in (
            (i8_assets, "LOCK_PATH", self.lock_path),
            (i8_assets, "NOTICE_PATH", self.source / "licenses/THIRD_PARTY_OCR_NOTICES.md"),
        ):
            p = patch.object(module, name, value)
            p.start()
            self.addCleanup(p.stop)

    def test_missing_model_refuses_and_preserves_previous_install(self):
        i8_assets.stage_bundle(self.source, self.out)
        before = self.snapshot(self.out)
        (self.source / "ncnn" / i8_assets.stage.__globals__["MODEL_NAMES"][0]).unlink()
        with self.assertRaises(candidate.PreparationError):
            i8_assets.stage_bundle(self.source, self.out)
        self.assertEqual(before, self.snapshot(self.out))

    def test_missing_licence_refuses(self):
        (self.source / "licenses/licence.txt").unlink()
        with self.assertRaises(candidate.PreparationError):
            i8_assets.stage_bundle(self.source, self.out)

    def test_copy_interruption_preserves_installed_bytes_and_mtimes(self):
        i8_assets.stage_bundle(self.source, self.out)
        before = self.snapshot(self.out)
        with patch("stage_official_bundle.shutil.copyfile", side_effect=OSError("copy interrupted")):
            with self.assertRaises(OSError):
                i8_assets.stage_bundle(self.source, self.out)
        self.assertEqual(before, self.snapshot(self.out))

    def test_extra_file_and_tampered_manifest_refused(self):
        i8_assets.stage_bundle(self.source, self.out)
        root = self.out / "wp17-ocr"
        i8_assets.check_bundle(root)
        (root / "unexpected.bin").write_bytes(b"extra")
        with self.assertRaisesRegex(candidate.PreparationError, "unexpected"):
            i8_assets.check_bundle(root)
        (root / "unexpected.bin").unlink()
        (root / "bundle-manifest.json").write_text("{}")
        with self.assertRaisesRegex(candidate.PreparationError, "manifest"):
            i8_assets.check_bundle(root)

    def test_false_self_consistent_notice_refused(self):
        reviewed_notice = self.root / "reviewed-notice"
        reviewed_notice.write_bytes(b"synthetic licence")
        changed = self.source / "licenses/THIRD_PARTY_OCR_NOTICES.md"
        changed.write_bytes(b"missing required terms")
        self.report["attachments"]["licenses/THIRD_PARTY_OCR_NOTICES.md"] = candidate.record(changed)
        self.write_report()
        with patch.object(i8_assets, "NOTICE_PATH", reviewed_notice):
            with self.assertRaises(candidate.PreparationError):
                i8_assets.reviewed(self.source)

    def test_candidate_abi_and_resources(self):
        i8_assets.stage_bundle(self.source, self.out)
        root = self.out / "wp17-ocr"
        apk = self.root / "candidate.apk"
        elf = bytearray(64)
        elf[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", elf, 18, 183)
        def write_apk(machine):
            struct.pack_into("<H", elf, 18, machine)
            with zipfile.ZipFile(apk, "w") as archive:
                for p in root.rglob("*"):
                    if p.is_file():
                        archive.write(p, "assets/wp17-ocr/" + p.relative_to(root).as_posix())
                archive.writestr("lib/arm64-v8a/libmatrixflow_ocr.so", elf)
        write_apk(62)
        with self.assertRaisesRegex(candidate.PreparationError, "ABI"):
            candidate.inspect(apk, "android-arm64-v8a", True, root)
        write_apk(183)
        self.assertEqual(candidate.inspect(apk, "android-arm64-v8a", True, root)["abi"], "arm64-v8a")

    def test_default_rejects_ocr_without_loading_models(self):
        folder = self.root / "default"
        folder.mkdir()
        (folder / "compoise.exe").write_bytes(b"synthetic executable")
        with patch.object(candidate, "check_bundle", side_effect=AssertionError("must not load models")):
            self.assertFalse(candidate.inspect(folder, "windows", False, None)["ocrEnabled"])
        (folder / "matrixflow_ocr.dll").write_bytes(b"residue")
        with self.assertRaisesRegex(candidate.PreparationError, "residue"):
            candidate.inspect(folder, "windows", False, None)


if __name__ == "__main__":
    unittest.main()
