#!/usr/bin/env python3
"""Shared helpers for the WP17-R2 harness (labels, boxes, image-side features).

Kept deliberately small: text scoring, structure scoring and the draft adapter
all import from here so that normalisation rules cannot drift apart.
"""
from __future__ import annotations

import json
import os
import platform
import unicodedata

# numpy / Pillow are imported lazily: run_bench.py must be importable with a bare
# stdlib interpreter so the Linux and Android legs can produce raw engine output
# without installing the imaging stack.  Only image-side helpers need them.

HERE = os.path.dirname(os.path.abspath(__file__))
R2 = os.path.dirname(HERE)
SAMPLES = os.path.join(R2, "samples")
LABELS = os.path.join(SAMPLES, "labels.json")
RESULTS = os.path.join(R2, "results")


def asset_root() -> str:
    if os.environ.get("WP17R2_ASSETS"):
        return os.path.abspath(os.environ["WP17R2_ASSETS"])
    if platform.system() == "Windows":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        return os.path.join(base, "wp17r2-assets")
    return os.path.expanduser("~/.cache/wp17r2-assets")


# --------------------------------------------------------------------- text
def norm_text(s: str, keep_spaces: bool = False) -> str:
    """NFKC, drop control chars; optionally keep single spaces as word breaks.

    PP-OCRv5 mobile does not emit inter-word spaces for CJK text while Tesseract
    does, so the headline metric is whitespace-insensitive.  The strict variant
    is reported separately for the Latin-only cases.
    """
    s = unicodedata.normalize("NFKC", s)
    s = "".join(ch for ch in s if unicodedata.category(ch)[0] != "C")
    s = s.replace("\u3000", " ")
    if keep_spaces:
        return " ".join(s.split())
    return "".join(s.split())


def levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def cer(ref: str, hyp: str, keep_spaces: bool = False) -> float:
    r = norm_text(ref, keep_spaces)
    h = norm_text(hyp, keep_spaces)
    if not r:
        return 0.0 if not h else 1.0
    return levenshtein(r, h) / len(r)


# --------------------------------------------------------------------- boxes
def box_xyxy(b):
    return (b[0], b[1], b[0] + b[2], b[1] + b[3])


def box_iou(a, b) -> float:
    ax0, ay0, ax1, ay1 = box_xyxy(a)
    bx0, by0, bx1, by1 = box_xyxy(b)
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = max(0.0, ix1 - ix0), max(0.0, iy1 - iy0)
    inter = iw * ih
    if inter <= 0:
        return 0.0
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


def box_center(b):
    return (b[0] + b[2] / 2.0, b[1] + b[3] / 2.0)


def center_in(inner, outer, slack=0.0) -> bool:
    cx, cy = box_center(inner)
    ox0, oy0, ox1, oy1 = box_xyxy(outer)
    return (ox0 - slack) <= cx <= (ox1 + slack) and (oy0 - slack) <= cy <= (oy1 + slack)


def match_lines(gt_lines: list[dict], rec_lines: list[dict], slack_frac: float = 0.6):
    """Greedy one-to-one matching between ground-truth and recognized lines.

    A recognized line may match a ground-truth line when its centre falls inside
    the ground-truth box grown by ``slack_frac * gt_height`` vertically and when
    the pair has non-zero IoU.  Candidates are taken in descending IoU order.

    Returns ``(pairs, unmatched_gt, unmatched_rec, duplicates)`` where ``pairs``
    is a list of ``(gt_index, rec_index)`` and ``duplicates`` maps a recognized
    index to the number of ground-truth lines that wanted it (that is a merge
    error: two GT lines collapsed into one recognized line).
    """
    cands = []
    for gi, g in enumerate(gt_lines):
        gb = g["box"]
        slack = slack_frac * gb[3]
        for ri, r in enumerate(rec_lines):
            rb = r["box"]
            iou = box_iou(gb, rb)
            if iou <= 0.0:
                continue
            if not center_in(rb, gb, slack=slack):
                continue
            cands.append((iou, gi, ri))
    cands.sort(reverse=True)

    used_g, used_r = set(), set()
    pairs = []
    wanted = {}
    for iou, gi, ri in cands:
        wanted.setdefault(ri, []).append(gi)
        if gi in used_g or ri in used_r:
            continue
        used_g.add(gi)
        used_r.add(ri)
        pairs.append((gi, ri))
    pairs.sort()
    unmatched_gt = [i for i in range(len(gt_lines)) if i not in used_g]
    unmatched_rec = [i for i in range(len(rec_lines)) if i not in used_r]
    duplicates = {ri: len(v) for ri, v in wanted.items() if len(v) > 1 and ri in used_r}
    return pairs, unmatched_gt, unmatched_rec, duplicates


# -------------------------------------------------------------------- labels
def load_labels() -> dict:
    with open(LABELS, encoding="utf-8") as f:
        return json.load(f)


def case_by_id(doc: dict, cid: str) -> dict:
    for c in doc["cases"]:
        if c["id"] == cid:
            return c
    raise KeyError(cid)


# ------------------------------------------------------- image side features
def load_gray(path: str):
    import numpy as np
    from PIL import Image

    with Image.open(path) as im:
        return np.asarray(im.convert("L"), dtype=np.int16)


def _runs(mask_row):
    import numpy as np

    if not mask_row.any():
        return []
    padded = np.concatenate(([0], mask_row.view(np.int8), [0]))
    edges = np.flatnonzero(np.diff(padded))
    return list(zip(edges[0::2].tolist(), edges[1::2].tolist()))


def find_checkboxes(img_path: str, max_gutter_frac: float = 0.25, ink_delta: int = 40):
    """Locate checkbox-sized square marks in the left gutter, plus their state.

    This is an *adapter-side* heuristic: it runs on the raw image and is
    independent of which OCR engine produced the text.  It is reported as part
    of the "task structure" score, never as an OCR text result.
    """
    import numpy as np

    gray = load_gray(img_path)
    h, w = gray.shape
    gutter = int(w * max_gutter_frac)
    strip = gray[:, :gutter]
    bg = int(np.median(strip))
    ink = np.abs(strip - bg) > ink_delta

    runs = []  # (y, x0, x1)
    for y in range(h):
        for x0, x1 in _runs(ink[y]):
            runs.append((y, x0, x1))
    if not runs:
        return []

    parent = list(range(len(runs)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i, j):
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[rj] = ri

    runs.sort()
    by_row: dict[int, list[int]] = {}
    for idx, (y, _, _) in enumerate(runs):
        by_row.setdefault(y, []).append(idx)
    for y, cur in by_row.items():
        prev = by_row.get(y - 1)
        if not prev:
            continue
        for i in cur:
            for j in prev:
                if runs[i][1] < runs[j][2] and runs[j][1] < runs[i][2]:
                    union(i, j)

    groups: dict[int, dict] = {}
    for idx, (y, x0, x1) in enumerate(runs):
        r = find(idx)
        g = groups.setdefault(r, {"x0": x0, "x1": x1, "y0": y, "y1": y, "px": 0})
        g["x0"] = min(g["x0"], x0)
        g["x1"] = max(g["x1"], x1)
        g["y0"] = min(g["y0"], y)
        g["y1"] = max(g["y1"], y)
        g["px"] += x1 - x0

    out = []
    for g in groups.values():
        bw = g["x1"] - g["x0"] + 1
        bh = g["y1"] - g["y0"] + 1
        if not (0.022 * w <= bw <= 0.075 * w and 0.022 * w <= bh <= 0.075 * w):
            continue
        if max(bw, bh) > 1.6 * min(bw, bh):
            continue
        # A checkbox is an isolated mark: it must have clear background on both
        # sides inside its own row band.  Without this, the first glyph of a CJK
        # word ("今", "待", "ス") is a perfect square and gets mistaken for a box.
        gap = max(6, int(round(0.35 * bw)))
        rows_band = ink[g["y0"] : g["y1"] + 1]
        right = g["x1"] + 1
        if right < gutter and rows_band[:, right : min(gutter, right + gap)].any():
            continue
        left = g["x0"]
        if left - gap > 0 and rows_band[:, max(0, left - gap) : left].any():
            continue
        fill = g["px"] / float(bw * bh)
        out.append(
            {
                "box": [float(g["x0"]), float(g["y0"]), float(bw), float(bh)],
                "fill": round(fill, 3),
                "checked": fill > 0.5,
            }
        )
    out.sort(key=lambda c: c["box"][1])
    return out
