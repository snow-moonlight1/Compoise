#!/usr/bin/env python3
"""Direct C ABI comparison against unchanged R2 text/geometry plus boundaries.

No app window/device is opened. Optional --report goes to an external directory;
the committed evidence contains aggregate measurements, never native logs.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import struct
import tempfile
import time
import zlib

REPO = Path(__file__).resolve().parents[3]


def peak_rss_kb():
    if os.name != "nt":
        for line in Path("/proc/self/status").read_text().splitlines():
            if line.startswith("VmHWM:"):
                return int(line.split()[1])
    else:
        class Memory(ctypes.Structure):
            _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong)] + [
                (name, ctypes.c_size_t) for name in ("peak", "working", "quota_peak_paged",
                "quota_paged", "quota_peak_nonpaged", "quota_nonpaged", "pagefile", "peak_pagefile")]
        memory = Memory()
        memory.cb = ctypes.sizeof(memory)
        kernel = ctypes.WinDLL("kernel32")
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        psapi = ctypes.WinDLL("psapi")
        psapi.GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(Memory), ctypes.c_ulong]
        assert psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(), ctypes.byref(memory), memory.cb)
        return memory.peak // 1024
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--recreate", type=int, default=2)
    args = parser.parse_args()
    lib = ctypes.CDLL(str(args.library.resolve()))
    lib.mf_ocr_create.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.mf_ocr_create.restype = ctypes.c_void_p
    lib.mf_ocr_destroy.argtypes = [ctypes.c_void_p]
    lib.mf_ocr_run_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.mf_ocr_run_file.restype = ctypes.c_void_p
    lib.mf_ocr_free.argtypes = [ctypes.c_void_p]
    def recognize(session, path):
        pointer = lib.mf_ocr_run_file(session, os.fsencode(path))
        assert pointer, "null native allocation"
        try:
            return json.loads(ctypes.string_at(pointer).decode("utf-8"))
        finally:
            lib.mf_ocr_free(pointer)
    reference = json.loads((REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json").read_text(encoding="utf-8"))["images"]
    batches, first, max_delta, line_count = [], {}, 0, 0
    started = time.perf_counter()
    for session_index in range(args.recreate + 1):
        session = lib.mf_ocr_create(os.fsencode(args.assets), 4)
        assert session
        try:
            for batch_index in range(args.repeat if session_index == 0 else 1):
                before = time.perf_counter()
                for image in reference:
                    name = image["path"].replace("\\", "/").split("/")[-1]
                    result = recognize(session, REPO / "docs/evidence/wp17r2/samples/images" / name)
                    assert result["error"] == "", (name, result["error"])
                    assert (result["width"], result["height"]) == (image["width"], image["height"])
                    assert len(result["lines"]) == len(image["lines"]), name
                    for actual, expected in zip(result["lines"], image["lines"]):
                        assert actual["text"] == expected["text"], (name, actual["text"], expected["text"])
                        delta = max(abs(a - b) for a, b in zip(actual["box"], expected["box"]))
                        max_delta = max(max_delta, delta)
                        assert delta <= 1, (name, actual["box"], expected["box"])
                    if name in first:
                        assert result == first[name], (name, "repeated/session recreation mismatch")
                    else:
                        first[name] = result
                        line_count += len(result["lines"])
                batches.append({"session": session_index, "batch": batch_index,
                    "images": len(reference), "elapsed_ms": round((time.perf_counter() - before) * 1000, 1),
                    "peak_rss_kb": peak_rss_kb()})
        finally:
            lib.mf_ocr_destroy(session)
    boundaries = {}
    with tempfile.TemporaryDirectory(prefix="wp17i5-runtime-") as temporary:
        root = Path(temporary)
        session = lib.mf_ocr_create(os.fsencode(args.assets), 4)
        try:
            cases = {"missing.png": (None, "cannot open image"),
                     "bad.png": (b"not a png", "PNG header decode failed"),
                     "empty.png": (b"", "image file exceeds 16 MiB or is empty")}
            for name, (data, expected) in cases.items():
                path = root / name
                if data is not None:
                    path.write_bytes(data)
                result = recognize(session, path)
                assert result["error"] == expected and result["lines"] == [], result
                boundaries[name] = result["error"]
            oversized = root / "oversized.png"
            with oversized.open("wb") as handle:
                handle.truncate(16 * 1024 * 1024 + 1)
            result = recognize(session, oversized)
            assert result["error"] == "image file exceeds 16 MiB or is empty", result
            boundaries[oversized.name] = result["error"]
            for name, w, h in (("wide.png", 4097, 8), ("tall.png", 8, 8193), ("pixels.png", 4000, 3200)):
                def chunk(kind, data):
                    body = kind + data
                    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
                # Complete valid PNGs exercise dimension rejection rather than
                # the earlier malformed-header branch. Stream rows to bound RAM.
                compressor = zlib.compressobj()
                row = b"\0" + b"\xff\xff\xff" * w
                compressed = b"".join(compressor.compress(row) for _ in range(h)) + compressor.flush()
                header = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
                (root / name).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))
                result = recognize(session, root / name)
                assert result["error"] == "image dimensions exceed OCR limit" and result["width"] == 0, result
                boundaries[name] = result["error"]
        finally:
            lib.mf_ocr_destroy(session)
        missing = lib.mf_ocr_create(os.fsencode(root), 4)
        try:
            result = recognize(missing, root / "bad.png")
            assert "cannot read dict" in result["error"] and result["width"] == 0 and not result["lines"], result
            boundaries["missing-models"] = "cannot read dict"
        finally:
            lib.mf_ocr_destroy(missing)
    report = {"images": len(reference), "lines": line_count, "text_mismatches": 0,
              "max_box_delta": round(max_delta, 4), "batches": batches, "boundaries": boundaries,
              "elapsed_ms": round((time.perf_counter() - started) * 1000, 1), "platform": sys_platform()}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))
    return 0


def sys_platform():
    import platform
    return platform.platform()


if __name__ == "__main__":
    raise SystemExit(main())
