#!/usr/bin/env python3
"""Unit-тесты annotate_fast (DATA-005/DATA-008 UX-итерация) — headless, без tkinter.

Проверяется чистая логика: машинные бакеты, группы/клавиши issues, фильтр действий
через DATA-002 (только disposition=mapped), санити issue↔action, вывод таргета,
evidence-ссылки, полный FSM-поток (все пути спецификации), сид-план/QC, сессия,
seeds-строитель (фикстуры + реальные silver-пары, если локальный диск доступен) и
экспорт через настоящий release_label_adapter.py (happy + honest reject).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parents[1]
TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(REPO / "ml" / "camera_coach" / "contracts"))

from annotation_labels import KEEP_ACTION, load_labels, sha256_file, validate_label  # noqa: E402

import annotate_fast as af  # noqa: E402
import build_fast_seeds as bfs  # noqa: E402

CAPTURED_AT = "2026-09-23T10:00:00Z"


def make_image(tmp_path: Path) -> Path:
    try:
        from PIL import Image
        image = Image.new("RGB", (64, 48), (30, 60, 90))
        path = tmp_path / "frame_0001.jpg"
        image.save(path, format="JPEG")
    except ImportError:
        path = tmp_path / "frame_0001.jpg"
        path.write_bytes(b"\xff\xd8fake-jpeg-for-tests-without-pillow")
    return path


def make_record(tmp_path: Path, **overrides) -> dict:
    tmp_path.mkdir(parents=True, exist_ok=True)
    image = make_image(tmp_path)
    record = {
        "record_id": "pilot23-test-01",
        "package_record_id": "photo__fixture__frame_0001",
        "source_family_id": "pilot_fixture",
        "image_path": str(image),
        "image_sha256": sha256_file(image),
        "strata_group": "composition",
        "review_mode": "blind",
        "provenance": {"kind": "fixture", "license": "test", "origin": "unit"},
    }
    record.update(overrides)
    return record


def letter_for(flow: "af.FrameFlow", action: str) -> str:
    issues = [m.head for m in flow.selected]
    mapping = {a: k for k, a, _ in af.assign_action_letters(af.candidate_actions(issues))}
    assert action in mapping, f"{action} не предложен для {issues}"
    return mapping[action]


# ------------------------------------------------------------- машинные бакеты
def test_severity_buckets_are_machine_derived():
    assert af.severity_value("1") == 0.3
    assert af.severity_value("2") == 0.6
    assert af.severity_value("3") == 0.85
    with pytest.raises(ValueError):
        af.severity_value("4")


def test_confidence_buckets_and_cant_point_step_down():
    assert af.confidence_value("1", False) == 0.9
    assert af.confidence_value("2", False) == 0.6
    # «не могу указать» ([X]) снижает бакет на один шаг — честно
    assert af.confidence_value("1", True) == 0.6
    assert af.confidence_value("2", True) == 0.45


def test_dwell_warning_only_for_needs_fix_under_threshold():
    assert af.dwell_warning(1.0, "2") is True
    assert af.dwell_warning(1.0, "3") is True
    assert af.dwell_warning(2.0, "2") is False
    assert af.dwell_warning(0.1, "1") is False  # keep не проверяется


# ------------------------------------------------------------ группы и клавиши
def test_issue_groups_cover_all_release_heads_with_unique_keys():
    heads = [h for _, rows in af.ISSUE_GROUPS for _, h, _ in rows]
    keys = [k for _, rows in af.ISSUE_GROUPS for k, _, _ in rows]
    schema = json.loads(af.SCHEMA_PATH.read_text(encoding="utf-8"))
    assert set(heads) == set(schema["$defs"]["issueID"]["enum"])
    assert len(keys) == len(set(keys)) == 15
    assert set(af.ISSUE_TITLES) == set(heads)
    # служебные клавиши потока не заняты проблемами
    assert not set(keys) & set(list("123USBRXYNW") + ["Enter", "Esc", " "])


def test_offered_actions_are_exactly_mapped_dispositions():
    mapping = json.loads(af.MAPPING_PATH.read_text(encoding="utf-8"))
    offered = {a for acts in af.ISSUE_TO_ACTIONS.values() for a in acts}
    mapped = af.mapped_actions(mapping)
    assert offered <= mapped  # неподдержанные действия не предлагаются никогда
    # честное отсутствие: у noise/lens_smudge нет поддержанных действий
    assert af.ISSUE_TO_ACTIONS["noise"] == []
    assert af.ISSUE_TO_ACTIONS["lens_smudge"] == []


def test_candidate_actions_union_and_relevance_order():
    assert af.candidate_actions(["noise", "lens_smudge"]) == []
    both = af.candidate_actions(["horizon_distracts", "underexposure"])
    assert "level_horizon" in both and "increase_exposure" in both
    # действие, покрывающее обе проблемы, стоит выше покрывающего одну
    both2 = af.candidate_actions(["subject_too_close_to_edge", "frame_visually_overloaded"])
    assert both2.index("step_back") < both2.index("shift_frame_left")


def test_action_letters_unique_and_n_reserved():
    letters = af.assign_action_letters(["shift_frame_left", "step_back", "refocus_subject"])
    keys = [k for k, _, _ in letters]
    assert len(keys) == len(set(keys))
    assert "N" not in keys


# ------------------------------------------------------------------- санити
def test_sanity_warns_on_spec_example_underexposure_plus_level_horizon():
    warnings = af.action_coverage_warnings(["underexposure", "horizon_distracts"], "level_horizon")
    assert warnings and "недосвет" in warnings[0]


def test_sanity_silent_when_action_covers_all_selected_issues():
    assert af.action_coverage_warnings(["horizon_distracts"], "level_horizon") == []


# ------------------------------------------------------------------- таргет
def test_derive_target_for_move_action_and_movability_answers():
    for answer, expected in (("Y", ("movable", "allowed")),
                             ("N", ("immovable", "denied")),
                             ("?", ("unknown", "unknown"))):
        target = af.derive_target(action="move_object_left", verdict="needs_fix",
                                  subject_rect=[0.1, 0.1, 0.4, 0.4], movability_answer=answer)
        assert target["identity_status"] == "resolved"
        assert target["kind"] == "object"
        assert target["role"] == "target"
        assert (target["movability_status"], target["movability_permission"]) == expected
    person = af.derive_target(action="move_subject_left", verdict="needs_fix",
                              subject_rect=[0.1, 0.1, 0.4, 0.4], movability_answer="Y")
    assert person["kind"] == "person"


def test_derive_target_auto_for_non_move_and_keep():
    # stabilize/reduce/increase exposure: resolvedTarget контрактом не требуется
    target = af.derive_target(action="stabilize_camera", verdict="needs_fix",
                              subject_rect=None, movability_answer=None)
    assert target["identity_status"] == "unknown"
    assert target["movability_status"] == "not_applicable"
    keep = af.derive_target(action=KEEP_ACTION, verdict="good",
                            subject_rect=None, movability_answer=None)
    assert keep["role"] == "context"
    # resolvedTarget-действие без рамки: honest весь кадр, identity resolved (schema allOf[6])
    full = af.derive_target(action="level_horizon", verdict="needs_fix",
                            subject_rect=None, movability_answer=None)
    assert full["identity_status"] == "resolved" and full["rect"] == [0.0, 0.0, 1.0, 1.0]


def test_evidence_refs_auto_from_rect_presence():
    assert af.evidence_ref("pilot23-x-01", 0, True) == "pilot23-x-01.r0"
    assert af.evidence_ref("pilot23-x-01", 2, False) == "pilot23-x-01.frame"


def test_assemble_issue_evidence_uses_machine_buckets():
    detail = {
        "record_id": "pilot23-x-01",
        "selected_issues": ["horizon_distracts", "underexposure"],
        "issue_rects": {"horizon_distracts": [0.1, 0.4, 0.8, 0.2]},
        "severity_value": 0.85,
        "confidence_value": 0.6,
    }
    evidence = af.assemble_issue_evidence(detail)
    assert evidence["horizon_distracts"]["evidence_refs"] == ["pilot23-x-01.r0"]
    assert evidence["horizon_distracts"]["rect"] == [0.1, 0.4, 0.8, 0.2]
    assert evidence["underexposure"]["evidence_refs"] == ["pilot23-x-01.frame"]
    assert "rect" not in evidence["underexposure"]
    assert evidence["horizon_distracts"]["severity"] == 0.85
    assert evidence["horizon_distracts"]["confidence"] == 0.6
    # экспорт идёт по v1-подмножеству записанной v1-метки
    subset = af.assemble_issue_evidence(detail, label_issues=["horizon_distracts"])
    assert list(subset) == ["horizon_distracts"]


# ------------------------------------------------------------------ FSM потоки
def run(flow: "af.FrameFlow", *keys: str) -> "af.FrameFlow":
    for key in keys:
        flow.key(key)
    return flow


def test_flow_good_is_two_keypresses(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("1")
    assert flow.step == af.STEP_CONFIRM_KEEP
    flow.enter()
    assert flow.outcome.kind == "save"
    label = flow.outcome.label
    assert label["beauty"] == "beautiful"
    assert label["improvement_needed"] is False
    assert label["actions"] == [KEEP_ACTION]
    assert validate_label(label) == []


def test_flow_technical_only_heads_have_no_v1_label_but_full_detail(tmp_path):
    """7 технических heads есть только в release-контракте: v1-словарь их не знает.

    Визард предлагает все 15 (спека); решённый needs_fix из чисто технических
    heads v1 закодировать не может — записи fast_labels нет, полная правда в
    fast_details (честное отсутствие вместо выдуманной совместимости).
    """
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("D")                    # недосвет — вне v1
    flow.enter()
    flow.key(letter_for(flow, "increase_exposure"))  # тоже вне v1 ACTIONS
    flow.key("2"); flow.key("2")
    assert flow.step == af.STEP_NOTE  # increase_exposure не требует resolvedTarget — рамки не нужно
    flow.set_note("тёмный кадр"); flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    assert label is None
    assert detail["verdict"] == "needs_fix"
    assert detail["selected_issues"] == ["underexposure"]
    assert detail["v1_label_written"] is False
    # предупреждение видно аннотатору ДО сохранения
    flow2 = af.FrameFlow(make_record(tmp_path), annotator_id="tester")
    flow2.key("2"); flow2.key("D"); flow2.enter()
    flow2.key(letter_for(flow2, "increase_exposure")); flow2.key("1"); flow2.key("1")
    flow2.key("R")
    warnings = flow2.snapshot()["warnings"]
    assert any("вне v1-словаря" in w for w in warnings)


def test_flow_mixed_heads_write_v1_subset_and_export_rejects_honestly(tmp_path):
    record = make_record(tmp_path, captured_at=CAPTURED_AT)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("H"); flow.key("D")     # горизонт (v1) + недосвет (release-only)
    flow.enter()
    flow.key(letter_for(flow, "level_horizon"))
    flow.key("2"); flow.key("1")
    flow.set_draft_rect([0.2, 0.2, 0.5, 0.5]); flow.enter()
    flow.set_note("завал и темно"); flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    assert label is not None and label["issues"] == ["horizon_distracts"]  # v1-подмножество
    assert detail["v1_incomplete"] is True
    out_dir = tmp_path / "export-mixed"
    result = af.export_labels(labels=[label], details=[detail], queue_rows=[record],
                              seeds_rows=[], out_dir=out_dir)
    assert not result["exported"] and len(result["rejected"]) == 1
    assert "v1-словарь" in result["rejected"][0]["reason"]
    assert not list(out_dir.glob("*.json"))


def test_flow_needs_fix_full_path_with_rect_and_exportable_detail(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2")
    flow.key("H")                       # horizon_distracts
    flow.set_draft_rect([0.1, 0.4, 0.8, 0.2])
    flow.enter()                        # рамка прикреплена к последней issue
    assert flow.step == af.STEP_ACTION
    flow.key(letter_for(flow, "level_horizon"))
    flow.key("3")                       # серьёзно → 0.85
    flow.key("1")                       # уверен → 0.9
    assert flow.step == af.STEP_TARGET_RECT  # level_horizon требует resolvedTarget
    flow.set_draft_rect([0.2, 0.2, 0.5, 0.5])
    flow.enter()
    assert flow.step == af.STEP_NOTE
    flow.set_note("горизонт заметно завален")
    flow.enter()

    label, detail = flow.outcome.label, flow.outcome.detail
    assert validate_label(label) == []
    assert label["issues"] == ["horizon_distracts"]
    assert label["actions"] == ["level_horizon"]
    assert detail["severity_value"] == 0.85
    assert detail["confidence_value"] == 0.9
    assert detail["issue_rects"]["horizon_distracts"] == [0.1, 0.4, 0.8, 0.2]
    assert detail["subject_rect"] == [0.2, 0.2, 0.5, 0.5]
    assert detail["target"]["identity_status"] == "resolved"
    assert detail["verdict"] == "needs_fix"


def test_flow_cant_point_lowers_confidence_bucket(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("H"); flow.key("X")   # не могу указать
    flow.enter()
    flow.key(letter_for(flow, "level_horizon"))
    flow.key("1"); flow.key("1")                  # уверен → 0.9, но X → 0.6
    flow.key("R")                                 # весь кадр вместо рамки субъекта
    flow.set_note("x"); flow.enter()
    assert flow.outcome.detail["confidence_value"] == 0.6
    assert flow.outcome.detail["confidence_capped_by_cant_point"] is True


def test_flow_ugly_requires_intentional_style_answer_and_note(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("3")
    assert flow.step == af.STEP_STYLE
    flow.key("Y")
    assert flow.step == af.STEP_STYLE_NOTE
    flow.enter()                                  # пустая заметка — отказ
    assert flow.step == af.STEP_STYLE_NOTE and flow.messages
    flow.set_note("намеренный тёмный силуэт")
    flow.enter()
    label = flow.outcome.label
    assert label["beauty"] == "ugly" and label["improvement_needed"] is False
    assert label["notes"] == "намеренный тёмный силуэт"
    flow2 = af.FrameFlow(make_record(tmp_path), annotator_id="tester")
    flow2.key("3"); flow2.key("N")
    assert flow2.step == af.STEP_ISSUES           # дефект → обычный путь


def test_flow_unsure_is_first_class_with_reason_and_optional_line(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("U")
    assert flow.step == af.STEP_UNSURE_REASON
    flow.key("2")                                 # двусмысленный субъект
    flow.enter()                                  # пустая строка допускается
    label, detail = flow.outcome.label, flow.outcome.detail
    assert label["unsure"] is True
    assert validate_label(label) == []
    assert detail["abstention_reason"] == "ambiguous_subject"
    assert "двусмысленный субъект" in label["notes"]


def test_flow_no_supported_action_is_honest_abstention(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("Z")                  # шум: поддержанных действий нет
    flow.enter()
    assert flow.step == af.STEP_ACTION
    assert flow.snapshot()["options"] == []
    flow.key("N")
    assert flow.step == af.STEP_NO_ACTION
    flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    assert label["unsure"] is True
    assert detail["no_supported_action"] is True
    assert detail["abstention_reason"] == "unsupported_case"
    assert "шум" in label["notes"]
    assert detail["selected_issues"] == ["noise"]  # правда сохранена рядом, не потеряна


def test_flow_good_plus_issues_is_blocked_and_verdict_reasked(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("1")
    flow.key("H")                                 # передумал прямо из confirm
    assert flow.step == af.STEP_ISSUES
    flow.enter()
    assert flow.step == af.STEP_VERDICT_REVISIT   # «хороший» больше недоступен
    flow.key("2")
    assert flow.step == af.STEP_ACTION


def test_flow_movability_asked_only_for_moving_actions(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("C"); flow.enter()    # фон спорит с субъектом
    flow.key(letter_for(flow, "move_object_left"))
    flow.key("2"); flow.key("1")
    assert flow.step == af.STEP_MOVABILITY
    flow.key("N")
    assert flow.step == af.STEP_MOVABILITY_WARN   # двигать нельзя → предупреждение
    flow.enter()                                  # всё равно продолжить (экспорт отклонит)
    assert flow.step == af.STEP_TARGET_RECT
    flow.set_draft_rect([0.3, 0.3, 0.3, 0.3]); flow.enter()
    flow.set_note(""); flow.enter()
    target = flow.outcome.detail["target"]
    assert target["movability_status"] == "immovable"
    assert target["movability_permission"] == "denied"

    flow2 = af.FrameFlow(make_record(tmp_path), annotator_id="tester")
    flow2.key("2"); flow2.key("H"); flow2.enter()
    flow2.key(letter_for(flow2, "level_horizon"))  # не move → вопроса movability нет
    flow2.key("2"); flow2.key("2")
    assert flow2.step == af.STEP_TARGET_RECT


def test_flow_skip_and_back_navigation(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("H")
    flow.enter()
    flow.back()                                    # Esc из action → issues (выбор сброшен)
    assert flow.step == af.STEP_ISSUES and flow.selected == []
    flow.back()
    assert flow.step == af.STEP_VERDICT and flow.verdict_key is None

    flow2 = af.FrameFlow(make_record(tmp_path), annotator_id="tester")
    flow2.key("S")
    assert flow2.outcome.kind == "skip"


# ------------------------------------------------------------- сиды и QC
def test_plan_seed_positions_five_to_seven_percent_deterministic():
    positions = af.plan_seed_positions(100, 10)
    assert 5 <= len(positions) <= 7
    assert positions == sorted(positions)
    assert positions == af.plan_seed_positions(100, 10)
    assert all(0 < p < 100 for p in positions)
    assert af.plan_seed_positions(5, 3)  # крошечная очередь — максимум 1 сид
    assert len(af.interleave_seeds(list(range(100)), [])) == 100


def test_interleave_seeds_hides_seed_marker_from_display_fields():
    queue = [{"record_id": f"q{i:03d}"} for i in range(100)]
    seeds = [{"record_id": f"qcseed-{i}"} for i in range(8)]
    items = af.interleave_seeds(queue, seeds)
    assert len(items) == 100 + len(af.plan_seed_positions(100, 8))
    # порядок очереди сохранён
    queue_ids = [i["record_id"] for i in items if not i.get("_is_seed")]
    assert queue_ids == [f"q{i:03d}" for i in range(100)]
    # сид-записи неотличимы по display-полям (маркер только служебный)
    seed_rows = [i for i in items if i.get("_is_seed")]
    assert all("qcseed" in r["record_id"] for r in seed_rows)


def test_qc_entry_and_agreement_report():
    detail = {"record_id": "qcseed-x", "verdict": "needs_fix", "selected_issues": ["horizon_distracts"],
              "action": "level_horizon"}
    label = {"record_id": "qcseed-x", "issues": ["horizon_distracts"], "actions": ["level_horizon"]}
    expected = {"expected_verdict": "needs_fix", "expected_issue": "horizon_distracts",
                "expected_action": "level_horizon"}
    ok = af.qc_entry(detail, label, expected)
    assert all(ok["matched"].values())
    bad = af.qc_entry({"record_id": "qcseed-y", "verdict": "unsure", "selected_issues": [],
                       "action": None}, {"issues": []}, expected)
    assert not any(bad["matched"].values())
    report = af.agreement_report([ok, bad])
    assert "1/2" in report and "qcseed-y" in report
    assert "нет записанных" in af.agreement_report([])


def test_session_roundtrip(tmp_path):
    session = af.FastSession(tmp_path / "session.json")
    assert session.load() is None
    state = {"annotator_id": "rustem", "index": 3, "done": ["a", "b"], "skipped": []}
    session.save(state)
    loaded = session.load()
    assert loaded["index"] == 3 and set(loaded["done"]) == {"a", "b"}
    (tmp_path / "session.json").write_text("{broken", encoding="utf-8")
    assert session.load() is None  # битая сессия не роняет инструмент


# ------------------------------------------------------------- seeds builder
@pytest.fixture
def synthetic_pairs(tmp_path: Path) -> Path:
    """Маленький манифест silver-пар: 2 однозначных рецепта + мусорные строки."""
    from PIL import Image

    images = tmp_path / "images"
    images.mkdir()
    rows = []

    def add(pair_id: str, recipe: str, action: str, issue: str, corrupted: bool = True):
        path = images / f"{pair_id}.png"
        image = Image.new("RGB", (32, 24), (90, 120, 30) if corrupted else (10, 10, 10))
        image.save(path, format="PNG")
        actions = ["shift_frame_left", "shift_frame_right", "step_back", "step_closer",
                   "level_horizon", KEEP_ACTION]
        issues = ["subject_too_close_to_edge", "horizon_distracts", "underexposure"]
        rows.append({
            "pair_id": pair_id,
            "source_family_id": "family_fixture",
            "recipe": {"name": recipe, "parameters": {}, "version": "test"},
            "derivative": {"relative_path": f"images/{pair_id}.png", "sha256": sha256_file(path),
                           "width": 32, "height": 24, "format": "png"},
            "source": {"source_record_id": f"src__{pair_id}", "source_id": "fixture"},
            "targets": {
                "action": {"ordered_names": actions,
                           "values": [1 if a == action else 0 for a in actions],
                           "mask": [1] * len(actions)},
                "issue": {"ordered_names": issues,
                          "values": [1 if i == issue else 0 for i in issues],
                          "mask": [1] * len(issues)},
            },
        })

    for i in range(4):
        add(f"pair_tr_{i:04d}", "crop_translate", "shift_frame_left", "subject_too_close_to_edge")
    for i in range(4):
        add(f"pair_rz_{i:04d}", "rotate_horizon", "level_horizon", "horizon_distracts")
    for i in range(2):
        add(f"pair_zm_{i:04d}", "crop_zoom_in", "step_back", "subject_too_close_to_edge")
    # неоднозначные/мусорные строки обязаны отфильтроваться
    add("pair_ambig", "crop_translate", "step_closer", "subject_too_close_to_edge")
    add("pair_wrong_recipe", "gaussian_blur", "stabilize_camera", "motion_blur")

    manifest = tmp_path / "pairs.jsonl"
    manifest.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return manifest


def test_build_seeds_filters_and_balances(synthetic_pairs: Path, tmp_path: Path):
    seeds = bfs.build_seeds([synthetic_pairs], count=8)
    assert len(seeds) == 8
    recipes = [s["provenance"]["recipe"] for s in seeds]
    assert recipes.count("crop_translate") == 3
    assert recipes.count("rotate_horizon") == 3
    assert recipes.count("crop_zoom_in") == 2
    assert all(s["expected_verdict"] == "needs_fix" for s in seeds)
    for seed in seeds:
        assert Path(seed["image_path"]).exists()
        assert seed["image_sha256"] == sha256_file(Path(seed["image_path"]))
        assert seed["research_only"] is True and seed["human_gold"] is False
    # двусмысленные строки не попали
    assert all("ambig" not in s["record_id"] and "wrong" not in s["record_id"] for s in seeds)
    # детерминизм
    assert seeds == bfs.build_seeds([synthetic_pairs], count=8)


def test_build_seeds_refuses_when_too_few_unambiguous(tmp_path: Path):
    manifest = tmp_path / "pairs.jsonl"
    manifest.write_text(json.dumps({
        "pair_id": "p1", "recipe": {"name": "rotate_horizon"}, "derivative": {},
        "targets": {"action": {"ordered_names": [], "values": []},
                    "issue": {"ordered_names": [], "values": []}},
    }) + "\n", encoding="utf-8")
    with pytest.raises(SystemExit):
        bfs.build_seeds([manifest], count=8)


def test_build_seeds_on_real_silver_pairs():
    real = bfs.DEFAULT_PAIRS
    if not real.exists():
        pytest.skip(f"локальные silver-пары недоступны: {real}")
    seeds = bfs.build_seeds([real], count=8)
    assert 6 <= len(seeds) <= 10
    for seed in seeds:
        assert seed["expected_verdict"] == "needs_fix"
        assert seed["expected_issue"] in {
            "horizon_distracts", "subject_too_close_to_edge",
        }
        assert seed["expected_action"] in {
            "level_horizon", "step_back", "shift_frame_left", "shift_frame_right",
            "shift_frame_up", "shift_frame_down",
        }
        assert Path(seed["image_path"]).exists()
        assert sha256_file(Path(seed["image_path"])) == seed["image_sha256"]


# ------------------------------------------------------------------- экспорт
def test_export_happy_path_and_reject_are_fail_closed(tmp_path: Path):
    record = make_record(tmp_path, captured_at=CAPTURED_AT)
    queue = [record]

    # happy: needs_fix с полной машинной обвязкой
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("H")
    flow.set_draft_rect([0.1, 0.4, 0.8, 0.2]); flow.enter()
    flow.key(letter_for(flow, "level_horizon"))
    flow.key("3"); flow.key("1")
    flow.set_draft_rect([0.2, 0.2, 0.5, 0.5]); flow.enter()
    flow.set_note("горизонт завален, но кадр спасаемый"); flow.enter()
    good_label, good_detail = flow.outcome.label, flow.outcome.detail

    # reject 1: keep без заметки — конверт требует raw opinion, честный отказ
    flow2 = af.FrameFlow(make_record(tmp_path, record_id="pilot23-keep-02",
                                     image_path=record["image_path"],
                                     image_sha256=record["image_sha256"]),
                         annotator_id="tester")
    flow2.key("1"); flow2.enter()
    bare_label, bare_detail = flow2.outcome.label, flow2.outcome.detail

    # reject 2: очередь без captured_at — время съёмки неизвестно, выдумывать нельзя
    no_time_record = make_record(tmp_path / "sub", record_id="pilot23-notime-03",
                                 image_path=record["image_path"],
                                 image_sha256=record["image_sha256"])
    flow3 = af.FrameFlow(no_time_record, annotator_id="tester")
    flow3.key("2"); flow3.key("H"); flow3.enter()
    flow3.key(letter_for(flow3, "level_horizon"))
    flow3.key("2"); flow3.key("2"); flow3.key("R")
    flow3.set_note("горизонт"); flow3.enter()
    notime_label, notime_detail = flow3.outcome.label, flow3.outcome.detail
    labels = [good_label, bare_label, notime_label]
    details = [good_detail, bare_detail, notime_detail]
    queue_rows = [record, make_record(tmp_path, record_id="pilot23-keep-02",
                                      image_path=record["image_path"],
                                      image_sha256=record["image_sha256"],
                                      captured_at=CAPTURED_AT), no_time_record]
    out_dir = tmp_path / "export"
    result = af.export_labels(labels=labels, details=details, queue_rows=queue_rows,
                              seeds_rows=[], out_dir=out_dir)

    assert len(result["exported"]) == 1
    exported_files = list(out_dir.glob("*.json"))
    assert len(exported_files) == 1
    envelope = json.loads(exported_files[0].read_text(encoding="utf-8"))
    assert envelope["release_label"]["verdict"] == "needs_fix"
    assert envelope["raw_opinion"]["text"] == "горизонт завален, но кадр спасаемый"
    # validate уже прогнан внутри export_labels; прогоним ещё раз явно
    adapter = TOOLS / "release_label_adapter.py"
    validated = subprocess.run([sys.executable, str(adapter), "validate", "--label",
                                str(exported_files[0])], capture_output=True, text=True, timeout=120)
    assert validated.returncode == 0 and "RELEASE LABEL VALID" in validated.stdout

    rejected_ids = {row["record_id"] for row in result["rejected"]}
    assert rejected_ids == {"pilot23-keep-02", "pilot23-notime-03"}
    reasons = {row["record_id"]: row["reason"] for row in result["rejected"]}
    assert "raw_opinion" in reasons["pilot23-keep-02"]
    assert "captured_at" in reasons["pilot23-notime-03"]


def test_export_unsure_record_uses_abstention_reason(tmp_path: Path):
    record = make_record(tmp_path, captured_at=CAPTURED_AT)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("U"); flow.key("1")
    flow.set_note("не понимаю, зачем этот кадр"); flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    out_dir = tmp_path / "export-unsure"
    result = af.export_labels(labels=[label], details=[detail], queue_rows=[record],
                              seeds_rows=[], out_dir=out_dir)
    assert len(result["exported"]) == 1, result["rejected"]
    envelope = json.loads(next(out_dir.glob("*.json")).read_text(encoding="utf-8"))
    release = envelope["release_label"]
    assert release["verdict"] is None
    assert release["abstention"] == {"status": "abstain", "reasons": ["unsupported_case"]}


def test_append_only_stores_never_rewrite(tmp_path: Path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("1"); flow.enter()
    first = flow.outcome
    af.append_jsonl(tmp_path / "fast_details.jsonl", first.detail)
    from annotation_labels import append_label
    append_label(tmp_path / "fast_labels.jsonl", first.label)

    # повторное сохранение того же кадра (просмотр назад + правка) — новая запись
    flow2 = af.FrameFlow(record, annotator_id="tester", restore={"label": first.label, "detail": first.detail})
    flow2.key("1"); flow2.enter()
    af.append_jsonl(tmp_path / "fast_details.jsonl", flow2.outcome.detail)
    append_label(tmp_path / "fast_labels.jsonl", flow2.outcome.label)

    labels = load_labels(tmp_path / "fast_labels.jsonl")
    assert len(labels) == 2
    assert labels[0]["created_at"] <= labels[1]["created_at"]


def test_latest_answers_prefill_restores_flow_state(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2"); flow.key("H")
    flow.set_draft_rect([0.1, 0.4, 0.8, 0.2]); flow.enter()
    flow.key(letter_for(flow, "level_horizon"))
    flow.key("3"); flow.key("1")
    flow.set_draft_rect([0.2, 0.2, 0.5, 0.5]); flow.enter()
    flow.set_note("завал"); flow.enter()
    saved = flow.outcome

    restore = af.latest_answers(record["record_id"], [saved.label], [saved.detail])
    assert restore is not None
    again = af.FrameFlow(record, annotator_id="tester", restore=restore)
    assert again.verdict_key == "2"
    assert [m.head for m in again.selected] == ["horizon_distracts"]
    assert again.chosen_action == "level_horizon"
    assert again.note == "завал"
    assert again.subject_rect == [0.2, 0.2, 0.5, 0.5]


def test_russian_layout_hotkeys_map_to_latin_positions():
    # ЙЦУКЕН: горячие клавиши должны работать и в русской раскладке
    mapping = af._FastApp.CYRILLIC_TO_LATIN
    assert mapping["р"] == "h"   # horizon
    assert mapping["з"] == "p"   # prominence
    assert mapping["с"] == "c"   # background competes
    assert mapping["у"] == "e"   # edge
    assert mapping["н"] == "y"   # movability Y
    assert mapping["т"] == "m"   # motion blur
    # все целевые латинские буквы достижимы и уникальны по источнику
    assert len(mapping) == len(set(mapping.values()))


# ---------------------------------------------------------------- [A] contract gap

def test_gap_button_with_selected_issues_rides_to_action(tmp_path):
    """[A] при уже выбранных проблемах: флаг едет дальше, действие обычное."""
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2")
    flow.key("E")                       # субъект у края (v1)
    flow.key("A")                       # + «и ещё контрактом не выразить»
    assert flow.step == af.STEP_GAP_NOTE
    assert flow.contract_gap is True
    flow.set_note("хочется симметрии по центру"); flow.enter()
    assert flow.step == af.STEP_ACTION
    flow.key(letter_for(flow, "step_back"))
    flow.key("2"); flow.key("1")
    assert flow.step == af.STEP_TARGET_RECT   # step_back требует рамку таргета
    flow.key("R")                              # весь кадр — честный таргет
    flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    assert label is not None and validate_label(label) == []
    assert detail["contract_gap"] is True
    assert detail["gap_note"] == "хочется симметрии по центру"


def test_gap_button_alone_saves_honest_abstain(tmp_path):
    """[A] без проблем: чистое «контрактом не выразить» → v1 unsure + unsupported_case."""
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2")
    flow.key("A")                       # ни одной проблемы не выбрано
    assert flow.step == af.STEP_GAP_NOTE
    flow.set_note("норм кадр, но хочется чуть правее для симметрии"); flow.enter()
    assert flow.outcome is not None and flow.outcome.kind == "save"
    label, detail = flow.outcome.label, flow.outcome.detail
    assert validate_label(label) == []
    assert label["unsure"] is True
    assert label["issues"] == [] and label["actions"] == []
    assert "симметрии" in label["notes"]
    assert detail["verdict"] == "contract_gap"
    assert detail["contract_gap"] is True
    assert detail["abstention_reason"] == "unsupported_case"
    assert detail["nominal_verdict"] == "2"


def test_gap_note_escape_clears_flag(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("2")
    flow.key("E")
    flow.key("A")
    assert flow.contract_gap is True
    flow.back()                         # Esc с шага gap-заметки
    assert flow.step == af.STEP_ISSUES
    assert flow.contract_gap is False
    assert flow.gap_note == ""


def test_gaps_report_lists_gap_records(tmp_path):
    lines = [
        json.dumps({"record_id": "pilot23-x-01", "verdict": "contract_gap",
                    "contract_gap": True, "gap_note": "хочется симметрии",
                    "selected_issues": []}, ensure_ascii=False),
        json.dumps({"record_id": "pilot23-x-02", "verdict": "needs_fix",
                    "contract_gap": False, "gap_note": "", "selected_issues": ["defocus"]}, ensure_ascii=False),
    ]
    report = af.gaps_report([json.loads(l) for l in lines])
    assert "1 запис" in report and "pilot23-x-01" in report and "хочется симметрии" in report
    assert "pilot23-x-02" not in report
    assert "пусто" in af.gaps_report([])


# ------------------------------------------------------- talk-режим и prefill

def test_talk_note_roundtrip_and_guards(tmp_path):
    import annotate_talk as at
    record = make_record(tmp_path)
    note = at.build_note(record=record, annotator_id="rustem",
                         text="  фон перегружен, хочется отойти назад и дать воздух справа  ",
                         verdict_tag="2", dwell_ms=12345)
    assert note["text"] == "фон перегружен, хочется отойти назад и дать воздух справа"
    assert note["verdict_tag"] == "mixed"
    assert note["talk_schema"] == "camera-talk-note-v1"
    assert note["human_gold"] is False
    with pytest.raises(ValueError):
        at.build_note(record=record, annotator_id="rustem", text="   ", verdict_tag=None, dwell_ms=1)
    bad = dict(record, image_sha256="0" * 64)
    with pytest.raises(ValueError):
        at.build_note(record=bad, annotator_id="rustem", text="текст", verdict_tag=None, dwell_ms=1)


def test_prefill_flow_confirm_in_enters(tmp_path):
    """Цикл: агент структурировал talk-заметку → аннотатор подтверждает Enter'ами."""
    record = make_record(tmp_path)
    prefill = {"record_id": record["record_id"], "source": "talk-v1",
               "label": {"beauty": "borderline", "improvement_needed": True,
                         "issues": ["background_competes_with_subject"],
                         "actions": ["change_camera_angle"], "unsure": False, "notes": ""},
               "detail": {"verdict": "needs_fix", "verdict_key": "2",
                          "selected_issues": ["background_competes_with_subject"],
                          # step_back для «фон спорит» DATA-002 не мапит (gap-кандидат v2),
                          # из mapped-кандидатов берём change_camera_angle
                          "action": "change_camera_angle", "severity_key": "2", "confidence_key": "1",
                          "movability_key": None}}
    flow = af.FrameFlow(record, annotator_id="tester",
                        restore={"label": prefill["label"], "detail": prefill["detail"]},
                        prefill_source=prefill["source"])
    flow.key("2")                                  # подтверждение вердикта
    flow.enter()                                   # issues: предвыбранная проблема → далее
    flow.key(letter_for(flow, "change_camera_angle"))  # подтверждение действия
    flow.key("2"); flow.key("1")                   # severity/confidence (предвыбраны — жмём те же)
    flow.key("R"); flow.enter()                    # рамка таргета: весь кадр → заметка
    flow.enter()                                   # заметка пустая — ок (prefill-источник отдельно)
    label, detail = flow.outcome.label, flow.outcome.detail
    assert label is not None and validate_label(label) == []
    assert detail["prefill_source"] == "talk-v1"
    assert detail["action"] == "change_camera_angle"


# --------------------------------------------- идентичность записей (DATA-008)
def test_identity_accepts_unique_queue_and_bound_store(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("1"); flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    assert af.queue_identity_problems(queue=[record], seeds=[], labels=[label],
                                      details=[detail]) == []


def test_identity_rejects_duplicate_record_id_for_two_frames(tmp_path):
    """Регрессия 2026-09-27 (DATA-008): дубль record_id в очереди молча показывал чужой кадр."""
    record = make_record(tmp_path)
    twin = dict(record, image_sha256="b" * 64, package_record_id="photo__fixture__frame_0002")
    problems = af.queue_identity_problems(queue=[record, twin], seeds=[], labels=[], details=[])
    assert len(problems) == 1
    assert "разные кадры" in problems[0]
    # повтор той же строки — тоже отказ: две позиции обхода не могут делить один id
    problems = af.queue_identity_problems(queue=[record, dict(record)], seeds=[], labels=[], details=[])
    assert len(problems) == 1 and "повторяется" in problems[0]


def test_identity_rejects_store_bound_to_another_queue(tmp_path):
    record = make_record(tmp_path)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("1"); flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    other_queue = dict(record, image_sha256="c" * 64)
    problems = af.queue_identity_problems(queue=[other_queue], seeds=[], labels=[label],
                                          details=[detail])
    assert any("привязана к другому кадру" in p for p in problems)
    stranger = dict(label, record_id="pilot23-stranger-99")
    problems = af.queue_identity_problems(queue=[record], seeds=[], labels=[stranger], details=[])
    assert any("отсутствует в этой очереди" in p for p in problems)


def test_export_rejects_unbound_and_misbound_labels(tmp_path):
    record = make_record(tmp_path, captured_at=CAPTURED_AT)
    flow = af.FrameFlow(record, annotator_id="tester")
    flow.key("1"); flow.enter()
    label, detail = flow.outcome.label, flow.outcome.detail
    misbound = dict(label, image_sha256="d" * 64)          # свой id, чужой кадр
    stranger = dict(label, record_id="pilot23-stranger-02")  # id чужой очереди
    out_dir = tmp_path / "export-identity"
    result = af.export_labels(labels=[misbound, stranger], details=[detail], queue_rows=[record],
                              seeds_rows=[], out_dir=out_dir)
    assert result["exported"] == []
    assert not list(out_dir.glob("*.json"))  # ничего не записано
    reasons = {row["record_id"]: row["reason"] for row in result["rejected"]}
    assert "экспорт запрещён" in reasons["pilot23-test-01"]
    assert "не привязана" in reasons["pilot23-stranger-02"]


def test_check_identity_cli_fails_on_duplicate_and_passes_clean(tmp_path):
    record = make_record(tmp_path)
    queue_file = tmp_path / "queue.jsonl"
    twin = dict(record, image_sha256="e" * 64)
    queue_file.write_text(json.dumps(record) + "\n" + json.dumps(twin) + "\n", encoding="utf-8")
    assert af.main(["--queue", str(queue_file), "--check-identity"]) == 2
    queue_file.write_text(json.dumps(record) + "\n", encoding="utf-8")
    assert af.main(["--queue", str(queue_file), "--check-identity"]) == 0


PILOT_DIR = Path("/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/"
                 "annotation/pilot-20260923-strata-v1")
KEPT_COMMON_SHA = "c9b2b39a9d8948415da6169e4eecd08bbba0b2a1b62b8affc17b422cc3c6c59b"


@pytest.mark.skipif(not (PILOT_DIR / "queue-v2-diverse.jsonl").exists(),
                    reason="локальный pilot-каталог недоступен")
def test_pilot_queue_v2_identity_repaired_on_disk():
    """Независимая проверка ремонта DATA-008 по реальным файлам (read-only)."""
    queue = af.load_jsonl(PILOT_DIR / "queue-v2-diverse.jsonl")
    seeds = af.load_jsonl(PILOT_DIR / "seeds.jsonl")
    labels = load_labels(PILOT_DIR / "fast_labels.jsonl")
    details = af.load_jsonl(PILOT_DIR / "fast_details.jsonl")
    assert af.queue_identity_problems(queue=queue, seeds=seeds, labels=labels,
                                      details=details) == []
    ids = [r["record_id"] for r in queue]
    assert len(ids) == len(set(ids)) == 100
    renamed = [r for r in queue if r.get("record_id_history")]
    assert [r["record_id"] for r in renamed] == ["pilot23-composition-11"]
    assert renamed[0]["record_id_history"] == ["pilot23-composition-07"]
    assert renamed[0]["image_sha256"] == ("02903aa642550f6210a9e0c96025716505131f05"
                                          "22ac9016794b684cd01c7ee1")
    kept = [r for r in queue if r["record_id"] == "pilot23-composition-07"]
    assert [r["image_sha256"] for r in kept] == [KEPT_COMMON_SHA]
    # v1-очередь делит с v2 те же record_id для ДРУГИХ кадров: смешивание с этим
    # хранилищем обязано падать (та же корневая причина, что и дубль)
    v1 = af.load_jsonl(PILOT_DIR / "queue.jsonl")
    mixed = af.queue_identity_problems(queue=v1, seeds=seeds, labels=labels, details=details)
    assert any("привязана к другому кадру" in p for p in mixed)
