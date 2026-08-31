#!/usr/bin/env python3
"""Validate a fixed image set and compare Android/iOS detector outputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


SCHEMA_VERSION = 1
REQUIRED_CATEGORIES = {
    "bird",
    "no_bird",
    "small_target",
    "occluded",
    "motion",
    "backlit",
    "complex_background",
}


class ValidationError(ValueError):
    """Raised when a validation artifact does not follow the contract."""


@dataclass(frozen=True)
class Detection:
    class_id: int
    score: float
    box: tuple[float, float, float, float]


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"无法读取 JSON {path}: {error}") from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _require_mapping(value: Any, field: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{field} 必须是对象")
    return value


def _require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{field} 必须是非空字符串")
    return value


def validate_dataset(
    payload: Any, manifest_path: Path, check_files: bool = False
) -> dict[str, Mapping[str, Any]]:
    root = _require_mapping(payload, "dataset")
    if root.get("schema_version") != SCHEMA_VERSION:
        raise ValidationError(f"dataset.schema_version 必须为 {SCHEMA_VERSION}")
    samples = root.get("samples")
    if not isinstance(samples, list) or not samples:
        raise ValidationError("dataset.samples 必须是非空数组")

    result: dict[str, Mapping[str, Any]] = {}
    covered_categories: set[str] = set()
    base = manifest_path.parent.resolve()
    for index, raw_sample in enumerate(samples):
        sample = _require_mapping(raw_sample, f"samples[{index}]")
        sample_id = _require_string(sample.get("id"), f"samples[{index}].id")
        if sample_id in result:
            raise ValidationError(f"样本 ID 重复：{sample_id}")
        image = _require_string(sample.get("image"), f"samples[{index}].image")
        categories = sample.get("categories")
        if not isinstance(categories, list) or not categories or not all(
            isinstance(item, str) and item for item in categories
        ):
            raise ValidationError(f"samples[{index}].categories 必须是非空字符串数组")
        unknown = set(categories) - REQUIRED_CATEGORIES
        if unknown:
            raise ValidationError(f"样本 {sample_id} 含未知场景分类：{sorted(unknown)}")
        if ("bird" in categories) == ("no_bird" in categories):
            raise ValidationError(f"样本 {sample_id} 必须且只能属于 bird/no_bird 之一")
        covered_categories.update(categories)

        if check_files:
            image_path = (base / image).resolve()
            if base not in image_path.parents:
                raise ValidationError(f"样本 {sample_id} 的图片路径越出清单目录")
            if not image_path.is_file():
                raise ValidationError(f"样本 {sample_id} 的图片不存在：{image}")
            expected_hash = _require_string(
                sample.get("sha256"), f"samples[{index}].sha256"
            ).lower()
            actual_hash = sha256_file(image_path)
            if actual_hash != expected_hash:
                raise ValidationError(
                    f"样本 {sample_id} 的 SHA-256 不匹配：{actual_hash}"
                )
        result[sample_id] = sample

    missing = REQUIRED_CATEGORIES - covered_categories
    if missing:
        raise ValidationError(f"验证集缺少场景分类：{sorted(missing)}")
    return result


def _parse_detection(value: Any, field: str) -> Detection | None:
    if value is None:
        return None
    item = _require_mapping(value, field)
    class_id = item.get("class_id")
    score = item.get("score")
    box = item.get("box")
    if not isinstance(class_id, int) or isinstance(class_id, bool):
        raise ValidationError(f"{field}.class_id 必须是整数")
    if not isinstance(score, (int, float)) or not math.isfinite(score):
        raise ValidationError(f"{field}.score 必须是有限数值")
    if not 0 <= score <= 1:
        raise ValidationError(f"{field}.score 必须在 0...1")
    if not isinstance(box, list) or len(box) != 4:
        raise ValidationError(f"{field}.box 必须为 [y1,x1,y2,x2]")
    if not all(isinstance(item, (int, float)) and math.isfinite(item) for item in box):
        raise ValidationError(f"{field}.box 必须只含有限数值")
    y1, x1, y2, x2 = (float(item) for item in box)
    if not (0 <= y1 < y2 <= 1 and 0 <= x1 < x2 <= 1):
        raise ValidationError(f"{field}.box 必须是 0...1 内的有效 y1,x1,y2,x2")
    return Detection(class_id, float(score), (y1, x1, y2, x2))


def validate_run(
    payload: Any, expected_sample_ids: set[str]
) -> tuple[Mapping[str, Any], dict[str, Detection | None], dict[str, float]]:
    root = _require_mapping(payload, "run")
    if root.get("schema_version") != SCHEMA_VERSION:
        raise ValidationError(f"run.schema_version 必须为 {SCHEMA_VERSION}")
    runtime = _require_string(root.get("runtime"), "run.runtime")
    if runtime not in {"android_tflite", "ios_tflite", "ios_coreml"}:
        raise ValidationError(f"不支持的 runtime：{runtime}")
    model_hash = _require_string(
        root.get("source_model_sha256"), "run.source_model_sha256"
    ).lower()
    if len(model_hash) != 64 or any(character not in "0123456789abcdef" for character in model_hash):
        raise ValidationError("run.source_model_sha256 必须是 64 位十六进制 SHA-256")
    samples = root.get("samples")
    if not isinstance(samples, list):
        raise ValidationError("run.samples 必须是数组")

    results: dict[str, Detection | None] = {}
    latencies: dict[str, float] = {}
    for index, raw_sample in enumerate(samples):
        sample = _require_mapping(raw_sample, f"run.samples[{index}]")
        sample_id = _require_string(sample.get("id"), f"run.samples[{index}].id")
        if sample_id in results:
            raise ValidationError(f"运行结果样本 ID 重复：{sample_id}")
        latency = sample.get("latency_ms")
        if not isinstance(latency, (int, float)) or not math.isfinite(latency) or latency < 0:
            raise ValidationError(f"样本 {sample_id} 的 latency_ms 必须是非负有限数值")
        latencies[sample_id] = float(latency)
        results[sample_id] = _parse_detection(
            sample.get("selected_detection"), f"样本 {sample_id}.selected_detection"
        )

    actual_ids = set(results)
    if actual_ids != expected_sample_ids:
        missing = sorted(expected_sample_ids - actual_ids)
        extra = sorted(actual_ids - expected_sample_ids)
        raise ValidationError(f"运行结果样本不完整；缺少={missing}，多余={extra}")
    return root, results, latencies


def latency_summary(values: Sequence[float]) -> dict[str, float]:
    ordered = sorted(values)
    percentile_index = max(0, math.ceil(len(ordered) * 0.95) - 1)
    return {
        "mean_ms": sum(ordered) / len(ordered),
        "p95_ms": ordered[percentile_index],
        "max_ms": ordered[-1],
    }


def intersection_over_union(first: Detection, second: Detection) -> float:
    y1 = max(first.box[0], second.box[0])
    x1 = max(first.box[1], second.box[1])
    y2 = min(first.box[2], second.box[2])
    x2 = min(first.box[3], second.box[3])
    intersection = max(0.0, y2 - y1) * max(0.0, x2 - x1)
    first_area = (first.box[2] - first.box[0]) * (first.box[3] - first.box[1])
    second_area = (second.box[2] - second.box[0]) * (second.box[3] - second.box[1])
    union = first_area + second_area - intersection
    return intersection / union if union else 0.0


def compare_runs(
    baseline: Mapping[str, Detection | None],
    candidate: Mapping[str, Detection | None],
) -> dict[str, Any]:
    sample_rows: list[dict[str, Any]] = []
    presence_matches = 0
    class_matches = 0
    ious: list[float] = []
    score_deltas: list[float] = []
    for sample_id in sorted(baseline):
        reference = baseline[sample_id]
        tested = candidate[sample_id]
        presence_match = (reference is None) == (tested is None)
        presence_matches += int(presence_match)
        row: dict[str, Any] = {"id": sample_id, "presence_match": presence_match}
        if reference is not None and tested is not None:
            class_match = reference.class_id == tested.class_id
            overlap = intersection_over_union(reference, tested)
            score_delta = abs(reference.score - tested.score)
            class_matches += int(class_match)
            ious.append(overlap)
            score_deltas.append(score_delta)
            row.update(
                class_match=class_match,
                iou=round(overlap, 6),
                score_delta=round(score_delta, 6),
            )
        sample_rows.append(row)

    count = len(sample_rows)
    matched_count = len(ious)
    return {
        "sample_count": count,
        "presence_agreement": presence_matches / count,
        "matched_detection_count": matched_count,
        "class_agreement": class_matches / matched_count if matched_count else None,
        "mean_iou": sum(ious) / matched_count if matched_count else None,
        "mean_score_delta": sum(score_deltas) / matched_count if matched_count else None,
        "samples": sample_rows,
    }


def evaluate_thresholds(
    report: Mapping[str, Any], min_presence: float, min_iou: float, max_score_delta: float
) -> list[str]:
    failures: list[str] = []
    if report["presence_agreement"] < min_presence:
        failures.append("presence_agreement")
    if report["matched_detection_count"]:
        if report["class_agreement"] < 1:
            failures.append("class_agreement")
        if report["mean_iou"] < min_iou:
            failures.append("mean_iou")
        if report["mean_score_delta"] > max_score_delta:
            failures.append("mean_score_delta")
    return failures


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="校验固定验证集并比较两端主目标输出")
    parser.add_argument("dataset", type=Path, help="验证集 manifest JSON")
    parser.add_argument("baseline", type=Path, nargs="?", help="Android 基线输出 JSON")
    parser.add_argument("candidate", type=Path, nargs="?", help="iOS 候选输出 JSON")
    parser.add_argument("--check-files", action="store_true", help="检查图片、路径和 SHA-256")
    parser.add_argument("--output", type=Path, help="写入完整 JSON 报告")
    parser.add_argument("--min-presence-agreement", type=float, default=0.95)
    parser.add_argument("--min-mean-iou", type=float, default=0.90)
    parser.add_argument("--max-mean-score-delta", type=float, default=0.05)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        dataset = validate_dataset(load_json(args.dataset), args.dataset, args.check_files)
        if (args.baseline is None) != (args.candidate is None):
            raise ValidationError("baseline 和 candidate 必须同时提供")
        if args.baseline is None:
            print(f"验证集清单有效：{len(dataset)} 个样本")
            return 0

        baseline_root, baseline, baseline_latencies = validate_run(
            load_json(args.baseline), set(dataset)
        )
        candidate_root, candidate, candidate_latencies = validate_run(
            load_json(args.candidate), set(dataset)
        )
        if baseline_root["source_model_sha256"] != candidate_root["source_model_sha256"]:
            raise ValidationError("两次运行的 source_model_sha256 不一致，不能作同权重比较")
        report = compare_runs(baseline, candidate)
        report["baseline_runtime"] = baseline_root["runtime"]
        report["candidate_runtime"] = candidate_root["runtime"]
        report["baseline_latency"] = latency_summary(list(baseline_latencies.values()))
        report["candidate_latency"] = latency_summary(list(candidate_latencies.values()))
        failures = evaluate_thresholds(
            report,
            args.min_presence_agreement,
            args.min_mean_iou,
            args.max_mean_score_delta,
        )
        report["passed"] = not failures
        report["failed_metrics"] = failures
        rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.write_text(rendered, encoding="utf-8")
        print(rendered, end="")
        return 0 if not failures else 2
    except ValidationError as error:
        print(f"错误：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
