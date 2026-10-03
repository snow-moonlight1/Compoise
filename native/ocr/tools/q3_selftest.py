#!/usr/bin/env python3
"""Positive and negative cases for the Q3 scorer. No model and no device."""
from __future__ import annotations

import contextlib
import io
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from q3_cli import main
from q3_common import SCHEMA_LABELS, Q3Error, REPO, bundle_problems, sha256_bytes
from q3_compare import compare_reports
from q3_dict_probe import tokens_after_loader
from q3_score import score_document
from q3_validate import validate_tree


# The 30 titles declared by q1_quality.py. Spaces removed give strict 55/504
# and stripped 0/449. A scorer that drops spaces before CER fails this lock.
Q1_TITLES = [
    "整理项目 2026-10-03", "复查数字 0123456789", "提交报告 Q1",
    "今晚整理资料", "明天 2026/10/04 09:30", "检查预算 128.50 元",
    "Review 报告 レポート 2026-10-03", "確認 Task 12 完了", "会议 meeting 会議 09:30",
    "检查 API v5 2026/10/03", "Write tests 测试 42", "確認資料 report 100%",
    "发布前检查", "准备模型文件", "核对 SHA256 123456",
    "复查日期 2026-10-04", "提交变更", "运行单元测试",
    "Review code 12", "保存证据", "归档记录",
    "Review the complete offline OCR report and check every task before saving",
    "Numbers 0123456789 dates 2026-10-03 and time 09:30 remain editable",
    "测试很小的文字 2026-10-03", "嵌套子任务 0123456789",
    "保存结果不自动写入日程", "English small text 42",
    "会議の資料を確認する", "レポートを作成 2026/10/03", "買い物リスト 12345",
]


def _png(width, height, rgb=(255, 255, 255)) -> bytes:
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


def _line(text, index, task_id):
    return {"text": text, "box": [40, 30 + index * 40, 200, 24], "role": "task", "task_id": task_id}


def _task(task_id, title, index, checked=False, level=0, parent=None, date=None):
    return {
        "id": task_id, "title": title, "checked": checked, "level": level, "parent": parent,
        "date": date, "line_indexes": [index], "checkbox": [8, 30 + index * 40, 20, 20],
    }


def _labels(cases):
    font_sha = "a" * 64
    rows = [f"{case['id']} {case['sha256']}" for case in cases]
    image_set = sha256_bytes("\n".join(rows).encode("utf-8"))
    return {
        "schema": SCHEMA_LABELS,
        "seed": 17217,
        "dataset_id": f"q3-s17217-font{font_sha[:12]}-img{image_set[:12]}",
        "image_set_sha256": image_set,
        "font": {"sha256": font_sha, "license_excerpt": "SIL Open Font License, Version 1.1", "redistributed": False},
        "cases": cases,
    }


def _write_tree(root: Path, cases):
    root.mkdir(parents=True, exist_ok=True)
    stored = []
    for case in cases:
        payload = _png(case["width"], case["height"], (10 + len(stored), 20, 30))
        (root / f"{case['id']}.png").write_bytes(payload)
        item = dict(case)
        item["sha256"] = sha256_bytes(payload)
        stored.append(item)
    labels = _labels(stored)
    (root / "labels.json").write_text(json.dumps(labels), encoding="utf-8")
    return labels


def _one_case():
    return {
        "id": "sample",
        "width": 320,
        "height": 200,
        "lines": [_line("整理项目 2026-10-03", 0, "plan")],
        "tasks": [_task("plan", "整理项目 2026-10-03", 0, date="2026-10-03")],
    }


def _raw(image_id, lines, error=""):
    return {"schema": "wp17-q3-raw/1", "images": [{"id": image_id, "error": error, "lines": lines}]}


def _hyp(text, index):
    return {"text": text, "box": [40, 30 + index * 40, 200, 24], "score": 0.9}


class Q3SelfTest(unittest.TestCase):
    def test_locked_space_defect_is_55_of_504(self):
        self.assertEqual(len(Q1_TITLES), 30)
        lines = [_line(title, index, f"t{index}") for index, title in enumerate(Q1_TITLES)]
        tasks = [_task(f"t{index}", title, index) for index, title in enumerate(Q1_TITLES)]
        labels = _labels([{
            "id": "q1-30", "width": 640, "height": 1600, "sha256": "b" * 64,
            "lines": lines, "tasks": tasks,
        }])
        raw = _raw("q1-30", [_hyp("".join(title.split()), index) for index, title in enumerate(Q1_TITLES)])
        report = score_document(labels, raw, None)
        self.assertEqual(report["raw"]["strict"]["edits"], 55)
        self.assertEqual(report["raw"]["strict"]["ref_chars"], 504)
        self.assertEqual(report["raw"]["stripped"]["edits"], 0)
        self.assertEqual(report["raw"]["stripped"]["ref_chars"], 449)
        self.assertEqual(report["raw"]["missed_lines"], 0)
        self.assertEqual(report["raw"]["extra_lines"], 0)
        self.assertFalse(report["draft"]["supplied"])

    def test_extra_line_is_outside_cer_and_miss_is_charged(self):
        case = _one_case()
        labels = _labels([dict(case, sha256="b" * 64)])
        lines = [_hyp("整理项目2026-10-03", 0), {"text": "噪声", "box": [40, 120, 40, 20], "score": 0.2}]
        report = score_document(labels, _raw("sample", lines), None)
        self.assertEqual(report["raw"]["strict"]["edits"], 1)
        self.assertEqual(report["raw"]["stripped"]["edits"], 0)
        self.assertEqual(report["raw"]["extra_lines"], 1)
        self.assertEqual(report["raw"]["extra_chars_strict"], 2)
        missing = score_document(labels, _raw("sample", []), None)
        self.assertEqual(missing["raw"]["empty_images"], 1)
        self.assertEqual(missing["raw"]["missed_lines"], 1)
        self.assertEqual(missing["raw"]["strict"]["edits"], missing["raw"]["strict"]["ref_chars"])

    def test_failed_image_is_separate_from_cer(self):
        case = _one_case()
        labels = _labels([dict(case, sha256="b" * 64)])
        report = score_document(labels, _raw("sample", [], error="cannot read dict"), None)
        self.assertEqual(report["raw"]["failed_images"], 1)
        self.assertEqual(report["raw"]["empty_images"], 0)
        self.assertEqual(report["raw"]["strict"]["ref_chars"], 0)

    def test_draft_checked_parent_and_spaced_date(self):
        case = {
            "id": "sample",
            "width": 320,
            "height": 240,
            "sha256": "b" * 64,
            "lines": [
                _line("整理项目 2026-10-03", 0, "plan"),
                _line("明天 2026-10-03 09:30", 1, "when"),
            ],
            "tasks": [
                _task("plan", "整理项目 2026-10-03", 0, date="2026-10-03"),
                _task("when", "明天 2026-10-03 09:30", 1, checked=True, level=1, parent="plan",
                      date="2026-10-03 09:30"),
            ],
        }
        labels = _labels([case])
        raw = _raw("sample", [_hyp("整理项目2026-10-03", 0), _hyp("明天2026-10-0309:30", 1)])
        draft = {"schema": "wp17-q3-draft/1", "images": [{"id": "sample", "tasks": [
            {"id": "plan", "title": "整理项目 2026-10-03", "checked": False, "parentId": None},
            {"id": "when", "title": "明天2026-10-0309:30", "checked": False, "parentId": "plan"},
        ]}]}
        report = score_document(labels, raw, draft)
        self.assertEqual(report["raw"]["date_retained_strict"], {"hit": 1, "total": 2})
        self.assertEqual(report["raw"]["date_retained_stripped"], {"hit": 2, "total": 2})
        self.assertEqual(report["draft"]["missed_tasks"], 0)
        self.assertEqual(report["draft"]["extra_tasks"], 0)
        self.assertEqual(report["draft"]["checked"], {"correct": 1, "total": 2})
        self.assertEqual(report["draft"]["parent"], {"correct": 2, "total": 2})
        self.assertEqual(report["draft"]["date_retained_strict"]["hit"], 1)
        self.assertEqual(report["draft"]["date_retained_stripped"]["hit"], 2)

    def test_duplicate_titles_pair_in_order(self):
        case = {
            "id": "sample", "width": 320, "height": 200, "sha256": "b" * 64,
            "lines": [_line("整理项目 2026-10-03", 0, "copy-a"), _line("整理项目 2026-10-03", 1, "copy-b")],
            "tasks": [
                _task("copy-a", "整理项目 2026-10-03", 0, checked=False),
                _task("copy-b", "整理项目 2026-10-03", 1, checked=True),
            ],
        }
        labels = _labels([case])
        raw = _raw("sample", [_hyp("整理项目2026-10-03", 0), _hyp("整理项目2026-10-03", 1)])
        draft = {"schema": "wp17-q3-draft/1", "images": [{"id": "sample", "tasks": [
            {"id": "d0", "title": "整理项目 2026-10-03", "checked": True, "parentId": None},
            {"id": "d1", "title": "整理项目 2026-10-03", "checked": False, "parentId": None},
        ]}]}
        report = score_document(labels, raw, draft)
        self.assertEqual(report["draft"]["ambiguous_titles"], 2)
        self.assertEqual(report["draft"]["checked"]["correct"], 0)
        self.assertEqual(report["draft"]["missed_tasks"], 0)

    def test_validate_accepts_a_consistent_tree_and_rejects_damage(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_tree(root, [_one_case()])
            self.assertEqual(validate_tree(root), [])
            labels = json.loads((root / "labels.json").read_text(encoding="utf-8"))
            labels["cases"].append(json.loads(json.dumps(labels["cases"][0])))
            (root / "labels.json").write_text(json.dumps(labels), encoding="utf-8")
            self.assertTrue(any("duplicate case id" in item for item in validate_tree(root)))

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_tree(root, [_one_case()])
            labels = json.loads((root / "labels.json").read_text(encoding="utf-8"))
            labels["cases"][0]["sha256"] = "c" * 64
            (root / "labels.json").write_text(json.dumps(labels), encoding="utf-8")
            self.assertTrue(any("image sha256 mismatch" in item for item in validate_tree(root)))

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_tree(root, [_one_case()])
            labels = json.loads((root / "labels.json").read_text(encoding="utf-8"))
            labels["cases"][0]["tasks"][0]["date"] = "1999-01-01"
            (root / "labels.json").write_text(json.dumps(labels), encoding="utf-8")
            self.assertTrue(any(item.startswith("bad date") for item in validate_tree(root)))

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            case = _one_case()
            case["tasks"].append(_task("plan", "整理项目 2026-10-03", 0))
            case["tasks"][1]["line_indexes"] = [0]
            _write_tree(root, [case])
            self.assertTrue(any("duplicate task id" in item for item in validate_tree(root)))

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            case = _one_case()
            case["lines"].append(_line("子任务", 1, "child"))
            case["tasks"].append(_task("child", "子任务", 1, level=1, parent="missing"))
            _write_tree(root, [case])
            self.assertTrue(any("parent link" in item for item in validate_tree(root)))

    def test_cli_score_exit_codes_and_repo_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_tree(root, [_one_case()])
            raw_path = root / "raw.json"
            raw_path.write_text(json.dumps(_raw("sample", [_hyp("整理项目2026-10-03", 0)])), encoding="utf-8")
            report = root / "score.json"
            self.assertEqual(main(["score", "--labels", str(root), "--raw", str(raw_path), "--out", str(report)]), 0)
            saved = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(saved["raw"]["strict"]["edits"], 1)
            self.assertEqual(saved["raw"]["stripped"]["edits"], 0)
            failed = root / "failed-raw.json"
            failed.write_text(json.dumps(_raw("sample", [], error="missing model")), encoding="utf-8")
            failed_report = root / "failed-score.json"
            self.assertEqual(main(["score", "--labels", str(root), "--raw", str(failed), "--out", str(failed_report)]), 1)
            self.assertEqual(json.loads(failed_report.read_text(encoding="utf-8"))["raw"]["failed_images"], 1)
            empty = root / "empty-raw.json"
            empty.write_text(json.dumps(_raw("sample", [])), encoding="utf-8")
            empty_report = root / "empty-score.json"
            self.assertEqual(main(["score", "--labels", str(root), "--raw", str(empty), "--out", str(empty_report)]), 0)
            self.assertEqual(main([
                "score", "--labels", str(root), "--raw", str(empty), "--out", str(root / "empty-fail.json"),
                "--fail-on-empty",
            ]), 1)
            self.assertEqual(main([
                "score", "--labels", str(root), "--raw", str(raw_path), "--out", str(REPO / "q3-not-allowed.json"),
            ]), 1)
            self.assertFalse((REPO / "q3-not-allowed.json").exists())

    def test_compare_rejects_a_different_dataset(self):
        case = _one_case()
        labels = _labels([dict(case, sha256="b" * 64)])
        left = score_document(labels, _raw("sample", [_hyp("整理项目 2026-10-03", 0)]), None)
        right = score_document(labels, _raw("sample", [_hyp("整理项目2026-10-03", 0)]), None)
        problems, delta = compare_reports(left, right)
        self.assertEqual(problems, [])
        self.assertEqual(delta["strict_edits"], 1)
        problems, _delta = compare_reports(left, right, max_strict_edit_increase=0)
        self.assertTrue(problems)
        other = json.loads(json.dumps(right))
        other["dataset_id"] = "q3-s17217-font" + "d" * 12 + "-img" + "e" * 12
        problems, delta = compare_reports(left, other)
        self.assertIsNone(delta)
        self.assertTrue(any("dataset_id" in item for item in problems))

    def test_missing_model_and_space_token_loader(self):
        with tempfile.TemporaryDirectory() as tmp:
            problems = bundle_problems(Path(tmp))
        self.assertTrue(any("missing model file" in item for item in problems))
        tokens = tokens_after_loader("\u3000\n \nA\n".encode("utf-8"))
        self.assertEqual(tokens[0], "\u3000")
        self.assertEqual(tokens[1], "")
        self.assertNotIn(" ", tokens)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            labels = root / "labels"
            _write_tree(labels, [_one_case()])
            self.assertEqual(main(["probe-dict", "--assets", str(root / "assets")]), 1)
            error = io.StringIO()
            with contextlib.redirect_stderr(error):
                code = main([
                    "score", "--labels", str(labels), "--enable-model", "--library", str(root / "missing.dll"),
                    "--assets", str(root / "assets"), "--out", str(root / "out"),
                ])
            self.assertEqual(code, 1)
            self.assertIn("missing model file", error.getvalue())
            self.assertFalse((root / "out" / "score.json").exists())

    def test_duplicate_raw_id_fails(self):
        labels = _labels([dict(_one_case(), sha256="b" * 64)])
        raw = _raw("sample", [_hyp("整理项目 2026-10-03", 0)])
        raw["images"].append(raw["images"][0])
        with self.assertRaises(Q3Error):
            score_document(labels, raw, None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
