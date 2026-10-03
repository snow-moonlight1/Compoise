#!/usr/bin/env python3
"""Fail closed on labels that cannot be scored."""
from __future__ import annotations

import json
import re
from pathlib import Path

from q3_common import SCHEMA_LABELS, Q3Error, png_size, sha256_file


_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def _integer(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _box_inside(box, width, height, label: str, problems: list[str]) -> None:
    if not isinstance(box, list) or len(box) != 4 or not all(_integer(item) and item >= 0 for item in box):
        problems.append(f"{label} box is not four non-negative integers")
        return
    if box[2] <= 0 or box[3] <= 0 or box[0] + box[2] > width or box[1] + box[3] > height:
        problems.append(f"{label} box is outside the image")


def validate_document(labels: dict, root: Path) -> list[str]:
    problems = []
    if labels.get("schema") != SCHEMA_LABELS:
        problems.append("label schema is not wp17-q3-synthetic/1")
    if labels.get("seed") != 17217:
        problems.append("seed is not the fixed Q3 seed")
    dataset_id = labels.get("dataset_id")
    if not isinstance(dataset_id, str) or not dataset_id.startswith("q3-s17217-"):
        problems.append("dataset_id is missing or does not name this seed")
    font = labels.get("font") or {}
    if not isinstance(font.get("sha256"), str) or len(font.get("sha256", "")) != 64:
        problems.append("font sha256 is missing")
    excerpt = font.get("license_excerpt") or ""
    if "SIL Open Font License" not in excerpt:
        problems.append("font license excerpt is missing")
    if font.get("redistributed") is not False:
        problems.append("font redistributed flag must stay false")
    cases = labels.get("cases")
    if not isinstance(cases, list) or not cases:
        return problems + ["labels have no cases"]

    seen_cases = set()
    seen_hashes = set()
    hash_rows = []
    for case in cases:
        case_id = case.get("id")
        if not isinstance(case_id, str) or not _ID.match(case_id):
            problems.append(f"bad case id: {case_id!r}")
            continue
        if case_id in seen_cases:
            problems.append(f"duplicate case id: {case_id}")
        seen_cases.add(case_id)
        width, height = case.get("width"), case.get("height")
        if not _integer(width) or not _integer(height) or width < 16 or height < 16:
            problems.append(f"{case_id} has no usable image size")
            continue
        digest = case.get("sha256")
        if not isinstance(digest, str) or len(digest) != 64:
            problems.append(f"{case_id} sha256 is missing")
        elif digest in seen_hashes:
            problems.append(f"duplicate image sha256: {case_id}")
        else:
            seen_hashes.add(digest)
            hash_rows.append(f"{case_id} {digest}")
        image_path = root / f"{case_id}.png"
        if not image_path.is_file():
            problems.append(f"missing image: {case_id}.png")
        else:
            data = image_path.read_bytes()
            actual = sha256_file(image_path)
            if digest != actual:
                problems.append(f"image sha256 mismatch: {case_id}")
            try:
                got_w, got_h = png_size(data)
            except Q3Error:
                problems.append(f"image is not a PNG: {case_id}")
            else:
                if (got_w, got_h) != (width, height):
                    problems.append(f"image size mismatch: {case_id}")

        tasks = case.get("tasks")
        lines = case.get("lines")
        if not isinstance(tasks, list) or not tasks or not isinstance(lines, list) or not lines:
            problems.append(f"{case_id} is missing tasks or lines")
            continue
        task_ids = []
        for task in tasks:
            task_id = task.get("id")
            if not isinstance(task_id, str) or not _ID.match(task_id):
                problems.append(f"{case_id} has a bad task id")
                continue
            if task_id in task_ids:
                problems.append(f"duplicate task id: {case_id}/{task_id}")
            task_ids.append(task_id)
            title = task.get("title")
            if not isinstance(title, str) or not title.strip():
                problems.append(f"empty title: {case_id}/{task_id}")
                title = ""
            if not isinstance(task.get("checked"), bool):
                problems.append(f"checked is not boolean: {case_id}/{task_id}")
            if task.get("level") not in (0, 1):
                problems.append(f"level is not 0 or 1: {case_id}/{task_id}")
            date = task.get("date")
            if date is not None and (not isinstance(date, str) or date not in title):
                problems.append(f"bad date: {case_id}/{task_id}")
            indexes = task.get("line_indexes")
            if not isinstance(indexes, list) or not indexes:
                problems.append(f"task has no lines: {case_id}/{task_id}")
                continue
            pieces = []
            for index in indexes:
                if not _integer(index) or index < 0 or index >= len(lines):
                    problems.append(f"line index out of range: {case_id}/{task_id}")
                    continue
                line = lines[index]
                if line.get("task_id") != task_id or not isinstance(line.get("text"), str):
                    problems.append(f"line does not belong to its task: {case_id}/{task_id}")
                else:
                    pieces.append(line["text"])
                _box_inside(line.get("box"), width, height, f"{case_id}/{task_id}", problems)
            if "".join(pieces) != title:
                problems.append(f"line text does not rebuild the title: {case_id}/{task_id}")
            _box_inside(task.get("checkbox"), width, height, f"{case_id}/{task_id} checkbox", problems)

        parent = None
        for task in tasks:
            task_id = task.get("id")
            if task.get("level") == 0:
                if task.get("parent") is not None:
                    problems.append(f"level 0 task has a parent: {case_id}/{task_id}")
                parent = task_id
            elif task.get("level") == 1:
                if parent is None or task.get("parent") != parent:
                    problems.append(f"parent link does not match the level rule: {case_id}/{task_id}")
        claimed = []
        for line in lines:
            claimed.append(line.get("task_id"))
        if sorted(index for task in tasks for index in task.get("line_indexes") or []) != list(range(len(lines))):
            problems.append(f"lines are not exactly the task lines: {case_id}")
        if any(task_id not in task_ids for task_id in claimed):
            problems.append(f"line points at an unknown task: {case_id}")

    if hash_rows and not any(item.startswith("image sha256 mismatch") for item in problems):
        from q3_common import sha256_bytes
        image_set = sha256_bytes("\n".join(hash_rows).encode("utf-8"))
        if labels.get("image_set_sha256") != image_set:
            problems.append("image set sha256 mismatch")
        font_sha = (labels.get("font") or {}).get("sha256", "")
        expected_id = f"q3-s17217-font{font_sha[:12]}-img{image_set[:12]}"
        if dataset_id != expected_id:
            problems.append("dataset_id does not match the font and image set")
    return problems


def validate_tree(root: Path) -> list[str]:
    path = root / "labels.json"
    if not path.is_file():
        return ["missing labels.json"]
    try:
        labels = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return ["labels.json is not valid JSON"]
    return validate_document(labels, root)
