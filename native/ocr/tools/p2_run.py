#!/usr/bin/env python3
"""Explicit P2 serial build/benchmark/regression driver with command/exit evidence.

Supply existing verified ncnn/stb/model roots. Nothing is fetched, no device or
GUI starts. Defaults stay unchanged; generated CMake targets exist only outside
the checkout. Do not run this alongside other builds/model measurements.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

from p2_benchmark import verify_assets
from q1_benchmark import REPO

STRATEGIES = ("q1", "rec-bounded", "all-bounded", "q1-pool")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--ncnn", type=Path, help="existing ncnn install root, required for build")
    parser.add_argument("--stb", type=Path, help="existing verified stb_image.h directory")
    parser.add_argument("--stage", choices=("build", "benchmark", "regression"), required=True)
    parser.add_argument("--label", default="final")
    parser.add_argument("--rounds", type=int, default=4)
    parser.add_argument("--modes", nargs="+", choices=("reuse", "recreate"), default=["reuse", "recreate"])
    args = parser.parse_args()
    root = args.root.resolve()
    if root == REPO or REPO in root.parents:
        parser.error("private external root required")
    if not args.label or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in args.label):
        parser.error("label must be lowercase letters/digits/hyphens/underscores")
    root.mkdir(parents=True, exist_ok=True)
    (root / "logs").mkdir(exist_ok=True)
    (root / "tmp").mkdir(exist_ok=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", TEMP=str(root / "tmp"),
               TMP=str(root / "tmp"), TMPDIR=str(root / "tmp"))

    def run(label, command):
        log = root / "logs" / (label + ".log")
        if log.exists():
            raise ValueError(f"evidence exists; use a new root/label: {log}")
        print(label, flush=True)
        started = time.time()
        with log.open("w", encoding="utf-8") as stream:
            process = subprocess.run([str(word) for word in command], cwd=REPO, env=env,
                                     stdout=stream, stderr=subprocess.STDOUT)
        (root / "logs" / (label + ".exit")).write_text(str(process.returncode) + "\n")
        with (root / "commands.jsonl").open("a", encoding="utf-8") as trace:
            trace.write(json.dumps({"label": label, "command": [str(word) for word in command],
                "cwd": str(REPO), "exit": process.returncode, "log": str(log),
                "started_unix": started, "seconds": time.time() - started}) + "\n")
        if process.returncode:
            raise RuntimeError(f"{label} exit {process.returncode}; {log}")

    tools = Path(__file__).parent
    windows = os.name == "nt"
    prefix = "win" if windows else "linux"

    def library(strategy):
        build = root / f"build-{prefix}-{strategy}"
        return build / "Release/matrixflow_ocr.dll" if windows else build / "libmatrixflow_ocr.so"

    verified = verify_assets(args.assets)
    if args.stage == "build":
        if not args.ncnn or not args.stb:
            parser.error("build requires --ncnn and --stb")
        sdk_lib = args.ncnn / "lib" / ("ncnn.lib" if windows else "libncnn.a")
        sdk_sha = hashlib.sha256(sdk_lib.read_bytes()).hexdigest()
        stb_sha = hashlib.sha256((args.stb / "stb_image.h").read_bytes()).hexdigest()
        if stb_sha != "594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3":
            raise ValueError("stb hash differs from reviewed Q1 SDK")
        expected_lib = ("7a3da36c6295ab64d1c40b1f4ad123daa72daf916d6612a129cc21f9e955312f" if windows
                        else "d6dea6d6eba1a50ab8774de131753c4d8ef7b18bd5bca8f058903461948b0c18")
        if sdk_sha != expected_lib:
            raise ValueError("ncnn library differs from reviewed Q1 SDK")
        (root / "sdk.json").write_text(json.dumps({"platform": platform.platform(),
            "ncnn": str(args.ncnn), "ncnn_sha256": sdk_sha, "stb_sha256": stb_sha,
            "assets_sha256": verified}, indent=2), encoding="utf-8")
        for strategy in STRATEGIES:
            source, build = root / ("src-" + strategy), root / f"build-{prefix}-{strategy}"
            run(f"generate-{strategy}", [sys.executable, tools / "p2_experiment.py", "--out", source,
                                       "--strategy", strategy])
            configure = ["cmake", "-S", source, "-B", build]
            configure += (["-G", "Visual Studio 17 2022", "-A", "x64"] if windows else
                          ["-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_CXX_COMPILER=clang++"])
            configure += [f"-Dncnn_DIR={args.ncnn / 'lib/cmake/ncnn'}", f"-DWP17_STB_DIR={args.stb}"]
            run(f"configure-{prefix}-{strategy}", configure)
            run(f"build-{prefix}-{strategy}", ["cmake", "--build", build, "--config", "Release", "--parallel", "2"])
            test = build / "Release/p2_allocator_test.exe" if windows else build / "p2_allocator_test"
            run(f"allocator-{prefix}-{strategy}", [test])
    elif args.stage == "benchmark":
        command = [sys.executable, tools / "p2_benchmark.py", "--assets", args.assets,
                   "--out", root / f"bench-{prefix}-{args.label}", "--rounds", str(args.rounds),
                   "--modes", *args.modes]
        for strategy in STRATEGIES:
            command += ["--candidate", f"{strategy}={library(strategy)}"]
        run(f"bench-{prefix}-{args.label}", command)
    else:
        for strategy in STRATEGIES:
            run(f"lifecycle-{prefix}-{strategy}-{args.label}", [sys.executable, tools / "p2_lifecycle.py",
                "--library", library(strategy), "--baseline-library", library("q1"), "--assets", args.assets,
                "--out", root / f"lifecycle-{prefix}-{strategy}-{args.label}"])
            run(f"limits-{prefix}-{strategy}-{args.label}", [sys.executable, tools / "q1_limits.py",
                "--library", library(strategy), "--assets", args.assets,
                "--out", root / f"limits-{prefix}-{strategy}-{args.label}"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
