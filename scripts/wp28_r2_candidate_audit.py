"""Compare same-commit Windows candidates and their complete extracted bundles.

Read-only candidate checks; writes only the requested R2 evidence report.
Does not launch an executable or replace R1 proof/seal/verify/extract.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

_spec = importlib.util.spec_from_file_location(
    "r2_release_gate", Path(__file__).with_name("release_candidate.py")
)
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

DIAGNOSTIC_MARKERS = (
    "WP28_U2_ROOT", "WP28_U2_NAMESPACE", "WP28_U2_RUN", "wp28U2Status",
    "wp28-u2-device-", "wp28-u2-", "WP28-U2 pid=",
    "WP15_D3_RUN", "WP15_D3_NAMESPACE", "WP15_D3_ROOT", "matrixflow/wp15_d3",
    "SYNTHETIC_OLD_ENCRYPTED_FILE_NEVER_READ", "synthetic-screenshot-",
    "R2SeedCredentials", "Synthetic transaction retry",
    "store-open-approved-",
)


def inspect_extracted(directory, inventory):
    gate.require(directory.is_dir() and not directory.is_symlink(), "Missing extracted bundle")
    actual = []
    for path in directory.rglob("*"):
        gate.require(not path.is_symlink(), "Linked extracted entry")
        if path.is_file():
            value = gate.snapshot(path)
            actual.append({"path": path.relative_to(directory).as_posix(),
                           "bytes": value["bytes"], "sha256": value["sha256"]})
            if path.suffix.lower() in (".exe", ".dll", ".so"):
                data = path.read_bytes()
                for marker in DIAGNOSTIC_MARKERS:
                    gate.require(marker.encode("utf-8") not in data and
                                 marker.encode("utf-16-le") not in data,
                                 f"Normal bundle contains diagnostic marker {marker}: {value['name']}")
    gate.require(sorted(actual, key=lambda f: f["path"]) == inventory,
                 "Complete extracted inventory differs from proof")
    return inventory


def compare_inventories(first, second):
    a = {f["path"]: f for f in first}
    b = {f["path"]: f for f in second}
    return {"added": sorted(b.keys() - a.keys()),
            "removed": sorted(a.keys() - b.keys()),
            "changed": sorted(name for name in a.keys() & b.keys() if a[name] != b[name]),
            "identicalFiles": sum(a[name] == b[name] for name in a.keys() & b.keys())}


def candidate(directory, extracted, ctx):
    manifest = gate.verify(directory, "Windows", ctx, "")
    proof = gate.validate_proof(directory, "Windows", ctx, "")
    gate.require(proof["source"]["diffSha256"] == hashlib.sha256(b"").hexdigest(),
                 "Candidate contains source differences outside its commit")
    inventory = inspect_extracted(extracted, proof["zipFiles"])
    return {"directory": str(directory.resolve()), "extracted": str(extracted.resolve()),
            "artifact": proof["artifact"], "source": proof["source"],
            "identity": manifest["buildEvidence"]["Windows"], "files": inventory,
            "diagnosticMarkersAbsent": list(DIAGNOSTIC_MARKERS)}


def inspect_normal_build_gates(root):
    config = (root / "windows/flutter/ephemeral/generated_config.cmake").read_text(encoding="utf-8-sig")
    project = (root / "build/windows/x64/runner/compoise.vcxproj").read_text(encoding="utf-8-sig")
    for define in ("V1AyOF9VMl9IQVJORVNTPXRydWU=", "V1AxNV9EM19ERVZJQ0U9dHJ1ZQ=="):
        gate.require(define not in config, "Normal Dart build has a diagnostic gate")
    for line in project.splitlines():
        if "<PreprocessorDefinitions>" in line:
            gate.require("WP28_U2_HARNESS" not in line and "WP15_D3_DEVICE" not in line,
                         "Normal native build has a diagnostic gate")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--first", type=Path, required=True)
    parser.add_argument("--second", type=Path, required=True)
    parser.add_argument("--extracted-first", type=Path, required=True)
    parser.add_argument("--extracted-second", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tag", default="v1.0.0+1")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        # A failed recheck must never leave a previous passing R2 report.
        args.output.unlink(missing_ok=True)
        head = subprocess.check_output(["git", "-C", str(args.root), "rev-parse", "HEAD"], text=True).strip()
        gate.require(head == args.commit, "Current source HEAD differs from candidate commit")
        trace = gate.source_trace(args.root)
        gate.require(trace["diffSha256"] == hashlib.sha256(b"").hexdigest(), "Current source has uncommitted differences")
        inspect_normal_build_gates(args.root)
        ctx = gate.context(args.root, args.tag, args.commit)
        first = candidate(args.first, args.extracted_first, ctx)
        second = candidate(args.second, args.extracted_second, ctx)
        comparison = compare_inventories(first["files"], second["files"])
        gate.require(not comparison["added"] and not comparison["removed"], "Same-commit candidate file sets differ")
        report = {"schema": 1, "passed": True, **ctx, "source": trace,
                  "normalBuildGatesClosed": True, "first": first, "second": second,
                  "comparison": comparison,
                  "zipBytesIdentical": first["artifact"]["sha256"] == second["artifact"]["sha256"],
                  "normalCandidateRealInstallUpgradeVerified": False,
                  "reproducibilityScope": "Two local incremental builds; not independent clean-cache builds."}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"R2 candidate audit: PASS; {comparison['identicalFiles']} identical files, {len(comparison['changed'])} changed")
        return 0
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"R2 candidate audit: REJECTED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
