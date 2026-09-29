#!/usr/bin/env python3
"""Score an already-recorded raw run directory.

Kept separate from run_bench.py on purpose:

  * the same scoring code must be applied to every platform, including the ones
    where the Python helper stack is not installed (the Linux and Android legs
    only need to produce raw engine output);
  * adapter/scoring changes must not force a re-run of the models.

Reads results/<platform>/summary.json plus raw/<config>/all.json, writes the
text score, the structure score, duplicate hints and the per-image diff files
back into the summary, and (optionally) annotated review images.
"""
from __future__ import annotations

import argparse
import json
import os

import adapter
import score_structure
import score_text
from wp17r2lib import LABELS, RESULTS, load_labels

#: annotated review images are only produced for these cases on the reference
#: platform: the full per-image diff JSON is kept for every case anyway.
REVIEW_CASES = [
    "zh_light_base",
    "zh_dark_base",
    "en_light_base",
    "ja_light_base",
    "zh_small_text",
    "zh_long_scroll",
]


def _case_images(doc):
    return {c["id"]: os.path.join(os.path.dirname(LABELS), c["file"]) for c in doc["cases"]}


def _draw_overlay(case, rec_lines, out_path):
    from PIL import Image, ImageDraw, ImageFont

    img_path = os.path.join(os.path.dirname(LABELS), case["file"])
    with Image.open(img_path) as im:
        canvas = im.convert("RGB")
    d = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    for g in case["lines"]:
        b = g["box"]
        d.rectangle([b[0], b[1], b[0] + b[2], b[1] + b[3]], outline=(0, 160, 0), width=2)
    for r in rec_lines:
        b = r["box"]
        d.rectangle([b[0], b[1], b[0] + b[2], b[1] + b[3]], outline=(220, 30, 30), width=3)
        d.text((b[0] + 3, max(0, b[1] - 24)), r["text"][:40], fill=(220, 30, 30), font=font)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.save(out_path, optimize=True)
    return os.path.getsize(out_path)


def score_platform(platform: str, overlays: bool = True) -> dict:
    out_dir = os.path.join(RESULTS, platform)
    summary_path = os.path.join(out_dir, "summary.json")
    with open(summary_path, encoding="utf-8") as f:
        summary = json.load(f)
    doc = load_labels()
    by_id = {c["id"]: c for c in doc["cases"]}

    for cid, entry in summary["runs"].items():
        raw_path = os.path.join(out_dir, "raw", cid, "all.json")
        if not os.path.exists(raw_path):
            entry["score_error"] = "missing " + raw_path
            continue
        with open(raw_path, encoding="utf-8") as f:
            allres = json.load(f)

        text_rows, struct_rows, drafts = [], [], []
        diff_dir = os.path.join(out_dir, "diffs", cid)
        os.makedirs(diff_dir, exist_ok=True)
        overlay_dir = os.path.join(out_dir, "overlays", cid)
        is_primary = entry["config"].get("primary", False)

        for im in allres["images"]:
            case_id = os.path.splitext(os.path.basename(im["path"]))[0]
            case = by_id.get(case_id)
            if case is None:
                continue
            img_path = os.path.join(os.path.dirname(LABELS), case["file"])
            rec_lines = im["lines"]

            trow = score_text.score_image(case, rec_lines)
            text_rows.append(trow)

            single = {
                "engine": allres.get("engine", ""),
                "engine_version": allres.get("engine_version", ""),
                "config": allres.get("config", {}),
                "images": [im],
            }
            draft = adapter.build_draft(single, img_path, case_id)
            drafts.append(draft)
            srow = score_structure.score_image(case, rec_lines, draft)
            struct_rows.append(srow)

            with open(os.path.join(diff_dir, case_id + ".json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "id": case_id,
                        "engine": allres.get("engine", ""),
                        "engine_version": allres.get("engine_version", ""),
                        "config": cid,
                        "timing": {
                            "width": im["width"],
                            "height": im["height"],
                            "det_ms": im["det_ms"],
                            "rec_ms": im["rec_ms"],
                            "total_ms": im["total_ms"],
                        },
                        "text": {k: v for k, v in trow.items() if k != "diffs"},
                        "text_diffs": trow["diffs"],
                        "structure": {k: v for k, v in srow.items() if k not in ("details", "spurious_detail")},
                        "structure_details": srow["details"],
                        "spurious_detail": srow["spurious_detail"],
                        "draft": draft,
                    },
                    f,
                    ensure_ascii=False,
                    indent=1,
                )
            if overlays and is_primary and platform == "win" and case_id in REVIEW_CASES:
                _draw_overlay(case, rec_lines, os.path.join(overlay_dir, case_id + ".png"))

        paths = {d["id"]: os.path.join(os.path.dirname(LABELS), by_id[d["id"]]["file"]) for d in drafts}
        entry["text"] = {"per_image": text_rows, "aggregate": score_text.aggregate(text_rows)}
        entry["structure"] = {"per_image": struct_rows, "aggregate": score_structure.aggregate(struct_rows)}
        entry["duplicates"] = adapter.duplicate_hints(drafts, paths)

    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=1)
    return summary


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", required=True)
    ap.add_argument("--no-overlays", action="store_true")
    a = ap.parse_args()
    s = score_platform(a.platform, overlays=not a.no_overlays)
    for cid, e in s["runs"].items():
        if "text" not in e:
            print(f"{cid}: {e.get('score_error', 'not scored')}")
            continue
        t, st = e["text"]["aggregate"], e["structure"]["aggregate"]
        print(
            f"{cid:18} CER={t['cer_micro']:.4f} macro={t['cer_macro']:.4f} "
            f"missed={t['missed_gt_lines']:3d} spurious={t['spurious_rec_lines']:3d} "
            f"taskR={st['task_recall_micro']:.3f} taskP={st['task_precision_micro']:.3f} "
            f"kendall={st['order_task_kendall_macro']:.3f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
