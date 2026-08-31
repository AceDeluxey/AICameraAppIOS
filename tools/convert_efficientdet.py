#!/usr/bin/env python3
"""Convert a TensorFlow 2 EfficientDet SavedModel to the app's Core ML contract.

The converter intentionally requires a SavedModel supplied by the operator. It never
downloads or copies the Android model, because model provenance and reuse permission
must be confirmed before an artifact is distributed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


INPUT_NAME = "image"
INPUT_SHAPE = (1, 448, 448, 3)
OUTPUT_NAMES = ("locations", "classes", "scores", "num_detections")
DEFAULT_SOURCE_OUTPUTS = {
    "locations": "detection_boxes",
    "classes": "detection_classes",
    "scores": "detection_scores",
    "num_detections": "num_detections",
}


@dataclass(frozen=True)
class TensorContract:
    name: str
    shape: tuple[int, ...]


EXPECTED_OUTPUTS = (
    TensorContract("locations", (1, 25, 4)),
    TensorContract("classes", (1, 25)),
    TensorContract("scores", (1, 25)),
    TensorContract("num_detections", (1,)),
)


def parse_output_mapping(values: Sequence[str]) -> dict[str, str]:
    mapping = dict(DEFAULT_SOURCE_OUTPUTS)
    for value in values:
        destination, separator, source = value.partition("=")
        if not separator or destination not in OUTPUT_NAMES or not source:
            raise ValueError(
                "--map-output 必须为 locations|classes|scores|num_detections=源输出名"
            )
        mapping[destination] = source
    return mapping


def verify_source_outputs(
    available: Sequence[str], mapping: Mapping[str, str]
) -> None:
    missing = [source for source in mapping.values() if source not in available]
    if missing:
        raise ValueError(
            f"SavedModel 缺少映射的输出：{', '.join(missing)}；"
            f"实际输出：{', '.join(sorted(available))}"
        )


def hash_directory(path: Path) -> str:
    digest = hashlib.sha256()
    for child in sorted(item for item in path.rglob("*") if item.is_file()):
        digest.update(child.relative_to(path).as_posix().encode("utf-8"))
        with child.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest()


def load_signature(saved_model: Path, signature_name: str) -> tuple[Any, Any]:
    import tensorflow as tf

    loaded = tf.saved_model.load(str(saved_model))
    if signature_name not in loaded.signatures:
        names = ", ".join(sorted(loaded.signatures)) or "（无）"
        raise ValueError(f"SavedModel 不含签名 {signature_name}；可用签名：{names}")
    return loaded, loaded.signatures[signature_name]


def signature_report(signature: Any) -> dict[str, Any]:
    _, keyword_inputs = signature.structured_input_signature
    return {
        "inputs": {
            name: {
                "shape": _shape_list(tensor.shape),
                "dtype": tensor.dtype.name,
            }
            for name, tensor in keyword_inputs.items()
        },
        "outputs": {
            name: {
                "shape": _shape_list(tensor.shape),
                "dtype": tensor.dtype.name,
            }
            for name, tensor in signature.structured_outputs.items()
        },
    }


def _shape_list(shape: Any) -> list[int | None]:
    return [dimension if dimension is not None else None for dimension in shape.as_list()]


def make_normalized_function(signature: Any, mapping: Mapping[str, str]) -> Any:
    import tensorflow as tf

    available = tuple(signature.structured_outputs)
    verify_source_outputs(available, mapping)
    _, keyword_inputs = signature.structured_input_signature
    if len(keyword_inputs) != 1:
        raise ValueError(
            "转换器只支持单图像输入；实际输入：" + ", ".join(keyword_inputs)
        )
    source_input_name = next(iter(keyword_inputs))
    source_spec = keyword_inputs[source_input_name]

    @tf.function(
        input_signature=[
            tf.TensorSpec(INPUT_SHAPE, source_spec.dtype, name=INPUT_NAME),
        ]
    )
    def normalized(image: Any) -> tuple[Any, Any, Any, Any]:
        outputs = signature(**{source_input_name: image})
        locations = tf.ensure_shape(
            outputs[mapping["locations"]][:, :25, :], (1, 25, 4)
        )
        classes = tf.ensure_shape(outputs[mapping["classes"]][:, :25], (1, 25))
        scores = tf.ensure_shape(outputs[mapping["scores"]][:, :25], (1, 25))
        count = tf.ensure_shape(outputs[mapping["num_detections"]], (1,))
        count = tf.minimum(count, tf.cast(25, count.dtype))
        return (
            tf.identity(locations, name="locations"),
            tf.identity(classes, name="classes"),
            tf.identity(scores, name="scores"),
            tf.identity(count, name="num_detections"),
        )

    return normalized.get_concrete_function()


def convert_model(concrete_function: Any, output_path: Path) -> Any:
    import coremltools as ct

    model = ct.convert(
        [concrete_function],
        source="tensorflow",
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
        inputs=[
            ct.ImageType(
                name=INPUT_NAME,
                shape=INPUT_SHAPE,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name=name) for name in OUTPUT_NAMES],
    )
    model.author = "AICameraApp model conversion tool"
    model.short_description = "EfficientDet Lite2 whole-bird detector"
    model.input_description[INPUT_NAME] = "448×448 RGB image, stretched without letterbox"
    model.save(str(output_path))
    return model


def verify_coreml_contract(model: Any) -> dict[str, Any]:
    spec = model.get_spec()
    inputs = {feature.name: feature for feature in spec.description.input}
    if INPUT_NAME not in inputs or not inputs[INPUT_NAME].type.HasField("imageType"):
        raise ValueError("Core ML 输入必须是名为 image 的 Image")
    image = inputs[INPUT_NAME].type.imageType
    if (image.width, image.height) != (448, 448):
        raise ValueError(f"Core ML 图像尺寸错误：{image.width}×{image.height}")

    outputs = {feature.name: feature for feature in spec.description.output}
    report: list[dict[str, Any]] = []
    for expected in EXPECTED_OUTPUTS:
        feature = outputs.get(expected.name)
        if feature is None or not feature.type.HasField("multiArrayType"):
            raise ValueError(f"Core ML 缺少 MultiArray 输出：{expected.name}")
        shape = tuple(feature.type.multiArrayType.shape)
        if shape != expected.shape:
            raise ValueError(
                f"Core ML 输出 {expected.name} 形状错误：{shape}，预期 {expected.shape}"
            )
        report.append({"name": expected.name, "shape": list(shape)})
    return {
        "input": {"name": INPUT_NAME, "shape": list(INPUT_SHAPE), "type": "image"},
        "outputs": report,
    }


def write_manifest(
    path: Path,
    source_path: Path,
    signature_name: str,
    mapping: Mapping[str, str],
    source_report: Mapping[str, Any],
    coreml_report: Mapping[str, Any] | None,
) -> None:
    import coremltools as ct
    import tensorflow as tf

    manifest = {
        "source": {
            "path": str(source_path.resolve()),
            "sha256": hash_directory(source_path),
            "signature": signature_name,
            "contract": source_report,
        },
        "mapping": dict(mapping),
        "target": coreml_report,
        "expected_outputs": [asdict(output) for output in EXPECTED_OUTPUTS],
        "environment": {
            "python": platform.python_version(),
            "tensorflow": tf.__version__,
            "coremltools": ct.__version__,
            "platform": platform.platform(),
        },
    }
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="将 TF2 EfficientDet SavedModel 转为固定接口的 Core ML 模型"
    )
    parser.add_argument("saved_model", type=Path, help="SavedModel 目录")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("EfficientDetLite2.mlpackage"),
        help="输出 .mlpackage 路径",
    )
    parser.add_argument(
        "--signature", default="serving_default", help="SavedModel signature 名称"
    )
    parser.add_argument(
        "--map-output",
        action="append",
        default=[],
        metavar="TARGET=SOURCE",
        help="覆盖源输出映射，可重复",
    )
    parser.add_argument(
        "--inspect-only", action="store_true", help="只检查 SavedModel 接口，不转换"
    )
    parser.add_argument(
        "--manifest", type=Path, help="转换记录 JSON；默认位于模型同级"
    )
    parser.add_argument(
        "--force", action="store_true", help="允许覆盖已存在的输出和转换记录"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.saved_model.is_dir() or not (args.saved_model / "saved_model.pb").is_file():
        raise SystemExit(f"不是有效的 SavedModel 目录：{args.saved_model}")
    if args.output.suffix != ".mlpackage":
        raise SystemExit("--output 必须使用 .mlpackage 后缀")

    try:
        mapping = parse_output_mapping(args.map_output)
        _, signature = load_signature(args.saved_model, args.signature)
        source_report = signature_report(signature)
        verify_source_outputs(tuple(signature.structured_outputs), mapping)
    except (ImportError, ValueError) as error:
        raise SystemExit(str(error)) from error

    print(json.dumps(source_report, ensure_ascii=False, indent=2))
    if args.inspect_only:
        return 0
    manifest_path = args.manifest or args.output.with_suffix(".conversion.json")
    existing = [path for path in (args.output, manifest_path) if path.exists()]
    if existing and not args.force:
        names = "、".join(str(path) for path in existing)
        raise SystemExit(f"输出已存在：{names}；确认后使用 --force 覆盖")
    if args.force:
        for path in existing:
            if path.is_dir():
                import shutil

                shutil.rmtree(path)
            else:
                path.unlink()

    concrete = make_normalized_function(signature, mapping)
    model = convert_model(concrete, args.output)
    coreml_report = verify_coreml_contract(model)
    write_manifest(
        manifest_path,
        args.saved_model,
        args.signature,
        mapping,
        source_report,
        coreml_report,
    )
    print(f"已生成：{args.output}")
    print(f"转换记录：{manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
