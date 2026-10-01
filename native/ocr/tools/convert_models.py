#!/usr/bin/env python3
"""Convert the official PP-OCRv5 mobile inference models to the ncnn files the
WP17 OCR runtime loads.

Provenance chain this script records and enforces:

  PaddlePaddle/PP-OCRv5_mobile_{det,rec}  (Hugging Face, licence apache-2.0)
    -> Paddle inference model (inference.json + inference.pdiparams, SHA-256 pinned)
    -> ONNX (paddle2onnx, fixed paddlepaddle/paddle2onnx/pnnx versions)
    -> ncnn param + bin (pnnx, fixed input shapes and fp16 setting)

Every input file is verified against ``models.lock.json`` before conversion and
every output file is hashed into the same lock file. A mismatch is a hard
failure: the script never rewrites a pinned digest silently.

Usage:
    python convert_models.py --assets <assetsRoot> [--work <dir>] [--check]
    python convert_models.py --assets <assetsRoot> --offline

``--check`` only verifies hashes, ``--offline`` forbids downloads and requires
that every input blob is already present. The converted files are written to
``<assetsRoot>/ncnn-official/`` so they never overwrite the historical
nihui-derived blobs in ``<assetsRoot>/ncnn/``.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK_PATH = HERE / "models.lock.json"

# Attempted conversion toolchain; official PIR export has not succeeded yet.
# A working toolchain and its outputs must be recorded before release.
TOOLCHAIN = {
    "paddlepaddle": "3.0.0",
    "paddle2onnx": "1.3.1",
    "pnnx": "20260526",
}

# Hugging Face repositories with an explicit apache-2.0 model card. The
# nihui/ncnn-android-ppocrv5 converted blobs previously used by WP17-R2 have no
# declared licence for the weights, so they are not a conversion input.
MODELS = {
    "det": {
        "repo": "PaddlePaddle/PP-OCRv5_mobile_det",
        "files": ["inference.json", "inference.pdiparams", "inference.yml"],
        "onnx_shapes": ["inputshape=[1,3,320,320]", "inputshape2=[1,3,256,256]"],
        "onnx_name": "PP_OCRv5_mobile_det.onnx",
        "ncnn_prefix": "PP_OCRv5_mobile_det",
    },
    "rec": {
        "repo": "PaddlePaddle/PP-OCRv5_mobile_rec",
        "files": ["inference.json", "inference.pdiparams", "inference.yml"],
        "onnx_shapes": ["inputshape=[1,3,48,160]", "inputshape2=[1,3,48,256]"],
        "onnx_name": "PP_OCRv5_mobile_rec.onnx",
        "ncnn_prefix": "PP_OCRv5_mobile_rec",
    },
}

HF = "https://huggingface.co/{repo}/resolve/main/{name}"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_lock() -> dict:
    if LOCK_PATH.exists():
        return json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    return {"schema": 1, "toolchain": TOOLCHAIN, "files": {}}


def save_lock(lock: dict) -> None:
    lock["schema"] = 1
    lock["toolchain"] = TOOLCHAIN
    LOCK_PATH.write_text(
        json.dumps(lock, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "wp17i4-model-prep/1"})
    with urllib.request.urlopen(request, timeout=300) as response, tmp.open("wb") as out:
        shutil.copyfileobj(response, out)
    os.replace(tmp, dest)


def verify(path: Path, expected: str | None, label: str) -> str:
    digest = sha256(path)
    if expected is not None and digest != expected:
        raise SystemExit(
            f"checksum mismatch for {label}: expected {expected}, got {digest}"
        )
    return digest


def ensure_input(lock: dict, repo: str, name: str, dest: Path, offline: bool) -> str:
    key = f"{repo}/{name}"
    pinned = lock["files"].get(key, {}).get("sha256")
    if pinned is None:
        raise SystemExit(f"no pinned input hash for {key}")
    if not dest.exists():
        if offline:
            raise SystemExit(f"offline: missing pinned input {dest}")
        print(f"[fetch] {key}")
        download(HF.format(repo=repo, name=name), dest)
    digest = verify(dest, pinned, key)
    lock["files"][key] = {
        "kind": "paddle-inference-model",
        "source": HF.format(repo=repo, name=name),
        "licence": "apache-2.0",
        "bytes": dest.stat().st_size,
        "sha256": digest,
    }
    return digest


def run(cmd: list[str], cwd: Path | None = None) -> None:
    printable = " ".join(str(part) for part in cmd)
    print(f"[run] {printable}")
    result = subprocess.run(cmd, cwd=str(cwd) if cwd else None)
    if result.returncode != 0:
        raise SystemExit(f"command failed with exit code {result.returncode}: {printable}")


def _console_script(name: str, python: str) -> str:
    """Locate a console script installed next to [python], then on PATH.

    ``python -m paddle2onnx`` is not valid for 1.x: the package ships a console
    entry point only. pnnx is installed the same way.
    """
    suffix = ".exe" if os.name == "nt" else ""
    alongside = Path(python).resolve().parent / f"{name}{suffix}"
    if alongside.exists():
        return str(alongside)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(
        f"{name} was not found next to {python} or on PATH. Install "
        f"{name}=={TOOLCHAIN['pnnx']} into the conversion environment."
    )


def paddle2onnx_export(model_dir: Path, onnx_path: Path, python: str) -> None:
    """Export with paddle2onnx.

    The conversion interpreter is separate from the interpreter this script
    runs under: paddle2onnx and paddlepaddle pins do not exist for every Python
    version, so ``--python`` (or ``WP17_CONVERT_PYTHON``) names the environment
    that has them. The PaddleX CLI equivalent is
    ``paddlex --paddle2onnx --paddle_model_dir <dir> --onnx_model_dir <dir>``.
    """
    probe = subprocess.run(
        [python, "-c", "import paddle, paddle2onnx; print(paddle2onnx.__version__)"],
        capture_output=True,
        text=True,
    )
    if probe.returncode != 0:
        raise SystemExit(
            f"{python} cannot import paddle and paddle2onnx: {probe.stderr.strip()}\n"
            f"Install paddlepaddle=={TOOLCHAIN['paddlepaddle']} and "
            f"paddle2onnx=={TOOLCHAIN['paddle2onnx']} into that interpreter."
        )
    cli = _console_script("paddle2onnx", python)
    run(
        [
            cli,
            "--model_dir",
            str(model_dir),
            "--model_filename",
            "inference.json",
            "--params_filename",
            "inference.pdiparams",
            "--save_file",
            str(onnx_path),
            "--opset_version",
            "11",
            "--enable_onnx_checker",
            "False",
            "--enable_auto_update_opset",
            "True",
        ]
    )


def pnnx_convert(onnx_path: Path, shapes: list[str], work: Path, python: str) -> tuple[Path, Path]:
    exe = _console_script("pnnx", python)
    run([exe, str(onnx_path), *shapes, "fp16=1"], cwd=work)
    param = work / f"{onnx_path.stem}.ncnn.param"
    binary = work / f"{onnx_path.stem}.ncnn.bin"
    if not param.exists() or not binary.exists():
        raise SystemExit(f"pnnx did not produce {param.name} and {binary.name}")
    return param, binary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", required=True, help="asset root that receives ncnn-official/")
    parser.add_argument("--work", default=None, help="scratch directory (default: <assets>/convert-work)")
    parser.add_argument("--check", action="store_true", help="verify hashes only")
    parser.add_argument("--offline", action="store_true", help="never download")
    parser.add_argument(
        "--python",
        default=os.environ.get("WP17_CONVERT_PYTHON", sys.executable),
        help="interpreter holding the pinned paddlepaddle/paddle2onnx",
    )
    parser.add_argument("--only", choices=sorted(MODELS), action="append")
    args = parser.parse_args()

    assets = Path(args.assets).expanduser().resolve()
    work = Path(args.work).expanduser().resolve() if args.work else assets / "convert-work"
    model_root = work / "paddle"
    out_root = assets / "ncnn-official"
    lock = load_lock()

    print(f"host      : {platform.platform()}")
    print(f"python    : {platform.python_version()} ({sys.executable})")
    print(f"convert   : {args.python}")
    print(f"assets    : {assets}")
    print(f"work      : {work}")
    print(f"toolchain : {json.dumps(TOOLCHAIN, sort_keys=True)}")

    names = args.only or sorted(MODELS)
    produced: list[Path] = []
    for name in names:
        spec = MODELS[name]
        model_dir = model_root / spec["repo"].split("/")[-1]
        for file_name in spec["files"]:
            ensure_input(lock, spec["repo"], file_name, model_dir / file_name, args.offline or args.check)

    if args.check:
        print("inputs verified; --check does not run the conversion")
        return 0

    out_root.mkdir(parents=True, exist_ok=True)
    for name in names:
        spec = MODELS[name]
        model_dir = model_root / spec["repo"].split("/")[-1]
        model_work = work / name
        model_work.mkdir(parents=True, exist_ok=True)
        onnx_path = model_work / spec["onnx_name"]
        if not onnx_path.exists():
            paddle2onnx_export(model_dir, onnx_path, args.python)
        key = f"{spec['repo']}/{spec['onnx_name']}"
        pinned = lock["files"].get(key, {}).get("sha256")
        digest = verify(onnx_path, pinned, key)
        lock["files"][key] = {
            "kind": "onnx",
            "source": f"paddle2onnx {TOOLCHAIN['paddle2onnx']} from {spec['repo']}",
            "bytes": onnx_path.stat().st_size,
            "sha256": digest,
        }
        param, binary = pnnx_convert(onnx_path, spec["onnx_shapes"], model_work, args.python)
        for produced_path, suffix in ((param, "ncnn.param"), (binary, "ncnn.bin")):
            target = out_root / f"{spec['ncnn_prefix']}.{suffix}"
            target_key = f"ncnn-official/{target.name}"
            pinned_out = lock["files"].get(target_key, {}).get("sha256")
            out_digest = verify(produced_path, pinned_out, target_key)
            shutil.copyfile(produced_path, target)
            lock["files"][target_key] = {
                "kind": suffix,
                "source": f"pnnx {TOOLCHAIN['pnnx']} {' '.join(spec['onnx_shapes'])}",
                "bytes": target.stat().st_size,
                "sha256": out_digest,
            }
            produced.append(target)
            print(f"[out] {target}  {target.stat().st_size} bytes  {out_digest[:16]}")

    save_lock(lock)
    print(f"\nlock file: {LOCK_PATH}")
    print(f"converted: {out_root}")
    for path in produced:
        print(f"  {path.name}  {path.stat().st_size} bytes  {sha256(path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
