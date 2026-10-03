#!/usr/bin/env python3
"""Strict I8 official resource validation; no network or model updates."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
sys.dont_write_bytecode = True
from convert_models import LOCK_PATH, PreparationError, verify
from publish_models import NOTICE_PATH
from stage_official_bundle import stage, validate


def reviewed(root: Path) -> dict:
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    manifest = validate(root, lock)
    # I6 records the local notice digest. I8 additionally binds that notice to
    # the reviewed source, rather than accepting a self-consistent replacement.
    name = "licenses/THIRD_PARTY_OCR_NOTICES.md"
    verify(root / name, verify(NOTICE_PATH, None, name), name)
    for name, record in manifest["files"].items():
        path = root / name
        if path.is_symlink() or path.stat().st_size != record["bytes"]:
            raise PreparationError("linked or incomplete resource: " + name)
        pinned = lock.get("attachments", {}).get(name)
        if pinned and path.stat().st_size != pinned["bytes"]:
            raise PreparationError("licence size differs: " + name)
    return manifest


def check_bundle(root: Path) -> dict:
    expected = reviewed(root)
    actual = json.loads((root / "bundle-manifest.json").read_text(encoding="utf-8"))
    if actual != expected:
        raise PreparationError("bundle manifest differs from reviewed resources")
    names = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if names != set(expected["files"]) | {"bundle-manifest.json"}:
        raise PreparationError("unexpected or missing bundle files")
    if any(p.is_symlink() for p in root.rglob("*")):
        raise PreparationError("linked resource directory")
    return expected


def stage_bundle(deploy: Path, out: Path) -> dict:
    reviewed(deploy)
    return stage(deploy, out, json.loads(LOCK_PATH.read_text(encoding="utf-8")))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--deploy", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.bundle and not (args.deploy or args.out):
        check_bundle(args.bundle.resolve())
    elif args.deploy and args.out and not args.bundle:
        stage_bundle(args.deploy.resolve(), args.out.resolve())
    else:
        parser.error("choose --bundle or --deploy with --out")
    print("reviewed official resources and complete notices verified")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PreparationError, OSError, ValueError, KeyError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(getattr(error, "exit_code", 3))
