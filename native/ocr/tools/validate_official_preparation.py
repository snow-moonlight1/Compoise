#!/usr/bin/env python3
"""Real cached/offline/check/corruption/retry evidence in private asset roots.

Run only against an expendable, dedicated validation cache. Damaged test files
are restored in finally blocks; output/lock hashes are never recalibrated.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from convert_models import LOCK_PATH, sha256

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


def snapshot(*roots):
    files = {LOCK_PATH}
    for root in roots:
        if root.exists():
            files.update(path for path in root.rglob("*") if path.is_file())
    return {str(path): (sha256(path), path.stat().st_mtime_ns) for path in files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--deploy", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--powershell", action="store_true")
    args = parser.parse_args()
    results = {}
    def prepare(assets=args.assets, deploy=args.deploy, check=False):
        if args.powershell:
            return ["powershell.exe", "-NoProfile", "-File", str(REPO / "tool/prepare_ocr_assets.ps1"),
                "-AssetRoot", str(assets), "-DeployRoot", str(deploy), "-ModelSource", "official",
                "-SkipNcnnSource", "-Ncnn", "none", "-Offline", *(["-Check"] if check else [])]
        return [sys.executable, str(HERE / "prepare_ocr_assets.py"), "--assets", str(assets),
                "--deploy", str(deploy), "--offline", *(["--check"] if check else [])]
    def execute(name, command, expected):
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode == expected, (name, result.returncode, result.stdout, result.stderr)
        results[name] = {"exit": result.returncode, "expected": expected}
    execute("offline-cached", prepare(), 0)
    before = snapshot(args.assets, args.deploy)
    execute("check-read-only", prepare(check=True), 0)
    assert before == snapshot(args.assets, args.deploy), "prepare check mutated bytes/mtime"
    results["check-read-only"]["bytes_and_mtime_unchanged"] = True
    converter_check = [sys.executable, str(HERE / "convert_models.py"), "--assets", str(args.assets), "--check"]
    execute("converter-check-read-only", converter_check, 0)
    assert before == snapshot(args.assets, args.deploy), "converter check mutated bytes/mtime"
    results["converter-check-read-only"]["bytes_and_mtime_unchanged"] = True
    for label, path, command in (
        ("bad-input", args.assets / "convert-work/paddle/PP-OCRv5_mobile_det/inference.json", converter_check),
        ("bad-output", args.assets / "ncnn-official/PP_OCRv5_mobile_rec.ncnn.bin", prepare())):
        content, metadata = path.read_bytes(), path.stat()
        deployed_before = snapshot(args.deploy)
        try:
            damaged = bytearray(content); damaged[0] ^= 1
            path.write_bytes(damaged)
            execute(label, command, 3)
            assert deployed_before == snapshot(args.deploy), "failure changed deployment/lock"
            results[label]["deployment_and_lock_unchanged"] = True
        finally:
            path.write_bytes(content)
            os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
    execute("retry-restored-input-output", prepare(), 0)
    with tempfile.TemporaryDirectory(prefix="wp17i5-empty-", dir=args.assets.parent) as directory:
        empty = Path(directory) / "assets"
        deploy = Path(directory) / "deploy"
        execute("empty-offline", prepare(empty, deploy), 4)
        assert not deploy.exists()
        results["empty-offline"]["no_deployment"] = True
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
