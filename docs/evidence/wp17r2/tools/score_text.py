#!/usr/bin/env python3
"""Stage 1 scoring: how well did the engine read the pixels?

Nothing in here looks at task structure, checkboxes, indentation or parents.
Those belong to score_structure.py on purpose: WP17-R2 must be able to say
"the text was fine but the task model came out wrong" and vice versa.

Definitions
-----------
CER          per-image edit distance over the ground-truth text divided by the
             ground-truth character count.  Missed ground-truth lines contribute
             their full length; extra recognized lines are *not* charged here
             (they are reported separately as spurious) so that "read badly" and
             "invented text" stay distinguishable.
strict CER   same, but with single spaces kept - only meaningful for the Latin
             corpus, PP-OCRv5 mobile does not emit inter-word spaces at all.
"""
from __future__ import annotations

from wp17r2lib import levenshtein, match_lines, norm_text

TASK_ROLES = {"task"}
DECOR_ROLES = {"status_clock", "app_title", "app_meta", "section_header", "due_date"}


def score_image(case: dict, rec_lines: list[dict]) -> dict:
    gt = case["lines"]
    pairs, un_gt, un_rec, merges = match_lines(gt, rec_lines)

    dist = 0
    ref_chars = 0
    dist_strict = 0
    ref_chars_strict = 0
    exact_matched = 0
    role_ref = {}
    role_dist = {}
    per_line = []

    for gi, ri in pairs:
        g, r = gt[gi], rec_lines[ri]
        ref = norm_text(g["text"])
        hyp = norm_text(r["text"])
        d = levenshtein(ref, hyp)
        dist += d
        ref_chars += len(ref)
        ds = levenshtein(norm_text(g["text"], True), norm_text(r["text"], True))
        dist_strict += ds
        ref_chars_strict += len(norm_text(g["text"], True))
        role = g["role"]
        role_ref[role] = role_ref.get(role, 0) + len(ref)
        role_dist[role] = role_dist.get(role, 0) + d
        if d == 0:
            exact_matched += 1
        else:
            per_line.append(
                {
                    "kind": "mismatch",
                    "role": role,
                    "gt_index": gi,
                    "rec_index": ri,
                    "gt_box": g["box"],
                    "rec_box": r["box"],
                    "ref": g["text"],
                    "hyp": r["text"],
                    "edit_distance": d,
                }
            )

    for gi in un_gt:
        g = gt[gi]
        ref = norm_text(g["text"])
        dist += len(ref)
        ref_chars += len(ref)
        dist_strict += len(norm_text(g["text"], True))
        ref_chars_strict += len(norm_text(g["text"], True))
        role = g["role"]
        role_ref[role] = role_ref.get(role, 0) + len(ref)
        role_dist[role] = role_dist.get(role, 0) + len(ref)
        per_line.append(
            {"kind": "missed", "role": role, "gt_index": gi, "gt_box": g["box"], "ref": g["text"], "hyp": ""}
        )

    spurious = []
    for ri in un_rec:
        r = rec_lines[ri]
        spurious.append(
            {
                "kind": "spurious",
                "rec_index": ri,
                "rec_box": r["box"],
                "hyp": r["text"],
                "score": r.get("score", 0.0),
                "chars": len(norm_text(r["text"])),
            }
        )
        per_line.append(spurious[-1])

    for ri, n in merges.items():
        per_line.append(
            {
                "kind": "merged",
                "rec_index": ri,
                "rec_box": rec_lines[ri]["box"],
                "hyp": rec_lines[ri]["text"],
                "gt_merged": n,
            }
        )

    task_ref = sum(v for k, v in role_ref.items() if k in TASK_ROLES)
    task_dist = sum(v for k, v in role_dist.items() if k in TASK_ROLES)
    deco_ref = sum(v for k, v in role_ref.items() if k in DECOR_ROLES)
    deco_dist = sum(v for k, v in role_dist.items() if k in DECOR_ROLES)

    return {
        "id": case["id"],
        "gt_lines": len(gt),
        "rec_lines": len(rec_lines),
        "matched": len(pairs),
        "missed_gt": len(un_gt),
        "spurious_rec": len(un_rec),
        "spurious_chars": sum(s["chars"] for s in spurious),
        "merged_gt_into_one_rec": sum(1 for _ in merges),
        "edit_distance": dist,
        "ref_chars": ref_chars,
        "cer": (dist / ref_chars) if ref_chars else 0.0,
        "cer_strict": (dist_strict / ref_chars_strict) if ref_chars_strict else 0.0,
        "line_exact_rate": (exact_matched / len(gt)) if gt else 0.0,
        "task_line_cer": (task_dist / task_ref) if task_ref else None,
        "decor_line_cer": (deco_dist / deco_ref) if deco_ref else None,
        "diffs": per_line,
    }


def aggregate(rows: list[dict]) -> dict:
    if not rows:
        return {}
    ref = sum(r["ref_chars"] for r in rows)
    dist = sum(r["edit_distance"] for r in rows)
    return {
        "images": len(rows),
        "cer_micro": (dist / ref) if ref else 0.0,
        "cer_macro": sum(r["cer"] for r in rows) / len(rows),
        "ref_chars": ref,
        "edit_distance": dist,
        "missed_gt_lines": sum(r["missed_gt"] for r in rows),
        "spurious_rec_lines": sum(r["spurious_rec"] for r in rows),
        "spurious_chars": sum(r["spurious_chars"] for r in rows),
        "merged_gt_lines": sum(r["merged_gt_into_one_rec"] for r in rows),
        "line_exact_rate_macro": sum(r["line_exact_rate"] for r in rows) / len(rows),
    }
