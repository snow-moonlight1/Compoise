#!/usr/bin/env python3
"""Opt-in C ABI benchmark. No downloads; outputs must be outside the checkout.

Each mode is a fresh process (process-cold, OS caches unspecified). Current RSS,
OS high-water RSS and PSS are named separately; unavailable fields are null.
The parent samples the actual worker PID, including peaks during native calls.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[3]


def memory(pid):
    result = {"rss_kib": None, "hwm_kib": None, "pss_kib": None}
    if os.name == "nt":
        class Counters(ctypes.Structure):
            _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong)] + [
                (name, ctypes.c_size_t) for name in
                ("peak", "working", "qp", "q", "qn", "n", "pagefile", "peak_pagefile")]
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        psapi = ctypes.WinDLL("psapi")
        psapi.GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(Counters), ctypes.c_ulong]
        handle = kernel.OpenProcess(0x410, False, pid)
        if handle:
            try:
                counters = Counters()
                counters.cb = ctypes.sizeof(counters)
                if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                    result.update(rss_kib=counters.working // 1024, hwm_kib=counters.peak // 1024)
            finally:
                kernel.CloseHandle(handle)
    else:
        try:
            for line in Path(f"/proc/{pid}/status").read_text().splitlines():
                if line.startswith("VmRSS:"): result["rss_kib"] = int(line.split()[1])
                if line.startswith("VmHWM:"): result["hwm_kib"] = int(line.split()[1])
            for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
                if line.startswith("Pss:"): result["pss_kib"] = int(line.split()[1])
        except (OSError, ValueError):
            pass
    return result


def inputs():
    labels = json.loads((REPO / "docs/evidence/wp17r2/samples/labels.json").read_text(encoding="utf-8"))
    # Separate legal ten-image stress batch including real byte duplicates.
    # The historical R2 ten-image batch is covered by native capture regression.
    ids = json.loads((Path(__file__).parent / "q1_cases.json").read_text())["batch"]
    paths = [REPO / "docs/evidence/wp17r2/samples/images" / (name + ".png") for name in ids]
    dims = [struct.unpack(">II", path.read_bytes()[16:24]) for path in paths]
    sizes = [path.stat().st_size for path in paths]
    assert len(paths) == 10 and sum(w * h for w, h in dims) <= 24 * 1024 * 1024
    assert sum(sizes) <= 48 * 1024 * 1024
    return paths, [{"id": name, "width": w, "height": h, "bytes": size}
                   for name, (w, h), size in zip(ids, dims, sizes)]


def bind(library):
    lib = ctypes.CDLL(str(library.resolve()))
    lib.mf_ocr_create.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.mf_ocr_create.restype = ctypes.c_void_p
    lib.mf_ocr_destroy.argtypes = [ctypes.c_void_p]
    lib.mf_ocr_run_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.mf_ocr_run_file.restype = ctypes.c_void_p
    lib.mf_ocr_free.argtypes = [ctypes.c_void_p]
    return lib


def recognize(lib, session, path):
    pointer = lib.mf_ocr_run_file(session, os.fsencode(path))
    assert pointer, "native result allocation failed"
    try:
        return json.loads(ctypes.string_at(pointer).decode("utf-8"))
    finally:
        lib.mf_ocr_free(pointer)


def worker(args):
    records = []
    def event(stage, **fields):
        records.append({"stage": stage, "pid": os.getpid(), "elapsed_ms": round((time.perf_counter() - start) * 1000, 2),
                        **memory(os.getpid()), **fields})
    start = time.perf_counter()
    event("idle")
    lib = bind(args.library)
    event("library")
    paths, dimensions = inputs()
    reference = json.loads((REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json").read_text(encoding="utf-8"))["images"]
    expected = {Path(row["path"].replace("\\", "/")).name: row for row in reference}
    session = None
    first = {}
    try:
        for batch in range(1 if args.worker == "single" else args.batches):
            for index, path in enumerate(paths[:1] if args.worker == "single" else paths):
                if session is None:
                    before = time.perf_counter()
                    session = lib.mf_ocr_create(os.fsencode(args.assets), args.threads)
                    assert session
                    event("create", batch=batch, image=index, duration_ms=round((time.perf_counter() - before) * 1000, 2))
                before = time.perf_counter()
                result = recognize(lib, session, path)
                want = expected[path.name]
                assert result["error"] == "", result["error"]
                assert (result["width"], result["height"]) == (want["width"], want["height"])
                assert len(result["lines"]) == len(want["lines"]), path.name
                for actual, golden in zip(result["lines"], want["lines"]):
                    assert actual["text"] == golden["text"], (path.name, actual["text"], golden["text"])
                    assert max(abs(a - b) for a, b in zip(actual["box"], golden["box"])) <= 1
                if path.name in first: assert first[path.name] == result, "repeat changed"
                first[path.name] = result
                event("ocr", batch=batch, image=index, duration_ms=round((time.perf_counter() - before) * 1000, 2), lines=len(result["lines"]))
                if args.worker == "recreate":
                    lib.mf_ocr_destroy(session)
                    session = None
                    event("destroy", batch=batch, image=index)
            event("batch", batch=batch)
    finally:
        if session:
            lib.mf_ocr_destroy(session)
            event("destroy")
    # Observe allocator retention after all owned native objects are gone.
    time.sleep(0.1)
    event("settled")
    args.report.write_text(json.dumps({"mode": args.worker, "build": args.build, "threads": args.threads,
                                     "inputs": dimensions, "records": records}, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--build", required=True, choices=("Debug", "Release"))
    parser.add_argument("--threads", type=int, default=4, choices=range(1, 5))
    parser.add_argument("--batches", type=int, default=5)
    parser.add_argument("--worker", choices=("single", "reuse", "recreate"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.worker:
        worker(args)
        return 0
    if not args.out: parser.error("--out required")
    out = args.out.resolve()
    if out == REPO or REPO in out.parents: parser.error("output must be outside checkout")
    if args.batches < 2: parser.error("use at least two batches")
    out.mkdir(parents=True, exist_ok=True)
    # Verify the official five-file bundle, never download or update a lock.
    lock = json.loads((REPO / "native/ocr/tools/models.lock.json").read_text())
    hashes = {}
    for name in ("PP_OCRv5_mobile_det.ncnn.param", "PP_OCRv5_mobile_det.ncnn.bin",
                 "PP_OCRv5_mobile_rec.ncnn.param", "PP_OCRv5_mobile_rec.ncnn.bin", "ppocrv5_dict.txt"):
        digest = hashlib.sha256((args.assets / "ncnn" / name).read_bytes()).hexdigest()
        source = lock["dependencies"]["ncnn/" + name] if name.endswith(".txt") else lock["files"]["ncnn-official/" + name]
        assert digest == source["sha256"], name
        hashes[name] = digest
    summaries = []
    for mode in ("single", "reuse", "recreate"):
        command = [sys.executable, str(Path(__file__).resolve()), "--library", str(args.library.resolve()),
                   "--assets", str(args.assets.resolve()), "--build", args.build, "--threads", str(args.threads),
                   "--batches", str(args.batches), "--worker", mode, "--report", str(out / (mode + ".json"))]
        samples = []
        with (out / (mode + ".stderr")).open("w") as log:
            process = subprocess.Popen(command, stderr=log)
            while process.poll() is None:
                samples.append({"time": time.monotonic(), "pid": process.pid, **memory(process.pid)})
                time.sleep(.02)
            code = process.wait()
        (out / (mode + ".samples.json")).write_text(json.dumps(samples))
        assert code == 0, (mode, code, str(out / (mode + ".stderr")))
        data = json.loads((out / (mode + ".json")).read_text())
        peaks = {key: max((row[key] for row in samples if row[key] is not None), default=None)
                 for key in ("rss_kib", "hwm_kib", "pss_kib")}
        summaries.append({"mode": mode, "pid": process.pid, "exit": code, "sampled_peaks": peaks, "records": data["records"]})
    report = {"platform": platform.platform(), "python": sys.version, "build": args.build, "threads": args.threads,
              "cold": "fresh process; filesystem cache uncontrolled", "sample_interval_ms": 20,
              "library_sha256": hashlib.sha256(args.library.read_bytes()).hexdigest(),
              "model_sha256": hashes, "modes": summaries, "inputs": inputs()[1]}
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"report": str(out / "summary.json"), "peaks": [m["sampled_peaks"] for m in summaries]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
