#!/usr/bin/env python3
"""Explicit official model preparation. Offline by default; never updates pins."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-root", required=True, type=Path)
    parser.add_argument("--convert-python", type=Path)
    parser.add_argument("--download", action="store_true", help="allow fixed TLS/hash-checked inputs; no fallback")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.private_root.resolve()
    if root == REPO or root.is_relative_to(REPO) or REPO.is_relative_to(root):
        parser.error("private root must be outside and not contain the repository")
    if args.download and args.check:
        parser.error("--check is read-only and cannot download")
    if not args.check:
        (root / "tmp").mkdir(parents=True, exist_ok=True)
        (root / "logs").mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(root / "tmp"), TEMP=str(root / "tmp"), TMP=str(root / "tmp"), PYTHONDONTWRITEBYTECODE="1")
    command = [sys.executable, str(REPO / "native/ocr/tools/prepare_ocr_assets.py"),
               "--assets", str(root / "assets"), "--deploy", str(root / "deploy")]
    if args.convert_python:
        # Resolving a venv's python symlink selects the system interpreter and
        # loses the pinned environment. Preserve the executable path.
        command += ["--python", str(args.convert_python.expanduser().absolute())]
    if not args.download:
        command.append("--offline")
    if args.check:
        command.append("--check")
        return subprocess.run(command, env=env).returncode
    result = subprocess.run(command, env=env, capture_output=True)
    (root / "logs/model-preparation.log").write_bytes(result.stdout + result.stderr)
    (root / "logs/model-preparation.exit").write_text(str(result.returncode) + "\n")
    print(result.stdout.decode("utf-8", errors="replace"), end="")
    print(result.stderr.decode("utf-8", errors="replace"), end="", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
