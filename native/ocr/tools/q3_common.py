#!/usr/bin/env python3
"""Shared definitions for the WP17-Q3 quality gate.

Text normalisation matches the WP17-R2 scorer: NFKC, drop controls, map
U+3000 to ASCII space, then either keep single spaces or remove them all.
The locked 30-title fixture is 55/504 strict and 0/449 with spaces removed.
This module does not insert spaces into recognizer output.
"""
from __future__ import annotations

import hashlib
import struct
import unicodedata
from pathlib import Path


SCHEMA_LABELS = "wp17-q3-synthetic/1"
SCHEMA_RAW = "wp17-q3-raw/1"
SCHEMA_DRAFT = "wp17-q3-draft/1"
SCHEMA_SCORE = "wp17-q3-score/1"
SCHEMA_DICT = "wp17-q3-dict-probe/1"
SEED = 17217
REPO = Path(__file__).resolve().parents[3]
LOCK_PATH = REPO / "native" / "ocr" / "tools" / "models.lock.json"

MODEL_FILES = (
    ("PP_OCRv5_mobile_det.ncnn.param", "files", "ncnn-official/PP_OCRv5_mobile_det.ncnn.param"),
    ("PP_OCRv5_mobile_det.ncnn.bin", "files", "ncnn-official/PP_OCRv5_mobile_det.ncnn.bin"),
    ("PP_OCRv5_mobile_rec.ncnn.param", "files", "ncnn-official/PP_OCRv5_mobile_rec.ncnn.param"),
    ("PP_OCRv5_mobile_rec.ncnn.bin", "files", "ncnn-official/PP_OCRv5_mobile_rec.ncnn.bin"),
    ("ppocrv5_dict.txt", "dependencies", "ncnn/ppocrv5_dict.txt"),
)


class Q3Error(Exception):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def require_outside_repo(path: Path) -> Path:
    resolved = path.resolve()
    if resolved == REPO or REPO in resolved.parents:
        raise Q3Error(f"output must stay outside the checkout: {resolved}")
    return resolved


def norm_text(value: str, keep_spaces: bool = False) -> str:
    value = unicodedata.normalize("NFKC", value)
    value = "".join(ch for ch in value if unicodedata.category(ch)[0] != "C")
    value = value.replace("\u3000", " ")
    if keep_spaces:
        return " ".join(value.split())
    return "".join(value.split())


def levenshtein(left: str, right: str) -> int:
    if left == right:
        return 0
    if not left:
        return len(right)
    if not right:
        return len(left)
    previous = list(range(len(right) + 1))
    for i, ca in enumerate(left, 1):
        current = [i]
        for j, cb in enumerate(right, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def box_iou(a, b) -> float:
    ax0, ay0, ax1, ay1 = a[0], a[1], a[0] + a[2], a[1] + a[3]
    bx0, by0, bx1, by1 = b[0], b[1], b[0] + b[2], b[1] + b[3]
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    if inter <= 0:
        return 0.0
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


def center_in(inner, outer, slack: float = 0.0) -> bool:
    cx = inner[0] + inner[2] / 2.0
    cy = inner[1] + inner[3] / 2.0
    return (outer[0] - slack) <= cx <= (outer[0] + outer[2] + slack) and (
        outer[1] - slack
    ) <= cy <= (outer[1] + outer[3] + slack)


def match_lines(gt_lines, rec_lines, slack_frac: float = 0.6):
    """Greedy one-to-one match. Extra lines stay unmatched and are not CER."""
    candidates = []
    for gi, gt in enumerate(gt_lines):
        slack = slack_frac * gt["box"][3]
        for ri, rec in enumerate(rec_lines):
            iou = box_iou(gt["box"], rec["box"])
            if iou <= 0.0 or not center_in(rec["box"], gt["box"], slack):
                continue
            candidates.append((iou, gi, ri))
    candidates.sort(reverse=True)
    used_gt, used_rec = set(), set()
    pairs = []
    wanted = {}
    for _iou, gi, ri in candidates:
        wanted.setdefault(ri, []).append(gi)
        if gi in used_gt or ri in used_rec:
            continue
        used_gt.add(gi)
        used_rec.add(ri)
        pairs.append((gi, ri))
    pairs.sort()
    unmatched_gt = [i for i in range(len(gt_lines)) if i not in used_gt]
    unmatched_rec = [i for i in range(len(rec_lines)) if i not in used_rec]
    return pairs, unmatched_gt, unmatched_rec


def png_size(data: bytes):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise Q3Error("file is not a PNG with an IHDR")
    return struct.unpack(">II", data[16:24])


def font_license_excerpt(data: bytes) -> str:
    for encoding in ("utf-8", "utf-16be", "utf-16le"):
        text = data.decode(encoding, "ignore")
        marker = text.find("SIL Open Font License")
        if marker >= 0:
            return " ".join(text[marker:marker + 120].split())
    raise Q3Error("font file does not contain a SIL Open Font License string")


def load_lock() -> dict:
    import json
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def expected_model_entry(lock: dict, section: str, key: str) -> dict:
    try:
        return lock[section][key]
    except KeyError as exc:
        raise Q3Error(f"models.lock.json has no {section}/{key}") from exc


def bundle_problems(assets: Path, lock: dict | None = None) -> list[str]:
    lock = load_lock() if lock is None else lock
    problems = []
    root = assets / "ncnn"
    for name, section, key in MODEL_FILES:
        entry = expected_model_entry(lock, section, key)
        path = root / name
        if not path.is_file():
            problems.append(f"missing model file: {name}")
            continue
        digest = sha256_file(path)
        if digest != entry["sha256"]:
            problems.append(f"model sha256 mismatch: {name}")
        if "bytes" in entry and path.stat().st_size != entry["bytes"]:
            problems.append(f"model size mismatch: {name}")
        licence = entry.get("licence") or entry.get("license")
        if section == "files" and licence != "apache-2.0":
            problems.append(f"model licence is not apache-2.0: {name}")
    return problems
