import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from compare_detection_outputs import (
    Detection,
    ValidationError,
    compare_runs,
    evaluate_thresholds,
    intersection_over_union,
    latency_summary,
    validate_dataset,
    validate_run,
)


class DetectionOutputComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.samples = [
            {"id": "bird", "image": "images/bird.jpg", "categories": ["bird", "small_target", "occluded", "motion", "backlit", "complex_background"]},
            {"id": "empty", "image": "images/empty.jpg", "categories": ["no_bird"]},
        ]

    def test_dataset_requires_full_scene_coverage(self) -> None:
        samples = [dict(self.samples[0], categories=["bird"]), self.samples[1]]
        with self.assertRaisesRegex(ValidationError, "缺少场景分类"):
            validate_dataset({"schema_version": 1, "samples": samples}, Path("manifest.json"))

    def test_dataset_checks_file_hash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "images").mkdir()
            for sample in self.samples:
                path = root / sample["image"]
                path.write_bytes(sample["id"].encode())
                sample["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            result = validate_dataset(
                {"schema_version": 1, "samples": self.samples},
                root / "manifest.json",
                check_files=True,
            )
            self.assertEqual(set(result), {"bird", "empty"})

    def test_run_must_contain_every_dataset_sample(self) -> None:
        payload = self.run_payload([self.result("bird", None)])
        with self.assertRaisesRegex(ValidationError, "样本不完整"):
            validate_run(payload, {"bird", "empty"})

    def test_invalid_normalized_box_is_rejected(self) -> None:
        detection = {"class_id": 14, "score": 0.8, "box": [0.5, 0.1, 0.4, 0.8]}
        payload = self.run_payload([self.result("bird", detection), self.result("empty", None)])
        with self.assertRaisesRegex(ValidationError, "有效 y1,x1,y2,x2"):
            validate_run(payload, {"bird", "empty"})

    def test_iou_and_comparison_metrics(self) -> None:
        first = Detection(14, 0.8, (0.0, 0.0, 0.5, 0.5))
        second = Detection(14, 0.75, (0.0, 0.0, 1.0, 1.0))
        self.assertAlmostEqual(intersection_over_union(first, second), 0.25)
        report = compare_runs({"bird": first, "empty": None}, {"bird": second, "empty": None})
        self.assertEqual(report["presence_agreement"], 1)
        self.assertEqual(report["class_agreement"], 1)
        self.assertAlmostEqual(report["mean_iou"], 0.25)
        self.assertAlmostEqual(report["mean_score_delta"], 0.05)

    def test_threshold_failures_are_named(self) -> None:
        report = {
            "presence_agreement": 0.5,
            "matched_detection_count": 1,
            "class_agreement": 0.0,
            "mean_iou": 0.4,
            "mean_score_delta": 0.2,
        }
        self.assertEqual(
            evaluate_thresholds(report, 0.95, 0.9, 0.05),
            ["presence_agreement", "class_agreement", "mean_iou", "mean_score_delta"],
        )

    def test_latency_summary_uses_nearest_rank_p95(self) -> None:
        summary = latency_summary([1, 2, 3, 4, 100])
        self.assertEqual(summary, {"mean_ms": 22, "p95_ms": 100, "max_ms": 100})

    @staticmethod
    def result(sample_id, detection):
        return {"id": sample_id, "latency_ms": 10, "selected_detection": detection}

    @staticmethod
    def run_payload(samples):
        return {
            "schema_version": 1,
            "runtime": "android_tflite",
            "source_model_sha256": "a" * 64,
            "samples": samples,
        }


if __name__ == "__main__":
    unittest.main()
