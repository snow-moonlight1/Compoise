#!/usr/bin/env python3
"""Prepare/deploy the official model set on Linux or Windows.

Only the Python standard library is needed to reuse a verified converted cache.
When outputs are missing, --python selects the isolated conversion interpreter.
This never bootstraps output pins: reviewed complete pins remain a prerequisite.
ncnn compilation is separate (build_ncnn_linux.sh / prepare_ocr_assets.ps1).
"""
from __future__ import annotations
import argparse
import json
import os
import sys
from pathlib import Path
sys.dont_write_bytecode = True
from convert_models import LOCK_PATH, PreparationError, download, run, verify
from publish_models import MODEL_NAMES, publish


def ensure_blob(path: Path, entry: dict, offline: bool, check: bool) -> None:
    if path.exists():
        verify(path, entry["sha256"], str(path))
        return
    if check:
        raise PreparationError(f"missing cached file: {path}")
    if offline:
        raise PreparationError(f"offline: missing cached file: {path}", 4)
    tmp = path.with_suffix(path.suffix + ".part")
    try:
        download(entry["source"], tmp)
        verify(tmp, entry["sha256"], str(path))
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--deploy", type=Path)
    parser.add_argument("--python", default=os.environ.get("WP17_CONVERT_PYTHON", sys.executable))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    assets = args.assets.expanduser().resolve()
    deploy = args.deploy.expanduser().resolve() if args.deploy else assets / "deploy"
    repo = Path(__file__).resolve().parents[3]
    if assets.is_relative_to(repo) or deploy.is_relative_to(repo):
        parser.error("model/deployment directories must be outside the repository")
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    for name in MODEL_NAMES:
        if not lock["files"].get(f"ncnn-official/{name}", {}).get("sha256"):
            raise PreparationError(f"no pinned official output {name}; complete and review the official conversion first")
    for name, entry in {**lock.get("dependencies", {}), **lock.get("attachments", {})}.items():
        ensure_blob(assets / name, entry, args.offline, args.check)
    # Fail on corrupt cached outputs before attempting any conversion or publish.
    for name in MODEL_NAMES:
        path = assets / "ncnn-official" / name
        if path.exists():
            verify(path, lock["files"][f"ncnn-official/{name}"]["sha256"], name)
    if any(not (assets / "ncnn-official" / name).exists() for name in MODEL_NAMES) and not args.check:
        command = [args.python, str(Path(__file__).with_name("convert_models.py")),
                   "--assets", str(assets), "--python", args.python]
        if args.offline:
            command.append("--offline")
        run(command)
    publish(assets, deploy, lock, args.check)
    print(f"official models and notices {'checked read-only' if args.check else 'deployed'}: {deploy}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error.message}", file=sys.stderr)
        raise SystemExit(error.exit_code)
    except OSError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(3)
