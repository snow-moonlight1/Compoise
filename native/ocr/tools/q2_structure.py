#!/usr/bin/env python3
"""Q2 structure fixtures for the wide-image checkbox miss.

The Q1 generator is the source of the 30-task scenes. This tool only reports
which of those declared checkboxes the historical 2.2% width rule drops, and
can regenerate the synthetic PNGs outside the checkout. It does not download
models, fonts, or weights. Default unit tests do not call it.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from q1_benchmark import REPO  # noqa: E402
from q1_quality import SCENES, generate  # noqa: E402

# q1_quality draws a 28px rectangle whose inclusive extent is 29px.
CHECKBOX_SIDE = 29


def misses():
    """Tasks whose declared checkbox is below 2.2% of image width."""
    lost = []
    for name, width, _height, _size, _spacing, _dark, _face, tasks in SCENES:
        threshold = 0.022 * width
        if CHECKBOX_SIDE < threshold:
            lost.append(
                {
                    "id": name,
                    "width": width,
                    "checkbox_side": CHECKBOX_SIDE,
                    "width_fraction_min": round(threshold, 2),
                    "tasks": len(tasks),
                }
            )
    return lost


def expect():
    lost = misses()
    kept = sum(len(scene[-1]) for scene in SCENES) - sum(item["tasks"] for item in lost)
    report = {
        "scenes": len(SCENES),
        "tasks": sum(len(scene[-1]) for scene in SCENES),
        "legacy_kept": kept,
        "legacy_misses": lost,
    }
    if [item["id"] for item in lost] != ["long-lines"] or sum(item["tasks"] for item in lost) != 2:
        raise SystemExit(f"unexpected legacy misses: {report}")
    print(json.dumps(report, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("expect", "generate"))
    parser.add_argument("--out", type=Path)
    parser.add_argument("--fonts", type=Path, default=Path("C:/Windows/Fonts"))
    args = parser.parse_args()
    if args.action == "expect":
        expect()
        return
    if args.out is None:
        parser.error("generate requires --out")
    target = args.out.resolve()
    if target == REPO or REPO in target.parents:
        parser.error("output must be outside checkout")
    generate(args.out, args.fonts)


if __name__ == "__main__":
    main()
