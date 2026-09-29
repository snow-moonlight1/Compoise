#!/usr/bin/env python3
"""WP17-R2 benchmark driver: produce raw engine output for one platform.

    python run_bench.py --platform win --cli <path/to/wp17r2_ocr[.exe]> \
                        --assets <asset root> [--only id1,id2] [--no-score]

This driver only *runs* the OCR binary and records what came back (including
timings and peak RSS).  All judging happens in score_raw.py so that the exact
same scoring code can be applied to the Windows, Linux and Android raw runs,
including on platforms where the Python helper stack is not installed.

Per configuration three process invocations are recorded:

    cold1.json    one image, fresh process  -> model load + first result
    batch10.json  the fixed 10-image batch  -> batch cost and peak memory
    all.json      every corpus image        -> the per-image material to score
"""
from __future__ import annotations

import argparse
import json
import os
import platform as pyplatform
import subprocess
import sys
import time

from wp17r2lib import RESULTS, load_labels

PLATFORM = None
CLI = None
ASSETS = None
TESSDATA = None

CONFIGS = [
    {
        "id": "ncnn-cpu-t4",
        "engine": "ncnn",
        "args": ["--threads", "4"],
        "cases": "all",
        "primary": True,
        "label": "ncnn + PP-OCRv5 mobile det/rec (CPU, 4 threads, Vulkan off)",
    },
    {
        "id": "tess-tri-psm3",
        "engine": "tesseract",
        "args": ["--tess-langs", "chi_sim+eng+jpn", "--tess-psm", "3"],
        "cases": "all",
        "primary": True,
        "label": "Tesseract 5 + tessdata_fast chi_sim+eng+jpn, PSM 3 (auto)",
    },
    {
        "id": "ncnn-cpu-t1",
        "engine": "ncnn",
        "args": ["--threads", "1"],
        "cases": "subset",
        "primary": False,
        "label": "ncnn 单线程（单核/低端设备下限）",
    },
    {
        "id": "ncnn-reccap320",
        "engine": "ncnn",
        "args": ["--threads", "4", "--rec-max-width", "320"],
        "cases": "subset",
        "primary": False,
        "label": "ncnn 识别宽度上限 320（PaddleOCR 默认真实识别器的裁切策略）",
    },
    {
        "id": "tess-tri-psm6",
        "engine": "tesseract",
        "args": ["--tess-langs", "chi_sim+eng+jpn", "--tess-psm", "6"],
        "cases": "subset",
        "primary": False,
        "label": "Tesseract 同上，PSM 6（单一文本块）",
    },
    {
        "id": "tess-oracle-lang",
        "engine": "tesseract",
        "args": ["--tess-psm", "3"],
        "cases": "all",
        "primary": False,
        "per_case_langs": {"zh": "chi_sim", "en": "eng", "ja": "jpn"},
        "label": "Tesseract 按标注语言单语言（oracle，真实应用没有这个信息）",
    },
]

SUBSET = [
    "zh_light_base",
    "en_light_base",
    "zh_small_text",
    "ja_dark_small_text",
    "zh_scale_150",
    "zh_long_scroll",
]


def run_cli(engine, args, out_path, images, langs=None):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    cmd = [CLI, "--engine", engine, "--assets", ASSETS, "--out", out_path, "--quiet"]
    cmd += args
    if engine == "tesseract":
        cmd += ["--tessdata", TESSDATA]
        if langs:
            cmd += ["--tess-langs", langs]
    cmd += images
    t0 = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    wall = time.time() - t0
    if proc.returncode != 0:
        return None, wall, (proc.stderr or "")[-4000:]
    try:
        with open(out_path, encoding="utf-8") as f:
            return json.load(f), wall, ""
    except Exception as e:  # noqa: BLE001
        return None, wall, f"cannot parse {out_path}: {e}"


def main() -> int:
    global PLATFORM, CLI, ASSETS, TESSDATA
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", required=True)
    ap.add_argument("--cli", required=True)
    ap.add_argument("--assets", required=True)
    ap.add_argument("--samples", default=None, help="override samples dir (non-ASCII/WSL paths)")
    ap.add_argument("--tessdata", default=None)
    ap.add_argument("--only", default=None, help="comma separated config ids")
    ap.add_argument("--configs", default=None, help="path to a json file overriding CONFIGS")
    ap.add_argument("--no-score", action="store_true")
    a = ap.parse_args()

    PLATFORM = a.platform
    CLI = a.cli
    ASSETS = a.assets
    TESSDATA = a.tessdata or os.path.join(ASSETS, "tessdata_fast")

    configs = CONFIGS
    if a.configs:
        with open(a.configs, encoding="utf-8") as f:
            configs = json.load(f)
    if a.only:
        want = set(a.only.split(","))
        configs = [c for c in configs if c["id"] in want]

    doc = load_labels()
    cases = doc["cases"]
    by_id = {c["id"]: c for c in cases}
    batch10 = doc["batch_of_10"]
    sample_dir = a.samples or os.path.join(os.path.dirname(RESULTS), "samples")

    def path_of(cid):
        return os.path.join(sample_dir, by_id[cid]["file"])

    out_dir = os.path.join(RESULTS, PLATFORM)
    raw_dir = os.path.join(out_dir, "raw")
    os.makedirs(raw_dir, exist_ok=True)

    summary = {
        "platform": PLATFORM,
        "host": pyplatform.platform(),
        "host_node": pyplatform.node(),
        "host_cpu": pyplatform.processor(),
        "cli": CLI,
        "assets": ASSETS,
        "samples": sample_dir,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "runs": {},
    }

    for cfg in configs:
        cid = cfg["id"]
        case_ids = [c["id"] for c in cases] if cfg["cases"] == "all" else SUBSET
        images = [path_of(i) for i in case_ids]
        rdir = os.path.join(raw_dir, cid)
        entry = {"config": cfg, "cases": case_ids, "errors": []}

        cold, wall, err = run_cli(
            cfg["engine"], cfg["args"], os.path.join(rdir, "cold1.json"), [images[0]],
            cfg.get("per_case_langs", {}).get(by_id[case_ids[0]]["locale"][0]),
        )
        if cold is None:
            entry["errors"].append({"stage": "cold1", "error": err})
            entry["cold_start"] = None
            print(f"[{PLATFORM}/{cid}] cold1 FAILED: {err[:300]}")
        else:
            ci = cold["images"][0]
            entry["cold_start"] = {
                "image": case_ids[0],
                "model_load_ms": cold["model_load_ms"],
                "first_image_ms": ci["total_ms"],
                "cold_to_first_result_ms": cold["model_load_ms"] + ci["total_ms"],
                "process_wall_ms": wall * 1000.0,
                "peak_rss_kb": cold["peak_rss_kb"],
                "engine": cold["engine"],
                "engine_version": cold["engine_version"],
                "cli_config": cold["config"],
            }
            print(f"[{PLATFORM}/{cid}] cold1 load={cold['model_load_ms']:.0f}ms "
                  f"first={ci['total_ms']:.0f}ms rss={cold['peak_rss_kb'] / 1024:.0f}MiB")

        bres, wall, err = run_cli(cfg["engine"], cfg["args"], os.path.join(rdir, "batch10.json"),
                                  [path_of(i) for i in batch10])
        if bres is None:
            entry["errors"].append({"stage": "batch10", "error": err})
            entry["batch10"] = None
            print(f"[{PLATFORM}/{cid}] batch10 FAILED: {err[:300]}")
        else:
            per = [im["total_ms"] for im in bres["images"]]
            entry["batch10"] = {
                "images": batch10,
                "batch_total_ms": bres["batch_total_ms"],
                "per_image_ms": per,
                "median_per_image_ms": sorted(per)[len(per) // 2],
                "mean_per_image_ms": sum(per) / len(per),
                "peak_rss_kb": bres["peak_rss_kb"],
                "process_wall_ms": wall * 1000.0,
            }
            print(f"[{PLATFORM}/{cid}] batch10 total={bres['batch_total_ms']:.0f}ms "
                  f"median={entry['batch10']['median_per_image_ms']:.0f}ms "
                  f"rss={bres['peak_rss_kb'] / 1024:.0f}MiB")

        allres, wall, err = run_cli(cfg["engine"], cfg["args"], os.path.join(rdir, "all.json"), images)
        if allres is None:
            entry["errors"].append({"stage": "all", "error": err})
            print(f"[{PLATFORM}/{cid}] all FAILED: {err[:300]}")
        elif cfg.get("per_case_langs"):
            merged = {
                "engine": allres["engine"], "engine_version": allres["engine_version"],
                "model_load_ms": allres["model_load_ms"], "batch_total_ms": allres["batch_total_ms"],
                "peak_rss_kb": allres["peak_rss_kb"], "config": allres["config"], "images": [],
            }
            for c in cases:
                langs = cfg["per_case_langs"][c["locale"][0]]
                r, _, e = run_cli(cfg["engine"], cfg["args"],
                                  os.path.join(rdir, "all-%s.json" % c["id"]), [path_of(c["id"])], langs)
                if r is None:
                    entry["errors"].append({"stage": "all:" + c["id"], "error": e})
                    continue
                merged["images"].append(r["images"][0])
            allres = merged
            with open(os.path.join(rdir, "all.json"), "w", encoding="utf-8") as f:
                json.dump(allres, f, ensure_ascii=False, indent=1)
        if allres is not None:
            entry["per_image_ms"] = {os.path.splitext(os.path.basename(i["path"]))[0]: i["total_ms"]
                                     for i in allres["images"]}
            entry["all_peak_rss_kb"] = allres.get("peak_rss_kb")
            entry["engine"] = allres.get("engine")
            entry["engine_version"] = allres.get("engine_version")
            entry["cli_config"] = allres.get("config", {})

        summary["runs"][cid] = entry

    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    print(f"wrote {os.path.join(out_dir, 'summary.json')}")

    if not a.no_score:
        import score_raw

        score_raw.score_platform(PLATFORM, overlays=True)
        print("scored")
    return 0


if __name__ == "__main__":
    sys.exit(main())
