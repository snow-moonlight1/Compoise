"""Regression checks for read-only preparation and verified model deployment.

Run: python -m unittest discover -s native/ocr/tools -p test_ocr_preparation.py
Only synthetic files in an OS temporary directory are modified.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
spec = importlib.util.spec_from_file_location("convert_models", HERE / "convert_models.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class ReadOnlyConversionTest(unittest.TestCase):
    def test_check_preserves_lock_and_all_files(self):
        with tempfile.TemporaryDirectory(prefix="wp17-prep-") as directory:
            root = Path(directory)
            lock = {"schema": 1, "files": {}}
            for model in converter.MODELS.values():
                for name in model["files"]:
                    path = root / "convert-work/paddle" / model["repo"].split("/")[-1] / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b"synthetic pinned input")
                    lock["files"][f"{model['repo']}/{name}"] = {"sha256": converter.sha256(path)}
            lock_path = root / "lock.json"
            lock_path.write_text(json.dumps(lock), encoding="utf-8")
            before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob("*") if p.is_file()}
            with patch.object(converter, "LOCK_PATH", lock_path), patch.object(sys, "argv", ["convert", "--assets", str(root), "--check"]):
                self.assertEqual(converter.main(), 0)
            after = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob("*") if p.is_file()}
            self.assertEqual(before, after)
            self.assertFalse((root / "ncnn-official").exists())

    def test_check_does_not_download_missing_inputs(self):
        lock = json.loads((HERE / "models.lock.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory(prefix="wp17-prep-") as directory, patch.object(converter, "download") as download:
            with patch.object(converter, "load_lock", return_value=lock), patch.object(sys, "argv", ["convert", "--assets", directory, "--check"]):
                with self.assertRaisesRegex(SystemExit, "offline: missing pinned input"):
                    converter.main()
            download.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_unpinned_inputs_are_rejected_before_download(self):
        with patch.object(converter, "download") as download:
            with self.assertRaisesRegex(SystemExit, "no pinned input hash"):
                converter.ensure_input({"files": {}}, "unknown/model", "inference.json", Path("unused"), False)
            download.assert_not_called()


@unittest.skipUnless(os.name == "nt", "PowerShell preparation script is Windows-specific")
class PowerShellDeploymentTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wp17-prep-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.assets = self.root / "assets"
        script = self.repo / "tool/prepare_ocr_assets.ps1"
        script.parent.mkdir(parents=True)
        shutil.copyfile(REPO / "tool/prepare_ocr_assets.ps1", script)
        pin = self.repo / "third_party/ncnn_pin.txt"
        pin.parent.mkdir(parents=True)
        shutil.copyfile(REPO / "third_party/ncnn_pin.txt", pin)
        self.lock_path = self.repo / "native/ocr/tools/models.lock.json"
        self.lock_path.parent.mkdir(parents=True)
        # Use known local dictionary/header bytes, never download in these tests.
        cache = Path(os.environ["LOCALAPPDATA"]) / "wp17r2-assets"
        for relative in ("ncnn/ppocrv5_dict.txt", "third_party/stb_image.h"):
            if not (cache / relative).is_file():
                self.skipTest("verified dictionary/header cache is not available")
            target = self.assets / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(cache / relative, target)
        self.names = [f"PP_OCRv5_mobile_{kind}.ncnn.{suffix}" for kind in ("det", "rec") for suffix in ("param", "bin")]
        self.lock = {"files": {}}
        for name in self.names:
            data = f"synthetic official {name}".encode()
            path = self.assets / "ncnn-official" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            (self.assets / "ncnn" / name).write_bytes(b"historical validation model")
            self.lock["files"][f"ncnn-official/{name}"] = {"sha256": hashlib.sha256(data).hexdigest()}
        self.lock_path.write_text(json.dumps(self.lock), encoding="utf-8")

    def run_script(self, *extra):
        shell = shutil.which("pwsh") or "powershell.exe"
        return subprocess.run([shell, "-NoProfile", "-File", str(self.repo / "tool/prepare_ocr_assets.ps1"), "-AssetRoot", str(self.assets), "-ModelSource", "official", "-Ncnn", "none", "-SkipNcnnSource", "-Offline", *extra], capture_output=True, text=True, timeout=30)

    def test_official_conversion_cache_is_deployed_and_check_is_read_only(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in self.names:
            expected = (self.assets / "ncnn-official" / name).read_bytes()
            self.assertEqual((self.assets / "ncnn" / name).read_bytes(), expected)
            self.assertEqual((self.assets / "deploy/ncnn" / name).read_bytes(), expected)
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.assets.rglob("*") if p.is_file()}
        result = self.run_script("-Check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.assets.rglob("*") if p.is_file()})
        (self.assets / "deploy/ncnn" / self.names[-1]).write_bytes(b"damaged deployment")
        self.assertEqual(self.run_script("-Check").returncode, 3)

    def test_one_bad_hash_preserves_all_historical_models(self):
        (self.assets / "ncnn-official" / self.names[-1]).write_bytes(b"bad conversion")
        result = self.run_script()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        for name in self.names:
            self.assertEqual((self.assets / "ncnn" / name).read_bytes(), b"historical validation model")
        self.assertFalse((self.assets / "deploy").exists())

    def test_unlocked_official_outputs_fail_with_verification_exit(self):
        self.lock_path.write_text('{"files": {}}', encoding="utf-8")
        result = self.run_script()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("complete and review the official conversion first", result.stdout)

    def test_check_refuses_cleanup_and_does_not_create_directories(self):
        self.assertEqual(self.run_script("-Check", "-CleanWork").returncode, 2)
        shutil.rmtree(self.assets / "third_party")
        result = self.run_script("-Check")
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertFalse((self.assets / "third_party").exists())


if __name__ == "__main__":
    unittest.main()
