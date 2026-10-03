import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("wp28_r3_report", ROOT / "scripts" / "wp28_r3_report.py")
report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(report)

COMMIT = "a" * 40
SOURCE = "b" * 64
EXE = "c" * 64
FILE_HASH = "d" * 64


def _source():
    return {"dirty": False, "paths": [], "diffSha256": SOURCE}


def _write(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def _process(pid, **overrides):
    item = {"pid": pid, "timedOut": False, "alive": False, "exitCode": 0, "cleanup": "not-needed"}
    item.update(overrides)
    return item


def _runtime_case(name, **overrides):
    item = {"case": name, "timedOut": False, "alive": False, "exitCode": 2, "cleanup": "not-needed"}
    item.update(overrides)
    return item


def _build_case(name, **overrides):
    item = {"case": name, "exitCode": 1}
    item.update(overrides)
    return item


def _passing_tree(root: Path):
    _write(root / "source.json", _source())
    _write(root / "desktop.json", {"usable": True, "skip": False, "isolated": True, "sessionId": 1})
    _write(root / "gates-Build-aaaa/result.json", {
        "kind": "Build", "exitCode": 0, "commit": COMMIT,
        "cases": [_build_case(name) for name in report.BUILD_CASES],
    })
    files = [{"path": "compoise.exe", "bytes": 12, "sha256": FILE_HASH}]
    for config in ("Debug", "Release"):
        _write(root / config / f"diagnostic-{config}.json", {
            "schema": 1, "normalCandidate": False, "configuration": config, "commit": COMMIT,
            "source": _source(), "buildExitCode": 0, "executableSHA256": EXE, "files": files,
        })
        _write(root / config / "matrix/run/harness.json", {
            "passed": True, "normalCandidate": False, "commit": COMMIT, "source": _source(),
            "executableSHA256": EXE,
            "results": [{"scenario": f"s{i}", "passed": True} for i in range(report.EXPECTED_RESULTS)],
            "processes": [_process(1000 + i) for i in range(report.EXPECTED_PROCESSES)],
        })
        _write(root / config / "gates-Runtime-bbbb/result.json", {
            "kind": "Runtime", "exitCode": 0, "commit": COMMIT, "sourceAtCheck": _source(),
            "cases": [_runtime_case(name) for name in report.RUNTIME_CASES],
        })


class ReportContractTests(unittest.TestCase):
    def test_require_fresh_allows_allocated_placeholder_only(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-") as raw:
            root = Path(raw)
            _write(root / "ci-report.json", {"status": "allocated", "passed": False, "skip": False})
            report.require_fresh(root)
            _write(root / "desktop.json", {"usable": True})
            with self.assertRaisesRegex(ValueError, "not fresh"):
                report.require_fresh(root)

    def test_require_fresh_rejects_a_previous_pass(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-") as raw:
            root = Path(raw)
            _write(root / "ci-report.json", {"status": "complete", "passed": True})
            with self.assertRaisesRegex(ValueError, "passing"):
                report.require_fresh(root)

    def test_assemble_accepts_bound_debug_and_release_evidence(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-") as raw:
            root = Path(raw)
            _passing_tree(root)
            payload = report.assemble(root, COMMIT, "All")
            self.assertTrue(payload["passed"], payload["failures"])
            self.assertFalse(payload["skip"])
            self.assertFalse(payload["normalCandidate"])
            self.assertEqual(payload["commit"], COMMIT)
            self.assertEqual(payload["source"]["diffSha256"], SOURCE)
            self.assertIn("Debug", payload["configurations"])
            self.assertIn("Release", payload["configurations"])

    def test_timeout_kill_unknown_skip_and_stale_hash_are_failures(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-") as raw:
            root = Path(raw)
            _passing_tree(root)
            matrix = json.loads((root / "Debug/matrix/run/harness.json").read_text())
            matrix["processes"][0]["timedOut"] = True
            matrix["processes"][1]["cleanup"] = "owned-process-killed-after-failure"
            matrix["processes"][2]["exitCode"] = None
            matrix["executableSHA256"] = "e" * 64
            matrix["skip"] = True
            _write(root / "Debug/matrix/run/harness.json", matrix)
            payload = report.assemble(root, COMMIT, "All")
            self.assertFalse(payload["passed"])
            joined = " ".join(payload["failures"])
            self.assertIn("timeout", joined)
            self.assertIn("cleanup owned-process-killed-after-failure", joined)
            self.assertIn("unknown_gate_status", joined)
            self.assertIn("exe_hash_mismatch", joined)
            self.assertTrue(any(item.startswith("skip ") for item in payload["failures"]))

    def test_missing_desktop_is_a_failure_not_a_skip(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-") as raw:
            root = Path(raw)
            _passing_tree(root)
            (root / "desktop.json").write_text(json.dumps({
                "usable": False, "skip": False, "error": "OpenInputDesktop failed",
                "requiredRunner": report.REQUIRED_RUNNER,
            }), encoding="utf-8")
            payload = report.assemble(root, COMMIT, "All")
            self.assertFalse(payload["passed"])
            self.assertFalse(payload["skip"])
            self.assertIn("desktop_unavailable", payload["failures"])
            self.assertEqual(payload["requiredRunner"], report.REQUIRED_RUNNER)

    def test_cli_overwrites_allocated_placeholder_with_a_failing_report(self):
        with tempfile.TemporaryDirectory(prefix="wp28-r3-") as raw:
            root = Path(raw)
            output = root / "ci-report.json"
            _write(output, {"status": "allocated", "passed": False})
            _write(root / "source.json", _source())
            code = report.main([
                "assemble", "--evidence", str(root), "--commit", COMMIT,
                "--configuration", "All", "--output", str(output),
            ])
            self.assertEqual(code, 1)
            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertFalse(payload["passed"])
            self.assertEqual(payload["status"], "complete")
            self.assertTrue(any("desktop" in item for item in payload["failures"]))


if __name__ == "__main__":
    unittest.main()
