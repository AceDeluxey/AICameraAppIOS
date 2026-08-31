import tempfile
import unittest
from pathlib import Path

from convert_efficientdet import (
    DEFAULT_SOURCE_OUTPUTS,
    hash_directory,
    parse_output_mapping,
    verify_source_outputs,
)


class ConvertEfficientDetTests(unittest.TestCase):
    def test_default_output_mapping(self) -> None:
        self.assertEqual(parse_output_mapping([]), DEFAULT_SOURCE_OUTPUTS)

    def test_output_mapping_can_be_overridden(self) -> None:
        mapping = parse_output_mapping(["locations=boxes", "classes=labels"])
        self.assertEqual(mapping["locations"], "boxes")
        self.assertEqual(mapping["classes"], "labels")

    def test_invalid_output_mapping_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "--map-output"):
            parse_output_mapping(["unknown=value"])

    def test_missing_source_output_is_reported(self) -> None:
        with self.assertRaisesRegex(ValueError, "detection_scores"):
            verify_source_outputs(
                ["detection_boxes", "detection_classes", "num_detections"],
                DEFAULT_SOURCE_OUTPUTS,
            )

    def test_directory_hash_is_stable_and_path_sensitive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a").mkdir()
            (root / "a" / "model").write_bytes(b"weights")
            first = hash_directory(root)
            self.assertEqual(first, hash_directory(root))
            (root / "a" / "model").rename(root / "model")
            self.assertNotEqual(first, hash_directory(root))


if __name__ == "__main__":
    unittest.main()
