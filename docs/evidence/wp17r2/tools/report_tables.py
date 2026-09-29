#!/usr/bin/env python3
"""Emit the markdown tables quoted by docs/WP17_OCR_EVALUATION.md.

Reads every results/<platform>/summary.json plus the on-disk model / binary
sizes, so the numbers in the report can be regenerated instead of retyped.
"""
from __future__ import annotations

import json
import os

from wp17r2lib import RESULTS, asset_root

PLATFORMS = ["win", "linux", "android"]


def load_all():
    out = {}
    for p in PLATFORMS:
        f = os.path.join(RESULTS, p, "summary.json")
        if os.path.exists(f):
            with open(f, encoding="utf-8") as fh:
                out[p] = json.load(fh)
    return out


def fmt(v, n=1):
    return "-" if v is None else f"{v:.{n}f}"


def main():
    data = load_all()
    L = []
    A = L.append

    A("## A. 冷启动 / 批处理 / 峰值内存\n")
    A("| 平台 | 配置 | 模型加载 ms | 首图 ms | 冷启动到首结果 ms | 10 张批处理 ms | 单张中位 ms | 峰值内存 MiB |")
    A("|---|---|---:|---:|---:|---:|---:|---:|")
    for p in PLATFORMS:
        if p not in data:
            continue
        for cid, e in data[p]["runs"].items():
            cs, b10 = e.get("cold_start"), e.get("batch10")
            rss = (b10 or cs or {}).get("peak_rss_kb")
            A(
                "| {} | `{}` | {} | {} | {} | {} | {} | {} |".format(
                    p, cid,
                    fmt(cs and cs["model_load_ms"], 0),
                    fmt(cs and cs["first_image_ms"], 0),
                    fmt(cs and cs["cold_to_first_result_ms"], 0),
                    fmt(b10 and b10["batch_total_ms"], 0),
                    fmt(b10 and b10["median_per_image_ms"], 0),
                    fmt(rss and rss / 1024.0, 0),
                )
            )

    A("\n## B. 文字评分（逐行对齐后编辑距离）\n")
    A("| 平台 | 配置 | CER(micro) | CER(macro) | 漏检 GT 行 | 误检行 | 误检字符 | 行完全正确率 | 任务行 CER | 非任务行 CER |")
    A("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for p in PLATFORMS:
        if p not in data:
            continue
        for cid, e in data[p]["runs"].items():
            t = e.get("text", {}).get("aggregate")
            if not t:
                A(f"| {p} | `{cid}` | 未评分 | | | | | | | |")
                continue
            rows = e["text"]["per_image"]
            tl = [r["task_line_cer"] for r in rows if r["task_line_cer"] is not None]
            dl = [r["decor_line_cer"] for r in rows if r["decor_line_cer"] is not None]
            A(
                "| {} | `{}` | {:.4f} | {:.4f} | {} | {} | {} | {:.3f} | {} | {} |".format(
                    p, cid, t["cer_micro"], t["cer_macro"], t["missed_gt_lines"],
                    t["spurious_rec_lines"], t["spurious_chars"], t["line_exact_rate_macro"],
                    fmt(sum(tl) / len(tl), 4) if tl else "-",
                    fmt(sum(dl) / len(dl), 4) if dl else "-",
                )
            )

    A("\n## C. 任务结构评分\n")
    A("| 平台 | 配置 | 任务召回 | 任务准确 | GT 任务 | 预测任务 | 误提取 | 勾选态正确 | 父级正确 | 截止时间正确 | 任务序完全一致图数 | Kendall |")
    A("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for p in PLATFORMS:
        if p not in data:
            continue
        for cid, e in data[p]["runs"].items():
            s = e.get("structure", {}).get("aggregate")
            if not s:
                A(f"| {p} | `{cid}` | 未评分 | | | | | | | | | |")
                continue
            n = s["images"]
            A(
                "| {} | `{}` | {:.3f} | {:.3f} | {} | {} | {} | {} | {} | {} | {}/{} | {:.3f} |".format(
                    p, cid, s["task_recall_micro"], s["task_precision_micro"], s["gt_tasks"],
                    s["pred_tasks"], s["spurious_total"],
                    fmt(s["checked_accuracy_macro"], 3), fmt(s["parent_accuracy_macro"], 3),
                    fmt(s["due_accuracy_macro"], 3), s["order_task_exact_images"], n,
                    s["order_task_kendall_macro"],
                )
            )

    A("\n## C2. 阅读顺序与需人工确认项\n")
    A("| 平台 | 配置 | 引擎原生行序正确图数 | 适配器分组后行序正确图数 | 任务序正确图数 | 任务序 Kendall | 需人工确认项 | 合并错误(GT 多行→1 行) |")
    A("|---|---|---:|---:|---:|---:|---:|---:|")
    for p in PLATFORMS:
        if p not in data:
            continue
        for cid, e in data[p]["runs"].items():
            s = e.get("structure", {}).get("aggregate")
            t = e.get("text", {}).get("aggregate")
            if not s:
                continue
            A(
                "| {} | `{}` | {}/{} | {}/{} | {}/{} | {:.3f} | {} | {} |".format(
                    p, cid, s["order_engine_native_exact_images"], s["images"],
                    s["order_after_adapter_exact_images"], s["images"],
                    s["order_task_exact_images"], s["images"],
                    s["order_task_kendall_macro"], s["needs_confirmation_total"],
                    t["merged_gt_lines"] if t else "-",
                )
            )

    A("\n## D. 逐图 CER（主配置）\n")
    cases = None
    for p in PLATFORMS:
        if p not in data:
            continue
        for cid, e in data[p]["runs"].items():
            if not e.get("config", {}).get("primary") or "text" not in e:
                continue
            ids = [r["id"] for r in e["text"]["per_image"]]
            cases = cases or ids
            A(f"### {p} / {cid}\n")
            A("| 用例 | " + " | ".join(ids) + " |")
            A("|" + "---|" * (len(ids) + 1))
            vals = {r["id"]: r["cer"] for r in e["text"]["per_image"]}
            A("| CER | " + " | ".join(f"{vals.get(i, float('nan')):.3f}" for i in ids) + " |")

    A("\n## E. 逐图任务结构（主配置）\n")
    for p in PLATFORMS:
        if p not in data:
            continue
        for cid, e in data[p]["runs"].items():
            if not e.get("config", {}).get("primary") or "structure" not in e:
                continue
            A(f"### {p} / {cid}\n")
            A("| 用例 | GT 任务 | 预测 | 命中 | 漏 | 误提取 | 勾选态 | 父级 | 任务序一致 |")
            A("|---|---:|---:|---:|---:|---:|---:|---:|---|")
            for r in e["structure"]["per_image"]:
                A(
                    "| {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                        r["id"], r["gt_tasks"], r["pred_tasks"], r["true_positive"], r["missing"],
                        r["spurious"], fmt(r["checked_accuracy"], 3), fmt(r["parent_accuracy"], 3),
                        "是" if r["order_task_exact"] else "否",
                    )
                )

    A("\n## F. 体积\n")
    a = asset_root()
    sizes = []
    for label, rel in [
        ("det param", r"ncnn\PP_OCRv5_mobile_det.ncnn.param"),
        ("det bin", r"ncnn\PP_OCRv5_mobile_det.ncnn.bin"),
        ("rec param", r"ncnn\PP_OCRv5_mobile_rec.ncnn.param"),
        ("rec bin", r"ncnn\PP_OCRv5_mobile_rec.ncnn.bin"),
        ("dict", r"ncnn\ppocrv5_dict.txt"),
        ("tessdata chi_sim", r"tessdata_fast\chi_sim.traineddata"),
        ("tessdata eng", r"tessdata_fast\eng.traineddata"),
        ("tessdata jpn", r"tessdata_fast\jpn.traineddata"),
        ("android x86_64 cli (stripped)", r"build-android-x86_64\wp17r2_ocr.stripped"),
        ("android arm64-v8a cli (stripped)", r"build-android-arm64-v8a\wp17r2_ocr.stripped"),
    ]:
        p = os.path.join(a, rel)
        if os.path.exists(p):
            sizes.append((label, os.path.getsize(p)))
    A("| 资产 | 字节 | KiB |")
    A("|---|---:|---:|")
    for label, n in sizes:
        A(f"| {label} | {n} | {n / 1024.0:.1f} |")

    text = "\n".join(L) + "\n"
    out = os.path.join(RESULTS, "tables.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    print(text)
    print("wrote", out)


if __name__ == "__main__":
    main()
