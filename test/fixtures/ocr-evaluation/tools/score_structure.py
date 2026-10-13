#!/usr/bin/env python3
"""Stage 2 scoring: can the result be turned into a correct *task* structure?

Deliberately independent of score_text.py.  A draft can have perfect characters
and still be useless (wrong parents, invented tasks from the app bar), and the
WP17 acceptance criteria care about the second axis as much as the first.

Scored here:
  task recall / precision  - was every real to-do row picked up, and how many
                             non-task rows (status bar, app bar, section header,
                             due-date chip) leaked in as tasks?
  checkbox state           - adapter-side gutter scan vs ground truth
  parent edges             - indentation -> parent link, vs ground truth
  due text                 - right-aligned chip attached to the right task
  reading order            - engine-native order, post-adapter order, and the
                             final task sequence, each by exact match and by
                             normalised Kendall tau distance
"""
from __future__ import annotations

from wp17r2lib import match_lines, norm_text


def _gt_lines_reading_order(case: dict) -> list[dict]:
    lines = list(case["lines"])
    return sorted(lines, key=lambda l: (l["box"][1] + l["box"][3] / 2.0, l["box"][0]))


def _gt_tasks(case: dict) -> list[dict]:
    """Ground-truth task rows in reading order, with parent/due/checked."""
    ordered = _gt_lines_reading_order(case)
    tasks = []
    seen = set()
    for ln in ordered:
        if ln["role"] != "task" or ln["task_key"] in seen:
            continue
        seen.add(ln["task_key"])
        tasks.append(ln)
    # parent = nearest preceding level-0 task
    parents = {}
    last_level0 = None
    for t in tasks:
        if t["indent"] == 0:
            last_level0 = t["task_key"]
            parents[t["task_key"]] = None
        else:
            parents[t["task_key"]] = last_level0
    # due = right-aligned chip whose band overlaps the task line band
    for t in tasks:
        ty0, ty1 = t["box"][1], t["box"][1] + t["box"][3]
        due = None
        for ln in ordered:
            if ln["role"] != "due_date":
                continue
            cy = ln["box"][1] + ln["box"][3] / 2.0
            if ty0 - 10 <= cy <= ty1 + 10:
                due = ln["text"]
                break
        t["_parent"] = parents[t["task_key"]]
        t["_due"] = due
    return tasks


def _kendall_normalised(seq_a: list, seq_b: list) -> float:
    """0.0 = identical order, 1.0 = fully reversed, over the shared items."""
    common = [x for x in seq_a if x in set(seq_b)]
    pos = {x: i for i, x in enumerate(seq_b)}
    ranks = [pos[x] for x in common]
    n = len(ranks)
    if n < 2:
        return 0.0
    inv = 0
    for i in range(n):
        for j in range(i + 1, n):
            if ranks[i] > ranks[j]:
                inv += 1
    return inv / (n * (n - 1) / 2.0)


def score_image(case: dict, rec_lines: list[dict], draft: dict) -> dict:
    gt_all = case["lines"]
    ordered_gt = _gt_lines_reading_order(case)
    pairs, un_gt, un_rec, _ = match_lines(gt_all, rec_lines)
    gt2rec = {gi: ri for gi, ri in pairs}
    rec2gt = {ri: gi for gi, ri in pairs}

    gt_tasks = _gt_tasks(case)
    gt_task_by_key = {t["task_key"]: t for t in gt_tasks}
    gt_task_order = [t["task_key"] for t in gt_tasks]

    # --- map every GT line to its position in the ground-truth reading order ---
    order_index = {id(l): i for i, l in enumerate(ordered_gt)}

    # --- predicted tasks -------------------------------------------------------
    pred_tasks = draft["tasks"]
    pred_gt_keys = []
    spurious = []
    details = []
    for pt in pred_tasks:
        rec_idx = pt.get("anchor_line")
        if rec_idx is None and pt["line_indices"]:
            rec_idx = pt["line_indices"][0]
        gi = rec2gt.get(rec_idx) if rec_idx is not None else None
        gt_line = gt_all[gi] if gi is not None else None
        if gt_line is not None and gt_line["role"] == "task":
            pred_gt_keys.append(gt_line["task_key"])
            details.append(
                {
                    "kind": "task",
                    "row": pt["row"],
                    "title": pt["title"],
                    "gt_title": gt_line["text"],
                    "gt_key": gt_line["task_key"],
                    "checked": pt["checked"],
                    "gt_checked": gt_line["checked"],
                    "level": pt["level"],
                    "gt_indent": gt_line["indent"],
                    "parent_key": gt_line["_parent"],
                    "due": pt["due"],
                    "gt_due": gt_line["_due"],
                    "needs_confirmation": pt["needs_confirmation"],
                }
            )
        else:
            spurious.append(
                {
                    "row": pt["row"],
                    "title": pt["title"],
                    "matched_gt_role": gt_line["role"] if gt_line is not None else None,
                    "matched_gt_text": gt_line["text"] if gt_line is not None else None,
                    "reason": "no matching image line" if gt_line is None else "matched non-task line",
                }
            )

    hits = set(pred_gt_keys)
    gt_keys = set(gt_task_order)
    matched_gt = hits & gt_keys
    recall = len(matched_gt) / len(gt_task_order) if gt_task_order else 1.0
    precision = len(matched_gt) / len(pred_tasks) if pred_tasks else (1.0 if not gt_task_order else 0.0)

    # parent / due / checked accuracy over the matched tasks
    correct_checked = correct_parent = correct_due = 0
    parent_total = due_total = 0
    pred_key_order = []
    for d in details:
        if d["gt_key"] not in matched_gt:
            continue
        if bool(d["checked"]) == bool(d["gt_checked"]):
            correct_checked += 1
        if d["gt_indent"] == 1:
            parent_total += 1
            pred_parent_key = None
            # find the previous predicted task's gt key (level 0)
            for prev in reversed(details[: details.index(d)]):
                if prev["gt_key"] in matched_gt and prev["level"] == 0:
                    pred_parent_key = prev["gt_key"]
                    break
            if pred_parent_key == d["parent_key"]:
                correct_parent += 1
        if d["gt_due"] is not None:
            due_total += 1
            if norm_text(d["due"] or "") == norm_text(d["gt_due"]):
                correct_due += 1
        pred_key_order.append(d["gt_key"])

    # --- reading order ---------------------------------------------------------
    # (a) engine-native order of all recognized lines that matched a GT line
    engine_seq = [gt_all[rec2gt[ri]]["task_key"] if gt_all[rec2gt[ri]]["role"] == "task"
                  else "L%d" % rec2gt[ri]
                  for ri in range(len(rec_lines)) if ri in rec2gt]
    gt_seq_all = ["L%d" % gi for gi in range(len(gt_all))]
    gt_seq_all_ordered = ["L%d" % order_index[id(l)] for l in ordered_gt]
    engine_order_ok = engine_seq == [s for s in gt_seq_all_ordered if s in set(engine_seq)]

    # (b) order after the adapter's row grouping, over the same line set
    adapter_seq = []
    for row in draft["rows"]:
        for li in sorted(row["line_indices"], key=lambda i: rec_lines[i]["box"][0]):
            if li in rec2gt:
                adapter_seq.append("L%d" % rec2gt[li])
    adapter_order_ok = adapter_seq == [s for s in gt_seq_all_ordered if s in set(adapter_seq)]

    # (c) final task order
    task_order_ok = pred_key_order == [k for k in gt_task_order if k in set(pred_key_order)]

    return {
        "id": case["id"],
        "gt_tasks": len(gt_task_order),
        "pred_tasks": len(pred_tasks),
        "true_positive": len(matched_gt),
        "missing": len(gt_keys - matched_gt),
        "spurious": len(spurious),
        "spurious_matched_non_task": sum(1 for s in spurious if s["matched_gt_role"] is not None),
        "task_recall": recall,
        "task_precision": precision,
        "checked_accuracy": (correct_checked / len(matched_gt)) if matched_gt else None,
        "parent_accuracy": (correct_parent / parent_total) if parent_total else None,
        "parent_total": parent_total,
        "due_accuracy": (correct_due / due_total) if due_total else None,
        "due_total": due_total,
        "order_engine_native_exact": engine_order_ok,
        "order_after_adapter_exact": adapter_order_ok,
        "order_task_exact": task_order_ok,
        "order_task_kendall": _kendall_normalised(pred_key_order, gt_task_order),
        "needs_confirmation": sum(1 for d in details if d["needs_confirmation"]),
        "details": details,
        "spurious_detail": spurious,
    }


def aggregate(rows: list[dict]) -> dict:
    if not rows:
        return {}
    gt = sum(r["gt_tasks"] for r in rows)
    pred = sum(r["pred_tasks"] for r in rows)
    tp = sum(r["true_positive"] for r in rows)
    acc = [r["checked_accuracy"] for r in rows if r["checked_accuracy"] is not None]
    par = [r["parent_accuracy"] for r in rows if r["parent_accuracy"] is not None]
    due = [r["due_accuracy"] for r in rows if r["due_accuracy"] is not None]
    return {
        "images": len(rows),
        "gt_tasks": gt,
        "pred_tasks": pred,
        "true_positive": tp,
        "task_recall_micro": (tp / gt) if gt else 0.0,
        "task_precision_micro": (tp / pred) if pred else 0.0,
        "spurious_total": sum(r["spurious"] for r in rows),
        "spurious_matched_non_task": sum(r["spurious_matched_non_task"] for r in rows),
        "checked_accuracy_macro": (sum(acc) / len(acc)) if acc else None,
        "parent_accuracy_macro": (sum(par) / len(par)) if par else None,
        "due_accuracy_macro": (sum(due) / len(due)) if due else None,
        "order_engine_native_exact_images": sum(1 for r in rows if r["order_engine_native_exact"]),
        "order_after_adapter_exact_images": sum(1 for r in rows if r["order_after_adapter_exact"]),
        "order_task_exact_images": sum(1 for r in rows if r["order_task_exact"]),
        "order_task_kendall_macro": sum(r["order_task_kendall"] for r in rows) / len(rows),
        "needs_confirmation_total": sum(r["needs_confirmation"] for r in rows),
    }
