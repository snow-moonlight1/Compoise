#!/usr/bin/env python3
"""Opt-in real C ABI lifecycle/error regression; no benchmark claims or downloads.

Includes exact Q1 JSON comparison for all 12 R2 images, partial model-load
teardown, decoded-PNG failure, recovery, and concurrent independent sessions.
Production serialises sessions; this concurrency is an allocator regression.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil

from p2_benchmark import verify_assets
from q1_benchmark import REPO, bind, recognize
from q1_limits import png


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--baseline-library", type=Path, required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.resolve() == REPO or REPO in args.out.resolve().parents:
        parser.error("external output required")
    verified = verify_assets(args.assets)
    args.out.mkdir(parents=True, exist_ok=False)
    lib, baseline = bind(args.library), bind(args.baseline_library)
    reference = json.loads((REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json")
                           .read_text(encoding="utf-8"))["images"]
    paths = [REPO / "docs/evidence/wp17r2/samples/images" / Path(row["path"].replace("\\", "/")).name
             for row in reference]
    expected = {}
    session = baseline.mf_ocr_create(os.fsencode(args.assets), 4)
    assert session
    try:
        for path in paths:
            expected[path.name] = recognize(baseline, session, path)
    finally:
        baseline.mf_ocr_destroy(session)
    line_count = 0
    max_delta = 0
    for path, golden in zip(paths, reference):
        actual = expected[path.name]
        assert actual["error"] == "" and len(actual["lines"]) == len(golden["lines"])
        for line, want in zip(actual["lines"], golden["lines"]):
            assert line["text"] == want["text"]
            delta = max(abs(a - b) for a, b in zip(line["box"], want["box"]))
            assert delta <= 1
            max_delta = max(delta, max_delta)
        line_count += len(actual["lines"])

    checks = []
    for recreation in range(3):
        session = lib.mf_ocr_create(os.fsencode(args.assets), 4)
        assert session
        try:
            for repeat in range(3 if recreation == 0 else 1):
                for path in paths:
                    assert recognize(lib, session, path) == expected[path.name], path.name
                checks.append(f"12-images-session-{recreation}-repeat-{repeat}")
            cases = [("missing.png", None, "cannot open image"),
                     ("bad.png", b"not a PNG", "PNG header decode failed"),
                     ("empty.png", b"", "image file exceeds 16 MiB or is empty")]
            for name, content, error in cases:
                path = args.out / name
                if content is not None:
                    path.write_bytes(content)
                result = recognize(lib, session, path)
                assert result["error"] == error and result["lines"] == []
                assert recognize(lib, session, paths[0]) == expected[paths[0].name]
                checks.append(f"{name}-recover-{recreation}")
            # Complete IHDR is accepted by stbi_info; truncated IDAT then fails
            # decoding, after a valid cached-pool image has already completed.
            truncated = args.out / "truncated.png"
            png(truncated, 64, 64)
            truncated.write_bytes(truncated.read_bytes()[:45])
            result = recognize(lib, session, truncated)
            assert result["error"] == "PNG decode failed" and not result["lines"]
            assert recognize(lib, session, paths[0]) == expected[paths[0].name]
            checks.append(f"decode-failure-recover-{recreation}")
            for value in (None, b""):
                pointer = lib.mf_ocr_run_file(session, value)
                assert pointer
                try:
                    result = json.loads(ctypes.string_at(pointer))
                    assert result["error"] == "image path is empty" and not result["lines"]
                finally:
                    lib.mf_ocr_free(pointer)
            checks.append(f"null-empty-path-{recreation}")
            for name, width, height in (("over-width", 4097, 8), ("over-height", 8, 8193),
                                        ("over-pixels", 4000, 3200)):
                path = args.out / (name + ".png")
                png(path, width, height)
                result = recognize(lib, session, path)
                assert result["error"] == "image dimensions exceed OCR limit"
                assert result["width"] == 0 and not result["lines"]
                assert recognize(lib, session, paths[0]) == expected[paths[0].name]
                checks.append(f"{name}-recover-{recreation}")
            path = args.out / "over-bytes.png"
            with path.open("wb") as handle:
                handle.truncate(16 * 1024 * 1024 + 1)
            result = recognize(lib, session, path)
            assert result["error"] == "image file exceeds 16 MiB or is empty" and not result["lines"]
            assert recognize(lib, session, paths[0]) == expected[paths[0].name]
            checks.append(f"over-bytes-recover-{recreation}")
        finally:
            lib.mf_ocr_destroy(session)

    for failure in ("missing-dict", "missing-det-bin", "missing-rec-bin"):
        partial = args.out / failure / "ncnn"
        partial.mkdir(parents=True)
        if failure != "missing-dict":
            for source in (args.assets / "ncnn").iterdir():
                if source.name == ("PP_OCRv5_mobile_det.ncnn.bin" if failure == "missing-det-bin"
                                   else "PP_OCRv5_mobile_rec.ncnn.bin"):
                    continue
                shutil.copyfile(source, partial / source.name)
        session = lib.mf_ocr_create(os.fsencode(partial.parent), 4)
        assert session
        try:
            result = recognize(lib, session, paths[0])
            assert result["error"].startswith("cannot read dict" if failure == "missing-dict"
                                              else "cannot load det model" if failure == "missing-det-bin"
                                              else "cannot load rec model")
            assert not result["lines"] and result["width"] == 0
        finally:
            lib.mf_ocr_destroy(session)
        checks.append(failure + "-teardown")

    def independent_session(_):
        session = lib.mf_ocr_create(os.fsencode(args.assets), 4)
        assert session
        try:
            for path in paths[:2]:
                assert recognize(lib, session, path) == expected[path.name]
        finally:
            lib.mf_ocr_destroy(session)

    with ThreadPoolExecutor(max_workers=2) as executor:
        list(executor.map(independent_session, range(4)))
    checks.append("concurrent-independent-sessions-joined-before-destroy")
    lib.mf_ocr_destroy(None)
    lib.mf_ocr_free(None)
    result = recognize(lib, None, paths[0])
    assert result["error"] == "native OCR session allocation failed" and not result["lines"]
    checks.append("null-session-destroy-free")
    report = {"exit": 0, "images": len(paths), "lines": line_count, "max_box_delta": max_delta,
              "exact_q1_json": True, "checks": checks, "assets_sha256": verified,
              "library_sha256": hashlib.sha256(args.library.read_bytes()).hexdigest(),
              "baseline_sha256": hashlib.sha256(args.baseline_library.read_bytes()).hexdigest(),
              "not_measured": ["native cancellation (no C ABI for it)", "OOM injection", "device stability"]}
    (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("exit", "images", "lines", "max_box_delta", "exact_q1_json")}))


if __name__ == "__main__":
    main()
