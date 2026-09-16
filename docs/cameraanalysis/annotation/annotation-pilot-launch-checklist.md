# Annotation pilot v1 — чеклист запуска

Статус: 2026-09-12. Выборка v1 (35 записей), инструкции и инструменты готовы. Для исполнения нужны **2 независимых человека-аннотатора и 1 адъюдикатор** — это единственное, что требует владельца.

## Что уже готово

| Артефакт | Путь |
|---|---|
| Слепая выборка (JSONL) | `docs/cameraanalysis/annotation/pilot/pilot-sample-v1.jsonl` |
| Человекочитаемый пакет | `docs/cameraanalysis/annotation/pilot/pilot-packet.{csv,md}` |
| Ключ адъюдикатора (аннотаторам недоступен) | `docs/cameraanalysis/annotation/pilot/pilot-sample-v1-key.json` |
| Инструкция (good/bad/abstain, слепота, адъюдикация) | `docs/cameraanalysis/annotation/annotation-pilot-instructions.md` |
| Захват голосов (append-only) | `tools/camera_annotation/annotate_camera.py` |
| Отчёт согласованности | `tools/camera_annotation/pilot_agreement_report.py` |

## Порядок запуска

1. Выдать каждому аннотатору **свой** store-файл, например `annotation/<annotator-id>.jsonl`, и ID вида `ann_a`, `ann_b`. Аннотаторы не видят store друг друга и не открывают key-файл.
2. Аннотатор читает `pilot-packet.md` и для каждой записи голосует:
   ```sh
   python3 tools/camera_annotation/annotate_camera.py --store annotation/ann_a.jsonl vote \
     --record-id pilot_v1_001 --annotator-id ann_a \
     --verdict good|bad|abstain --subject-state selected|ambiguous|none|abstain \
     --notes "<краткая причина; обязательна для abstain>"
   ```
3. Проверка покрытия (у каждого — все 35 записей с одним голосом):
   ```sh
   python3 tools/camera_annotation/pilot_agreement_report.py --store annotation/ann_a.jsonl \
     --sample docs/cameraanalysis/annotation/pilot/pilot-sample-v1.jsonl
   ```
4. После завершения обоих аннотаторов — объединить голоса (конкатенация append-only store-файлов сохраняет порядок и авторство) и построить отчёт:
   ```sh
   cat annotation/ann_a.jsonl annotation/ann_b.jsonl > annotation/combined.jsonl
   python3 tools/camera_annotation/pilot_agreement_report.py --store annotation/combined.jsonl \
     --sample docs/cameraanalysis/annotation/pilot/pilot-sample-v1.jsonl \
     --out annotation/pilot-report.md
   ```
5. Адъюдикатор разбирает записи без единогласия (отчёт перечисляет их) и добавляет решения:
   ```sh
   python3 tools/camera_annotation/annotate_camera.py --store annotation/combined.jsonl adjudicate \
     --record-id pilot_v1_012 --adjudicator-id adj_1 --outcome uphold|override|split|quarantine \
     --referenced-vote-ids <id голосов> --notes "<обоснование>"
   ```
6. Приёмка пилота: отчёт построен, все спорные записи разобраны, уточнения инструкций зафиксированы.

## Правила

- Ключ (`pilot-sample-v1-key.json`) — только у адъюдикатора; расхождение с ключом может означать дефект брифа, а не ошибку аннотатора.
- Все результаты — `research_only`, не human-gold: пилот проверяет инструкции и механику согласованности, метрики качества приложения из него не выводятся.
- Аннотаторам не показывать отчёт и чужие голоса до завершения.

## Подготовительная проверка (выполнена)

Dry-run на временном store подтвердил сквозной поток: 35 голосов одного аннотатора → отчёт с покрытием 100% и корректными метриками; временный store удалён. Реальные человеческие голоса не создавались и не выдумывались.
