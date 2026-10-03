#!/usr/bin/env python3
"""Opt-in valid PNG tests at inclusive native byte/pixel limits, with recovery."""
import argparse
import json
from pathlib import Path
import struct
import zlib

from q1_benchmark import REPO, bind, memory, recognize


def png(path, width, height, target_bytes=None, compression=6):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    compressor = zlib.compressobj(compression)
    row = b"\0" + b"\xff\xff\xff" * width
    data = b"".join(compressor.compress(row) for _ in range(height)) + compressor.flush()
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    body = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", data)
    if target_bytes:
        # A legal ancillary chunk, not forbidden trailing bytes after IEND.
        padding = target_bytes - len(body) - 12 - 12
        assert padding >= 2
        body += chunk(b"tEXt", b"q\0" + b"x" * (padding - 2))
    body += chunk(b"IEND", b"")
    path.write_bytes(body)
    if target_bytes: assert path.stat().st_size == target_bytes


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--library", type=Path, required=True)
    p.add_argument("--assets", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    if a.out.resolve() == REPO or REPO in a.out.resolve().parents: p.error("external output required")
    a.out.mkdir(parents=True, exist_ok=True)
    specs = [("max-width", 4096, 8, None, ""), ("max-height", 8, 8192, None, ""),
             ("max-pixels", 4096, 3072, None, ""), ("max-bytes", 8, 8, 16 * 1024 * 1024, ""),
             ("over-bytes", 8, 8, 16 * 1024 * 1024 + 1, "image file exceeds 16 MiB or is empty")]
    for name, width, height, size, _ in specs:
        png(a.out / (name + ".png"), width, height, size)
    # Ten-file Flutter stress batches close to each unchanged aggregate cap.
    png(a.out / "near-max-pixels.png", 4096, 3071)
    png(a.out / "tiny.png", 32, 16)
    png(a.out / "near-max-bytes.png", 4096, 1364, 16 * 1024 * 1024 - 4096, compression=0)
    lib = bind(a.library)
    results = []
    for recreation in range(2):
        session = lib.mf_ocr_create(str(a.assets).encode(), 4)
        assert session
        try:
            for name, width, height, size, error in specs:
                result = recognize(lib, session, a.out / (name + ".png"))
                assert result["error"] == error, (name, result)
                if error: assert result["lines"] == [], (name, result)
                if not error: assert (result["width"], result["height"]) == (width, height)
                results.append({"case": name, "recreation": recreation, "width": width, "height": height,
                                "bytes": (a.out / (name + ".png")).stat().st_size,
                                "lines": len(result["lines"]), "error": error})
            # Recover after the rejected file, without rebuilding the session.
            assert recognize(lib, session, a.out / "max-width.png")["error"] == ""
        finally:
            lib.mf_ocr_destroy(session)
    import os
    report = {"pid": os.getpid(), "results": results, "after_destroy": memory(os.getpid())}
    (a.out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
