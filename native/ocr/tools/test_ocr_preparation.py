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
import types

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
spec = importlib.util.spec_from_file_location("convert_models", HERE / "convert_models.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)
import publish_models as publisher


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

    def test_changed_download_is_never_installed(self):
        with tempfile.TemporaryDirectory(prefix="wp17-prep-") as directory:
            path = Path(directory) / "model/inference.json"
            lock = {"files": {"official/model/inference.json": {"sha256": "0" * 64}}}
            def changed_download(url, destination):
                destination.parent.mkdir(parents=True)
                destination.write_bytes(b"upstream changed")
            with patch.object(converter, "download", side_effect=changed_download):
                with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
                    converter.ensure_input(lock, "official/model", "inference.json", path, False)
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix(".json.part").exists())

    def test_wrong_actual_tool_version_is_rejected(self):
        result = types.SimpleNamespace(returncode=0, stdout=json.dumps({"versions": {"paddle2onnx": "1.3.1"}}))
        with patch.object(converter.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(converter.PreparationError, "toolchain mismatch") as error:
                converter.check_toolchain(sys.executable)
            self.assertEqual(error.exception.exit_code, 5)

    def test_missing_interpreter_and_offline_child_preserve_exit_contract(self):
        with patch.object(converter.subprocess, "run", side_effect=FileNotFoundError("missing interpreter")):
            with self.assertRaises(converter.PreparationError) as error:
                converter.check_toolchain("missing-python")
            self.assertEqual(error.exception.exit_code, 5)
            with self.assertRaises(converter.PreparationError) as error:
                converter.run(["missing-python"])
            self.assertEqual(error.exception.exit_code, 5)
        with patch.object(converter.subprocess, "run", return_value=types.SimpleNamespace(returncode=4)):
            with self.assertRaises(converter.PreparationError) as error:
                converter.run(["conversion", "--offline"])
            self.assertEqual(error.exception.exit_code, 4)


class ConversionReplayTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wp17-replay-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.lock = {"schema": 1, "files": {}}
        for model in converter.MODELS.values():
            for name in model["files"]:
                path = self.root / "convert-work/paddle" / model["repo"].split("/")[-1] / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"pinned synthetic input")
                self.lock["files"][f"{model['repo']}/{name}"] = {"sha256": converter.sha256(path)}
        self.lock_path = self.root / "lock.json"
        self.lock_path.write_text(json.dumps(self.lock), encoding="utf-8")

    def fake_conversion(self, names, model_root, destination, python, actual):
        result = {}
        for key, path in converter.output_paths(names, destination, destination).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(key.encode())
            result[key] = path
        return result

    def invoke(self, *extra):
        with patch.object(converter, "LOCK_PATH", self.lock_path), patch.object(sys, "argv", ["convert", "--assets", str(self.root), "--offline", *extra]):
            return converter.main()

    def test_unreviewed_outputs_require_explicit_bootstrap(self):
        with patch.object(converter, "check_toolchain") as probe:
            with self.assertRaisesRegex(SystemExit, "no pinned output hash"):
                self.invoke()
            probe.assert_not_called()
        self.assertFalse((self.root / "ncnn-official").exists())

    def test_independent_replay_mismatch_preserves_lock_and_deployment(self):
        (self.root / "ncnn-official").mkdir()
        old = self.root / "ncnn-official/previous.bin"
        old.write_bytes(b"previous complete set")
        before = self.lock_path.read_bytes(), self.lock_path.stat().st_mtime_ns
        def divergent(*args):
            outputs = self.fake_conversion(*args)
            if args[2].name == "b":
                list(outputs.values())[-1].write_bytes(b"different second export")
            return outputs
        with patch.object(converter, "check_toolchain", return_value={}), patch.object(converter, "convert_once", side_effect=divergent):
            with self.assertRaisesRegex(SystemExit, "independent replay"):
                self.invoke("--record-outputs")
        self.assertEqual(before, (self.lock_path.read_bytes(), self.lock_path.stat().st_mtime_ns))
        self.assertEqual(old.read_bytes(), b"previous complete set")
        self.assertEqual(list(old.parent.iterdir()), [old])

    def test_matching_replays_record_then_read_only_check_verifies_outputs(self):
        with patch.object(converter, "check_toolchain", return_value={}), patch.object(converter, "convert_once", side_effect=self.fake_conversion):
            self.assertEqual(self.invoke("--record-outputs"), 0)
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(self.invoke("--check"), 0)
        self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.rglob("*") if p.is_file()})
        output = self.root / "ncnn-official/PP_OCRv5_mobile_rec.ncnn.bin"
        output.write_bytes(b"bad cached output")
        with patch.object(converter, "check_toolchain") as probe:
            with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
                self.invoke()
            probe.assert_not_called()
        self.assertEqual(output.read_bytes(), b"bad cached output")


class TransactionalPublicationTest(unittest.TestCase):
    def test_second_directory_rename_failure_rolls_back_first(self):
        with tempfile.TemporaryDirectory(prefix="wp17-publish-") as directory:
            root = Path(directory)
            targets = {}
            for name in ("cache", "deploy"):
                target, source = root / name, root / (name + "-source")
                target.mkdir(); source.mkdir()
                (target / "set").write_bytes(b"complete old set")
                (source / "set").write_bytes(b"complete new set")
                targets[target] = source
            original_replace = os.replace
            def failing_replace(source, destination):
                if Path(destination) == root / "deploy" and "stage" in str(source):
                    raise OSError("simulated locked deployment")
                return original_replace(source, destination)
            with patch.object(publisher.os, "replace", side_effect=failing_replace):
                with self.assertRaisesRegex(OSError, "locked deployment"):
                    publisher.replace_directories(targets)
            for target in targets:
                self.assertEqual((target / "set").read_bytes(), b"complete old set")
            publisher.replace_directories(targets)
            for target in targets:
                self.assertEqual((target / "set").read_bytes(), b"complete new set")

    def test_copy_failure_never_exposes_partial_set(self):
        with tempfile.TemporaryDirectory(prefix="wp17-publish-") as directory:
            root = Path(directory)
            target, source = root / "deploy", root / "source"
            target.mkdir(); source.mkdir()
            (target / "set").write_bytes(b"old")
            with patch.object(publisher.shutil, "copytree", side_effect=OSError("disk full")):
                with self.assertRaisesRegex(OSError, "disk full"):
                    publisher.replace_directories({target: source})
            self.assertEqual((target / "set").read_bytes(), b"old")

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
        for name in ("convert_models.py", "publish_models.py", "prepare_ocr_assets.py"):
            target = self.repo / "native/ocr/tools" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(HERE / name, target)
        shutil.copyfile(REPO / "native/ocr/THIRD_PARTY_OCR_NOTICES.md", self.repo / "native/ocr/THIRD_PARTY_OCR_NOTICES.md")
        pin = self.repo / "third_party/ncnn_pin.txt"
        pin.parent.mkdir(parents=True)
        shutil.copyfile(REPO / "third_party/ncnn_pin.txt", pin)
        self.lock_path = self.repo / "native/ocr/tools/models.lock.json"
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
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

    def test_bad_licence_preserves_models_and_deployment_report(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        roots = (self.assets / "ncnn", self.assets / "deploy")
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for root in roots for p in root.rglob("*") if p.is_file()}
        attachment = self.assets / "licenses/LICENSE.txt"
        attachment.parent.mkdir()
        attachment.write_bytes(b"changed licence attachment")
        self.lock["attachments"] = {"licenses/LICENSE.txt": {"sha256": "0" * 64}}
        self.lock_path.write_text(json.dumps(self.lock), encoding="utf-8")
        result = self.run_script()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mtime_ns) for root in roots for p in root.rglob("*") if p.is_file()})

    def test_check_refuses_cleanup_and_does_not_create_directories(self):
        self.assertEqual(self.run_script("-Check", "-CleanWork").returncode, 2)
        shutil.rmtree(self.assets / "third_party")
        result = self.run_script("-Check")
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertFalse((self.assets / "third_party").exists())


if __name__ == "__main__":
    unittest.main()
