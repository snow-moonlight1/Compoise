#!/usr/bin/env python3
"""Parse a restricted GitHub Actions YAML subset and lint the WP28-R3 workflow."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/wp28-native-validation.yml"
REQUIRED_RUNNER = (
    "interactive Windows session that can CreateDesktop and OpenInputDesktop; "
    "a hosted runner without a usable desktop is a failure, not a skip"
)
FORBIDDEN_TEXT = (
    "secrets.",
    "contents: write",
    "continue-on-error",
    "id-token",
    "softprops/action-gh-release",
    "Windows Sandbox",
    "skip-success",
    "workflow_dispatch:\n    inputs:",
)


def _split_key(text: str):
    if text.startswith("'") or text.startswith('"'):
        quote = text[0]
        end = text.find(quote, 1)
        if end < 0 or end + 1 >= len(text) or text[end + 1] != ":":
            raise ValueError(f"Invalid quoted key: {text}")
        return text[1:end], text[end + 2:].strip()
    match = re.match(r"([^:]+):(.*)$", text)
    if not match:
        raise ValueError(f"Expected key: value, got {text}")
    return match.group(1).strip(), match.group(2).strip()


def _parse_scalar(text: str):
    if text == "" or text in ("null", "~"):
        return None
    if text in ("true", "True"):
        return True
    if text in ("false", "False"):
        return False
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if (text.startswith('"') and text.endswith('"')) or (text.startswith("'") and text.endswith("'")):
        return text[1:-1]
    return text


def parse_yaml(text: str):
    lines = text.splitlines()
    n = len(lines)

    def indent_of(i: int) -> int:
        return len(lines[i]) - len(lines[i].lstrip(" "))

    def skip(i: int) -> int:
        while i < n:
            stripped = lines[i].strip()
            if stripped == "" or stripped.startswith("#"):
                i += 1
                continue
            return i
        return i

    def parse_literal(i: int, parent_indent: int):
        chunks = []
        content_indent = None
        while i < n:
            raw = lines[i]
            if raw.strip() == "":
                chunks.append("")
                i += 1
                continue
            if indent_of(i) <= parent_indent:
                break
            if content_indent is None:
                content_indent = indent_of(i)
            chunks.append(raw[content_indent:])
            i += 1
        while chunks and chunks[-1] == "":
            chunks.pop()
        return "\n".join(chunks) + ("\n" if chunks else ""), i

    def parse_value(i: int, parent_indent: int, inline: str):
        if inline == "|":
            return parse_literal(i, parent_indent)
        if inline != "":
            return _parse_scalar(inline), i
        nxt = skip(i)
        if nxt >= n or indent_of(nxt) <= parent_indent:
            return None, i
        return parse_node(nxt, indent_of(nxt))

    def parse_map_from(i: int, ind: int, first_key=None, first_inline=None):
        result = {}
        if first_key is not None:
            value, i = parse_value(i, ind, first_inline)
            result[first_key] = value
        while True:
            i = skip(i)
            if i >= n:
                return result, i
            if indent_of(i) != ind or lines[i].lstrip().startswith("- "):
                return result, i
            key, inline = _split_key(lines[i].strip())
            value, i = parse_value(i + 1, ind, inline)
            result[key] = value

    def parse_list(i: int, ind: int):
        items = []
        while True:
            i = skip(i)
            if i >= n or indent_of(i) != ind or not lines[i].lstrip().startswith("- "):
                return items, i
            body = lines[i].strip()[2:]
            if body == "|" or (body.endswith(":") and body != ":") or (":" in body and not body.startswith("{")):
                if body == "|":
                    value, i = parse_literal(i + 1, ind)
                    items.append(value)
                    continue
                key, inline = _split_key(body)
                value, i = parse_value(i + 1, ind, inline)
                item = {key: value}
                extra, i = parse_map_from(i, ind + 2)
                item.update(extra)
                items.append(item)
            else:
                items.append(_parse_scalar(body))
                i += 1

    def parse_node(i: int, ind: int):
        i = skip(i)
        if i >= n:
            return None, i
        if lines[i].lstrip().startswith("- "):
            return parse_list(i, ind)
        return parse_map_from(i, ind)

    i = skip(0)
    if i >= n:
        return {}
    doc, i = parse_node(i, indent_of(i))
    i = skip(i)
    if i < n:
        raise ValueError(f"Unconsumed YAML at line {i + 1}: {lines[i]}")
    return doc


def _runs(job: dict) -> str:
    chunks = []
    for step in job.get("steps") or []:
        run = step.get("run")
        if isinstance(run, str):
            chunks.append(run)
    return "\n".join(chunks)


def lint_workflow(doc: dict, text: str) -> list[str]:
    errors = []
    for token in FORBIDDEN_TEXT:
        if token in text:
            errors.append(f"forbidden {token.strip()!r}")
    triggers = doc.get("on")
    if not isinstance(triggers, dict) or "pull_request" not in triggers or "workflow_dispatch" not in triggers:
        errors.append("triggers must include pull_request and workflow_dispatch")
    if isinstance(triggers, dict) and "push" in triggers:
        errors.append("workflow must not auto-run on every push")
    permissions = doc.get("permissions")
    if not isinstance(permissions, dict) or permissions.get("contents") != "read":
        errors.append("permissions.contents must be read")
    if permissions and permissions.get("actions") != "write":
        errors.append("permissions.actions must be write for evidence upload")
    extra_perm = set(permissions or []) - {"contents", "actions"}
    if extra_perm:
        errors.append(f"extra permissions {sorted(extra_perm)}")
    concurrency = doc.get("concurrency")
    if not isinstance(concurrency, dict) or not concurrency.get("group") or concurrency.get("cancel-in-progress") is not True:
        errors.append("concurrency group and cancel-in-progress: true are required")
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or "windows-native-matrix" not in jobs:
        errors.append("missing windows-native-matrix job")
        return errors
    if set(jobs) != {"windows-native-matrix"}:
        errors.append(f"unexpected jobs {sorted(jobs)}")
    job = jobs["windows-native-matrix"]
    if job.get("runs-on") != "windows-2022":
        errors.append("job must run on windows-2022")
    timeout = job.get("timeout-minutes")
    if not isinstance(timeout, int) or timeout < 120:
        errors.append("job timeout-minutes must be >= 120")
    steps = job.get("steps")
    if not isinstance(steps, list) or not steps:
        errors.append("job has no steps")
        return errors
    for step in steps:
        if step.get("continue-on-error") is True:
            errors.append(f"continue-on-error on step {step.get('name')}")
        when = step.get("if")
        if when in ("false", False, "skipped", "success()"):
            errors.append(f"skip-style if on step {step.get('name')}: {when}")
    names = [step.get("name") for step in steps]
    uses = [step.get("uses") for step in steps]
    if "actions/checkout@v4" not in uses:
        errors.append("missing checkout")
    if "subosito/flutter-action@v2" not in uses:
        errors.append("missing Flutter action")
    upload = [step for step in steps if str(step.get("uses", "")).startswith("actions/upload-artifact@")]
    if len(upload) != 1:
        errors.append("exactly one upload-artifact step is required")
    else:
        step = upload[0]
        if step.get("if") != "always()":
            errors.append("evidence upload must use if: always()")
        with_ = step.get("with") or {}
        if with_.get("if-no-files-found") != "error":
            errors.append("upload if-no-files-found must be error")
        path = str(with_.get("path") or "")
        if "WP28_R3_EVIDENCE" not in path:
            errors.append("upload path must be the private evidence root")
    body = _runs(job)
    combined = body + "\n" + text
    for token in (
        "wp28_r3_windows_ci.ps1",
        "-Run",
        "-EvidenceDirectory",
        "-Flutter",
        "-ReportTimeoutMs",
        "-ExitTimeoutMs",
        "-GateTimeoutMs",
        "flutter pub get --enforce-lockfile",
        "verify_flutter_version.js",
        "test_wp28_r3",
        "WP28_R3_EVIDENCE",
        "[guid]::NewGuid()",
    ):
        if token not in combined:
            errors.append(f"missing command token {token}")
    if "3.32.8" not in text:
        errors.append("workflow must pin Flutter 3.32.8")
    if "not a skip" not in text:
        errors.append("workflow must state that a missing desktop is a failure, not a skip")
    return errors


def load_workflow(path: Path | None = None) -> tuple[dict, str]:
    target = path or WORKFLOW
    text = target.read_text(encoding="utf-8")
    return parse_yaml(text), text


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, default=WORKFLOW)
    parser.add_argument("--print-json", action="store_true")
    args = parser.parse_args(argv)
    doc, text = load_workflow(args.file)
    errors = lint_workflow(doc, text)
    if args.print_json:
        print(json.dumps(doc, indent=2))
    if errors:
        print("WORKFLOW LINT FAIL", file=sys.stderr)
        for item in errors:
            print(item, file=sys.stderr)
        return 1
    print(f"workflow lint: PASS ({args.file})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
