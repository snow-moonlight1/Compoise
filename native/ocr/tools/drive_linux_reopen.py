#!/usr/bin/env python3
"""Explicit I7 acceptance: production GTK selection, then a separate disk reader."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

from drive_official_import import Linux

MARKERS = ("WP17_I7_CANCEL_READY", "WP17_I7_REVIEW_CANCEL_READY", "WP17_I7_SAVE_READY")


def hashes(directory: Path) -> dict:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(directory.glob("*.png"))}


def validate_report(report: dict, phase: str, pid: int):
    if report.get("passed") is not True or report.get("phase") != phase or report.get("pid") != pid:
        raise RuntimeError("Missing or failed actual application report: " + phase)
    if phase == "import" and (report.get("real_picker") is not True or report.get("real_ocr") is not True):
        raise RuntimeError("Import must use the production picker and native OCR")
    if phase == "reopen" and report.get("independent_disk_reopen") is not True:
        raise RuntimeError("Second process did not read production Store")


def execute(application: Path, repo: Path, directory: Path, phase: str, env: dict, picker: Linux) -> dict:
    log = directory / f"application-{phase}.log"
    report = directory / f"flow-{phase}.json"
    phase_env = dict(env, WP17_I7_PHASE=phase, WP17_I7_REPORT=str(report))
    seen = set()
    started = time.monotonic()
    peak = 0
    error = None
    with log.open("w") as output:
        process = subprocess.Popen([str(application)], cwd=repo, env=phase_env,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                data = log.read_text(errors="replace")
                if phase == "import":
                    for marker in MARKERS:
                        if marker in data and marker not in seen:
                            seen.add(marker)
                            picker.choose(marker == MARKERS[0])
                try:
                    status = Path(f"/proc/{process.pid}/status").read_text()
                    line = next(line for line in status.splitlines() if line.startswith("VmHWM:"))
                    peak = max(peak, int(line.split()[1]))
                except (OSError, StopIteration):
                    pass
                if time.monotonic() - started > 900:
                    raise RuntimeError("Dedicated application timed out")
                time.sleep(0.2)
        except Exception as exception:
            error = str(exception)
        finally:
            # Only this application's process group. A terminated failure can
            # never satisfy normal_exit, even if a stale success report exists.
            forced = process.poll() is None
            if forced:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
    result = {"phase": phase, "pid": process.pid, "exit": code,
              "normal_exit": not forced and code == 0, "error": error,
              "elapsed_ms": round((time.monotonic() - started) * 1000),
              "peak_vm_hwm_kib": peak, "markers": sorted(seen)}
    (directory / f"process-{phase}.json").write_text(json.dumps(result, indent=2) + "\n")
    if error or not result["normal_exit"]:
        raise RuntimeError("Application failed: " + json.dumps(result))
    validate_report(json.loads(report.read_text()), phase, process.pid)
    if phase == "import" and seen != set(MARKERS):
        raise RuntimeError("Not all real selection cases ran")
    if Path(f"/proc/{process.pid}").exists():
        raise RuntimeError("First application is still alive")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--enable", action="store_true")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--application", type=Path, required=True)
    args = parser.parse_args()
    if not args.enable:
        print("SKIPPED: use --enable for real Linux device acceptance")
        return 0
    root, repo, application = args.root.resolve(), args.repo.resolve(), args.application.resolve()
    if root.name != "wp17i7-private" or repo != root / "repo" or not application.is_relative_to(root / "artifacts"):
        raise RuntimeError("Use the dedicated I7 source/artifact roots")
    env = dict(os.environ)
    directory = Path(env["WP17_I7_RUN"]).resolve()
    if not directory.is_relative_to(root / "runs"):
        raise RuntimeError("Invalid dedicated run directory")
    for key, leaf in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        if Path(env[key]).resolve() != directory / leaf:
            raise RuntimeError("Invalid isolated " + key)
    if env.get("DISPLAY") != env.get("WP17_LINUX_PRIVATE_DISPLAY") or env.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Only the script's private Xvfb display is allowed")
    fixtures = directory / "fixtures"
    fixtures.mkdir()
    samples = repo / "docs/evidence/wp17r2/samples/images"
    for target, source in (("01-zh.png", "zh_light_base.png"), ("02-en.png", "en_light_base.png"),
                           ("03-ja.png", "ja_light_base.png"), ("04-zh-duplicate.png", "zh_light_base.png")):
        shutil.copyfile(samples / source, fixtures / target)
    (fixtures / "05-corrupt.png").write_bytes(b"not a png")
    original = hashes(fixtures)
    env["WP17_I7_EXPECTED"] = str(directory / "expected.json")
    picker = Linux(fixtures, evidence=directory)
    outcome = {"passed": False, "root": str(root), "run": str(directory),
               "uid": os.getuid(), "display": env["DISPLAY"], "data_root": env["XDG_DATA_HOME"],
               "fixture_sha256": original, "processes": []}
    code = 1
    try:
        first = execute(application, repo, directory, "import", env, picker)
        outcome["processes"].append(first)
        # Retain the raw database independently of the comparison snapshot.
        disk = directory / "disk-after-import"
        shutil.copytree(directory / "data", disk)
        second = execute(application, repo, directory, "reopen", env, picker)
        outcome["processes"].append(second)
        if first["pid"] == second["pid"]:
            raise RuntimeError("Application PID was reused; rerun acceptance")
        if hashes(fixtures) != original:
            raise RuntimeError("Selected originals changed or were removed")
        outcome.update(passed=True, real_picker=True, real_ocr=True, independent_reopen=True,
                       originals_preserved=True)
        code = 0
    except Exception as exception:
        outcome["error"] = str(exception)
    finally:
        outcome["exit"] = code
        outcome["processes"] = [json.loads(path.read_text()) for phase in ("import", "reopen")
                                if (path := directory / f"process-{phase}.json").exists()]
        outcome["cleanup"] = {"application_processes_exited": all(
            not Path(f"/proc/{p['pid']}").exists() for p in outcome["processes"]),
            "disk_and_failure_evidence": "retained in private run directory"}
        (directory / "host.json").write_text(json.dumps(outcome, indent=2) + "\n")
        print(json.dumps(outcome))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
