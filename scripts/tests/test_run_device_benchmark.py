from __future__ import annotations

import importlib.util
import json
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "run_device_benchmark.py"
SPEC = importlib.util.spec_from_file_location("run_device_benchmark", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_normalize_exported_attachments_materializes_stable_aliases(tmp_path: Path) -> None:
    attachments_dir = tmp_path / "attachments"
    attachments_dir.mkdir()
    exported = attachments_dir / "ABC.json"
    exported.write_text('{"ok": true}', encoding="utf-8")
    (attachments_dir / "manifest.json").write_text(
        json.dumps(
            [
                {
                    "attachments": [
                        {
                            "exportedFileName": "ABC.json",
                            "suggestedHumanReadableName": "scene_summary_0_E79D0424-AA6F-40C8-9E85-88D722D99BD5.json",
                            "timestamp": 100,
                        }
                    ]
                }
            ]
        ),
        encoding="utf-8",
    )

    normalized = MODULE.normalize_exported_attachments(attachments_dir)

    assert normalized == {"scene_summary.json": "ABC.json"}
    assert (attachments_dir / "scene_summary.json").read_text(encoding="utf-8") == '{"ok": true}'


def test_normalize_exported_attachments_prefers_newest_duplicate_alias(tmp_path: Path) -> None:
    attachments_dir = tmp_path / "attachments"
    attachments_dir.mkdir()
    (attachments_dir / "OLD.json").write_text('{"version": "old"}', encoding="utf-8")
    (attachments_dir / "NEW.json").write_text('{"version": "new"}', encoding="utf-8")
    (attachments_dir / "manifest.json").write_text(
        json.dumps(
            [
                {
                    "attachments": [
                        {
                            "exportedFileName": "OLD.json",
                            "suggestedHumanReadableName": "scene_summary_0_11111111-1111-1111-1111-111111111111.json",
                            "timestamp": 100,
                        },
                        {
                            "exportedFileName": "NEW.json",
                            "suggestedHumanReadableName": "scene_summary_0_22222222-2222-2222-2222-222222222222.json",
                            "timestamp": 200,
                        },
                    ]
                }
            ]
        ),
        encoding="utf-8",
    )

    normalized = MODULE.normalize_exported_attachments(attachments_dir)

    assert normalized == {"scene_summary.json": "NEW.json"}
    assert json.loads((attachments_dir / "scene_summary.json").read_text(encoding="utf-8")) == {"version": "new"}


def test_normalize_exported_attachments_returns_empty_mapping_without_manifest(tmp_path: Path) -> None:
    attachments_dir = tmp_path / "attachments"
    attachments_dir.mkdir()
    (attachments_dir / "orphan.json").write_text("{}", encoding="utf-8")

    normalized = MODULE.normalize_exported_attachments(attachments_dir)

    assert normalized == {}
    assert not (attachments_dir / "scene_summary.json").exists()


def test_find_first_across_roots_falls_back_to_attachments_when_archive_is_incomplete(tmp_path: Path) -> None:
    extracted_dir = tmp_path / "extracted"
    attachments_dir = tmp_path / "attachments"
    extracted_dir.mkdir()
    attachments_dir.mkdir()
    (attachments_dir / "scene_summary.json").write_text('{"executionMode": "monolithic"}', encoding="utf-8")

    resolved = MODULE.find_first_across_roots([extracted_dir, attachments_dir], "scene_summary.json")

    assert resolved == attachments_dir / "scene_summary.json"


def test_find_first_across_roots_prefers_the_extracted_copy_when_both_exist(tmp_path: Path) -> None:
    """Restoring the fallback must not overturn precedence: extracted still wins."""
    extracted_dir = tmp_path / "extracted"
    attachments_dir = tmp_path / "attachments"
    extracted_dir.mkdir()
    attachments_dir.mkdir()
    (extracted_dir / "scene_summary.json").write_text('{"executionMode": "extracted"}', encoding="utf-8")
    (attachments_dir / "scene_summary.json").write_text('{"executionMode": "attachments"}', encoding="utf-8")

    resolved = MODULE.find_first_across_roots([extracted_dir, attachments_dir], "scene_summary.json")

    assert resolved == extracted_dir / "scene_summary.json"


def test_find_first_across_roots_returns_none_when_no_root_has_the_file(tmp_path: Path) -> None:
    first = tmp_path / "a"
    second = tmp_path / "b"
    first.mkdir()
    second.mkdir()

    assert MODULE.find_first_across_roots([first, second], "scene_summary.json") is None
