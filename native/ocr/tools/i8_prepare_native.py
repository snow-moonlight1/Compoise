#!/usr/bin/env python3
"""Prepare a private pinned CPU ncnn SDK, offline by default."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
sys.dont_write_bytecode = True
from convert_models import LOCK_PATH, PreparationError, verify

REPO = Path(__file__).resolve().parents[3]
PIN = (REPO / "third_party/ncnn_pin.txt").read_text().strip()
# Reviewed SDKs from I5/I6/Q1. Imported binaries must match these; freshly
# compiled SDKs instead record the verified source and actual output inventory.
REUSE = {
    "windows": ("lib/ncnn.lib", "7a3da36c6295ab64d1c40b1f4ad123daa72daf916d6612a129cc21f9e955312f"),
    "linux": ("lib/libncnn.a", "d6dea6d6eba1a50ab8774de131753c4d8ef7b18bd5bca8f058903461948b0c18"),
    "x86_64": ("lib/libncnn.a", "8507abea0095f6c61c6efd912fb24369bb1651ab31a2d4dce432c86a2c71c11a"),
    "arm64-v8a": ("lib/libncnn.a", "ff736cecd9851452724f3cb1fc47c40d789f83a805ba5855cdcc91eb80c77870"),
}


def inventory(root: Path) -> dict:
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise PreparationError("SDK contains a link")
        if path.is_file():
            result[path.relative_to(root).as_posix()] = {
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
    return result


def check(root: Path, platform: str) -> dict:
    record = json.loads((root / "native-dependency.json").read_text())
    if record["platform"] != platform or record["ncnnCommit"] != PIN:
        raise PreparationError("wrong native dependency platform/source")
    if record["files"] != inventory(root / "install"):
        raise PreparationError("native SDK inventory changed")
    lock = json.loads(LOCK_PATH.read_text())
    verify(root / "third_party/stb_image.h", lock["dependencies"]["third_party/stb_image.h"]["sha256"], "stb header")
    for name in ("licenses/ncnn-BSD-3-Clause.txt", "licenses/stb-LICENSE.txt"):
        verify(root / name, lock["attachments"][name]["sha256"], name)
    if record["mode"] == "reviewed-sdk":
        rel, sha = REUSE[platform]
        verify(root / "install" / rel, sha, "reviewed native SDK")
    elif record["mode"] != "pinned-source" or record.get("sourceCommit") != PIN:
        raise PreparationError("unknown dependency preparation")
    if not (root / "install/lib/cmake/ncnn/ncnnConfig.cmake").is_file():
        raise PreparationError("incomplete ncnn SDK")
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--assets", required=True, type=Path, help="verified official preparation cache")
    parser.add_argument("--platform", required=True, choices=REUSE)
    parser.add_argument("--reuse-sdk", type=Path)
    parser.add_argument("--source", type=Path, help="clean pinned ncnn Git checkout")
    parser.add_argument("--download", action="store_true", help="explicit HTTPS fetch of the fixed commit")
    parser.add_argument("--ndk", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    out = args.out.resolve()
    if out == REPO or out.is_relative_to(REPO) or REPO.is_relative_to(out):
        parser.error("native preparation must be outside and not contain the repository")
    if args.check:
        check(out, args.platform)
        return 0
    if out.exists():
        parser.error("destination must be new; use --check to verify an existing SDK")
    if bool(args.reuse_sdk) + bool(args.source) + bool(args.download) != 1:
        parser.error("choose --reuse-sdk, --source, or explicit --download")
    lock = json.loads(LOCK_PATH.read_text())
    required = {"third_party/stb_image.h": lock["dependencies"]["third_party/stb_image.h"],
                **{k: lock["attachments"][k] for k in ("licenses/ncnn-BSD-3-Clause.txt", "licenses/stb-LICENSE.txt")}}
    for name, entry in required.items():
        verify(args.assets / name, entry["sha256"], name)
    if args.reuse_sdk:
        rel, sha = REUSE[args.platform]
        verify(args.reuse_sdk / rel, sha, "reviewed native SDK")
    out.mkdir(parents=True)
    logs = out / "logs"
    logs.mkdir()
    commands = []
    def run(command: list[str]) -> str:
        command = [str(p) for p in command]
        env = dict(os.environ, TMPDIR=str(out / "tmp"), TEMP=str(out / "tmp"), TMP=str(out / "tmp"))
        env.pop("GIT_DIR", None)
        env.pop("GIT_WORK_TREE", None)
        env.pop("GIT_SSL_NO_VERIFY", None)
        (out / "tmp").mkdir(exist_ok=True)
        completed = subprocess.run(command, capture_output=True, env=env)
        log = logs / f"{len(commands):02d}.log"
        log.write_bytes(completed.stdout + completed.stderr)
        commands.append({"argv": command, "exit": completed.returncode})
        (logs / "commands.json").write_text(json.dumps(commands, indent=2))
        if completed.returncode:
            raise PreparationError("native preparation failed; see " + str(log))
        return completed.stdout.decode("utf-8")
    if args.reuse_sdk:
        shutil.copytree(args.reuse_sdk, out / "install")
        mode = "reviewed-sdk"
    else:
        source = args.source.resolve() if args.source else out / "source"
        if args.download:
            run(["git", "init", source])
            run(["git", "-C", source, "-c", "http.sslVerify=true", "fetch", "--depth=1", "https://github.com/Tencent/ncnn.git", PIN])
            run(["git", "-C", source, "-c", "core.autocrlf=false", "checkout", "--detach", "FETCH_HEAD"])
        if run(["git", "-C", source, "rev-parse", "HEAD"]).strip() != PIN:
            raise PreparationError("ncnn source commit differs from reviewed pin")
        if run(["git", "-C", source, "status", "--porcelain", "--untracked-files=all"]).strip():
            raise PreparationError("ncnn source is dirty")
        verify(source / "LICENSE.txt", lock["attachments"]["licenses/ncnn-BSD-3-Clause.txt"]["sha256"], "ncnn licence")
        command = ["cmake", "-S", source, "-B", out / "build", "-DCMAKE_BUILD_TYPE=Release",
                   f"-DCMAKE_INSTALL_PREFIX={out / 'install'}", "-DNCNN_VULKAN=OFF", "-DNCNN_SHARED_LIB=OFF",
                   "-DNCNN_BUILD_TOOLS=OFF", "-DNCNN_BUILD_TESTS=OFF", "-DNCNN_BUILD_BENCHMARK=OFF",
                   "-DNCNN_BUILD_EXAMPLES=OFF", "-DNCNN_INSTALL_SDK=ON", "-DNCNN_PIXEL=ON"]
        if args.platform in ("x86_64", "arm64-v8a"):
            if not args.ndk:
                parser.error("Android preparation requires --ndk")
            command += [f"-DCMAKE_TOOLCHAIN_FILE={args.ndk / 'build/cmake/android.toolchain.cmake'}",
                        f"-DANDROID_ABI={args.platform}", "-DANDROID_PLATFORM=android-23", "-DANDROID_STL=c++_static", "-DNCNN_OPENMP=OFF"]
        elif args.platform == "linux":
            command += ["-G", "Ninja", "-DCMAKE_CXX_COMPILER=clang++", "-DNCNN_OPENMP=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
        else:
            command += ["-G", "Visual Studio 17 2022", "-A", "x64"]
        run(command)
        run(["cmake", "--build", out / "build", "--config", "Release", "--target", "install", "--parallel", "2"])
        mode = "pinned-source"
    for name in required:
        destination = out / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.assets / name, destination)
    record = {"schema": 1, "platform": args.platform, "ncnnCommit": PIN, "mode": mode,
              "runtimePrerequisites": ["MSVC x64 runtime including VCOMP140.DLL"] if args.platform == "windows" else [],
              "sourceCommit": PIN if mode == "pinned-source" else None, "files": inventory(out / "install")}
    (out / "native-dependency.json").write_text(json.dumps(record, indent=2) + "\n")
    check(out, args.platform)
    print("verified private native SDK: " + str(out))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PreparationError, OSError, ValueError, KeyError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(getattr(error, "exit_code", 3))
