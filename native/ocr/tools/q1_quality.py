#!/usr/bin/env python3
"""Generate independently labelled synthetic scenes and score real native OCR.

Opt-in; Pillow/fonts are local tools, never downloaded or redistributed. Pixels
come from these declarations, not OCR output. Raw results go outside the repo.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

from q1_benchmark import REPO, bind, recognize

SCENES = [
    ("small-light", 960, 1024, 18, 60, False, "msyh.ttc", [
        ("整理项目 2026-10-03", False, 0), ("复查数字 0123456789", True, 1), ("提交报告 Q1", False, 0)]),
    ("large-dark", 960, 1280, 42, 110, True, "msyh.ttc", [
        ("今晚整理资料", True, 0), ("明天 2026/10/04 09:30", False, 1), ("检查预算 128.50 元", False, 0)]),
    ("mixed-light", 1080, 1400, 32, 94, False, "msyh.ttc", [
        ("Review 报告 レポート 2026-10-03", False, 0), ("確認 Task 12 完了", True, 1), ("会议 meeting 会議 09:30", False, 0)]),
    ("mixed-dark", 1080, 1400, 28, 94, True, "msyh.ttc", [
        ("检查 API v5 2026/10/03", False, 0), ("Write tests 测试 42", True, 1), ("確認資料 report 100%", False, 0)]),
    ("dense-subtasks", 960, 1280, 24, 44, False, "msyh.ttc", [
        ("发布前检查", False, 0), ("准备模型文件", True, 1), ("核对 SHA256 123456", False, 1),
        ("复查日期 2026-10-04", False, 1), ("提交变更", False, 0), ("运行单元测试", True, 1),
        ("Review code 12", False, 1), ("保存证据", False, 1), ("归档记录", True, 0)]),
    ("long-lines", 1600, 1100, 32, 130, False, "segoeui.ttf", [
        ("Review the complete offline OCR report and check every task before saving", False, 0),
        ("Numbers 0123456789 dates 2026-10-03 and time 09:30 remain editable", True, 0)]),
    ("tiny-dense", 960, 1024, 14, 40, True, "msyh.ttc", [
        ("测试很小的文字 2026-10-03", False, 0), ("嵌套子任务 0123456789", True, 1),
        ("保存结果不自动写入日程", False, 0), ("English small text 42", False, 1)]),
    ("japanese", 1080, 1280, 36, 100, False, "YuGothR.ttc", [
        ("会議の資料を確認する", False, 0), ("レポートを作成 2026/10/03", True, 1), ("買い物リスト 12345", False, 0)]),
]


def generate(out, fonts):
    from PIL import Image, ImageDraw, ImageFont, __version__
    out.mkdir(parents=True, exist_ok=True)
    cases, font_hashes = [], {}
    for name, width, height, size, spacing, dark, face, tasks in SCENES:
        path = fonts / face
        font_hashes[face] = hashlib.sha256(path.read_bytes()).hexdigest()
        font = ImageFont.truetype(str(path), size)
        image = Image.new("RGB", (width, height), (24, 26, 30) if dark else (248, 249, 251))
        draw = ImageDraw.Draw(image)
        fg = (234, 235, 239) if dark else (26, 28, 32)
        lines, truth = [], []
        parent = None
        for index, (text, checked, level) in enumerate(tasks):
            missing = bytes(font.getmask(chr(0x10ffff)))
            for char in set(text) - {" "}:
                assert bytes(font.getmask(char)) != missing, (face, "missing glyph", char)
            y = int(.32 * width) + index * spacing
            x = 112 + level * 52
            box = [int(v) for v in draw.textbbox((x, y), text, font=font)]
            assert box[2] < width and box[3] < height, (name, text, box)
            draw.text((x, y), text, font=font, fill=fg)
            bx, by, side = x - 62, y + max(0, (size - 28) // 2), 28
            draw.rectangle((bx, by, bx + side, by + side), outline=fg, width=2, fill=fg if checked else None)
            if checked:
                bg = (24, 26, 30) if dark else (248, 249, 251)
                draw.line((bx + 6, by + 14, bx + 12, by + 20, bx + 23, by + 7), fill=bg, width=3)
            if level == 0: parent = index
            lines.append({"text": text, "box": [box[0], box[1], box[2] - box[0], box[3] - box[1]], "role": "task"})
            truth.append({"title": text, "checked": checked, "level": level,
                          "parent": parent if level else None, "checkbox": [bx, by, side + 1, side + 1]})
        image.save(out / (name + ".png"))
        cases.append({"id": name, "width": width, "height": height, "font_px": size,
                      "spacing_px": spacing, "dark": dark, "lines": lines, "tasks": truth,
                      "sha256": hashlib.sha256((out / (name + ".png")).read_bytes()).hexdigest()})
    (out / "corrupt.png").write_bytes(b"not a png")
    labels = {"schema": "wp17-q1-synthetic/1", "source": "self-authored declarative scenes in q1_quality.py",
              "authorization": "synthetic only; no user images; fonts read locally, not redistributed",
              "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "pillow": __version__, "font_sha256": font_hashes, "cases": cases}
    (out / "labels.json").write_text(json.dumps(labels, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"images": len(cases), "gt_lines": sum(len(c["lines"]) for c in cases)}))


def score(out, library, assets, flutter, baseline=None):
    sys.path.insert(0, str(REPO / "docs/evidence/wp17r2/tools"))
    from score_text import aggregate, score_image
    from wp17r2lib import norm_text, levenshtein
    labels = json.loads((out / "labels.json").read_text(encoding="utf-8"))
    lib = bind(library)
    session = lib.mf_ocr_create(str(assets).encode(), 4)
    rows, raw = [], []
    try:
        for case in labels["cases"]:
            result = recognize(lib, session, out / (case["id"] + ".png"))
            assert result["error"] == "", result
            rows.append(score_image(case, result["lines"]))
            raw.append({"id": case["id"], **result})
    finally:
        lib.mf_ocr_destroy(session)
    unchanged = None
    if baseline:
        previous = bind(baseline)
        previous_session = previous.mf_ocr_create(str(assets).encode(), 4)
        try:
            for case, current in zip(labels["cases"], raw):
                before = recognize(previous, previous_session, out / (case["id"] + ".png"))
                assert {"id": case["id"], **before} == current, (case["id"], "quality regression")
            unchanged = True
        finally:
            previous.mf_ocr_destroy(previous_session)
    structure = []
    if flutter:
        actual = {row["id"]: row for row in json.loads(flutter.read_text(encoding="utf-8"))["quality"]}
        for case in labels["cases"]:
            gt = case["tasks"]
            got = actual[case["id"]]["tasks"]
            # Match by independently authored text distance, then expose misses
            # and wrong structure. Never align purely by order after a miss.
            used = set()
            pairs = []
            for gi, want in enumerate(gt):
                candidates = [(levenshtein(norm_text(want["title"]), norm_text(t["title"])) /
                               max(1, len(norm_text(want["title"]))), ai)
                              for ai, t in enumerate(got) if ai not in used]
                if candidates:
                    distance, ai = min(candidates)
                    if distance <= .35:
                        used.add(ai)
                        pairs.append((gi, ai))
            mapping = dict(pairs)
            checked = sum(gt[gi]["checked"] == got[ai]["checked"] for gi, ai in pairs)
            parents = 0
            for gi, ai in pairs:
                expected_parent = gt[gi]["parent"]
                actual_parent = got[ai]["parentId"]
                if expected_parent is None:
                    parents += actual_parent is None
                elif expected_parent in mapping:
                    # Draft ids use the source row; capture report includes it.
                    parents += actual_parent == got[mapping[expected_parent]].get("id")
            structure.append({"id": case["id"], "gt": len(gt), "actual": len(got), "matched": len(pairs),
                              "missed": len(gt) - len(pairs), "extra": len(got) - len(pairs),
                              "checked_correct": checked, "parent_correct": parents})
    text_scores = aggregate(rows)
    strict_lengths = [sum(len(norm_text(line["text"], True)) for line in case["lines"]) for case in labels["cases"]]
    strict_edits = sum(round(row["cer_strict"] * length) for row, length in zip(rows, strict_lengths))
    text_scores.update(cer_strict_micro=strict_edits / sum(strict_lengths),
                       strict_ref_chars=sum(strict_lengths), strict_edit_distance=strict_edits)
    report = {"text": text_scores, "per_image": rows, "structure": structure,
              "identical_to_baseline": unchanged,
              "real_screenshots": "unverified: no authorized deidentified real samples supplied"}
    (out / "native-raw.json").write_text(json.dumps(raw, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / "quality.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"text": report["text"], "structure": structure}))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=("generate", "score"))
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--fonts", type=Path, default=Path("C:/Windows/Fonts"))
    p.add_argument("--library", type=Path)
    p.add_argument("--assets", type=Path)
    p.add_argument("--flutter-report", type=Path)
    p.add_argument("--baseline-library", type=Path)
    a = p.parse_args()
    if REPO == a.out.resolve() or REPO in a.out.resolve().parents: p.error("output must be outside checkout")
    if a.action == "generate": generate(a.out, a.fonts)
    else:
        if not a.library or not a.assets: p.error("score needs --library and --assets")
        score(a.out, a.library, a.assets, a.flutter_report, a.baseline_library)


if __name__ == "__main__":
    main()
