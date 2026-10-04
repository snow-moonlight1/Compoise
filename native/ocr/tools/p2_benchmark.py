#!/usr/bin/env python3
"""Opt-in serial Release comparison, rotated order, fresh process per trial.

No downloads/devices. Run with a quiet host and the same verified SDK for every
candidate. OS filesystem cache is uncontrolled. Reports are external evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import time

from q1_benchmark import REPO, bind, inputs, memory, recognize


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_assets(assets):
    lock = json.loads((REPO / "native/ocr/tools/models.lock.json").read_text(encoding="utf-8"))
    verified = {}
    for name in ("PP_OCRv5_mobile_det.ncnn.param", "PP_OCRv5_mobile_det.ncnn.bin",
                 "PP_OCRv5_mobile_rec.ncnn.param", "PP_OCRv5_mobile_rec.ncnn.bin", "ppocrv5_dict.txt"):
        spec = (lock["dependencies"]["ncnn/" + name] if name.endswith(".txt")
                else lock["files"]["ncnn-official/" + name])
        actual = digest(assets / "ncnn" / name)
        if actual != spec["sha256"]:
            raise ValueError(f"official model hash mismatch: {name}")
        verified["ncnn/" + name] = actual
    for name, spec in lock["attachments"].items():
        actual = digest(assets / name)
        if actual != spec["sha256"]:
            raise ValueError(f"licence/model card hash mismatch: {name}")
        verified[name] = actual
    return verified


def worker(args):
    paths, dimensions = inputs()
    reference = json.loads((REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json")
                           .read_text(encoding="utf-8"))["images"]
    expected = {Path(row["path"].replace("\\", "/")).name: row for row in reference}
    records, outputs = [], {}
    started = time.perf_counter()

    def event(stage, **fields):
        records.append({"stage": stage, "elapsed_ms": (time.perf_counter() - started) * 1000,
                        **memory(os.getpid()), **fields})

    event("idle")
    lib = bind(args.library)
    event("library")
    session = None
    try:
        for batch in range(args.batches):
            for image_index, path in enumerate(paths):
                if session is None:
                    before = time.perf_counter()
                    session = lib.mf_ocr_create(os.fsencode(args.assets), args.threads)
                    if not session:
                        raise RuntimeError("native session allocation failed")
                    event("create", batch=batch, image=image_index,
                          duration_ms=(time.perf_counter() - before) * 1000)
                before = time.perf_counter()
                result = recognize(lib, session, path)
                elapsed = (time.perf_counter() - before) * 1000
                want = expected[path.name]
                assert result["error"] == "", (path.name, result["error"])
                assert (result["width"], result["height"]) == (want["width"], want["height"])
                assert len(result["lines"]) == len(want["lines"]), path.name
                for actual, golden in zip(result["lines"], want["lines"]):
                    assert actual["text"] == golden["text"], path.name
                    assert max(abs(a - b) for a, b in zip(actual["box"], golden["box"])) <= 1
                output_hash = hashlib.sha256(json.dumps(result, sort_keys=True, ensure_ascii=False)
                                             .encode("utf-8")).hexdigest()
                if path.name in outputs:
                    assert outputs[path.name] == output_hash, "repeat/recreation changed output"
                outputs[path.name] = output_hash
                event("ocr", batch=batch, image=image_index, duration_ms=elapsed,
                      lines=len(result["lines"]))
                if args.worker == "recreate":
                    before = time.perf_counter()
                    lib.mf_ocr_destroy(session)
                    session = None
                    event("destroy", batch=batch, image=image_index,
                          duration_ms=(time.perf_counter() - before) * 1000)
            event("batch", batch=batch)
    finally:
        if session:
            lib.mf_ocr_destroy(session)
            event("destroy")
    time.sleep(.1)
    event("settled")
    args.report.write_text(json.dumps({"pid": os.getpid(), "mode": args.worker,
        "threads": args.threads, "build": "Release", "inputs": dimensions,
        "output_sha256": outputs, "records": records}, indent=2) + "\n", encoding="utf-8")


def summarise_trial(data, samples):
    records = data["records"]
    peaks = {key: max((row[key] for row in samples + records if row[key] is not None), default=None)
             for key in ("rss_kib", "hwm_kib", "pss_kib")}
    batch_ids = [row["batch"] for row in records if row["stage"] == "batch"]
    # Full C ABI OCR (including PNG decode/JSON), plus creation/destruction in
    # recreate mode. Observation/hash/assertion overhead is excluded equally.
    times = [sum(row.get("duration_ms", 0) for row in records if row.get("batch") == batch)
             for batch in batch_ids]
    return {"pid": data["pid"], "peaks": peaks, "batch_ms": times,
            "hot_ten_ms": statistics.median(times[1:]), "cold_ten_ms": times[0],
            "batch_rss_kib": [row["rss_kib"] for row in records if row["stage"] == "batch"],
            "settled": records[-1], "output_sha256": data["output_sha256"]}


def comparison_summary(trials):
    summaries = []
    for name, mode in dict.fromkeys((trial["candidate"], trial["mode"]) for trial in trials):
        rows = [trial for trial in trials if (trial["candidate"], trial["mode"]) == (name, mode)]
        summaries.append({"candidate": name, "mode": mode, "trials": len(rows),
            "hot_ten_ms_median": statistics.median(row["hot_ten_ms"] for row in rows),
            "hot_ten_ms_range": [min(row["hot_ten_ms"] for row in rows), max(row["hot_ten_ms"] for row in rows)],
            "hwm_kib_median": statistics.median(row["peaks"]["hwm_kib"] for row in rows),
            "hwm_kib_max": max(row["peaks"]["hwm_kib"] for row in rows),
            "batch_rss_kib_median": statistics.median(value for row in rows for value in row["batch_rss_kib"]),
            "settled_rss_kib_median": statistics.median(row["settled"]["rss_kib"] for row in rows)})
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", action="append", default=[], metavar="NAME=LIBRARY")
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--batches", type=int, default=5)
    parser.add_argument("--threads", type=int, choices=range(1, 5), default=4)
    parser.add_argument("--seed", type=int, default=1702)
    parser.add_argument("--modes", nargs="+", choices=("reuse", "recreate"), default=["reuse"])
    parser.add_argument("--library", type=Path)
    parser.add_argument("--worker", choices=("reuse", "recreate"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.worker:
        if not args.library or not args.report or args.batches < 5:
            parser.error("worker requires library, report and five full batches")
        if args.report.resolve() == REPO or REPO in args.report.resolve().parents:
            parser.error("worker report must be outside checkout")
        worker(args)
        return 0
    if args.rounds < 3 or args.batches < 5:
        parser.error("at least three rounds and five complete ten-image batches required")
    if not args.out or args.out.resolve() == REPO or REPO in args.out.resolve().parents:
        parser.error("external output required")
    candidates = {}
    for candidate in args.candidate:
        name, path = candidate.split("=", 1)
        if not name or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in name) or name in candidates:
            parser.error("candidate names must be unique lowercase letters/digits/hyphens/underscores")
        candidates[name] = Path(path).resolve(strict=True)
    if len(candidates) < 2:
        parser.error("at least two candidates required")
    assets_verified = verify_assets(args.assets)
    args.out.mkdir(parents=True, exist_ok=False)
    order = list(candidates)
    random.Random(args.seed).shuffle(order)
    trials = []
    reference_outputs = None
    for round_index in range(args.rounds):
        rotated = order[round_index % len(order):] + order[:round_index % len(order)]
        for mode in args.modes:
            for name in rotated:
                label = f"r{round_index + 1}-{mode}-{name}"
                command = [sys.executable, str(Path(__file__).resolve()), "--worker", mode,
                           "--library", str(candidates[name]), "--assets", str(args.assets.resolve()),
                           "--threads", str(args.threads), "--batches", str(args.batches),
                           "--report", str(args.out / (label + ".json"))]
                samples = []
                started = time.time()
                with (args.out / (label + ".stderr")).open("w", encoding="utf-8") as stderr:
                    process = subprocess.Popen(command, stderr=stderr)
                    while process.poll() is None:
                        samples.append({"time": time.monotonic(), **memory(process.pid)})
                        time.sleep(.02)
                    code = process.wait()
                (args.out / (label + ".samples.json")).write_text(json.dumps(samples), encoding="utf-8")
                invocation = {"command": command, "exit": code, "started_unix": started,
                              "elapsed_seconds": time.time() - started}
                (args.out / (label + ".command.json")).write_text(json.dumps(invocation, indent=2), encoding="utf-8")
                if code:
                    raise RuntimeError(f"{label} failed {code}; see external stderr")
                data = json.loads((args.out / (label + ".json")).read_text(encoding="utf-8"))
                if reference_outputs is None:
                    reference_outputs = data["output_sha256"]
                assert data["output_sha256"] == reference_outputs, f"{label} differs from first candidate"
                trial = {"candidate": name, "mode": mode, "round": round_index + 1,
                         "command": invocation, **summarise_trial(data, samples)}
                trials.append(trial)
                (args.out / "trials.json").write_text(json.dumps(trials, indent=2), encoding="utf-8")
                print(json.dumps({"trial": label, "hot_ten_ms": round(trial["hot_ten_ms"], 1),
                                  "hwm_kib": trial["peaks"]["hwm_kib"]}), flush=True)
    report = {"platform": platform.platform(), "python": sys.version, "build": "Release",
              "threads_requested": args.threads, "sample_interval_ms": 20,
              "method": "fresh worker per trial; seeded rotation; OS file cache uncontrolled; serial execution",
              "seed": args.seed, "initial_order": order,
              "environment": {name: os.environ.get(name) for name in ("OMP_NUM_THREADS", "MALLOC_ARENA_MAX")},
              "libraries": {name: {"path": str(path), "sha256": digest(path)} for name, path in candidates.items()},
              "assets_sha256": assets_verified,
              "input_sha256": {path.name: digest(path) for path in inputs()[0]},
              "inputs": inputs()[1], "trials": trials, "summary": comparison_summary(trials)}
    (args.out / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
