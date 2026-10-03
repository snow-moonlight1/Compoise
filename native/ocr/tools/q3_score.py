#!/usr/bin/env python3
"""Score raw recognition and an optional draft as separate stages.

Missed ground-truth lines add their full length to CER. Extra recognized
lines, empty outputs and failed images are counted beside CER, not folded
into a single accuracy number. Spaces stay in the strict figure.
"""
from __future__ import annotations

import json
from pathlib import Path

from q3_common import (
    SCHEMA_DRAFT,
    SCHEMA_RAW,
    SCHEMA_SCORE,
    Q3Error,
    levenshtein,
    match_lines,
    norm_text,
)
from q3_validate import validate_tree


def _ratio(edits: int, ref: int):
    return (edits / ref) if ref else None


def _line_cer(gt_lines, rec_lines):
    pairs, missed, extra = match_lines(gt_lines, rec_lines)
    stripped_edits = strict_edits = stripped_ref = strict_ref = 0
    diffs = []
    for gi, ri in pairs:
        gt_text = gt_lines[gi]["text"]
        hyp_text = rec_lines[ri].get("text") or ""
        strict_ref_text = norm_text(gt_text, True)
        stripped_ref_text = norm_text(gt_text, False)
        strict_edit = levenshtein(strict_ref_text, norm_text(hyp_text, True))
        stripped_edit = levenshtein(stripped_ref_text, norm_text(hyp_text, False))
        strict_edits += strict_edit
        stripped_edits += stripped_edit
        strict_ref += len(strict_ref_text)
        stripped_ref += len(stripped_ref_text)
        if strict_edit or stripped_edit:
            diffs.append({
                "kind": "mismatch",
                "gt": gt_text,
                "hyp": hyp_text,
                "edit_strict": strict_edit,
                "edit_stripped": stripped_edit,
            })
    for gi in missed:
        gt_text = gt_lines[gi]["text"]
        strict_len = len(norm_text(gt_text, True))
        stripped_len = len(norm_text(gt_text, False))
        strict_edits += strict_len
        stripped_edits += stripped_len
        strict_ref += strict_len
        stripped_ref += stripped_len
        diffs.append({"kind": "missed", "gt": gt_text})
    extra_strict = extra_stripped = 0
    for ri in extra:
        hyp_text = rec_lines[ri].get("text") or ""
        extra_strict += len(norm_text(hyp_text, True))
        extra_stripped += len(norm_text(hyp_text, False))
        diffs.append({"kind": "extra", "hyp": hyp_text})
    return {
        "pairs": pairs,
        "missed_lines": len(missed),
        "extra_lines": len(extra),
        "extra_chars_strict": extra_strict,
        "extra_chars_stripped": extra_stripped,
        "strict_edits": strict_edits,
        "strict_ref": strict_ref,
        "stripped_edits": stripped_edits,
        "stripped_ref": stripped_ref,
        "diffs": diffs,
    }


def _contains(date: str, text: str, keep_spaces: bool) -> bool:
    needle = norm_text(date, keep_spaces)
    return bool(needle) and needle in norm_text(text, keep_spaces)


def _match_tasks(gt_tasks, draft_tasks):
    used = set()
    pairs = []
    for gi, want in enumerate(gt_tasks):
        ref = norm_text(want["title"], False)
        choices = []
        for ai, got in enumerate(draft_tasks):
            if ai in used:
                continue
            hyp = norm_text(got.get("title") or "", False)
            choices.append((levenshtein(ref, hyp) / max(1, len(ref)), ai))
        if not choices:
            continue
        distance, ai = min(choices)
        if distance <= 0.35:
            used.add(ai)
            pairs.append((gi, ai))
    return pairs


def _draft_case(case, draft_tasks):
    gt_tasks = case["tasks"]
    pairs = _match_tasks(gt_tasks, draft_tasks)
    mapping = dict(pairs)
    checked = parent = 0
    date_strict = date_stripped = date_total = 0
    for gi, ai in pairs:
        want, got = gt_tasks[gi], draft_tasks[ai]
        if bool(want["checked"]) == bool(got.get("checked")):
            checked += 1
        expected = want["parent"]
        actual = got.get("parentId")
        if expected is None:
            parent += actual is None
        elif expected in {gt_tasks[item]["id"]: item for item in mapping}:
            parent_index = {gt_tasks[item]["id"]: item for item in mapping}[expected]
            parent_draft = draft_tasks[mapping[parent_index]].get("id")
            parent += actual == parent_draft
        date = want.get("date")
        if date:
            date_total += 1
            title = got.get("title") or ""
            date_strict += _contains(date, title, True)
            date_stripped += _contains(date, title, False)
    titles = [norm_text(task["title"], False) for task in gt_tasks]
    ambiguous = sum(1 for title in titles if titles.count(title) > 1)
    return {
        "gt_tasks": len(gt_tasks),
        "draft_tasks": len(draft_tasks),
        "matched_tasks": len(pairs),
        "missed_tasks": len(gt_tasks) - len(pairs),
        "extra_tasks": len(draft_tasks) - len(pairs),
        "checked_correct": checked,
        "parent_correct": parent,
        "date_strict": date_strict,
        "date_stripped": date_stripped,
        "date_total": date_total,
        "ambiguous_titles": ambiguous,
    }


def _raw_dates(case, pairs, rec_lines):
    hyp_by_gt = {gi: rec_lines[ri].get("text") or "" for gi, ri in pairs}
    strict = stripped = total = 0
    for task in case["tasks"]:
        date = task.get("date")
        if not date:
            continue
        total += 1
        joined = "".join(hyp_by_gt.get(index, "") for index in task["line_indexes"])
        strict += _contains(date, joined, True)
        stripped += _contains(date, joined, False)
    return strict, stripped, total


def score_document(labels: dict, raw: dict, draft: dict | None) -> dict:
    if raw.get("schema") != SCHEMA_RAW:
        raise Q3Error("raw schema is not wp17-q3-raw/1")
    raw_images = {}
    for image in raw.get("images") or []:
        image_id = image.get("id")
        if image_id in raw_images:
            raise Q3Error(f"duplicate raw image id: {image_id}")
        raw_images[image_id] = image
    draft_images = None
    if draft is not None:
        if draft.get("schema") != SCHEMA_DRAFT:
            raise Q3Error("draft schema is not wp17-q3-draft/1")
        draft_images = {}
        for image in draft.get("images") or []:
            image_id = image.get("id")
            if image_id in draft_images:
                raise Q3Error(f"duplicate draft image id: {image_id}")
            draft_images[image_id] = image

    per_image = []
    totals = {key: 0 for key in (
        "strict_edits", "strict_ref", "stripped_edits", "stripped_ref",
        "missed_lines", "extra_lines", "extra_chars_strict", "extra_chars_stripped",
        "empty_images", "failed_images", "raw_date_strict", "raw_date_stripped", "raw_date_total",
    )}
    draft_totals = {key: 0 for key in (
        "gt_tasks", "draft_tasks", "matched_tasks", "missed_tasks", "extra_tasks",
        "checked_correct", "parent_correct", "date_strict", "date_stripped", "date_total",
        "ambiguous_titles",
    )}
    for case in labels["cases"]:
        image = raw_images.get(case["id"])
        error = ""
        if image is None:
            error = "missing raw image"
            rec_lines = []
        else:
            error = image.get("error") or ""
            rec_lines = image.get("lines") or []
        failed = bool(error)
        empty = (not failed) and len(case["lines"]) > 0 and len(rec_lines) == 0
        if failed:
            counted = {
                "missed_lines": 0, "extra_lines": 0, "extra_chars_strict": 0, "extra_chars_stripped": 0,
                "strict_edits": 0, "strict_ref": 0, "stripped_edits": 0, "stripped_ref": 0, "diffs": [],
                "pairs": [],
            }
            raw_date = (0, 0, 0)
        else:
            counted = _line_cer(case["lines"], rec_lines)
            raw_date = _raw_dates(case, counted["pairs"], rec_lines)
        row = {
            "id": case["id"],
            "failed": failed,
            "error": error,
            "empty": empty,
            "missed_lines": counted["missed_lines"],
            "extra_lines": counted["extra_lines"],
            "extra_chars_strict": counted["extra_chars_strict"],
            "strict_edits": counted["strict_edits"],
            "strict_ref": counted["strict_ref"],
            "stripped_edits": counted["stripped_edits"],
            "stripped_ref": counted["stripped_ref"],
            "date_strict": raw_date[0],
            "date_stripped": raw_date[1],
            "date_total": raw_date[2],
            "diffs": counted["diffs"],
        }
        if draft_images is not None:
            draft_case = draft_images.get(case["id"])
            if draft_case is None:
                raise Q3Error(f"missing draft image: {case['id']}")
            draft_row = _draft_case(case, draft_case.get("tasks") or [])
            row["draft"] = draft_row
            for key in draft_totals:
                draft_totals[key] += draft_row[key]
        per_image.append(row)
        if not failed:
            for key in ("strict_edits", "strict_ref", "stripped_edits", "stripped_ref",
                        "missed_lines", "extra_lines", "extra_chars_strict", "extra_chars_stripped"):
                totals[key] += counted[key]
            totals["raw_date_strict"] += raw_date[0]
            totals["raw_date_stripped"] += raw_date[1]
            totals["raw_date_total"] += raw_date[2]
        totals["empty_images"] += int(empty)
        totals["failed_images"] += int(failed)

    report = {
        "schema": SCHEMA_SCORE,
        "dataset_id": labels["dataset_id"],
        "image_set_sha256": labels["image_set_sha256"],
        "font_sha256": labels["font"]["sha256"],
        "image_ids": [case["id"] for case in labels["cases"]],
        "real_screenshots": "unverified",
        "raw": {
            "strict": {"edits": totals["strict_edits"], "ref_chars": totals["strict_ref"],
                       "micro": _ratio(totals["strict_edits"], totals["strict_ref"])},
            "stripped": {"edits": totals["stripped_edits"], "ref_chars": totals["stripped_ref"],
                         "micro": _ratio(totals["stripped_edits"], totals["stripped_ref"])},
            "missed_lines": totals["missed_lines"],
            "extra_lines": totals["extra_lines"],
            "extra_chars_strict": totals["extra_chars_strict"],
            "empty_images": totals["empty_images"],
            "failed_images": totals["failed_images"],
            "date_retained_strict": {"hit": totals["raw_date_strict"], "total": totals["raw_date_total"]},
            "date_retained_stripped": {"hit": totals["raw_date_stripped"], "total": totals["raw_date_total"]},
        },
        "draft": {"supplied": False},
        "per_image": per_image,
    }
    if draft_images is not None:
        matched = draft_totals["matched_tasks"]
        report["draft"] = {
            "supplied": True,
            "gt_tasks": draft_totals["gt_tasks"],
            "matched_tasks": matched,
            "missed_tasks": draft_totals["missed_tasks"],
            "extra_tasks": draft_totals["extra_tasks"],
            "checked": {"correct": draft_totals["checked_correct"], "total": matched},
            "parent": {"correct": draft_totals["parent_correct"], "total": matched},
            "date_retained_strict": {"hit": draft_totals["date_strict"], "total": draft_totals["date_total"]},
            "date_retained_stripped": {"hit": draft_totals["date_stripped"], "total": draft_totals["date_total"]},
            "ambiguous_titles": draft_totals["ambiguous_titles"],
        }
    return report


def failure_reasons(report: dict, fail_on_empty: bool) -> list[str]:
    reasons = []
    if report["raw"]["failed_images"]:
        reasons.append(f"failed images: {report['raw']['failed_images']}")
    if fail_on_empty and report["raw"]["empty_images"]:
        reasons.append(f"empty images: {report['raw']['empty_images']}")
    return reasons


def load_json(path: Path, label: str) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise Q3Error(f"cannot read {label}: {path}") from exc


def score_labels(labels_dir: Path, raw: dict, draft: dict | None) -> dict:
    problems = validate_tree(labels_dir)
    if problems:
        raise Q3Error("bad ground truth:\n" + "\n".join(problems))
    labels = load_json(labels_dir / "labels.json", "labels")
    return score_document(labels, raw, draft)
