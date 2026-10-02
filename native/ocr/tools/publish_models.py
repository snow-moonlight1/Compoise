#!/usr/bin/env python3
"""Validate a whole official model set and publish directories with rollback.

Each exposed ncnn directory contains either the previous five files or all five
verified new files. Copy failures occur before any destination is renamed;
rename failures roll back previous destinations. Stop OCR sessions while
replacing deployment directories (Windows may retain open handles).
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import sys
import tempfile
import uuid
from pathlib import Path
sys.dont_write_bytecode = True
from convert_models import LOCK_PATH, PreparationError, verify

MODEL_NAMES = [f"PP_OCRv5_mobile_{kind}.ncnn.{suffix}" for kind in ("det", "rec") for suffix in ("param", "bin")]
DICT_NAME = "ppocrv5_dict.txt"
DICT_SHA = "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b"
NOTICE_PATH = Path(__file__).resolve().parents[1] / "THIRD_PARTY_OCR_NOTICES.md"


def replace_directories(targets: dict[Path, Path]) -> None:
    """Stage on each destination filesystem, then rename with rollback."""
    staged, backups, installed = {}, {}, []
    try:
        for target, source in targets.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            stage = Path(tempfile.mkdtemp(prefix=f".{target.name}-stage-", dir=target.parent))
            staged[target] = stage
            shutil.copytree(source, stage, dirs_exist_ok=True)
        for target, stage in staged.items():
            if target.exists():
                backup = target.with_name(f".{target.name}-backup-{uuid.uuid4().hex}")
                os.replace(target, backup)
                backups[target] = backup
            os.replace(stage, target)
            installed.append(target)
    except BaseException:
        for target in reversed(list(staged)):
            if target in installed:
                shutil.rmtree(target)
            if target in backups:
                os.replace(backups.pop(target), target)
        raise
    finally:
        for stage in staged.values():
            if stage.exists():
                shutil.rmtree(stage)
    for backup in backups.values():
        shutil.rmtree(backup)


def publish(assets: Path, deploy: Path, lock: dict, check: bool = False) -> dict:
    if deploy == assets or deploy.is_relative_to(assets / "ncnn") or assets.is_relative_to(deploy):
        raise PreparationError("deployment must not overlap the asset root or ncnn cache", 2)
    sources = {}
    records = {}
    for name in MODEL_NAMES:
        entry = lock["files"].get(f"ncnn-official/{name}", {})
        if not entry.get("sha256"):
            raise PreparationError(f"no pinned official output {name}; complete and review the official conversion first")
        source = assets / "ncnn-official" / name
        verify(source, entry["sha256"], name)
        sources[name] = source
        records[name] = {"bytes": source.stat().st_size, "sha256": entry["sha256"]}
    source = assets / "ncnn" / DICT_NAME
    verify(source, DICT_SHA, DICT_NAME)
    sources[DICT_NAME] = source
    records[DICT_NAME] = {"bytes": source.stat().st_size, "sha256": DICT_SHA}
    # When the lock includes licence attachments, they are mandatory too.
    licence_sources = {}
    for name, entry in lock.get("attachments", {}).items():
        source = assets / name
        verify(source, entry["sha256"], name)
        licence_sources[name] = source
    notice_name = "licenses/THIRD_PARTY_OCR_NOTICES.md"
    notice_sha = verify(NOTICE_PATH, None, "project OCR third-party notice")
    licence_sources[notice_name] = NOTICE_PATH
    attachments = dict(lock.get("attachments", {}))
    attachments[notice_name] = {"source": "native/ocr/THIRD_PARTY_OCR_NOTICES.md",
                                "bytes": NOTICE_PATH.stat().st_size, "sha256": notice_sha}
    report = {"schema": 2, "generatedBy": "native/ocr/tools/publish_models.py",
              "modelSource": "official", "models": records, "conversion": lock.get("conversion"),
              "attachments": attachments,
              "inputs": {key: entry for key, entry in lock["files"].items() if entry.get("kind") == "paddle-inference-model"},
              "onnx": {key: entry for key, entry in lock["files"].items() if entry.get("kind") == "onnx"}}
    if check:
        for name, source in sources.items():
            for root in (assets, deploy):
                verify(root / "ncnn" / name, records[name]["sha256"], f"deployment {name}")
        for name in licence_sources:
            verify(deploy / name, attachments[name]["sha256"], name)
        return report
    with tempfile.TemporaryDirectory(prefix="wp17i5-publish-") as directory:
        root = Path(directory)
        models = root / "ncnn"
        models.mkdir()
        for name, source in sources.items():
            shutil.copyfile(source, models / name)
            verify(models / name, records[name]["sha256"], f"staged {name}")
        deployment = root / "deploy"
        if deploy.exists():
            shutil.copytree(deploy, deployment)
        else:
            deployment.mkdir()
        if (deployment / "ncnn").exists():
            shutil.rmtree(deployment / "ncnn")
        shutil.copytree(models, deployment / "ncnn")
        for name, source in licence_sources.items():
            destination = deployment / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        (deployment / "deployed.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        replace_directories({assets / "ncnn": models, deploy: deployment})
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--deploy", required=True, type=Path)
    parser.add_argument("--lock", default=LOCK_PATH, type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    publish(args.assets.resolve(), args.deploy.resolve(), lock, args.check)
    print("official five-file set and licence attachments verified" + (" (read-only)" if args.check else " and deployed"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error.message}", file=sys.stderr)
        raise SystemExit(error.exit_code)
    except OSError as error:
        print(f"ERROR: publication failed; previous directories restored: {error}", file=sys.stderr)
        raise SystemExit(3)
