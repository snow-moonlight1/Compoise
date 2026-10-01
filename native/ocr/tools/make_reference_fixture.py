#!/usr/bin/env python3
"""Generate the compact R2 geometry fixture used by the bundle OCR test.

The full baseline (``docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json``)
carries every recognized string and box. A device test cannot read a host file,
and re-typing the strings into the repository would be a second, unverified
copy. This tool keeps only the numbers the test compares - the line count and
the four box components per line, in baseline order - and records the SHA-256 of
the baseline it came from, so the fixture's provenance is checkable.

Usage:
    python native/ocr/tools/make_reference_fixture.py [--check]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
BASELINE = REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json"
FIXTURE = REPO / "test/support/wp17_i4_r2_geometry.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the fixture is stale")
    args = parser.parse_args()

    raw = BASELINE.read_bytes()
    baseline_sha = hashlib.sha256(raw).hexdigest()
    data = json.loads(raw.decode("utf-8"))

    images = []
    for image in data["images"]:
        lines = image["lines"]
        images.append(
            {
                "name": pathlib.PureWindowsPath(image["path"]).name,
                "width": image["width"],
                "height": image["height"],
                "boxes": [[round(float(value), 2) for value in line["box"]] for line in lines],
            }
        )

    fixture = {
        "schema": 1,
        "source": "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json",
        "sourceSha256": baseline_sha,
        "note": "text is compared against the baseline file on the host; this fixture carries geometry only",
        "images": images,
    }
    text = json.dumps(fixture, indent=1, sort_keys=False) + "\n"

    if args.check:
        current = FIXTURE.read_text(encoding="utf-8") if FIXTURE.exists() else ""
        if current != text:
            print(f"{FIXTURE} is stale; regenerate with this tool", file=sys.stderr)
            return 1
        print(f"{FIXTURE} is current ({len(images)} images, baseline {baseline_sha[:16]})")
        return 0

    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(text, encoding="utf-8")
    print(f"wrote {FIXTURE}: {len(images)} images, baseline sha256 {baseline_sha}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
