#!/usr/bin/env python3
"""WP17-R2 reference adapter: "OCR result -> editable task draft".

This is the data contract WP17-I has to implement.  It is deliberately
engine-agnostic: its only inputs are the raw OCR lines (text + axis-aligned
boxes, in whatever order the engine produced them) and the original image (used
for the checkbox gutter scan).  It never reads the ground-truth labels.

Contract (schema ``wp17r2-draft/1``)::

    { "schema": "wp17r2-draft/1",
      "images": [ { "id", "width", "height", "engine",
                    "rows":   [ {"index","kind","line_indices","text","y_center"} ],
                    "tasks":  [ {"row","title","checked","level","parent","due",
                                 "needs_confirmation":[str]} ],
                    "dropped":[ {"row","kind","text"} ],
                    "notes":  [str] } ],
      "duplicates": [ {"images":[id,id], "reason", "hint_only": true} ] }

Guarantees the contract makes explicit (and WP17-I must preserve):
  * OCR text is never treated as a checkbox.  ``checked`` comes from the image
    gutter scan, never from parsing "√"/"x" out of recognized text.
  * Anything the geometry cannot decide is listed in ``needs_confirmation`` and
    must stay unconfirmed in the UI; nothing is silently written to the task
    store.
  * Cross-image duplicates are *hints only* (``hint_only: true``); the adapter
    never drops or merges a task on its own.

Known limits of the heuristic (measured in docs/WP17_OCR_EVALUATION.md):
  * "chrome" (status bar + app bar) is assumed to live in the top ``0.22 *
    width`` band, which assumes dp-scaled phone screenshots.
  * "checked" is a fill-ratio threshold (0.5) on the gutter mark; strikethrough
    alone is not detected.
  * Indentation is a single threshold (level 0/1); deeper nesting is not
    inferred.
"""
from __future__ import annotations

import hashlib
import json
import os

from wp17r2lib import box_center, box_iou, center_in, find_checkboxes, load_gray, norm_text

CHROME_TOP_FRAC_OF_WIDTH = 0.22
INDENT_THRESHOLD_FRAC_OF_WIDTH = 0.07
META_X_FRAC_OF_WIDTH = 0.50


def _rows_from_lines(lines: list[dict]) -> list[list[int]]:
    """Group lines into rows: engine order is irrelevant, only geometry counts."""
    idx = sorted(
        range(len(lines)),
        key=lambda i: (lines[i]["box"][1] + lines[i]["box"][3] / 2.0, lines[i]["box"][0]),
    )
    rows: list[list[int]] = []
    bands: list[tuple[float, float]] = []
    for i in idx:
        b = lines[i]["box"]
        y0, y1 = b[1], b[1] + b[3]
        placed = False
        for r, (by0, by1) in enumerate(bands):
            overlap = min(y1, by1) - max(y0, by0)
            if overlap > 0.5 * min(y1 - y0, by1 - by0):
                rows[r].append(i)
                bands[r] = (min(y0, by0), max(y1, by1))
                placed = True
                break
        if not placed:
            rows.append([i])
            bands.append((y0, y1))
    for r in rows:
        r.sort(key=lambda i: lines[i]["box"][0])
    order = sorted(range(len(rows)), key=lambda r: bands[r][0])
    return [rows[r] for r in order]


def _inside_any_checkbox(box, cb_boxes) -> bool:
    for cb in cb_boxes:
        if box_iou(box, cb) > 0.5 or center_in(box, cb):
            return True
    return False


def build_draft(ocr: dict, image_path: str, image_id: str) -> dict:
    img = ocr["images"][0]
    w, h = img["width"], img["height"]
    # keep every recognized line, but remember its index in the raw engine output
    # so scorer/manual review can address the same objects.
    kept = [(i, ln) for i, ln in enumerate(img["lines"]) if norm_text(ln["text"])]
    raw_index = [i for i, _ in kept]
    lines = [ln for _, ln in kept]
    noise = [ln for ln in img["lines"] if not norm_text(ln["text"])]

    rows_idx = _rows_from_lines(lines)
    checkboxes = find_checkboxes(image_path)
    cb_boxes = [c["box"] for c in checkboxes]

    chrome_bottom = CHROME_TOP_FRAC_OF_WIDTH * w
    meta_x = META_X_FRAC_OF_WIDTH * w
    indent_x = INDENT_THRESHOLD_FRAC_OF_WIDTH * w

    rows = []
    tasks = []
    dropped = []
    notes = []
    used_cb = set()

    for r, members in enumerate(rows_idx):
        texts = [lines[i]["text"] for i in members]
        xs = [lines[i]["box"][0] for i in members]
        y_center = sum(lines[i]["box"][1] + lines[i]["box"][3] / 2.0 for i in members) / len(members)
        y0 = min(lines[i]["box"][1] for i in members)
        y1 = max(lines[i]["box"][1] + lines[i]["box"][3] for i in members)

        cb = None
        for ci, c in enumerate(checkboxes):
            if ci in used_cb:
                continue
            cy = c["box"][1] + c["box"][3] / 2.0
            if y0 - 8 <= cy <= y1 + 8:
                cb = c
                used_cb.add(ci)
                break

        if y_center < chrome_bottom:
            kind = "chrome"
        elif cb is not None:
            kind = "task"
        elif min(xs) > meta_x:
            kind = "meta"
        else:
            kind = "section"

        rows.append(
            {
                "index": r,
                "kind": kind,
                "line_indices": [raw_index[i] for i in members],
                "text": "".join(texts),
                "y_center": round(y_center, 2),
                "checkbox": cb,
            }
        )

        if kind != "task":
            dropped.append({"row": r, "kind": kind, "text": "".join(texts)})
            continue

        # A recognized text block that sits inside a detected checkbox is the
        # checkbox glyph itself, not task text.  PP-OCRv5 reads the filled box as
        # "V"/"√" on dark themes; without this rule the title becomes "V给妈妈打电话".
        text_members = [i for i in members if not _inside_any_checkbox(lines[i]["box"], cb_boxes)]
        if not text_members:
            text_members = members  # keep something for review instead of losing the row

        title_parts = [lines[i]["text"] for i in text_members if lines[i]["box"][0] <= meta_x]
        due_parts = [lines[i]["text"] for i in text_members if lines[i]["box"][0] > meta_x]
        needs = []
        if not title_parts:
            needs.append("task row has no left-aligned text")
        if len(text_members) > 2:
            needs.append("row contains %d text blocks; split/merge needs review" % len(text_members))
        title = "".join(title_parts)
        # anchor: the text block a reviewer would call "the task title"
        anchor = None
        if title_parts:
            widest = max(
                (i for i in text_members if lines[i]["box"][0] <= meta_x),
                key=lambda i: len(norm_text(lines[i]["text"])),
            )
            anchor = raw_index[widest]
        level = 0 if cb["box"][0] < indent_x else 1
        if level == 1 and not any(t["level"] == 0 for t in tasks):
            needs.append("indented task without a visible parent")
        parent = None
        if level == 1:
            for t in reversed(tasks):
                if t["level"] == 0:
                    parent = t["row"]
                    break
        tasks.append(
            {
                "row": r,
                "line_indices": [raw_index[i] for i in text_members],
                "anchor_line": anchor,
                "title": title,
                "checked": bool(cb["checked"]),
                "checkbox_box": cb["box"],
                "checkbox_fill": cb["fill"],
                "level": level,
                "parent": parent,
                "due": "".join(due_parts) or None,
                "needs_confirmation": needs,
            }
        )

    unmatched_cb = len(checkboxes) - len(used_cb)
    if unmatched_cb > 0:
        notes.append("%d gutter mark(s) matched no text row" % unmatched_cb)
    if noise:
        notes.append("%d recognized block(s) had no usable text" % len(noise))

    return {
        "schema": "wp17r2-draft/1",
        "id": image_id,
        "width": w,
        "height": h,
        "engine": ocr.get("engine", ""),
        "rows": rows,
        "tasks": tasks,
        "dropped": dropped,
        "noise_lines": [{"box": n["box"], "score": n["score"]} for n in noise],
        "notes": notes,
    }


def duplicate_hints(drafts: list[dict], image_paths: dict[str, str]) -> list[dict]:
    """Cheap, deterministic duplicate hints; never a silent merge."""
    out = []
    hashes = {}
    for d in drafts:
        p = image_paths[d["id"]]
        with open(p, "rb") as f:
            hashes[d["id"]] = hashlib.sha256(f.read()).hexdigest()

    ids = [d["id"] for d in drafts]
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = ids[i], ids[j]
            if hashes[a] == hashes[b]:
                out.append({"images": [a, b], "reason": "identical-bytes", "hint_only": True})
                continue
            ta = norm_text("".join(t["title"] for t in _tasks_of(drafts[i])))
            tb = norm_text("".join(t["title"] for t in _tasks_of(drafts[j])))
            if not ta or not tb:
                continue
            sa, sb = set(ta), set(tb)
            jac = len(sa & sb) / float(len(sa | sb))
            if jac >= 0.9:
                out.append(
                    {"images": [a, b], "reason": "char-jaccard=%.3f" % jac, "hint_only": True}
                )
    return out


def _tasks_of(d):
    return d["tasks"]


def main(argv: list[str]) -> int:
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True, help="raw OCR json (single image or batch)")
    ap.add_argument("--image", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    with open(a.raw, encoding="utf-8") as f:
        ocr = json.load(f)
    draft = build_draft(ocr, a.image, a.id)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(draft, f, ensure_ascii=False, indent=1)
    print(json.dumps({"id": a.id, "tasks": len(draft["tasks"]), "rows": len(draft["rows"])}))
    return 0


if __name__ == "__main__":
    import sys

    raise SystemExit(main(sys.argv[1:]))
