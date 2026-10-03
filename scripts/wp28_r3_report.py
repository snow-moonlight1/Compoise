#!/usr/bin/env python3
"""Assemble and classify WP28-R3 native CI evidence. Never treats skip as pass."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

EXPECTED_RESULTS = 20
EXPECTED_PROCESSES = 73
RUNTIME_CASES = (
    "missing-run", "missing-guid", "bad-guid", "missing-root", "temp-root",
    "workspace-root", "wrong-guid-root", "dot-root", "relative-root", "file-root",
)
BUILD_CASES = ("native-only", "dart-only", "combined")
PASS_CLEANUP = "not-needed"
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$", re.I)
REQUIRED_RUNNER = (
    "interactive Windows session that can CreateDesktop and OpenInputDesktop; "
    "a hosted runner without a usable desktop is a failure, not a skip"
)


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def first_glob(root: Path, pattern: str):
    matches = sorted(p for p in root.glob(pattern) if p.is_file())
    return matches[0] if matches else None


def collect_skips(value, prefix=""):
    found = []
    if isinstance(value, dict):
        if value.get("skip") is True or value.get("skipped") is True or value.get("status") in ("skipped", "skip"):
            found.append(prefix or "root")
        for key, child in value.items():
            found.extend(collect_skips(child, f"{prefix}.{key}" if prefix else str(key)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(collect_skips(child, f"{prefix}[{index}]"))
    return found


FRESH_LOGS = {"orchestrator.stdout.log", "orchestrator.stderr.log"}


def require_fresh(evidence: Path):
    if not evidence.is_dir() or evidence.is_symlink():
        raise ValueError("Evidence directory missing or linked")
    blocked = []
    for path in evidence.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(evidence).as_posix()
        if rel in FRESH_LOGS:
            continue
        if rel == "ci-report.json":
            data = load_json(path)
            if data.get("passed") is True:
                blocked.append("passing ci-report.json")
            elif data.get("status") not in ("allocated", "running"):
                blocked.append(f"completed ci-report.json status={data.get('status')}")
            continue
        blocked.append(rel)
    if blocked:
        raise ValueError("Evidence directory is not fresh: " + ", ".join(blocked))


def classify_processes(processes):
    failures = []
    for proc in as_list(processes):
        pid = proc.get("pid")
        if proc.get("timedOut") is True:
            failures.append(f"timeout pid={pid}")
        if proc.get("alive") is True:
            failures.append(f"alive pid={pid}")
        if proc.get("exitCode") is None:
            failures.append(f"unknown_gate_status pid={pid}")
        elif proc.get("exitCode") != 0:
            failures.append(f"exit {proc.get('exitCode')} pid={pid}")
        cleanup = proc.get("cleanup")
        if cleanup != PASS_CLEANUP:
            failures.append(f"cleanup {cleanup} pid={pid}")
    return failures


def classify_runtime_gates(doc):
    failures = []
    if doc.get("exitCode") != 0:
        failures.append(f"runtime_gates_script_exit={doc.get('exitCode')}")
    cases = {item.get("case"): item for item in as_list(doc.get("cases"))}
    for name in RUNTIME_CASES:
        case = cases.get(name)
        if case is None:
            failures.append(f"missing_runtime_case {name}")
            continue
        if case.get("timedOut") is True:
            failures.append(f"timeout {name}")
        if case.get("alive") is True:
            failures.append(f"alive {name}")
        if case.get("exitCode") is None:
            failures.append(f"unknown_gate_status {name}")
        elif case.get("exitCode") != 2:
            failures.append(f"runtime_exit {name}={case.get('exitCode')}")
        if case.get("cleanup") not in (None, PASS_CLEANUP):
            failures.append(f"cleanup {name} {case.get('cleanup')}")
    extra = set(cases) - set(RUNTIME_CASES)
    if extra:
        failures.append("unexpected_runtime_cases " + ",".join(sorted(extra)))
    return failures


def classify_build_gates(doc):
    failures = []
    if doc.get("exitCode") != 0:
        failures.append(f"build_gates_script_exit={doc.get('exitCode')}")
    cases = {item.get("case"): item for item in as_list(doc.get("cases"))}
    for name in BUILD_CASES:
        case = cases.get(name)
        if case is None:
            failures.append(f"missing_build_case {name}")
            continue
        if case.get("exitCode") is None:
            failures.append(f"unknown_gate_status {name}")
        elif case.get("exitCode") == 0:
            failures.append(f"build_gate_accepted {name}")
    extra = set(cases) - set(BUILD_CASES)
    if extra:
        failures.append("unexpected_build_cases " + ",".join(sorted(extra)))
    return failures


def _source_sha(blob):
    if not isinstance(blob, dict):
        return None
    value = blob.get("diffSha256")
    if isinstance(value, str) and SHA_RE.fullmatch(value):
        return value
    return None


def bind_configuration(evidence: Path, config: str, commit: str, source_sha: str):
    failures = []
    diagnostic_path = evidence / config / f"diagnostic-{config}.json"
    if not diagnostic_path.is_file():
        return [f"missing_diagnostic {config}"], None
    diagnostic = load_json(diagnostic_path)
    if diagnostic.get("normalCandidate") is not False:
        failures.append(f"normalCandidate {config} diagnostic")
    if diagnostic.get("commit") != commit:
        failures.append(f"diagnostic_commit {config}")
    if _source_sha(diagnostic.get("source")) != source_sha:
        failures.append(f"diagnostic_source {config}")
    if diagnostic.get("buildExitCode") != 0:
        failures.append(f"diagnostic_build {config}={diagnostic.get('buildExitCode')}")
    exe = diagnostic.get("executableSHA256")
    if not (isinstance(exe, str) and SHA_RE.fullmatch(exe)):
        failures.append(f"diagnostic_exe_hash {config}")
    files = as_list(diagnostic.get("files"))
    if not files:
        failures.append(f"diagnostic_files {config}")
    for item in files:
        if not item.get("path") or item.get("bytes") is None or not SHA_RE.fullmatch(str(item.get("sha256", ""))):
            failures.append(f"diagnostic_file_hash {config} {item.get('path')}")
            break
    matrix_path = first_glob(evidence / config, "**/harness.json")
    if matrix_path is None:
        return failures + [f"missing_matrix {config}"], {
            "diagnostic": str(diagnostic_path),
            "matrix": None,
            "runtimeGates": None,
            "executableSHA256": exe,
            "files": files,
        }
    matrix = load_json(matrix_path)
    if matrix.get("passed") is not True:
        failures.append(f"matrix_not_passed {config}")
    if matrix.get("normalCandidate") is not False:
        failures.append(f"normalCandidate {config} matrix")
    if matrix.get("commit") != commit:
        failures.append(f"matrix_commit {config}")
    if _source_sha(matrix.get("source")) != source_sha:
        failures.append(f"matrix_source {config}")
    if matrix.get("executableSHA256") != exe:
        failures.append(f"exe_hash_mismatch {config}")
    failures.extend(f"skip {config}.matrix{path}" for path in collect_skips(matrix))
    results = as_list(matrix.get("results"))
    if len(results) != EXPECTED_RESULTS:
        failures.append(f"scenario_count {config}={len(results)}")
    for item in results:
        if item.get("passed") is not True:
            failures.append(f"scenario_failed {config} {item.get('scenario')}")
    processes = as_list(matrix.get("processes"))
    if len(processes) != EXPECTED_PROCESSES:
        failures.append(f"process_count {config}={len(processes)}")
    failures.extend(f"{config} {msg}" for msg in classify_processes(processes))
    gates_path = first_glob(evidence / config, "**/gates-Runtime-*/result.json")
    if gates_path is None:
        failures.append(f"missing_runtime_gates {config}")
        runtime = None
    else:
        runtime = load_json(gates_path)
        if _source_sha(runtime.get("sourceAtCheck")) != source_sha:
            failures.append(f"runtime_source {config}")
        failures.extend(f"skip {config}.runtime{path}" for path in collect_skips(runtime))
        failures.extend(f"{config} {msg}" for msg in classify_runtime_gates(runtime))
    return failures, {
        "diagnostic": str(diagnostic_path),
        "matrix": str(matrix_path),
        "runtimeGates": str(gates_path) if gates_path else None,
        "executableSHA256": exe,
        "files": files,
        "scenarioCount": len(results),
        "processCount": len(processes),
    }


def assemble(evidence: Path, commit: str, configuration: str):
    failures = []
    if not COMMIT_RE.fullmatch(commit):
        failures.append("commit must be a full SHA")
    source_path = evidence / "source.json"
    source = load_json(source_path) if source_path.is_file() else {}
    source_sha = _source_sha(source)
    if source_sha is None:
        failures.append("missing_source")
    desktop_path = evidence / "desktop.json"
    desktop = load_json(desktop_path) if desktop_path.is_file() else {}
    if not desktop_path.is_file():
        failures.append("missing_desktop_probe")
    elif desktop.get("usable") is not True:
        failures.append("desktop_unavailable")
    configs = ("Debug", "Release") if configuration == "All" else (configuration,)
    configurations = {}
    if source_sha and COMMIT_RE.fullmatch(commit):
        for config in configs:
            item_failures, summary = bind_configuration(evidence, config, commit, source_sha)
            failures.extend(item_failures)
            configurations[config] = summary
    build_path = first_glob(evidence, "**/gates-Build-*/result.json")
    build = None
    if build_path is None:
        if desktop.get("usable") is True:
            failures.append("missing_build_gates")
    else:
        build = load_json(build_path)
        if build.get("commit") != commit:
            failures.append("build_gates_commit")
        failures.extend(classify_build_gates(build))
    for label, blob in (("desktop", desktop), ("source", source), ("build", build or {}), *[(name, load_json(Path(summary["diagnostic"]))) for name, summary in configurations.items() if summary and summary.get("diagnostic") and Path(summary["diagnostic"]).is_file()]):
        failures.extend(f"skip {label}{path}" for path in collect_skips(blob))
    unique = []
    for item in failures:
        if item not in unique:
            unique.append(item)
    report = {
        "schema": 1,
        "status": "complete",
        "passed": not unique,
        "skip": False,
        "normalCandidate": False,
        "commit": commit,
        "source": source,
        "desktop": desktop,
        "requiredRunner": REQUIRED_RUNNER,
        "configuration": configuration,
        "configurations": configurations,
        "buildGates": str(build_path) if build_path else None,
        "failures": unique,
        "reusedReport": False,
    }
    return report


def write_report(path: Path, report: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    fresh = sub.add_parser("require-fresh")
    fresh.add_argument("--evidence", type=Path, required=True)
    asm = sub.add_parser("assemble")
    asm.add_argument("--evidence", type=Path, required=True)
    asm.add_argument("--commit", required=True)
    asm.add_argument("--configuration", default="All")
    asm.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "require-fresh":
            require_fresh(args.evidence)
            print(f"require-fresh: PASS ({args.evidence})")
            return 0
        report = assemble(args.evidence, args.commit, args.configuration)
        write_report(args.output, report)
        if not report["passed"]:
            print("assemble: FAIL", file=sys.stderr)
            for item in report["failures"]:
                print(item, file=sys.stderr)
            return 1
        print(f"assemble: PASS ({args.output})")
        return 0
    except Exception as exc:
        if args.command == "assemble":
            failure = {
                "schema": 1,
                "status": "complete",
                "passed": False,
                "skip": False,
                "normalCandidate": False,
                "commit": getattr(args, "commit", ""),
                "failures": [str(exc)],
                "reusedReport": "not fresh" in str(exc).lower() or "reuse" in str(exc).lower(),
                "requiredRunner": REQUIRED_RUNNER,
            }
            try:
                write_report(args.output, failure)
            except Exception:
                pass
        print(f"{args.command}: FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
