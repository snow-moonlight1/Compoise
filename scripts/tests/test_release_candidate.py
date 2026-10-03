"""Execute the shipping validator against synthetic candidates, never secrets/devices."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'release_candidate.py'
ROOT = SCRIPT.parents[1]
spec = importlib.util.spec_from_file_location('candidate', SCRIPT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
COMMIT = 'a' * 40
CERT = 'b' * 64


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wp28-r1-test-')
        self.base = Path(self.temp.name)
        self.directory = self.base / 'candidate'
        self.directory.mkdir()
        self.ctx = gate.context(ROOT, 'v1.0.0+1', COMMIT)
        self.bundle = self.base / 'bundle'
        for name in ('compoise.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'data/flutter_assets/assets/licenses/THIRD_PARTY_NOTICES.txt'):
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('synthetic:' + name).encode())
        self.make_platform('Windows')

    def tearDown(self):
        self.temp.cleanup()

    def cli(self, command, platform='Windows', directory=None, ok=True, extra=()):
        args = [sys.executable, str(SCRIPT), command, '--root', str(ROOT), '--directory', str(directory or self.directory), '--platform', platform, '--tag', self.ctx['tag'], '--commit', COMMIT, '--android-cert-sha256', CERT, *map(str, extra)]
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if ok else 1, result.stdout + result.stderr)
        self.assertEqual('PASS' in result.stdout, ok, result.stdout)
        return result

    def make_platform(self, platform):
        artifact = self.directory / gate.artifact_name(self.ctx, platform)
        if platform == 'Windows':
            with zipfile.ZipFile(artifact, 'w') as archive:
                for path in self.bundle.rglob('*'):
                    if path.is_file():
                        archive.write(path, path.relative_to(self.bundle).as_posix())
            evidence = {'productName': 'Compoise', 'companyName': 'Compoise', 'authenticode': 'NotSigned', 'fileVersionNumeric': '1.0.0.1', 'fileVersionString': '1.0.0+1', 'legalCopyright': 'Compoise contributors', 'appDataDir': r'%APPDATA%\Compoise\Compoise'}
        else:
            artifact.write_bytes(b'synthetic APK; not signed or installable')
            evidence = {'apkSignatureVerified': 'true', 'apkSignatureDN': 'CN=Synthetic test', 'apkSignatureCertSha256': CERT, 'apkPackage': 'com.matrixflow.app', 'apkVersionName': '1.0.0', 'apkVersionCode': '1'}
        facts = {**self.ctx, 'source': {'dirty': False, 'paths': [], 'diffSha256': gate.digest(b'')}, 'evidence': evidence}
        facts_path = self.base / (platform + '-facts.json')
        facts_path.write_text(json.dumps(facts))
        extra = ['--facts', facts_path]
        if platform == 'Windows':
            extra += ['--bundle', self.bundle]
        self.cli('proof', platform, extra=extra)

    def change_proof(self, mutate, platform='Windows'):
        path = self.directory / gate.proof_name(platform)
        proof = json.loads(path.read_text())
        mutate(proof)
        path.write_text(json.dumps(proof))

    def rejected_seal(self, platform='Windows', extra=()):
        self.cli('seal', platform, ok=False, extra=extra)
        for name in gate.RECORDS:
            self.assertFalse((self.directory / name).exists(), 'failure must not leave success records')

    def test_positive_windows_two_verifications_and_extraction(self):
        self.cli('seal')
        first = (self.directory / 'SHA256SUMS.txt').read_bytes()
        self.cli('verify')
        self.cli('verify')
        self.cli('extract', extra=['--output', self.base / 'extracted'])
        for path in self.bundle.rglob('*'):
            if path.is_file():
                self.assertEqual(path.read_bytes(), (self.base / 'extracted' / path.relative_to(self.bundle)).read_bytes())
        self.cli('seal')
        self.assertEqual(first, (self.directory / 'SHA256SUMS.txt').read_bytes())

    def test_positive_all_with_notes(self):
        self.make_platform('Android')
        (self.directory / 'RELEASE_NOTES.md').write_text('Synthetic v3/local state upgrade note')
        self.cli('seal', 'All')
        self.cli('verify', 'All')
        sums = (self.directory / 'SHA256SUMS.txt').read_text()
        self.assertIn('apkSignatureCertSha256=' + CERT, (self.directory / 'RELEASE_METADATA.txt').read_text())
        for name in ('WINDOWS_PROOF.json', 'ANDROID_PROOF.json', 'RELEASE_METADATA.txt', 'RELEASE_MANIFEST.txt', 'RELEASE_NOTES.md'):
            self.assertIn(name, sums)

    def test_wrong_tag_after_success_invalidates_old_records(self):
        self.cli('seal')
        self.rejected_seal(extra=['--tag', 'v9.0.0+1'])

    def test_failed_proof_does_not_leave_old_proof(self):
        (self.bundle / 'missing-from-zip.dll').write_bytes(b'extra build output')
        self.cli('proof', ok=False, extra=['--facts', self.base / 'Windows-facts.json', '--bundle', self.bundle])
        self.assertFalse((self.directory / 'WINDOWS_PROOF.json').exists())

    def test_wrong_tag(self):
        self.rejected_seal(extra=['--tag', 'v9.0.0+1'])

    def test_wrong_expected_commit(self):
        self.rejected_seal(extra=['--commit', 'c' * 40])

    def test_short_commit(self):
        self.rejected_seal(extra=['--commit', 'abc123'])

    def test_proof_wrong_version_commit_and_pin(self):
        for key, value in [('version', '9.0.0+1'), ('commit', 'c' * 40), ('tag', 'v1.0.0'), ('toolchain', {})]:
            with self.subTest(key=key):
                self.make_platform('Windows')
                self.change_proof(lambda p: p.update({key: value}))
                self.rejected_seal()

    def test_missing_artifact(self):
        (self.directory / gate.artifact_name(self.ctx, 'Windows')).unlink()
        self.rejected_seal()

    def test_wrong_filename_old_version(self):
        artifact = self.directory / gate.artifact_name(self.ctx, 'Windows')
        artifact.rename(self.directory / 'compoise-v0.9.0+1-windows-portable.zip')
        self.rejected_seal()

    def test_extra_files_and_nested_directory(self):
        for name in ('old.apk', 'old.txt', 'old-directory'):
            with self.subTest(name=name):
                path = self.directory / name
                path.mkdir() if name == 'old-directory' else path.write_text('stale')
                self.rejected_seal()
                path.rmdir() if path.is_dir() else path.unlink()

    def test_missing_proof(self):
        (self.directory / 'WINDOWS_PROOF.json').unlink()
        self.rejected_seal()

    def test_bad_windows_identity_or_signature(self):
        for key, value in [('productName', 'Old app'), ('companyName', 'Old app'), ('authenticode', 'Valid'), ('authenticode', 'HashMismatch'), ('fileVersionNumeric', '0.9.0.1')]:
            with self.subTest(key=key, value=value):
                self.make_platform('Windows')
                self.change_proof(lambda p: p['evidence'].update({key: value}))
                self.rejected_seal()

    def test_corrupt_artifact_and_stale_proof(self):
        self.cli('seal')
        (self.directory / gate.artifact_name(self.ctx, 'Windows')).write_bytes(b'changed')
        self.cli('verify', ok=False)
        self.rejected_seal()

    def test_changed_metadata_manifest_notes_and_proof(self):
        for name in ('RELEASE_METADATA.txt', 'RELEASE_MANIFEST.txt', 'WINDOWS_PROOF.json', 'RELEASE_NOTES.md'):
            with self.subTest(name=name):
                self.make_platform('Windows')
                (self.directory / 'RELEASE_NOTES.md').write_text('Synthetic')
                self.cli('seal')
                path = self.directory / name
                path.write_bytes(path.read_bytes() + b'changed')
                self.cli('verify', ok=False)

    def test_bad_checksum_missing_duplicate_extra(self):
        for change in (lambda s: '', lambda s: s + s.splitlines()[0] + '\n', lambda s: s + ('0' * 64) + '  old.zip\n'):
            with self.subTest(change=change):
                self.cli('seal')
                path = self.directory / 'SHA256SUMS.txt'
                path.write_text(change(path.read_text()))
                self.cli('verify', ok=False)

    def test_android_missing_bad_unverified_debug_cert(self):
        self.make_platform('Android')
        for mutate in (lambda p: p['evidence'].pop('apkSignatureDN'), lambda p: p['evidence'].update(apkSignatureDN='CN=Android Debug'), lambda p: p['evidence'].update(apkSignatureCertSha256='c' * 64), lambda p: p['evidence'].update(apkSignatureVerified='false'), lambda p: p['evidence'].update(apkVersionCode='2')):
            with self.subTest(mutate=mutate):
                self.make_platform('Android')
                self.change_proof(mutate, 'Android')
                self.rejected_seal('All')
        self.make_platform('Android')
        self.rejected_seal('All', extra=['--android-cert-sha256', ''])
        self.rejected_seal('All', extra=['--android-cert-sha256', '1234'])

    def test_all_missing_android_side(self):
        self.rejected_seal('All')

    def test_reseal_failure_removes_previous_success(self):
        self.cli('seal')
        (self.directory / 'stale.apk').write_bytes(b'stale')
        self.rejected_seal()

    def test_ocr_and_unsafe_zip_residue(self):
        for name in ('matrixflow_ocr.dll', 'ncnn/PP_OCRv5_mobile_det.ncnn.bin', 'licenses/PaddleOCR-LICENSE.txt', 'licenses/APACHE-2.0.txt', 'licenses/PP-OCRv5_mobile_rec.MODEL_CARD.md', '../escape.txt', '/escape.txt', 'C:/escape.txt', 'compoise.exe'):
            with self.subTest(name=name):
                self.make_platform('Windows')
                with zipfile.ZipFile(self.directory / gate.artifact_name(self.ctx, 'Windows'), 'a') as archive:
                    archive.writestr(name, b'injected')
                # Rebind the archive hash to show content rules cannot be bypassed.
                self.change_proof(lambda p: p.update(artifact=gate.snapshot(self.directory / gate.artifact_name(self.ctx, 'Windows'))))
                self.rejected_seal()

    def test_zip_missing_payload_even_with_rebound_hash(self):
        with zipfile.ZipFile(self.directory / gate.artifact_name(self.ctx, 'Windows'), 'w') as archive:
            archive.writestr('compoise.exe', b'fake')
        self.change_proof(lambda p: p.update(artifact=gate.snapshot(self.directory / gate.artifact_name(self.ctx, 'Windows'))))
        self.rejected_seal()

    def test_proof_generation_rejects_incomplete_archive(self):
        (self.bundle / 'missing-from-zip.dll').write_bytes(b'extra build output')
        self.cli('proof', ok=False, extra=['--facts', self.base / 'Windows-facts.json', '--bundle', self.bundle])

    def test_assembly_verifies_both_inputs_and_refuses_stale_output(self):
        self.cli('seal')
        inputs = self.base / 'inputs'
        inputs.mkdir()
        self.directory.rename(inputs / 'windows-portable-zip')
        self.directory.mkdir()
        self.make_platform('Android')
        self.cli('seal', 'Android')
        self.directory.rename(inputs / 'android-release-apk')
        self.cli('assemble', 'All', extra=['--inputs', inputs])
        self.cli('verify', 'All')
        self.cli('assemble', 'All', ok=False, extra=['--inputs', inputs])
        self.directory.rename(self.base / 'saved')
        (inputs / 'windows-portable-zip' / 'extra.txt').write_text('stale')
        self.cli('assemble', 'All', ok=False, extra=['--inputs', inputs])
        self.assertFalse(self.directory.exists())


if __name__ == '__main__':
    unittest.main()
