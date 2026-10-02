#!/usr/bin/env python3
"""Pinned official PIR -> ONNX -> ncnn conversion with independent replay.

Normal runs require reviewed output pins. --record-outputs bootstraps pins only
after two byte-identical conversions in fresh directories. Existing pins are
never replaced. --check reads inputs and pinned outputs without importing tools;
--offline prohibits downloads. Models/scratch data must stay outside Git.
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
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK_PATH = HERE / "models.lock.json"
TOOLCHAIN = {"paddlepaddle": "3.0.0", "paddle2onnx": "2.1.0",
             "onnx": "1.17.0", "onnxoptimizer": "0.4.2", "pnnx": "20260526",
             "numpy": "1.26.4", "protobuf": "3.20.2", "setuptools": "75.8.0",
             "packaging": "24.2"}
MODELS = {
    "det": {"repo": "PaddlePaddle/PP-OCRv5_mobile_det",
            "files": ["inference.json", "inference.pdiparams", "inference.yml"],
            "onnx_shapes": ["inputshape=[1,3,320,320]", "inputshape2=[1,3,256,256]"],
            "onnx_name": "PP_OCRv5_mobile_det.onnx", "ncnn_prefix": "PP_OCRv5_mobile_det"},
    "rec": {"repo": "PaddlePaddle/PP-OCRv5_mobile_rec",
            "files": ["inference.json", "inference.pdiparams", "inference.yml"],
            "onnx_shapes": ["inputshape=[1,3,48,160]", "inputshape2=[1,3,48,256]"],
            "onnx_name": "PP_OCRv5_mobile_rec.onnx", "ncnn_prefix": "PP_OCRv5_mobile_rec"},
}
EXPORT_FLAGS = ["--opset_version", "11", "--enable_onnx_checker", "True",
                "--enable_auto_update_opset", "False", "--optimize_tool", "onnxoptimizer"]
PNNX_FLAGS = ["fp16=1", "optlevel=2"]
HF = "https://huggingface.co/{repo}/resolve/main/{name}"


class PreparationError(SystemExit):
    def __init__(self, message: str, code: int = 3):
        self.message, self.exit_code = message, code
        super().__init__(message)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_lock() -> dict:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def save_lock(lock: dict) -> None:
    lock.update(schema=1, toolchain=TOOLCHAIN)
    tmp = LOCK_PATH.with_suffix(".json.part")
    tmp.write_text(json.dumps(lock, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, LOCK_PATH)


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "wp17i5-model-prep/1"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response, dest.open("wb") as out:
            shutil.copyfileobj(response, out)
    except (OSError, urllib.error.URLError) as error:
        raise PreparationError(f"download failed for {url}: {error}", 4) from error


def verify(path: Path, expected: str | None, label: str) -> str:
    if not path.is_file():
        raise PreparationError(f"missing {label}: {path}")
    digest = sha256(path)
    if expected is not None and digest != expected:
        raise PreparationError(f"checksum mismatch for {label}: expected {expected}, got {digest}")
    return digest


def ensure_input(lock: dict, repo: str, name: str, dest: Path, offline: bool) -> str:
    key = f"{repo}/{name}"
    entry = lock["files"].get(key, {})
    pinned = entry.get("sha256")
    if pinned is None:
        raise PreparationError(f"no pinned input hash for {key}")
    if not dest.exists():
        if offline:
            raise PreparationError(f"offline: missing pinned input {dest}", 4)
        print(f"[fetch] {key}", flush=True)
        tmp = dest.with_suffix(dest.suffix + ".part")
        try:
            download(entry.get("source", HF.format(repo=repo, name=name)), tmp)
            verify(tmp, pinned, key)
            os.replace(tmp, dest)
        finally:
            tmp.unlink(missing_ok=True)
    return verify(dest, pinned, key)


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print(f"[run] {json.dumps(cmd)}", flush=True)
    try:
        result = subprocess.run(cmd, cwd=cwd)
    except OSError as error:
        raise PreparationError(f"cannot execute conversion tool {cmd[0]}: {error}", 5) from error
    if result.returncode:
        code = result.returncode if result.returncode in (2, 3, 4, 5) else 3
        raise PreparationError(f"command failed with exit code {result.returncode}: {cmd}", code)


def check_toolchain(python: str) -> dict:
    manifest = json.loads((HERE / "conversion_toolchain.lock.json").read_text(encoding="utf-8"))
    expected = {name: entry["version"] for name, entry in manifest["packages"].items()}
    if any(expected.get(name) != version for name, version in TOOLCHAIN.items()):
        raise PreparationError("conversion package manifest disagrees with script pins", 5)
    script = ("import json,sys,platform,importlib.metadata as m; "
              "import paddle,paddle2onnx,onnx,onnxoptimizer; "
              "print(json.dumps({'versions':{n:m.version(n) for n in " + repr(list(expected)) + "},"
              "'python':sys.version,'platform':platform.platform(),"
              "'pnnx_dir':str(m.distribution('pnnx').locate_file('pnnx'))}))")
    try:
        probe = subprocess.run([python, "-c", script], capture_output=True, text=True)
    except OSError as error:
        raise PreparationError(f"cannot execute conversion interpreter {python}: {error}", 5) from error
    if probe.returncode:
        raise PreparationError(f"{python} cannot load the conversion tools: {probe.stderr.strip()}", 5)
    actual = json.loads(probe.stdout.strip().splitlines()[-1])
    if actual["versions"] != expected:
        raise PreparationError(f"toolchain mismatch: expected {expected}, got {actual['versions']}", 5)
    binary = Path(actual["pnnx_dir"]) / ("pnnx.exe" if os.name == "nt" else "pnnx")
    if not binary.is_file():
        raise PreparationError(f"missing native pnnx executable: {binary}", 5)
    actual.update(pnnx_binary=str(binary), pnnx_sha256=sha256(binary))
    print(f"[toolchain] {json.dumps(actual, sort_keys=True)}", flush=True)
    return actual


def paddle2onnx_export(model_dir: Path, onnx_path: Path, python: str) -> None:
    graph = json.loads((model_dir / "inference.json").read_text(encoding="utf-8"))
    if graph.get("base_code", {}).get("magic") != "pir":
        raise PreparationError(f"expected official PIR inference.json in {model_dir}")
    # Using the selected interpreter prevents accidentally running another
    # environment's PATH entry point. Paddle2ONNX has no package __main__.
    run([python, "-c", "from paddle2onnx.command import main; main()",
         "--model_dir", str(model_dir), "--model_filename", "inference.json",
         "--params_filename", "inference.pdiparams", "--save_file", str(onnx_path), *EXPORT_FLAGS])
    run([python, "-c", "import onnx,sys; m=onnx.load(sys.argv[1]); onnx.checker.check_model(m); "
         "assert len(m.graph.input)==1 and len(m.graph.output)==1; "
         "print('ONNX opsets:',[(o.domain,o.version) for o in m.opset_import])", str(onnx_path)])


def convert_once(names: list[str], model_root: Path, destination: Path, python: str, actual: dict) -> dict[str, Path]:
    outputs = {}
    for name in names:
        spec = MODELS[name]
        model_work = destination / name
        model_work.mkdir(parents=True)
        onnx_path = model_work / spec["onnx_name"]
        paddle2onnx_export(model_root / spec["repo"].split("/")[-1], onnx_path, python)
        outputs[f"{spec['repo']}/{spec['onnx_name']}"] = onnx_path
        run([actual["pnnx_binary"], str(onnx_path), *spec["onnx_shapes"], *PNNX_FLAGS], cwd=model_work)
        for suffix in ("ncnn.param", "ncnn.bin"):
            path = model_work / f"{spec['ncnn_prefix']}.{suffix}"
            verify(path, None, path.name)
            outputs[f"ncnn-official/{path.name}"] = path
        param = outputs[f"ncnn-official/{spec['ncnn_prefix']}.ncnn.param"].read_text()
        if "pnnx." in param or " in0" not in param or " out0" not in param:
            raise PreparationError(f"unsupported ncnn graph or missing runtime in0/out0 in {name}")
    return outputs


def output_paths(names: list[str], work: Path, assets: Path) -> dict[str, Path]:
    result = {}
    for name in names:
        spec = MODELS[name]
        result[f"{spec['repo']}/{spec['onnx_name']}"] = work / name / spec["onnx_name"]
        for suffix in ("ncnn.param", "ncnn.bin"):
            file_name = f"{spec['ncnn_prefix']}.{suffix}"
            result[f"ncnn-official/{file_name}"] = assets / "ncnn-official" / file_name
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True)
    parser.add_argument("--work")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--record-outputs", action="store_true")
    parser.add_argument("--python", default=os.environ.get("WP17_CONVERT_PYTHON", sys.executable))
    parser.add_argument("--only", choices=sorted(MODELS), action="append")
    args = parser.parse_args()
    if args.check and args.record_outputs:
        parser.error("--check cannot record output hashes")
    assets = Path(args.assets).expanduser().resolve()
    work = Path(args.work).expanduser().resolve() if args.work else assets / "convert-work"
    checkout = HERE.parents[2]
    if assets.is_relative_to(checkout) or work.is_relative_to(checkout):
        parser.error("assets and work must be outside the repository")
    lock = load_lock()
    names = sorted(set(args.only or MODELS))
    model_root = work / "paddle"
    expected_paths = output_paths(names, work, assets)
    print(f"host: {platform.platform()}\nconvert: {args.python}\nassets: {assets}\nwork: {work}", flush=True)
    for name in names:
        spec = MODELS[name]
        for file_name in spec["files"]:
            ensure_input(lock, spec["repo"], file_name, model_root / spec["repo"].split("/")[-1] / file_name,
                         args.offline or args.check)
    if args.check:
        count = 0
        for key, path in expected_paths.items():
            pinned = lock["files"].get(key, {}).get("sha256")
            if pinned:
                verify(path, pinned, key)
                count += 1
        print(f"inputs verified; {count} pinned outputs verified; --check wrote nothing")
        return 0
    if not args.record_outputs:
        for key in expected_paths:
            if not lock["files"].get(key, {}).get("sha256"):
                raise PreparationError(f"no pinned output hash for {key}; bootstrap with --record-outputs after review")
    for key, path in expected_paths.items():
        pinned = lock["files"].get(key, {}).get("sha256")
        if path.exists() and pinned:
            verify(path, pinned, key)
    actual = check_toolchain(args.python)
    pinned_native = lock.get("conversion", {}).get("environment", {}).get("pnnx_sha256")
    if pinned_native and actual.get("pnnx_sha256") != pinned_native:
        raise PreparationError(f"native pnnx hash mismatch: expected {pinned_native}, got {actual.get('pnnx_sha256')}", 5)
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="replay-", dir=work) as scratch:
        first = convert_once(names, model_root, Path(scratch) / "a", args.python, actual)
        second = convert_once(names, model_root, Path(scratch) / "b", args.python, actual)
        for key, path in first.items():
            digest = verify(path, lock["files"].get(key, {}).get("sha256"), key)
            verify(second[key], digest, f"independent replay {key}")
            lock["files"][key] = {"kind": "onnx" if key.endswith(".onnx") else "ncnn." + key.rsplit(".", 1)[-1],
                "source": "official pinned PIR inputs -> paddle2onnx -> pnnx",
                "licence": "apache-2.0", "bytes": path.stat().st_size, "sha256": digest}
            print(f"[reproduced] {key} {path.stat().st_size} {digest}", flush=True)
        from publish_models import replace_directories
        targets = {}
        official_stage = Path(scratch) / "ncnn-official"
        official_stage.mkdir()
        if (assets / "ncnn-official").exists():
            shutil.copytree(assets / "ncnn-official", official_stage, dirs_exist_ok=True)
        for key, path in first.items():
            if key.startswith("ncnn-official/"):
                shutil.copyfile(path, official_stage / path.name)
            else:
                stage = Path(scratch) / ("publish-" + path.parent.name)
                stage.mkdir(exist_ok=True)
                shutil.copyfile(path, stage / path.name)
                targets[work / path.parent.name] = stage
        targets[assets / "ncnn-official"] = official_stage
        replace_directories(targets)
    if args.record_outputs:
        lock["conversion"] = {"export_flags": EXPORT_FLAGS, "pnnx_flags": PNNX_FLAGS,
                              "replays": 2, "byte_identical": True, "environment": actual}
        save_lock(lock)
    print(f"verified conversion published: {assets / 'ncnn-official'}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error.message}", file=sys.stderr)
        raise SystemExit(error.exit_code)
