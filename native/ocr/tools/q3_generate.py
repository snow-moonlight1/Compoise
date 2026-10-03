#!/usr/bin/env python3
"""Declare synthetic ground truth, then render it.

Task text, dates, checkbox state, parent links and line breaks are fixed
before any pixel is written. OCR output is never copied back into labels.
Fonts are read locally and are not redistributed.
"""
from __future__ import annotations

import json
import random
import zlib
from pathlib import Path

from q3_common import SCHEMA_LABELS, SEED, Q3Error, font_license_excerpt, require_outside_repo, sha256_bytes


# Level 0 starts a parent. A later level-1 task belongs to the nearest level 0.
SCENES = [
    {
        "id": "narrow-light",
        "width": 720,
        "height": 1280,
        "dark": False,
        "font_px": 28,
        "noise_pixels": 0,
        "tasks": [
            {"id": "plan", "title": "整理项目 2026-10-03", "checked": False, "level": 0, "date": "2026-10-03"},
            {"id": "digits", "title": "复查数字 0123456789", "checked": True, "level": 1, "date": None},
            {"id": "report", "title": "提交报告 Q1", "checked": False, "level": 0, "date": None},
        ],
    },
    {
        "id": "wide-dark",
        "width": 1440,
        "height": 1100,
        "dark": True,
        "font_px": 34,
        "noise_pixels": 0,
        "tasks": [
            {
                "id": "long-en",
                "title": "Review the complete offline OCR report and check every task before saving",
                "checked": False,
                "level": 0,
                "date": None,
            },
            {
                "id": "mix",
                "title": "Review 报告 レポート 2026-10-03",
                "checked": False,
                "level": 0,
                "date": "2026-10-03",
            },
            {"id": "money", "title": "检查预算 128.50 元", "checked": True, "level": 1, "date": None},
            {"id": "when", "title": "明天 2026/10/04 09:30", "checked": False, "level": 0, "date": "2026/10/04"},
        ],
    },
    {
        "id": "narrow-dark",
        "width": 720,
        "height": 1280,
        "dark": True,
        "font_px": 32,
        "noise_pixels": 0,
        "tasks": [
            {"id": "meet", "title": "会議の資料を確認する", "checked": False, "level": 0, "date": None},
            {
                "id": "report-ja",
                "title": "レポートを作成 2026/10/03",
                "checked": True,
                "level": 1,
                "date": "2026/10/03",
            },
            {"id": "shop", "title": "買い物リスト 12345", "checked": False, "level": 0, "date": None},
        ],
    },
    {
        "id": "parents",
        "width": 960,
        "height": 1400,
        "dark": False,
        "font_px": 26,
        "noise_pixels": 0,
        "tasks": [
            {"id": "release", "title": "发布前检查", "checked": False, "level": 0, "date": None},
            {"id": "model", "title": "准备模型文件", "checked": True, "level": 1, "date": None},
            {"id": "sha", "title": "核对 SHA256 123456", "checked": False, "level": 1, "date": None},
            {"id": "day", "title": "复查日期 2026-10-04", "checked": False, "level": 1, "date": "2026-10-04"},
            {"id": "submit", "title": "提交变更", "checked": False, "level": 0, "date": None},
        ],
    },
    {
        "id": "duplicates",
        "width": 960,
        "height": 900,
        "dark": False,
        "font_px": 28,
        "noise_pixels": 0,
        "tasks": [
            {"id": "copy-a", "title": "整理项目 2026-10-03", "checked": False, "level": 0, "date": "2026-10-03"},
            {"id": "copy-b", "title": "整理项目 2026-10-03", "checked": True, "level": 0, "date": "2026-10-03"},
        ],
    },
    {
        "id": "multiline",
        "width": 1080,
        "height": 1200,
        "dark": False,
        "font_px": 30,
        "noise_pixels": 0,
        "tasks": [
            {
                "id": "long-zh",
                "title": "请在 2026-10-03 09:30 前复核整份离线 OCR 质量记录，并逐项确认任务、日期和数字仍然可编辑",
                "checked": False,
                "level": 0,
                "date": "2026-10-03 09:30",
            },
            {"id": "save", "title": "保存证据", "checked": True, "level": 1, "date": None},
        ],
    },
    {
        "id": "noise",
        "width": 960,
        "height": 1100,
        "dark": False,
        "font_px": 20,
        "noise_pixels": 400,
        "tasks": [
            {"id": "tiny", "title": "测试很小的文字 2026-10-03", "checked": False, "level": 0, "date": "2026-10-03"},
            {"id": "small-en", "title": "English small text 42", "checked": True, "level": 1, "date": None},
        ],
    },
]


def _partition(title: str, width_of, max_width: int) -> list[str]:
    lines = []
    index = 0
    while index < len(title):
        last_ok = None
        end = index + 1
        while end <= len(title) and width_of(title[index:end]) <= max_width:
            last_ok = end
            end += 1
        if last_ok is None:
            raise Q3Error(f"glyph wider than the content box: {title[index]!r}")
        lines.append(title[index:last_ok])
        index = last_ok
    if "".join(lines) != title:
        raise Q3Error("line partition changed the declared title")
    return lines


def _place(scene: dict, draw, font) -> tuple[list[dict], list[dict]]:
    lines = []
    tasks = []
    parent = None
    origin_y = 48
    missing = bytes(font.getmask(chr(0x10FFFF)))

    def width_of(text: str) -> int:
        box = draw.textbbox((0, 0), text, font=font)
        return box[2] - box[0]

    for spec in scene["tasks"]:
        for char in set(spec["title"]) - {" "}:
            if bytes(font.getmask(char)) == missing:
                raise Q3Error(f"font is missing {char!r} for {scene['id']}")
        if spec["date"] is not None and spec["date"] not in spec["title"]:
            raise Q3Error(f"declared date is not in the title: {spec['id']}")
        level = spec["level"]
        if level == 0:
            parent_id = None
        else:
            if parent is None or level != 1:
                raise Q3Error(f"child task has no level-0 parent: {spec['id']}")
            parent_id = parent
        origin_x = 112 + level * 52
        max_width = scene["width"] - origin_x - 24
        parts = _partition(spec["title"], width_of, max_width)
        indexes = []
        for part in parts:
            box = draw.textbbox((origin_x, origin_y), part, font=font)
            record = {
                "text": part,
                "box": [int(box[0]), int(box[1]), int(box[2] - box[0]), int(box[3] - box[1])],
                "origin": [origin_x, origin_y],
                "role": "task",
                "task_id": spec["id"],
            }
            if record["box"][0] < 0 or record["box"][1] < 0:
                raise Q3Error(f"text box left the image: {scene['id']} {spec['id']}")
            if record["box"][0] + record["box"][2] >= scene["width"] or record["box"][1] + record["box"][3] >= scene["height"]:
                raise Q3Error(f"text box does not fit: {scene['id']} {spec['id']}")
            indexes.append(len(lines))
            lines.append(record)
            origin_y = int(box[3]) + 36
        side = 28
        first = lines[indexes[0]]["box"]
        checkbox = [origin_x - 62, first[1] + max(0, (scene["font_px"] - side) // 2), side + 1, side + 1]
        if checkbox[0] < 0 or checkbox[1] < 0 or checkbox[0] + side >= scene["width"] or checkbox[1] + side >= scene["height"]:
            raise Q3Error(f"checkbox does not fit: {scene['id']} {spec['id']}")
        tasks.append({
            "id": spec["id"],
            "title": spec["title"],
            "checked": spec["checked"],
            "level": level,
            "parent": parent_id,
            "date": spec["date"],
            "line_indexes": indexes,
            "checkbox": checkbox,
        })
        if level == 0:
            parent = spec["id"]
    return lines, tasks


def _paint(scene, draw, font, lines, tasks, bg, fg):
    for line in lines:
        draw.text(tuple(line["origin"]), line["text"], font=font, fill=fg)
    for task in tasks:
        bx, by, _w, _h = task["checkbox"]
        side = 28
        draw.rectangle((bx, by, bx + side, by + side), outline=fg, width=2, fill=fg if task["checked"] else None)
        if task["checked"]:
            draw.line((bx + 6, by + 14, bx + 12, by + 20, bx + 23, by + 7), fill=bg, width=3)


def _noise(image, scene):
    count = scene["noise_pixels"]
    if count <= 0:
        return
    rng = random.Random(SEED ^ zlib.crc32(scene["id"].encode("utf-8")))
    for _ in range(count):
        x = rng.randrange(scene["width"])
        y = rng.randrange(scene["height"])
        tone = rng.randrange(256)
        image.putpixel((x, y), (tone, tone, tone))


def generate(out: Path, font_path: Path) -> dict:
    from PIL import Image, ImageDraw, ImageFont, __version__ as pillow_version

    out = require_outside_repo(out)
    font_bytes = font_path.read_bytes()
    license_text = font_license_excerpt(font_bytes)
    font_sha = sha256_bytes(font_bytes)
    rendered = []
    for scene in SCENES:
        image = Image.new("RGB", (scene["width"], scene["height"]), (24, 26, 30) if scene["dark"] else (248, 249, 251))
        draw = ImageDraw.Draw(image)
        font = ImageFont.truetype(str(font_path), scene["font_px"])
        lines, tasks = _place(scene, draw, font)
        bg = (24, 26, 30) if scene["dark"] else (248, 249, 251)
        fg = (234, 235, 239) if scene["dark"] else (26, 28, 32)
        _paint(scene, draw, font, lines, tasks, bg, fg)
        _noise(image, scene)
        for line in lines:
            line.pop("origin", None)
        rendered.append((scene, image, lines, tasks))

    out.mkdir(parents=True, exist_ok=True)
    cases = []
    image_rows = []
    for scene, image, lines, tasks in rendered:
        from io import BytesIO
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        payload = buffer.getvalue()
        digest = sha256_bytes(payload)
        (out / f"{scene['id']}.png").write_bytes(payload)
        titles = [task["title"] for task in tasks]
        cases.append({
            "id": scene["id"],
            "width": scene["width"],
            "height": scene["height"],
            "dark": scene["dark"],
            "font_px": scene["font_px"],
            "noise_pixels": scene["noise_pixels"],
            "duplicate_titles": len(titles) != len(set(titles)),
            "sha256": digest,
            "lines": lines,
            "tasks": tasks,
        })
        image_rows.append(f"{scene['id']} {digest}")
    image_set = sha256_bytes("\n".join(image_rows).encode("utf-8"))
    labels = {
        "schema": SCHEMA_LABELS,
        "seed": SEED,
        "dataset_id": f"q3-s{SEED}-font{font_sha[:12]}-img{image_set[:12]}",
        "source": "self-authored declarations in q3_generate.py; labels are fixed before pixels",
        "authorization": "synthetic only; no user images; font read locally and not redistributed",
        "real_screenshots": "unverified",
        "space_policy": "strict CER keeps spaces; recognizer output is not rewritten",
        "parent_rule": "level 0 has no parent; level 1 belongs to the nearest preceding level 0",
        "noise_rule": "salt pixels use Random(SEED xor crc32(case id)) and do not change labels",
        "pillow": pillow_version,
        "generator_sha256": sha256_bytes(Path(__file__).read_bytes()),
        "image_set_sha256": image_set,
        "font": {
            "file_name": font_path.name,
            "sha256": font_sha,
            "license_excerpt": license_text,
            "redistributed": False,
        },
        "cases": cases,
    }
    (out / "labels.json").write_text(json.dumps(labels, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return labels
