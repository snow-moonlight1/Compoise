#!/usr/bin/env python3
"""WP17-Q3 quality gate: generate, validate, score, compare.

Real-model scoring runs only with --enable-model. The default selftest does
not download a model or start a device.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from q3_common import Q3Error, require_outside_repo
from q3_compare import compare_reports
from q3_dict_probe import probe_assets
from q3_generate import generate
from q3_model import recognize_directory
from q3_score import failure_reasons, load_json, score_labels
from q3_validate import validate_tree


def _print(payload) -> None:
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True))


def _write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def command_generate(args) -> int:
    labels = generate(args.out, args.font)
    problems = validate_tree(args.out)
    if problems:
        raise Q3Error("generated labels failed validation:\n" + "\n".join(problems))
    _print({"dataset_id": labels["dataset_id"], "cases": len(labels["cases"]),
            "tasks": sum(len(case["tasks"]) for case in labels["cases"])})
    return 0


def command_validate(args) -> int:
    problems = validate_tree(args.labels)
    if args.font:
        from q3_common import font_license_excerpt, sha256_file
        labels = load_json(args.labels / "labels.json", "labels")
        data = args.font.read_bytes()
        if sha256_file(args.font) != labels.get("font", {}).get("sha256"):
            problems.append("font file sha256 does not match labels")
        if "SIL Open Font License" not in font_license_excerpt(data):
            problems.append("font file has no SIL Open Font License string")
    if problems:
        raise Q3Error("\n".join(problems))
    _print({"status": "ok", "labels": str(args.labels)})
    return 0


def command_score(args) -> int:
    if args.enable_model == bool(args.raw):
        raise Q3Error("score needs exactly one of --raw or --enable-model")
    if args.enable_model and (args.library is None or args.assets is None):
        raise Q3Error("enable-model needs --library and --assets")
    out = require_outside_repo(args.out)
    if validate_tree(args.labels):
        raise Q3Error("bad ground truth:\n" + "\n".join(validate_tree(args.labels)))
    draft = load_json(args.draft, "draft") if args.draft else None
    if args.enable_model:
        labels = load_json(args.labels / "labels.json", "labels")
        raw = recognize_directory(args.library, args.assets, args.labels, labels["cases"], args.threads)
        _write(out / "raw.json", raw)
        report_path = out / "score.json"
    else:
        raw = load_json(args.raw, "raw")
        report_path = out
    report = score_labels(args.labels, raw, draft)
    _write(report_path, report)
    reasons = failure_reasons(report, args.fail_on_empty)
    summary = {
        "strict_edits": report["raw"]["strict"]["edits"],
        "strict_ref": report["raw"]["strict"]["ref_chars"],
        "stripped_edits": report["raw"]["stripped"]["edits"],
        "stripped_ref": report["raw"]["stripped"]["ref_chars"],
        "missed_lines": report["raw"]["missed_lines"],
        "extra_lines": report["raw"]["extra_lines"],
        "empty_images": report["raw"]["empty_images"],
        "failed_images": report["raw"]["failed_images"],
        "draft": report["draft"].get("supplied"),
        "report": str(report_path),
    }
    _print(summary)
    if reasons:
        raise Q3Error("\n".join(reasons))
    return 0


def command_compare(args) -> int:
    left = load_json(args.left, "left")
    right = load_json(args.right, "right")
    problems, delta = compare_reports(left, right, args.max_strict_edit_increase)
    if problems:
        raise Q3Error("\n".join(problems))
    _print(delta)
    return 0


def command_probe(args) -> int:
    report = probe_assets(args.assets)
    if args.out:
        _write(require_outside_repo(args.out), report)
    _print({
        "sha256": report["sha256"],
        "ascii_space_indexes": report["ascii_space_u0020_indexes"],
        "ideographic_space_indexes": report["ideographic_space_u3000_indexes"],
        "first_token_codepoints": report["first_token_codepoints"],
        "tokens": report["tokens_after_loader"],
    })
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    generate_parser = commands.add_parser("generate")
    generate_parser.add_argument("--out", type=Path, required=True)
    generate_parser.add_argument("--font", type=Path, required=True)
    generate_parser.set_defaults(func=command_generate)

    validate_parser = commands.add_parser("validate")
    validate_parser.add_argument("--labels", type=Path, required=True)
    validate_parser.add_argument("--font", type=Path)
    validate_parser.set_defaults(func=command_validate)

    score_parser = commands.add_parser("score")
    score_parser.add_argument("--labels", type=Path, required=True)
    score_parser.add_argument("--out", type=Path, required=True)
    score_parser.add_argument("--raw", type=Path)
    score_parser.add_argument("--draft", type=Path)
    score_parser.add_argument("--enable-model", action="store_true")
    score_parser.add_argument("--library", type=Path)
    score_parser.add_argument("--assets", type=Path)
    score_parser.add_argument("--threads", type=int, default=4)
    score_parser.add_argument("--fail-on-empty", action="store_true")
    score_parser.set_defaults(func=command_score)

    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("--left", type=Path, required=True)
    compare_parser.add_argument("--right", type=Path, required=True)
    compare_parser.add_argument("--max-strict-edit-increase", type=int)
    compare_parser.set_defaults(func=command_compare)

    probe_parser = commands.add_parser("probe-dict")
    probe_parser.add_argument("--assets", type=Path, required=True)
    probe_parser.add_argument("--out", type=Path)
    probe_parser.set_defaults(func=command_probe)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except Q3Error as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
