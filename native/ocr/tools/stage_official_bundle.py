#!/usr/bin/env python3
"""Stage a verified I5 deployment as optional Android/Linux application assets."""
from __future__ import annotations
import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path
sys.dont_write_bytecode = True
from convert_models import LOCK_PATH, PreparationError, verify
from publish_models import DICT_NAME, DICT_SHA, MODEL_NAMES, replace_directories


def validate(root: Path, lock: dict) -> dict:
    report = json.loads((root / "deployed.json").read_text(encoding="utf-8"))
    expected_inputs = {k: v for k, v in lock["files"].items() if v.get("kind") == "paddle-inference-model"}
    expected_onnx = {k: v for k, v in lock["files"].items() if v.get("kind") == "onnx"}
    if (report.get("modelSource") != "official" or report.get("inputs") != expected_inputs
            or report.get("onnx") != expected_onnx or report.get("conversion") != lock.get("conversion")):
        raise PreparationError("deployment provenance differs from reviewed official lock")
    records = {}
    for name in MODEL_NAMES + [DICT_NAME]:
        sha = DICT_SHA if name == DICT_NAME else lock["files"]["ncnn-official/" + name]["sha256"]
        path = root / "ncnn" / name
        verify(path, sha, name)
        record = {"sha256": sha, "bytes": path.stat().st_size}
        if report.get("models", {}).get(name) != record:
            raise PreparationError("deployment model record differs from pinned output: " + name)
        records["ncnn/" + name] = record
    for name, expected in lock["attachments"].items():
        if report.get("attachments", {}).get(name) != expected:
            raise PreparationError("deployment licence provenance differs: " + name)
        verify(root / name, expected["sha256"], name)
        records[name] = {"sha256": expected["sha256"], "bytes": (root / name).stat().st_size}
    # The upstream attachments are pinned; this project's notice may gain newer
    # handoff text without changing the models. Preserve its recorded bytes.
    name = "licenses/THIRD_PARTY_OCR_NOTICES.md"
    expected = report["attachments"][name]
    verify(root / name, expected["sha256"], name)
    records[name] = {"sha256": expected["sha256"], "bytes": (root / name).stat().st_size}
    data = (root / "deployed.json").read_bytes()
    records["deployed.json"] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    return {"schema": 1, "modelSource": "official", "files": records}


def stage(root: Path, out: Path, lock: dict, check: bool = False) -> dict:
    if root == out or root.is_relative_to(out) or out.is_relative_to(root):
        raise PreparationError("source deployment and asset destination must not overlap", 2)
    manifest = validate(root, lock)
    target = out / "wp17-ocr"
    if check:
        for name, record in manifest["files"].items():
            verify(target / name, record["sha256"], name)
        if json.loads((target / "bundle-manifest.json").read_text()) != manifest:
            raise PreparationError("bundle manifest differs")
    else:
        with tempfile.TemporaryDirectory(prefix="wp17i6-stage-") as temporary:
            staged = Path(temporary)
            for name, record in manifest["files"].items():
                destination = staged / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / name, destination)
                verify(destination, record["sha256"], name)
            (staged / "bundle-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            replace_directories({target: staged})
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deploy", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stage(args.deploy.resolve(), args.out.resolve(), json.loads(LOCK_PATH.read_text()), args.check)
    print("official application assets and provenance verified")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PreparationError, OSError, ValueError, KeyError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(error.exit_code if isinstance(error, PreparationError) else 3)
