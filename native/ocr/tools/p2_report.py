#!/usr/bin/env python3
"""Add paired-by-round ratios to completed P2 trials, preserving original evidence.

Ratios describe sequential processes on a variable-load host, not causal speed
guarantees. Report absolute medians/ranges too; never drop a slow trial.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import statistics

from p2_benchmark import comparison_summary
from q1_benchmark import REPO


def paired_summary(trials, baseline="q1"):
    summaries = comparison_summary(trials)
    references = {(row["mode"], row["round"]): row for row in trials if row["candidate"] == baseline}
    if not references:
        raise ValueError("Q1 baseline missing")
    for summary in summaries:
        rows = [row for row in trials if row["candidate"] == summary["candidate"] and row["mode"] == summary["mode"]]
        ratios = []
        for row in rows:
            reference = references[(row["mode"], row["round"])]
            ratios.append({"round": row["round"], "time": row["hot_ten_ms"] / reference["hot_ten_ms"],
                           "hwm": row["peaks"]["hwm_kib"] / reference["peaks"]["hwm_kib"]})
        summary["paired_round_ratios"] = ratios
        summary["paired_time_ratio_median"] = statistics.median(row["time"] for row in ratios)
        summary["paired_hwm_ratio_median"] = statistics.median(row["hwm"] for row in ratios)
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", type=Path, action="append", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.resolve() == REPO or REPO in args.out.resolve().parents:
        parser.error("external output required")
    results = []
    for path in args.benchmark:
        data = json.loads(path.read_text(encoding="utf-8"))
        results.append({"source": str(path.resolve()), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "platform": data["platform"], "build": data["build"],
                        "summary": paired_summary(data["trials"])})
    # New file only: do not rewrite a benchmark, log, or previous report.
    with args.out.open("x", encoding="utf-8") as output:
        output.write(json.dumps(results, indent=2) + "\n")
    print(args.out)


if __name__ == "__main__":
    main()
