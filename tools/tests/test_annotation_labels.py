from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
ANNOTATION_DIR = REPO_ROOT / "tools/camera_annotation"
if str(ANNOTATION_DIR) not in sys.path:
    sys.path.insert(0, str(ANNOTATION_DIR))

import annotation_labels as labels  # noqa: E402
import assist_hints  # noqa: E402
import phrase_suggestions as phrases  # noqa: E402


def _spec(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _contract_catalog() -> tuple[list[str], list[str]]:
    contract = json.loads(
        (REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json").read_text(encoding="utf-8")
    )
    heads = {head["name"]: head for head in contract["outputs"]["heads"]}
    return heads["issue_logits"]["ordered_names"], heads["action_utility_logits"]["ordered_names"]


def _keep_label(**overrides) -> dict:
    base = dict(
        record_id="r1",
        image_sha256="0" * 64,
        annotator_id="tester",
        beauty="beautiful",
        improvement_needed=False,
        actions=["keep_current_setup"],
        created_at="2026-09-13T00:00:00Z",
    )
    base.update(overrides)
    return labels.build_label(**base)


def test_label_vocabulary_matches_the_frozen_contract_exactly() -> None:
    issues, actions = _contract_catalog()
    assert list(labels.ISSUES) == list(issues), "issue vocabulary drifted from the model contract"
    assert list(labels.ACTIONS) == list(actions), "action vocabulary drifted from the model contract"
    assert labels.KEEP_ACTION in labels.ACTIONS


def test_valid_keep_label_passes_and_maps_to_targets() -> None:
    record = _keep_label()
    assert labels.validate_label(record) == []
    targets = labels.training_targets(record)
    assert targets["good_frame_probability"] == 1.0
    assert len(targets["issue_logits"]) == 8
    assert len(targets["action_utility_logits"]) == 26
    # D02a: a decided record always carries the five delta slots; every
    # unexpressed one is masked. The shape is per-element so a consumer cannot
    # confuse "nothing expressed" with "zero change expressed".
    assert targets["continuous_target_deltas"] == [None] * len(labels.DELTAS)
    assert targets["target_mask"]["continuous_target_deltas"] == [False] * len(labels.DELTAS)
    keep_index = list(labels.ACTIONS).index(labels.KEEP_ACTION)
    assert targets["action_utility_logits"][keep_index] == 1.0
    assert sum(targets["action_utility_logits"]) == 1.0


def test_valid_fix_label_maps_issues_actions_and_deltas() -> None:
    record = labels.build_label(
        record_id="r2",
        image_sha256="1" * 64,
        annotator_id="tester",
        beauty="ugly",
        improvement_needed=True,
        issues=["background_competes_with_subject"],
        actions=["simplify_background", "step_back"],
        regions=[{"role": "distractor", "rect": [0.1, 0.2, 0.3, 0.3]}],
        deltas={"delta_x": 0.25, "scale_delta": -0.5},
        unsure=False,
        notes="лампа мешает",
        created_at="2026-09-13T00:00:00Z",
    )
    targets = labels.training_targets(record)
    assert targets["good_frame_probability"] == 0.0
    assert targets["issue_logits"][list(labels.ISSUES).index("background_competes_with_subject")] == 1.0
    assert sum(targets["issue_logits"]) == 1.0
    # D02a: only the deltas the annotator expressed carry a value; the rest stay
    # masked. Filling 0.0 taught "no change needed" for directions nobody gave.
    assert targets["continuous_target_deltas"] == [0.25, None, -0.5, None, None]
    assert targets["target_mask"]["continuous_target_deltas"] == [True, False, True, False, False]
    assert targets["regions"][0]["role"] == "distractor"


@pytest.mark.parametrize(
    "overrides,expected_error",
    [
        ({"improvement_needed": True, "actions": [], "issues": []},
         "requires at least one corrective action"),
        ({"improvement_needed": True, "actions": ["step_back"], "issues": []},
         "requires at least one issue"),
        ({"improvement_needed": True, "actions": ["step_back", "keep_current_setup"],
          "issues": ["horizon_distracts"]},
         "forbids keep_current_setup"),
        ({"improvement_needed": False, "actions": ["step_back"], "issues": []},
         "requires actions=['keep_current_setup']"),
        ({"improvement_needed": False, "actions": ["keep_current_setup"],
          "issues": ["horizon_distracts"]},
         "forbids issues"),
        ({"beauty": "ugly", "improvement_needed": False, "actions": ["keep_current_setup"], "notes": ""},
         "requires a note"),
    ],
)
def test_inconsistent_labels_are_rejected(overrides, expected_error) -> None:
    with pytest.raises(ValueError) as error:
        _keep_label(**overrides)
    assert expected_error in str(error.value)


def test_unknown_vocabulary_and_bad_regions_are_rejected() -> None:
    with pytest.raises(ValueError) as error:
        _keep_label(improvement_needed=True, issues=["not_a_real_issue"], actions=["step_back"])
    assert "unknown issues" in str(error.value)

    with pytest.raises(ValueError) as error:
        _keep_label(improvement_needed=True, issues=["horizon_distracts"],
                    actions=["not_a_real_action"])
    assert "unknown actions" in str(error.value)

    with pytest.raises(ValueError) as error:
        _keep_label(improvement_needed=True, issues=["horizon_distracts"], actions=["level_horizon"],
                    regions=[{"role": "problem", "rect": [0.9, 0.9, 0.5, 0.5]}])
    assert "normalized inside [0,1]" in str(error.value)

    with pytest.raises(ValueError) as error:
        _keep_label(improvement_needed=True, issues=["horizon_distracts"], actions=["level_horizon"],
                    deltas={"delta_x": 2.0})
    assert "in [-1,1]" in str(error.value)


def test_intentional_mood_ugly_keep_is_allowed_with_a_note() -> None:
    record = _keep_label(beauty="ugly", notes="задумано: силуэт против света")
    assert labels.validate_label(record) == []
    assert labels.training_targets(record)["good_frame_probability"] == 0.0


def test_append_only_store_round_trip(tmp_path: Path) -> None:
    store = tmp_path / "labels.jsonl"
    assert labels.labelled_record_ids(store) == set()
    labels.append_label(store, _keep_label(record_id="a"))
    labels.append_label(store, _keep_label(record_id="b", beauty="borderline"))
    assert labels.labelled_record_ids(store) == {"a", "b"}
    records = labels.load_labels(store)
    summary = labels.label_summary(records)
    assert summary["total"] == 2
    assert summary["per_beauty"]["beautiful"] == 1
    assert summary["per_beauty"]["borderline"] == 1
    assert records[0]["schema_id"] == labels.SCHEMA_ID


def test_phrase_suggestions_map_language_to_catalog() -> None:
    direction = phrases.suggest("сдвинь кадр вправо и убери лампу")
    assert "shift_frame_right" in direction["actions"]
    assert "remove_distracting_object" in direction["actions"]

    defect = phrases.suggest("фон слишком занят, субъект мелкий")
    assert "background_competes_with_subject" in defect["issues"]
    assert "subject_not_prominent_enough" in defect["issues"]

    mood = phrases.suggest("это задумано, мрачное настроение, так и надо")
    assert mood["keep"] is True
    assert mood["issues"] == [] and mood["actions"] == []

    assert phrases.suggest("") == {"issues": [], "actions": [], "keep": False}


def test_phrase_suggestions_only_emit_known_catalog_ids() -> None:
    texts = [
        "темно и мутно", "горизонт завален", "пересвет в фоне", "шаг ближе",
        "отойти назад", "повернуть к свету", "упростить фон", "дождаться пока пройдут люди",
    ]
    for text in texts:
        result = phrases.suggest(text)
        assert set(result["issues"]) <= set(labels.ISSUES), text
        assert set(result["actions"]) <= set(labels.ACTIONS), text


def test_queue_builder_is_deterministic_and_carries_provenance(tmp_path: Path) -> None:
    module = _spec("build_annotation_queue", ANNOTATION_DIR / "build_annotation_queue.py")
    images = tmp_path / "images"
    images.mkdir()
    for index in range(10):
        (images / f"img{index}.jpg").write_bytes(b"not-a-real-jpeg")

    sources = {"fake": (images, "research only (test)", "unit-test")}
    first = module.build_queue(per_source={"fake": 4}, seed=7, sources=sources)
    second = module.build_queue(per_source={"fake": 4}, seed=7, sources=sources)
    assert len(first) == 4
    assert [r["record_id"] for r in first] == [r["record_id"] for r in second], "sampling must be seeded"
    for record in first:
        assert record["provenance"]["license"] == "research only (test)"
        assert record["provenance"]["origin"] == "unit-test"
        assert len(record["image_sha256"]) == 64
        assert Path(record["image_path"]).exists()

    everything = module.build_queue(per_source={"fake": 99}, seed=7, sources=sources)
    assert len(everything) == 10, "asking for more than available must return all images"


def test_queue_builder_rejects_unknown_sources() -> None:
    module = _spec("build_annotation_queue", ANNOTATION_DIR / "build_annotation_queue.py")
    assert "benchmark" in module.DEFAULT_SOURCES
    assert "ava" in module.DEFAULT_SOURCES
    assert "aadb" in module.DEFAULT_SOURCES


def test_assisted_records_require_a_source_and_stay_marked() -> None:
    record = labels.build_label(
        record_id="a1", image_sha256="2" * 64, annotator_id="tester",
        beauty="borderline", improvement_needed=True,
        issues=["frame_visually_overloaded"], actions=["simplify_background"],
        assisted=True, assist_source="heuristics-v1", created_at="2026-09-13T00:00:00Z",
    )
    assert record["assisted"] is True
    assert record["assist_source"] == "heuristics-v1"
    assert labels.validate_label(record) == []

    with pytest.raises(ValueError) as error:
        labels.build_label(
            record_id="a2", image_sha256="3" * 64, annotator_id="tester",
            beauty="borderline", improvement_needed=True,
            issues=["frame_visually_overloaded"], actions=["simplify_background"],
            assisted=True, created_at="2026-09-13T00:00:00Z",
        )
    assert "requires assist_source" in str(error.value)


def test_human_score_preselects_beauty_bands() -> None:
    assert assist_hints.beauty_from_score(7.4, "ava") == "beautiful"
    assert assist_hints.beauty_from_score(5.1, "ava") == "borderline"
    assert assist_hints.beauty_from_score(2.0, "ava") == "ugly"
    assert assist_hints.beauty_from_score(0.8, "aadb") == "beautiful"
    assert assist_hints.beauty_from_score(0.1, "aadb") == "ugly"
    assert assist_hints.beauty_from_score(None, "ava") is None
    assert assist_hints.beauty_from_score(5.0, "unknown-scale") is None


def test_image_hints_are_catalog_valid_and_explainable(tmp_path: Path) -> None:
    from PIL import Image
    dark = tmp_path / "dark.png"
    Image.new("L", (64, 64), color=8).save(dark)
    hints = assist_hints.hints_for_image(dark)
    assert set(hints["issues"]) <= set(labels.ISSUES)
    assert set(hints["actions"]) <= set(labels.ACTIONS)
    assert hints["notes"], "hints must explain themselves"
    assert hints["source"] == assist_hints.ASSIST_SOURCE

    bright = tmp_path / "bright.png"
    Image.new("L", (64, 64), color=250).save(bright)
    bright_hints = assist_hints.hints_for_image(bright)
    assert "background_competes_with_subject" in bright_hints["issues"]
    assert "remove_background_hotspot" in bright_hints["actions"]

    missing = tmp_path / "nope.png"
    assert assist_hints.hints_for_image(missing)["issues"] == []


def test_unsure_records_mask_heads_instead_of_fabricating_negatives() -> None:
    """D02a: 'unsure' must not turn silence into negative evidence."""
    record = _keep_label(unsure=True)
    targets = labels.training_targets(record)
    assert targets["abstention_probability"] == 1.0
    assert targets["issue_logits"] is None, "an unsure record has no issue evidence"
    assert targets["action_utility_logits"] is None, "an unsure record has no action evidence"
    assert targets["continuous_target_deltas"] is None
    assert targets["target_mask"]["issue_logits"] == [False] * len(labels.ISSUES)
    assert targets["target_mask"]["action_utility_logits"] == [False] * len(labels.ACTIONS)
    # good_frame_probability still comes from the beauty rating: it is a rating, not a keep decision


def test_beauty_and_keep_are_independent_labels() -> None:
    """D02a: an ugly frame may be a deliberate keep, and the target says so."""
    record = labels.build_label(
        record_id="r3",
        image_sha256="2" * 64,
        annotator_id="tester",
        beauty="ugly",
        improvement_needed=False,
        actions=["keep_current_setup"],
        notes="задуманный low-key силуэт",
        created_at="2026-09-13T00:00:00Z",
    )
    targets = labels.training_targets(record)
    assert targets["good_frame_probability"] == 0.0, "the rating stays ugly"
    keep_index = list(labels.ACTIONS).index(labels.KEEP_ACTION)
    assert targets["action_utility_logits"][keep_index] == 1.0, "the decision is still an explicit keep"
    assert targets["issue_logits"] == [0.0] * len(labels.ISSUES)


def test_unexpressed_delta_never_becomes_zero() -> None:
    """A one-direction annotation must not teach 'no change' on the other axes."""
    record = labels.build_label(
        record_id="r4",
        image_sha256="3" * 64,
        annotator_id="tester",
        beauty="borderline",
        improvement_needed=True,
        issues=["insufficient_look_space"],
        actions=["shift_frame_right"],
        deltas={"delta_x": 0.4},
        created_at="2026-09-13T00:00:00Z",
    )
    targets = labels.training_targets(record)
    assert targets["continuous_target_deltas"] == [0.4, None, None, None, None]
    assert sum(1 for value in targets["continuous_target_deltas"] if value == 0.0) == 0


def test_gui_exposes_every_frozen_head() -> None:
    """D02b: the annotator must be able to label every head of the frozen contract."""
    gui = _spec("annotate_gui_labels", ANNOTATION_DIR / "annotate_gui.py")
    assert set(gui.ISSUE_LABELS_RU) == set(labels.ISSUES), "GUI issue labels drifted from the frozen catalog"
    assert set(gui.ACTION_LABELS_RU) == set(labels.ACTIONS), "GUI action labels drifted from the frozen catalog"
    assert set(gui.DELTA_LABELS_RU) == set(labels.DELTAS), "GUI delta labels drifted from the frozen catalog"
    assert set(gui.BEAUTY_LABELS_RU) == set(labels.BEAUTY_LEVELS)
