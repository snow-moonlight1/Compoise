#!/usr/bin/env python3
"""Generate the WP17-R2 synthetic screenshot corpus and its ground truth.

Why synthetic: WP17-R2 must not ship or process real user to-do screenshots.
Every pixel here is drawn from a declarative spec, so the labels are exact by
construction and the corpus can be regenerated from this file alone.

Fonts are *not* redistributed; the script reads them from the host:

    C:/Windows/Fonts/msyh.ttc    Microsoft YaHei      (zh + latin)
    C:/Windows/Fonts/msyhbd.ttc  Microsoft YaHei Bold
    C:/Windows/Fonts/YuGothR.ttc Yu Gothic            (ja + latin)
    C:/Windows/Fonts/YuGothB.ttc Yu Gothic Bold
    C:/Windows/Fonts/segoeui.ttf Segoe UI             (en)

Because those fonts are host-specific, the generated PNGs and labels.json are
committed; this script is the provenance record, not a build step that the
Android/Linux legs need to re-run.

Usage:  python gen_samples.py            # writes ./images/*.png + ./labels.json
        python gen_samples.py --check    # verify committed images match the spec
"""
from __future__ import annotations

import hashlib
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, "images")
LABELS = os.path.join(HERE, "labels.json")

FONT_FILES = {
    ("zh", "regular"): ("C:/Windows/Fonts/msyh.ttc", 0),
    ("zh", "bold"): ("C:/Windows/Fonts/msyhbd.ttc", 0),
    ("ja", "regular"): ("C:/Windows/Fonts/YuGothR.ttc", 0),
    ("ja", "bold"): ("C:/Windows/Fonts/YuGothB.ttc", 0),
    ("en", "regular"): ("C:/Windows/Fonts/segoeui.ttf", 0),
    ("en", "bold"): ("C:/Windows/Fonts/segoeui.ttf", 0),
}

THEMES = {
    "light": {
        "bg": (247, 248, 250),
        "surface": (255, 255, 255),
        "text": (26, 27, 30),
        "text_muted": (150, 155, 165),
        "accent": (37, 99, 235),
        "divider": (231, 233, 238),
        "box_border": (170, 176, 188),
        "box_fill": (37, 99, 235),
        "tick": (255, 255, 255),
        "strike": (150, 155, 165),
    },
    "dark": {
        "bg": (18, 19, 22),
        "surface": (28, 30, 34),
        "text": (236, 238, 242),
        "text_muted": (140, 146, 158),
        "accent": (96, 165, 250),
        "divider": (48, 51, 57),
        "box_border": (130, 137, 150),
        "box_fill": (96, 165, 250),
        "tick": (18, 19, 22),
        "strike": (140, 146, 158),
    },
}

BASE_W = 1080
BASE_ROW_H = 132
BASE_FONT = 40
BASE_STATUSBAR_H = 72
BASE_APPBAR_H = 148
SECTION_H = 86


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Renderer:
    """Draws one synthetic screenshot and accumulates its ground truth."""

    def __init__(self, case_id: str, locale: str, theme: str, scale: float, height_base: int):
        self.case_id = case_id
        self.locale = locale
        self.theme = THEMES[theme]
        self.theme_name = theme
        self.scale = scale
        self.width = int(round(BASE_W * scale))
        self.height = int(round(height_base * scale))
        self.img = Image.new("RGB", (self.width, self.height), self.theme["bg"])
        self.d = ImageDraw.Draw(self.img)
        self.lines: list[dict] = []
        self.checkboxes: list[dict] = []
        self.y = 0.0
        self._font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}

    # -- geometry helpers ---------------------------------------------------
    def sx(self, v: float) -> float:
        return v * self.scale

    def sy(self, v: float) -> float:
        return v * self.scale

    def _font(self, size_base: float, style: str = "regular") -> ImageFont.FreeTypeFont:
        key = (style, int(round(size_base * self.scale)))
        if key not in self._font_cache:
            path, index = FONT_FILES[(self.locale, key[0])]
            self._font_cache[key] = ImageFont.truetype(path, max(6, key[1]), index=index)
        return self._font_cache[key]

    # -- primitives ---------------------------------------------------------
    def rect(self, x, y, w, h, fill=None, outline=None, width=1):
        if fill is not None or outline is not None:
            self.d.rectangle([x, y, x + w - 1, y + h - 1], fill=fill, outline=outline, width=width)

    def text_line(
        self,
        text: str,
        x: float,
        y_top: float,
        size_base: float = BASE_FONT,
        *,
        role: str,
        style: str = "regular",
        color: str = "text",
        indent: int = 0,
        task_key: str | None = None,
        checked: bool | None = None,
        strike: bool = False,
        pad_x: float = 12.0,
    ) -> dict:
        """Draw one text line, record exact geometry, return the label entry."""
        font = self._font(size_base, style)
        x_px, y_px = self.sx(x), self.sy(y_top)
        self.d.text((x_px, y_px), text, font=font, fill=self.theme[color])
        tight = self.d.textbbox((x_px, y_px), text, font=font)
        adv = self.d.textlength(text, font=font)
        line_h = self.sy(size_base * 1.35)
        box = [x_px - self.sx(pad_x), y_px - self.sy(4), adv + self.sx(2 * pad_x), line_h]
        entry = {
            "text": text,
            "box": [round(v, 2) for v in box],
            "tight_box": [round(float(v), 2) for v in tight],
            "role": role,
            "indent": indent,
            "checked": checked,
            "task_key": task_key,
        }
        if strike:
            mid = (tight[1] + tight[3]) / 2
            self.d.line(
                [tight[0], mid, tight[0] + adv, mid],
                fill=self.theme["strike"],
                width=max(1, int(round(self.sy(3)))),
            )
        self.lines.append(entry)
        return entry

    def checkbox(self, x: float, y_top: float, size_base: float, checked: bool, task_key: str, indent: int):
        s = self.sx(size_base)
        y_px = self.sy(y_top)
        x_px = self.sx(x)
        r = max(1, int(round(self.sx(3))))
        if checked:
            self.rect(x_px, y_px, s, s, fill=self.theme["box_fill"])
            self.d.line(
                [
                    (x_px + s * 0.22, y_px + s * 0.52),
                    (x_px + s * 0.43, y_px + s * 0.73),
                    (x_px + s * 0.79, y_px + s * 0.25),
                ],
                fill=self.theme["tick"],
                width=max(r, int(round(self.sx(4)))),
                joint="curve",
            )
        else:
            self.rect(x_px, y_px, s, s, outline=self.theme["box_border"], width=r)
        self.checkboxes.append(
            {
                "box": [round(x_px, 2), round(y_px, 2), round(s, 2), round(s, 2)],
                "checked": checked,
                "task_key": task_key,
                "indent": indent,
            }
        )

    # -- screen furniture ---------------------------------------------------
    def status_bar(self, clock: str = "9:41"):
        h = BASE_STATUSBAR_H
        self.rect(0, 0, self.width, self.sy(h), fill=self.theme["surface"])
        self.text_line(clock, 42, 22, 34, role="status_clock", color="text", pad_x=6)
        # battery / signal glyphs are pure decoration and deliberately textless:
        # they must never surface as task lines.
        self.d.rectangle(
            [self.sx(BASE_W - 84), self.sy(26), self.sx(BASE_W - 44), self.sy(46)],
            outline=self.theme["text_muted"],
            width=max(1, int(round(self.sx(2)))),
        )
        self.d.rectangle(
            [self.sx(BASE_W - 80), self.sy(30), self.sx(BASE_W - 58), self.sy(42)],
            fill=self.theme["text_muted"],
        )
        for i in range(4):
            bx = BASE_W - 140 + i * 14
            self.d.rectangle(
                [self.sx(bx), self.sy(40 - i * 5), self.sx(bx + 9), self.sy(46)],
                fill=self.theme["text_muted"],
            )
        self.y = h

    def app_bar(self, title: str, count_hint: str | None = None):
        h = BASE_APPBAR_H
        self.rect(0, self.sy(self.y), self.width, self.sy(h), fill=self.theme["surface"])
        self.text_line(title, 48, self.y + 46, 52, role="app_title", style="bold")
        if count_hint:
            self.text_line(count_hint, 860, self.y + 60, 30, role="app_meta", color="text_muted")
        self.y += h
        self.rect(0, self.sy(self.y), self.width, max(1, int(round(self.sy(1)))), fill=self.theme["divider"])
        self.y += 1

    def section(self, title: str):
        self.y += 26
        self.text_line(title, 48, self.y, 32, role="section_header", style="bold", color="accent")
        self.y += 60

    def task_row(
        self,
        key: str,
        text: str,
        checked: bool,
        *,
        indent: int = 0,
        due: str | None = None,
        small: bool = False,
        muted: bool = False,
        strike: bool = False,
        role: str = "task",
    ):
        row_h = BASE_ROW_H * (0.78 if small else 1.0)
        font_size = BASE_FONT * (0.62 if small else 1.0)
        self.rect(0, self.sy(self.y), self.width, self.sy(row_h), fill=self.theme["surface"])
        box_x = 48 + indent * 56
        box_size = 44 * (0.8 if small else 1.0)
        box_y = self.y + (row_h - box_size) / 2
        self.checkbox(box_x, box_y, box_size, checked, key, indent)
        tx = box_x + box_size + 28
        self.text_line(
            text,
            tx,
            self.y + (row_h - font_size * 1.35) / 2,
            font_size,
            role=role,
            indent=indent,
            task_key=key,
            checked=checked,
            color="text_muted" if muted else "text",
            strike=strike,
            pad_x=6,
        )
        if due:
            self.text_line(due, 760, self.y + (row_h - 30 * 1.35) / 2, 30, role="due_date", color="text_muted")
        self.y += row_h
        self.rect(0, self.sy(self.y), self.width, max(1, int(round(self.sy(1)))), fill=self.theme["divider"])

    def blank_row(self, rows: float = 1.0):
        self.y += BASE_ROW_H * rows
        self.rect(0, self.sy(self.y), self.width, max(1, int(round(self.sy(1)))), fill=self.theme["divider"])


# ---------------------------------------------------------------------------
# Corpus definition (data only, so the spec reads like the WP17 acceptance list)
# ---------------------------------------------------------------------------

ZH_TASKS = [
    ("t1", "买菜：西红柿、鸡蛋、牛奶", False, 0, "今天 18:00", False),
    ("t2", "给妈妈打电话", True, 0, None, False),
    ("t3", "项目周报", False, 0, "周五", False),
    ("t4", "整理上周会议记录", False, 1, None, False),
    ("t5", "补充测试用例清单", False, 1, None, False),
    ("t6", "读《Designing Data-Intensive》第 5 章", False, 0, None, False),
    ("t7", "缴纳水电费", False, 0, "10月15日", False),
    ("t8", "预约牙医 9:30", True, 0, None, True),
]

EN_TASKS = [
    ("t1", "Buy groceries: tomatoes, eggs, milk", False, 0, "Today 6:00 PM", False),
    ("t2", "Call mom back", True, 0, None, False),
    ("t3", "Write weekly status report", False, 0, "Fri", False),
    ("t4", "Tidy up last week's meeting notes", False, 1, None, False),
    ("t5", "Fill in the regression test checklist", False, 1, None, False),
    ("t6", "Read chapter 5 of DDIA", False, 0, None, False),
    ("t7", "Pay the utility bill", False, 0, "Oct 15", False),
    ("t8", "Dentist appointment at 9:30", True, 0, None, False),
]

JA_TASKS = [
    ("t1", "スーパーで食材を買う（トマト・卵・牛乳）", False, 0, "今日 18:00", False),
    ("t2", "母に電話をかける", True, 0, None, False),
    ("t3", "週報を書く", False, 0, "金曜", False),
    ("t4", "先週の議事録を整理する", False, 1, None, False),
    ("t5", "回帰テストの項目を追加", False, 1, None, False),
    ("t6", "技術書の第5章を読む", False, 0, None, False),
    ("t7", "公共料金を支払う", False, 0, "10月15日", False),
    ("t8", "歯医者の予約 9:30", True, 0, None, False),
]

TITLES = {"zh": ("待办清单", "今天", "8 项"), "en": ("To-do", "Today", "8 items"), "ja": ("やること", "今日", "8件")}


def render_list(
    case_id: str,
    locale: str,
    theme: str,
    scale: float,
    tasks,
    *,
    small: bool = False,
    extra_blank: bool = False,
) -> Renderer:
    row_h = BASE_ROW_H * (0.78 if small else 1.0)
    height = BASE_STATUSBAR_H + BASE_APPBAR_H + 1 + SECTION_H + len(tasks) * row_h + 40
    if extra_blank:
        height += row_h * 3
    r = Renderer(case_id, locale, theme, scale, height)
    r.status_bar()
    title, section, count = TITLES[locale]
    r.app_bar(title, count)
    r.section(section)
    for (key, text, checked, indent, due, strike) in tasks:
        r.task_row(key, text, checked, indent=indent, due=due, small=small, strike=strike)
    if extra_blank:
        r.blank_row(3 if not small else 3 * 0.78)
    return r


def render_long(case_id: str, locale: str, theme: str, scale: float, tasks, screens: int = 3) -> Renderer:
    per_screen = BASE_STATUSBAR_H + BASE_APPBAR_H + 1 + SECTION_H + (len(tasks) + 1) * BASE_ROW_H
    height = per_screen * screens + 40
    r = Renderer(case_id, locale, theme, scale, height)
    # The whole image is a scrolling capture: the app bar only exists on the
    # first screen, exactly like a stitched long screenshot.
    title, section, count = TITLES[locale]
    for s in range(screens):
        if s == 0:
            r.status_bar()
            r.app_bar(title, count)
        else:
            r.y += BASE_STATUSBAR_H + BASE_APPBAR_H + 1
        r.section(section)
        for (key, text, checked, indent, due, strike) in tasks:
            r.task_row(f"{key}-s{s + 1}", text, checked, indent=indent, due=due, strike=strike)
        r.blank_row(1.0)
    return r


def build_corpus() -> list[tuple[Renderer, dict]]:
    out: list[tuple[Renderer, dict]] = []

    def add(spec_id: str, r: Renderer, **meta):
        label = {
            "id": spec_id,
            "file": f"images/{spec_id}.png",
            "theme": r.theme_name,
            "locale": meta.pop("locale", r.locale),
            "scale": r.scale,
            "size": [r.width, r.height],
            "tags": meta.pop("tags", []),
            "notes": meta.pop("notes", ""),
            "lines": r.lines,
            "checkboxes": r.checkboxes,
        }
        label.update(meta)
        out.append((r, label))

    add(
        "zh_light_base",
        render_list("zh_light_base", "zh", "light", 1.0, ZH_TASKS),
        locale=["zh", "en"],
        tags=["baseline", "zh", "mixed-latin", "light", "checkbox", "indent"],
        notes="基准：浅色主题，中文为主并夹英文书名与数字；含已完成项和缩进子任务",
    )
    add(
        "zh_dark_base",
        render_list("zh_dark_base", "zh", "dark", 1.0, ZH_TASKS),
        locale=["zh", "en"],
        tags=["dark", "zh", "checkbox", "indent"],
        notes="与 zh_light_base 同内容、深色主题，用于明暗主题对照",
    )
    add(
        "en_light_base",
        render_list("en_light_base", "en", "light", 1.0, EN_TASKS),
        locale=["en"],
        tags=["en", "light", "checkbox"],
        notes="纯英文列表，含长标题与右对齐日期",
    )
    add(
        "ja_light_base",
        render_list("ja_light_base", "ja", "light", 1.0, JA_TASKS),
        locale=["ja"],
        tags=["ja", "light", "checkbox"],
        notes="纯日文列表，含全角括号、中点与日语数字",
    )
    add(
        "zh_small_text",
        render_list("zh_small_text", "zh", "light", 1.0, ZH_TASKS, small=True, extra_blank=True),
        locale=["zh", "en"],
        tags=["small-text", "zh", "light", "blank-area"],
        notes="小字场景：约 24.8px 字号 / 103px 行高（≈0.62x 基准），末尾留空行",
    )
    add(
        "zh_scale_075",
        render_list("zh_scale_075", "zh", "light", 0.75, ZH_TASKS),
        locale=["zh", "en"],
        tags=["scale", "zh", "light"],
        notes="同内容按 0.75 缩放（810x…），模拟低密度屏截图",
    )
    add(
        "zh_scale_150",
        render_list("zh_scale_150", "zh", "light", 1.5, ZH_TASKS),
        locale=["zh", "en"],
        tags=["scale", "zh", "light"],
        notes="同内容按 1.5 缩放（1620x…），模拟高密度屏截图",
    )
    add(
        "zh_long_scroll",
        render_long("zh_long_scroll", "zh", "light", 1.0, ZH_TASKS),
        locale=["zh", "en"],
        tags=["long-image", "zh", "light", "duplicate-content"],
        notes="长图：三屏拼接（1080x…），同一批待办重复三次，用于跨屏重复提示",
    )
    add(
        "zh_dark_long_scroll",
        render_long("zh_dark_long_scroll", "zh", "dark", 1.0, ZH_TASKS),
        locale=["zh", "en"],
        tags=["long-image", "dark", "zh", "duplicate-content"],
        notes="长图 + 深色主题，验证长图耗时与读序是否受主题影响",
    )
    add(
        "en_small_text",
        render_list("en_small_text", "en", "light", 1.0, EN_TASKS, small=True, extra_blank=True),
        locale=["en"],
        tags=["small-text", "en", "light"],
        notes="小字 + 英文，检验小字上两种引擎的差距",
    )
    add(
        "ja_dark_small_text",
        render_list("ja_dark_small_text", "ja", "dark", 1.0, JA_TASKS, small=True, extra_blank=True),
        locale=["ja"],
        tags=["small-text", "ja", "dark"],
        notes="小字 + 日文 + 深色，三者叠加的最难组合",
    )
    return out


#: fixed batch used for the "cold start + 10 images" timing measurement
BATCH_OF_10 = [
    "zh_light_base",
    "zh_dark_base",
    "en_light_base",
    "ja_light_base",
    "zh_small_text",
    "zh_scale_075",
    "zh_scale_150",
    "zh_long_scroll",
    "en_small_text",
    "ja_dark_small_text",
]

#: byte-identical duplicate of another corpus image: the same screenshot picked
#: twice.  Cross-image duplicate detection must only *hint*, never merge silently.
DUPLICATE_PAIRS = [("zh_light_base_dup", "zh_light_base")]


def generate() -> dict:
    os.makedirs(IMAGES, exist_ok=True)
    cases = []
    for r, label in build_corpus():
        path = os.path.join(IMAGES, f"{label['id']}.png")
        r.img.save(path, optimize=True)
        label["sha256"] = sha256_file(path)
        label["bytes"] = os.path.getsize(path)
        cases.append(label)

    # 12th case: a byte-identical copy of zh_light_base, simulating "the user
    # selected the same screenshot twice".
    src = next(c for c in cases if c["id"] == "zh_light_base")
    dup_path = os.path.join(IMAGES, "zh_light_base_dup.png")
    with open(os.path.join(HERE, src["file"]), "rb") as fi, open(dup_path, "wb") as fo:
        fo.write(fi.read())
    dup = dict(src)
    dup["id"] = "zh_light_base_dup"
    dup["file"] = "images/zh_light_base_dup.png"
    dup["duplicate_of"] = "zh_light_base"
    dup["tags"] = ["duplicate-image", "zh", "light"]
    dup["notes"] = "与 zh_light_base 逐字节相同的重复截图，用于跨图重复提示"
    dup["bytes"] = os.path.getsize(dup_path)
    dup["sha256"] = sha256_file(dup_path)
    cases.append(dup)

    batch = list(BATCH_OF_10)
    doc = {
        "schema": "wp17r2-samples/1",
        "generator": "samples/gen_samples.py",
        "generator_sha256": sha256_file(os.path.abspath(__file__)),
        "fonts": {f"{k[0]}/{k[1]}": v[0] for k, v in FONT_FILES.items()},
        "base": {"width": BASE_W, "row_height": BASE_ROW_H, "font_px": BASE_FONT},
        "batch_of_10": batch,
        "duplicate_pairs": DUPLICATE_PAIRS,
        "cases": cases,
    }
    with open(LABELS, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write("\n")
    return doc


def check() -> int:
    with open(LABELS, encoding="utf-8") as f:
        doc = json.load(f)
    bad = 0
    for case in doc["cases"]:
        path = os.path.join(HERE, case["file"])
        if not os.path.exists(path):
            print(f"MISSING {case['file']}")
            bad += 1
            continue
        got = sha256_file(path)
        if got != case["sha256"]:
            print(f"CHANGED {case['file']} {got[:12]} != {case['sha256'][:12]}")
            bad += 1
    print(f"{'FAIL' if bad else 'OK'}: {len(doc['cases'])} cases, {bad} mismatched")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        raise SystemExit(check())
    d = generate()
    total = sum(c["bytes"] for c in d["cases"])
    print(f"wrote {len(d['cases'])} images ({total / 1024:.0f} KiB) -> {IMAGES}")
    print(f"wrote {LABELS}")
    for c in d["cases"]:
        print(f"  {c['id']:22} {c['size'][0]:>5}x{c['size'][1]:<5} {c['bytes'] / 1024:>7.1f} KiB  {c['sha256'][:12]}")
