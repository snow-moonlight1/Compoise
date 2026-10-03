#!/usr/bin/env python3
"""Summarize externally stored Q1 runs, keeping platform/build/metric separate."""
import argparse
import json
from pathlib import Path
import statistics
import re


def summarize_native(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    result = []
    for mode in data["modes"]:
        durations = {}
        rss = []
        for row in mode["records"]:
            if row["stage"] in ("create", "ocr"):
                batch = row["batch"]
                durations[batch] = durations.get(batch, 0) + row["duration_ms"]
            if row["stage"] == "batch": rss.append(row["rss_kib"])
        result.append({"mode": mode["mode"], "pid": mode["pid"], "peaks": mode["sampled_peaks"],
                       "batch_ms": [round(v, 1) for v in durations.values()],
                       "hot_median_ms": round(statistics.median(list(durations.values())[1:]), 1) if len(durations) > 1 else None,
                       "batch_rss_kib": rss, "settled": mode["records"][-1]})
    return {"platform": data["platform"], "build": data["build"], "threads": data["threads"], "modes": result}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, required=True)
    a = p.parse_args()
    results = {}
    for path in sorted(a.root.glob("bench-*/summary.json")):
        results[path.parent.name] = summarize_native(path)
    for path in sorted(a.root.glob("flutter-*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        phases = [row for row in data["records"] if row.get("phase") in
                  ("idle", "draft", "released", "boundary-selected", "boundary-draft", "ocr-cancelled", "exception-recovery", "finished")]
        results[path.stem] = {"build": data["build"], "pid": data["pid"], "exit": data["exit"],
                              "peaks": data["sampled_peaks"], "phases": phases}
    for path in sorted((a.root / "logs").glob("dart-profile-run-*.log")):
        rows = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.startswith("Q1_TRACE"): continue
            match = re.search(r"stage=(\S+) pid=(\d+) time_us=(\d+) payload=(\d+)", line)
            fields = dict((key, int(value)) for key, value in re.findall(r"(VmRSS|VmHWM|RssAnon|Threads):\s*(\d+)", line))
            rows.append({"stage": match[1], "pid": int(match[2]), "time_us": int(match[3]),
                         "payload": int(match[4]), **fields})
        results[path.stem] = rows
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
