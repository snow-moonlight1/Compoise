#!/usr/bin/env python3
"""Run the shared ncnn CLI on an already-booted API 23 x86_64 emulator.

Records the same cold1/batch10/all files and summary schema as run_bench.py.
The timings are emulator diagnostics, not phone performance measurements.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import subprocess
import time

from wp17r2lib import LABELS, RESULTS, load_labels

REMOTE = "/data/local/tmp/wp17r2"
MODELS = (
    "PP_OCRv5_mobile_det.ncnn.param",
    "PP_OCRv5_mobile_det.ncnn.bin",
    "PP_OCRv5_mobile_rec.ncnn.param",
    "PP_OCRv5_mobile_rec.ncnn.bin",
    "ppocrv5_dict.txt",
)


def checked(*args: str) -> subprocess.CompletedProcess:
    p = subprocess.run(args, capture_output=True, text=True, errors="replace")
    if p.returncode:
        raise RuntimeError(f"{' '.join(args[:3])}: {p.stderr[-1200:]}")
    return p


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", required=True, help="stripped x86_64 android-23 wp17r2_ocr")
    ap.add_argument("--assets", required=True)
    ap.add_argument("--adb", default="adb")
    a = ap.parse_args()

    sdk = checked(a.adb, "shell", "getprop ro.build.version.sdk").stdout.strip()
    abi = checked(a.adb, "shell", "getprop ro.product.cpu.abi").stdout.strip()
    if (sdk, abi) != ("23", "x86_64"):
        raise RuntimeError(f"expected API 23 x86_64 device, got API {sdk} {abi}")

    doc = load_labels()
    ids = [c["id"] for c in doc["cases"]]
    files = {c["id"]: c["file"] for c in doc["cases"]}
    samples = os.path.dirname(LABELS)
    out_dir = os.path.join(RESULTS, "android")
    raw_dir = os.path.join(out_dir, "raw", "ncnn-cpu-t4")
    os.makedirs(raw_dir, exist_ok=True)

    checked(a.adb, "shell", f"mkdir -p {REMOTE}/assets/ncnn {REMOTE}/images")
    checked(a.adb, "push", a.cli, f"{REMOTE}/wp17r2_ocr")
    checked(a.adb, "shell", f"chmod 755 {REMOTE}/wp17r2_ocr")
    for name in MODELS:
        checked(a.adb, "push", os.path.join(a.assets, "ncnn", name), f"{REMOTE}/assets/ncnn/{name}")
    for cid in ids:
        checked(a.adb, "push", os.path.join(samples, files[cid]), f"{REMOTE}/images/{cid}.png")

    def run(stage: str, case_ids: list[str]) -> tuple[dict, float]:
        paths = " ".join(f"./images/{cid}.png" for cid in case_ids)
        command = (
            f"cd {REMOTE} && ./wp17r2_ocr --engine ncnn --assets ./assets "
            f"--out {stage}.json --threads 4 --quiet {paths} 2>/dev/null"
        )
        started = time.monotonic()
        checked(a.adb, "shell", command)
        wall_ms = (time.monotonic() - started) * 1000
        local = os.path.join(raw_dir, stage + ".json")
        checked(a.adb, "pull", f"{REMOTE}/{stage}.json", local)
        with open(local, encoding="utf-8") as f:
            result = json.load(f)
        if len(result["images"]) != len(case_ids) or any(i["error"] for i in result["images"]):
            raise RuntimeError(f"{stage}: incomplete OCR result")
        print(f"{stage}: {len(result['images'])} images, {result['batch_total_ms']:.0f} ms")
        return result, wall_ms

    cold, cold_wall = run("cold1", ids[:1])
    batch, batch_wall = run("batch10", doc["batch_of_10"])
    all_res, _ = run("all", ids)
    first = cold["images"][0]
    per = [i["total_ms"] for i in batch["images"]]
    config = {
        "id": "ncnn-cpu-t4", "engine": "ncnn", "args": ["--threads", "4"],
        "cases": "all", "primary": True,
        "label": "ncnn PP-OCRv5 mobile CPU; API 23 x86_64 emulator; x86 SIMD disabled",
    }
    entry = {
        "config": config, "cases": ids, "errors": [],
        "cold_start": {
            "image": ids[0], "model_load_ms": cold["model_load_ms"],
            "first_image_ms": first["total_ms"],
            "cold_to_first_result_ms": cold["model_load_ms"] + first["total_ms"],
            "process_wall_ms": cold_wall, "peak_rss_kb": cold["peak_rss_kb"],
            "engine": cold["engine"], "engine_version": cold["engine_version"],
            "cli_config": cold["config"],
        },
        "batch10": {
            "images": doc["batch_of_10"], "batch_total_ms": batch["batch_total_ms"],
            "per_image_ms": per, "median_per_image_ms": sorted(per)[len(per) // 2],
            "mean_per_image_ms": statistics.mean(per),
            "peak_rss_kb": batch["peak_rss_kb"], "process_wall_ms": batch_wall,
        },
        "per_image_ms": {
            os.path.splitext(os.path.basename(i["path"]))[0]: i["total_ms"]
            for i in all_res["images"]
        },
        "all_peak_rss_kb": all_res["peak_rss_kb"],
        "engine": all_res["engine"], "engine_version": all_res["engine_version"],
        "cli_config": all_res["config"],
    }
    summary = {
        "platform": "android", "host": platform.platform(),
        "device": "Android API 23 x86_64 emulator (SSE4.2, no AVX)",
        "cli": a.cli, "assets": a.assets, "samples": samples,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "runs": {"ncnn-cpu-t4": entry},
    }
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
