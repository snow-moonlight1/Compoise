#!/usr/bin/env python3
"""Compare two score reports. Different datasets fail instead of looking equal."""
from __future__ import annotations


def compare_reports(left: dict, right: dict, max_strict_edit_increase: int | None = None):
    problems = []
    if left.get("schema") != "wp17-q3-score/1":
        problems.append("left schema is not a Q3 score report")
    if right.get("schema") != "wp17-q3-score/1":
        problems.append("right schema is not a Q3 score report")
    if problems:
        return problems, None
    if left.get("dataset_id") != right.get("dataset_id"):
        problems.append("dataset_id differs, so this is not the same对照")
    if left.get("font_sha256") != right.get("font_sha256"):
        problems.append("font sha256 differs")
    if left.get("image_ids") != right.get("image_ids"):
        problems.append("image id set differs")
    left_draft = bool((left.get("draft") or {}).get("supplied"))
    right_draft = bool((right.get("draft") or {}).get("supplied"))
    if left_draft != right_draft:
        problems.append("draft stage presence differs")
    if problems:
        return problems, None
    delta = {
        "strict_edits": right["raw"]["strict"]["edits"] - left["raw"]["strict"]["edits"],
        "stripped_edits": right["raw"]["stripped"]["edits"] - left["raw"]["stripped"]["edits"],
        "missed_lines": right["raw"]["missed_lines"] - left["raw"]["missed_lines"],
        "extra_lines": right["raw"]["extra_lines"] - left["raw"]["extra_lines"],
        "empty_images": right["raw"]["empty_images"] - left["raw"]["empty_images"],
        "failed_images": right["raw"]["failed_images"] - left["raw"]["failed_images"],
    }
    if left_draft:
        delta["missed_tasks"] = right["draft"]["missed_tasks"] - left["draft"]["missed_tasks"]
        delta["extra_tasks"] = right["draft"]["extra_tasks"] - left["draft"]["extra_tasks"]
    if max_strict_edit_increase is not None and delta["strict_edits"] > max_strict_edit_increase:
        problems.append(
            f"strict edits increased by {delta['strict_edits']}, limit is {max_strict_edit_increase}"
        )
    return problems, delta
