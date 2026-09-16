#!/usr/bin/env python3
"""Build the Camera Coach annotation pilot sample (R13 preparation).

Selects pilot cases from the R00 traceability map (implemented_local and
partial cases only), pairs each with one authored scenario/advice brief, and
writes a blinded sample for human annotators plus a separate adjudicator key.

Everything in the sample is AI-authored synthetic structured briefs:
research_only, human_gold=false, no pixels, no model outputs. The pilot
validates instruction clarity and agreement mechanics; it is not quality
evidence. Vote capture happens exclusively through the existing
tools/camera_annotation/annotate_camera.py store.
"""

from __future__ import annotations

import argparse
import json
import random
import re
from datetime import datetime, timezone
from pathlib import Path

SAMPLE_ID = "camera-annotation-pilot-v1"
SEED = 20260912
TARGET_SIZE = 35
ELIGIBLE_STATUSES = {"implemented_local", "partial"}
VERDICTS = {"good", "bad"}


def parse_map_statuses(map_path: Path) -> dict[str, str]:
    statuses: dict[str, str] = {}
    for line in map_path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\| (CC-[A-Z]\d{2}) \|.*`\(([a-z_]+)\)` *\|", line)
        if not match:
            match = re.match(r"^\| (CC-[A-Z]\d{2}) \|.*`([a-z_]+)` *\|", line)
        if match:
            statuses[match.group(1)] = match.group(2)
    return statuses


def parse_map_modes(map_path: Path) -> dict[str, str]:
    modes: dict[str, str] = {}
    for line in map_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| CC-"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 3:
            modes[cells[0]] = cells[2]
    return modes


def brief(case_id: str, scenario: str, advice: str, focus: str, verdict: str, reason: str) -> dict:
    assert verdict in VERDICTS, case_id
    return {
        "case_id": case_id,
        "scenario": scenario,
        "advice": advice,
        "focus": focus,
        "intended_verdict": verdict,
        "intended_reason": reason,
    }


# One authored brief per selected case. Scenarios and advice are synthetic
# Russian structured briefs derived from requirements §23 wording; seven
# advices deliberately contain a subtle flaw (wrong referent, unmeasured
# units, style violation, stale overlay, masked trade-off) so the pilot can
# measure whether annotators catch it consistently.
BRIEFS = [
    brief("CC-T01", "Крупный план чашки на столе. Выбранная чашка стоит справа, резкость ушла на фон.",
          "Наведи фокус на отмеченную чашку.", "target_binding", "good",
          "резкость привязана к выбранной цели"),
    brief("CC-T02", "Съёмка детали вышивки с рук, лёгкая тряска; смаз мешает читать стежки.",
          "Смаз неизбежен — снимай в чёрно-белом стиле, так artistic.", "cause_vs_style", "bad",
          "не устраняет причину (неподвижность/опора) и навязывает стиль вместо задачи"),
    brief("CC-T03", "Тёмная сцена: фактура ткани на фото не читается.",
          "Если возможно, добавь света рядом со сценой.", "executability", "good",
          "совет выполним и проверим по деталям"),
    brief("CC-T04", "Сильный зум на дальнем здании; детали мыльные.",
          "Уменьши увеличение и подойди ближе, если это безопасно.", "executability", "good",
          "возврат к доступной линзе/дистанции"),
    brief("CC-T05", "В кадре экран монитора; по снимку идут полосы.",
          "В кадре мерцание от подсветки: смени свет или сними у окна.", "diagnosis_confidence", "good",
          "назван наблюдаемый факт (полосы), а не неподтверждённый диагноз"),
    brief("CC-T06", "Угол кадра размыт; палец частично закрывает край объектива.",
          "Освободи край объектива — угол кадра перекрыт.", "diagnosis_confidence", "good",
          "перекрытие видно уверенно, гипотеза про грязную линзу не заявляется"),
    brief("CC-R01", "Портрет у окна: выбранное лицо читается, фон спокойный.",
          "Можно снимать: лицо читается, фон не мешает.", "no_move", "good",
          "нет придуманной коррекции ради активности"),
    brief("CC-R02", "Выбранная кружка вышла из кадра, на экране остался старый совет про неё.",
          "Подожди, совет ещё актуален.", "stale_advice", "bad",
          "устаревший overlay и совет должны быть немедленно сняты (WAIT/ABSTAIN)"),
    brief("CC-R03", "Контровой свет даёт блик на посуде; чтобы его убрать, героя нужно развернуть спиной к окну, и лицо уйдёт в тень.",
          "Разверни героя к окну, чтобы убрать блик с посуды.", "masked_tradeoff", "bad",
          "устранение одной проблемы ценой защищённой (лицо в тени); такой совет запрещён кейсом"),
    brief("CC-R04", "Был совет «сдвинь чашку правее — прижата к краю»; пользователь выполнил, сцена сопоставима.",
          "Стало лучше: чашка отошла от края.", "verified_improvement", "good",
          "улучшение привязано к конкретной проблеме и сопоставимой паре"),
    brief("CC-R06", "Нет сети; облачный разбор недоступен, локальные подсказки продолжают работать.",
          "Облачный разбор недоступен (нет сети). Локальные подсказки продолжают работать.", "honest_status", "good",
          "статус назван честно, локальный режим сохранён"),
    brief("CC-O01", "Две одинаковые настольные лампы; левая касается контура головы героя. Отметкой выделена левая.",
          "Сдвинь отмеченную левую лампу вправо, пока она не перестанет сливаться с головой.", "referent_binding", "good",
          "совет относится к отмеченному экземпляру и к проверяемому результату"),
    brief("CC-O03", "Ваза стоит за плечом героя и пересекает контур головы на фоне.",
          "Сдвинь отмеченную вазу из области за головой.", "protected_contour", "good",
          "устраняет конфликт с контуром головы"),
    brief("CC-O04", "На столе рядом с целью лежит упаковка от товара.",
          "Убери отмеченную упаковку из кадра.", "executability", "good",
          "действие пользователя, предмет выделен"),
    brief("CC-O06", "Композиция заметно перевешивает вправо из-за книги на столе.",
          "Перемести книгу на три сантиметра влево.", "unmeasured_units", "bad",
          "сантиметры без измерительного основания запрещены требованиями"),
    brief("CC-O07", "Чашка стоит на пёстром пледе и сливается с фоном.",
          "Поставь чашку на свободный участок стола, чтобы отделить её от пледа.", "executability", "good",
          "разделяет цель и фон"),
    brief("CC-O08", "Герой стоит вплотную к стене, кадр плоский.",
          "Если есть место, отодвинься от стены на шаг — появится глубина.", "conditional_advice", "good",
          "совет обусловлен доступностью места"),
    brief("CC-I01", "В кадре человек у окна и интересная лампа; оба выглядят значимыми, цель пользователем не выбрана.",
          "Что снимаем: человека или лампу? Коснись цели на экране.", "ask_not_guess", "good",
          "при неоднозначности система спрашивает, а не выбирает сама"),
    brief("CC-I05", "Намеренный силуэт: герой снят против окна, лицо в тени — это выбранный стиль.",
          "Лицо тёмное — добавь заполняющий свет.", "style_preservation", "bad",
          "исправляет намеренный стиль против выбора пользователя"),
    brief("CC-I06", "У правого края кадра неизвестный тёмный предмет; надёжной области и названия нет.",
          "Передвинь торшер слева чуть правее.", "hallucinated_reference", "bad",
          "выдуманное название и неверная сторона; должен быть воздержаться/выбор области"),
    brief("CC-V01", "Сопровождение идущего героя; он смещается к левому краю кадра.",
          "Держи героя в отмеченной зоне кадра.", "framing_follow", "good",
          "зона названа, требование выполнимо в движении"),
    brief("CC-V02", "Панорама слева направо выходит слишком резкой для выбранного плана.",
          "Веди телефон плавнее — движение быстрее, чем нужно для этого плана.", "motion_control", "good",
          "управление телефоном, а не предметом; причина названа"),
    brief("CC-V03", "Статичный план стола, у рук микродрожание.",
          "Удерживай телефон устойчивее: обопрись локтями или о поверхность.", "motion_control", "good",
          "конкретное исполнимое действие"),
    brief("CC-V04", "Во время проводки кадр периодически проходит мимо яркого окна и пересвечивается.",
          "На проходе мимо окна держи точку экспозиции на герое.", "parameter_lock", "good",
          "предупреждение о параметре до следующего дубля"),
    brief("CC-V06", "Репетиция: герой проходит мимо фонаря, на проходе ожидается яркое пятно.",
          "На проходе у фонаря будет яркое пятно: сдвинь траекторию чуть левее или прими его намеренно.", "rehearsal_warning", "good",
          "ограниченная альтернатива названа до записи"),
    brief("CC-F01", "Съёмка группы для ленты: целевой формат 4:5, крайний справа человек у будущей границы кадра.",
          "Сместите группу чуть влево, чтобы крайний человек вошёл в область будущего формата.", "format_projection", "good",
          "совет про конечный формат, не только текущий кадр"),
    brief("CC-F03", "Готовое фото: композиция упирается в правый край, слева осталось пустое место.",
          "В следующем снимке оставь место справа: сейчас кадр обрезан по краю.", "reshoot_advice", "good",
          "конкретное исправление при пересъёмке"),
    brief("CC-P01", "Двое у стены: человек слева заслоняет лицо правого. Отмечен левый.",
          "Человеку у отметки — немного вправо: откроется лицо соседа.", "protected_faces", "good",
          "лицо открывается, группа не режется"),
    brief("CC-P02", "Герой повернулся вполоборота; нужное выражение не читается.",
          "Повернись немного к камере.", "executability", "good",
          "просьба о действии без оценки внешности"),
    brief("CC-P03", "Чашка в руке героя закрывает нижнюю часть лица.",
          "Опусти чашку чуть ниже, чтобы открыть лицо.", "protected_faces", "good",
          "реквизит и лицо читаются согласно задаче"),
    brief("CC-P04", "Двое под навесом: один в глубокой тени, второй на свету.",
          "Человек в тени плохо читается — переместите группу в более ровный свет.", "group_readability", "good",
          "учтены оба выбранных участника"),
    brief("CC-P05", "Серия кадров: в момент съёмки у героя закрылись глаза.",
          "Сделай ещё кадр: глаза закрылись.", "timing", "good",
          "повтор кадра вместо автоспуска и ретуши"),
    brief("CC-P06", "Диалог двоих: взгляды уходят в разные стороны за пределы кадра.",
          "Оставь место между героями и по направлению взглядов.", "relationships", "good",
          "связь героев видна, сюжет не придумывается"),
    brief("CC-S01", "Предметная съёмка упаковки: лицевая сторона отвёрнута от камеры.",
          "Поверни упаковку лицевой стороной к камере.", "chosen_side", "good",
          "выбранная сторона становится видимой"),
    brief("CC-S02", "Слоёный торт снят строго сверху; слои не видны.",
          "Снимай торт строго сверху — это правильный ракурс для еды.", "prescribed_angle", "bad",
          "навязывает «правильный» ракурс вместо цели показать слои"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, default=Path("docs/cameraanalysis/34-case-traceability-map.md"))
    parser.add_argument("--out-dir", type=Path, default=Path("docs/cameraanalysis/annotation/pilot"))
    args = parser.parse_args()

    statuses = parse_map_statuses(args.map)
    if not statuses:
        raise SystemExit(f"no case statuses parsed from {args.map}")
    modes = parse_map_modes(args.map)
    eligible = {cid for cid, status in statuses.items() if status in ELIGIBLE_STATUSES}
    covered = {b["case_id"] for b in BRIEFS}
    ineligible = sorted(covered - eligible)
    if ineligible:
        raise SystemExit(f"briefs reference ineligible cases: {ineligible}")
    if len(BRIEFS) != TARGET_SIZE:
        raise SystemExit(f"expected {TARGET_SIZE} briefs, got {len(BRIEFS)}")

    rng = random.Random(SEED)
    ordered = list(BRIEFS)
    rng.shuffle(ordered)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    sample_path = args.out_dir / "pilot-sample-v1.jsonl"
    key_path = args.out_dir / "pilot-sample-v1-key.json"

    records = []
    key_entries = []
    for index, item in enumerate(ordered, start=1):
        record_id = f"pilot_v1_{index:03d}"
        records.append({
            "pilot_record_id": record_id,
            "sample_id": SAMPLE_ID,
            "case_id": item["case_id"],
            "family_status": statuses[item["case_id"]],
            "mode": modes.get(item["case_id"], "unknown"),
            "scenario": item["scenario"],
            "advice": item["advice"],
            "question": "Оцени совет по инструкции: good / bad / abstain (через annotate_camera.py).",
            "provenance": {
                "origin": "ai_authored_synthetic_brief",
                "human_gold": False,
                "research_only": True,
                "pixels": "none_structured_only",
                "generated_at": now,
                "seed": SEED,
            },
        })
        key_entries.append({
            "pilot_record_id": record_id,
            "case_id": item["case_id"],
            "intended_verdict": item["intended_verdict"],
            "intended_reason": item["intended_reason"],
            "focus": item["focus"],
        })

    with sample_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    key_path.write_text(
        json.dumps(
            {
                "sample_id": SAMPLE_ID,
                "adjudicator_only": True,
                "note": "Интенции автора брифов. Не для аннотаторов. Синтетический ориентир для адъюдикации, не human-gold истина.",
                "entries": key_entries,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )

    family_counts: dict[str, int] = {}
    for item in BRIEFS:
        family_counts[item["case_id"][3]] = family_counts.get(item["case_id"][3], 0) + 1
    bad_count = sum(1 for item in BRIEFS if item["intended_verdict"] == "bad")
    print(f"WROTE {sample_path} records={len(records)}")
    print(f"WROTE {key_path} (adjudicator only)")
    print(f"cases={len(covered)} families={dict(sorted(family_counts.items()))} intended_bad={bad_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
