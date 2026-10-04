"""Explicit statistical regression: python -m unittest discover ... -p p2_tools_test.py."""
import unittest

from p2_benchmark import summarise_trial
from p2_report import paired_summary


class ReportTests(unittest.TestCase):
    def test_changing_host_load_can_reverse_ratio_of_medians(self):
        # Absolute medians: 5/10 = .5 (looks faster). Within the same rounds:
        # 2/1, 11/10, 5/20 -> median 1.1 (slower in two of three rounds).
        trials = []
        for name, values in (("q1", [1, 10, 20]), ("pool", [2, 11, 5])):
            for number, value in enumerate(values, 1):
                trials.append({"candidate": name, "mode": "reuse", "round": number,
                    "hot_ten_ms": value, "peaks": {"hwm_kib": 100},
                    "batch_rss_kib": [50], "settled": {"rss_kib": 25}})
        candidate = next(row for row in paired_summary(trials) if row["candidate"] == "pool")
        self.assertEqual(candidate["hot_ten_ms_median"], 5)
        self.assertAlmostEqual(candidate["paired_time_ratio_median"], 1.1)
        self.assertEqual(len(candidate["paired_round_ratios"]), 3)

    def test_recreate_timing_includes_create_and_destroy_and_final_hwm(self):
        records = []
        for batch in range(5):
            for stage, value in (("create", 10), ("ocr", 100 if batch == 0 else 20), ("destroy", 5)):
                records.append({"stage": stage, "batch": batch, "duration_ms": value,
                                "rss_kib": 50, "hwm_kib": 100, "pss_kib": 40})
            records.append({"stage": "batch", "batch": batch, "rss_kib": 50,
                            "hwm_kib": 100, "pss_kib": 40})
        records.append({"stage": "settled", "rss_kib": 25, "hwm_kib": 200, "pss_kib": 20})
        result = summarise_trial({"pid": 1, "records": records, "output_sha256": {}}, [])
        self.assertEqual(result["cold_ten_ms"], 115)
        self.assertEqual(result["hot_ten_ms"], 35)
        self.assertEqual(result["peaks"]["hwm_kib"], 200)


if __name__ == "__main__":
    unittest.main()
