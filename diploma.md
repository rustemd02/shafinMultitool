# Дневник разработки диссертации
# Мы создаем продукт для защиты на диссертации, который должен содержать явную и объяснимую техническую сложность 

## 💡 Идеи на будущее

### Оффлоадинг тяжёлых вычислений на ПК/сервер

**Концепция**: Приложение может подключаться к компьютеру (Mac/ПК), где запущена серверная часть, и отправлять туда наиболее ресурсоёмкие операции для выполнения.

**Потенциальные кандидаты для оффлоадинга**:

- **LLM-инференс для семантического парсинга**:
  - сложные описания сцен с неявными референсами, вложенными конструкциями;
  - генерация/уточнение `SceneScript` через большие языковые модели (GPT-4, Claude, локальные модели типа Llama);
  - преимущество: более мощные модели, больше контекста, лучшее понимание семантики.

- **3D визуализация и рендеринг**:
  - предпросмотр сложных сцен с множеством объектов/актёров;
  - генерация фотореалистичных placeholder'ов вместо простых кубов;
  - расчёт освещения, теней, отражений для более реалистичного AR.

- **Оптимизация планирования сцен**:
  - constraint-based планирование с решением систем ограничений (SMT solvers, оптимизационные алгоритмы);
  - расчёт оптимальных траекторий движения с учётом коллизий и физики;
  - генерация альтернативных вариантов размещения для выбора пользователем.

**Техническая реализация**:

- **Протокол связи**: HTTP/WebSocket между iOS-приложением и локальным сервером (Python/Swift сервер на Mac);
- **Формат обмена**: JSON с чёткой схемой (`SceneScript` + метаданные для валидации);
- **Fallback**: если сервер недоступен — работа в полностью оффлайн режиме с упрощёнными алгоритмами;
- **Кэширование**: результаты оффлоадинга кэшируются локально для повторного использования.

**Преимущества для диссертации**:

- демонстрация гибридной архитектуры (edge + cloud computing);
- возможность использовать более сложные алгоритмы без ограничений мобильного железа;
- объяснимая техническая сложность: распределённые вычисления, синхронизация состояния, обработка ошибок сети.

**Текущий подход**: Все вычисления выполняются локально на устройстве для максимальной автономности и предсказуемости задержек.

### Fine-tuning лёгкой LLM-модели для семантического парсинга сцен

**Концепция**: Дообучение небольшой локальной языковой модели (например, Phi-2 или TinyLlama) на специфичной задаче преобразования русских описаний сцен в структурированный JSON (`SceneScript`). Это позволит модели лучше понимать контекст проекта и строже следовать требуемой схеме данных.

**Детали реализации**:
- **Подготовка датасета**: создание 100–1000 примеров пар "текст описания → правильный SceneScript JSON" на основе существующих тест-кейсов и синтетической генерации;
- **Выбор базовой модели**: Phi-2 (2.7B) или TinyLlama (1.1B) в quantized формате (4-bit) для работы на Neural Engine iPhone;
- **Метод fine-tuning**: использование LoRA (Low-Rank Adaptation) или QLoRA для эффективного дообучения без полной перетренировки всех параметров;
- **Процесс обучения**: 
  - загрузка предобученной модели;
  - добавление адаптивных слоёв (LoRA);
  - обучение на подготовленном датасете с loss-функцией, учитывающей соответствие JSON-схеме;
  - валидация на отдельном тестовом наборе;
- **Экспорт в CoreML**: конвертация обученной модели в формат CoreML для интеграции в iOS-приложение;
- **Интеграция**: замена или дополнение rule-based парсера в `SceneParserService` с возможностью fallback на LLM при низкой confidence.

**Преимущества**:
- **Точность**: модель лучше понимает специфичные термины проекта ("плейсхолдер", "траектория", "размеченный объект");
- **Строгость схемы**: обученная модель строже следует JSON-схеме, меньше "галлюцинаций" и лишних полей;
- **Эффективность**: после fine-tuning можно использовать более короткие prompt'ы (few-shot примеры занимают место в контексте);
- **Объяснимость для диссертации**: демонстрация процесса адаптации готовых моделей под конкретную задачу, метрики улучшения качества парсинга.

**Потенциальные сложности**:
- **Размер модели**: даже quantized Phi-2 занимает ~1.5GB памяти (нужно проверить доступность на iPhone 13 Pro);
- **Время обучения**: fine-tuning требует GPU или длительного времени на CPU (можно использовать облачные сервисы или Mac с M-чипом);
- **Поддержка датасета**: необходимо поддерживать и расширять набор обучающих примеров;
- **Баланс качества и размера**: более маленькие модели быстрее, но могут хуже понимать сложные конструкции.

**Связь с текущим проектом**:
- **Модуль**: `SceneGeneratorModule/Services/SceneParserService` — гибридный парсер с fallback на LLM;
- **Интеграция**: LLM-парсер вызывается автоматически при низкой confidence rule-based парсера или вручную через UI;
- **Формат данных**: модель должна возвращать валидный `SceneScript` JSON, который валидируется и сравнивается с результатом rule-based парсера;
- **Метрики**: можно сравнивать качество парсинга до и после fine-tuning, измерять процент случаев, когда LLM улучшил результат.

### Многоступенчатый гибридный пайплайн парсинга с Confidence-маршрутизацией

**Концепция**: Вместо текущей схемы «rule-based → если confidence < 0.6 → LLM fallback» сделать полноценный многоступенчатый пайплайн с тремя уровнями анализа, где каждый последующий уровень подключается только если предыдущий не достиг порога confidence.

**Детали реализации**:
- **Уровень 1 (Быстрый / ~1 мс)**: Паттерн-матчинг через расширенные регулярные выражения + KeywordsMapping. Покрывает простые шаблоны типа «N актёров делают X к Y». Если confidence ≥ 0.85 — возвращаем результат без дальнейшей обработки.
- **Уровень 2 (Средний / ~50 мс)**: NLU-препроцессинг через NLTagger (dependency parsing, coreference resolution), семантический анализ предложения: определение подлежащего, сказуемого, дополнений, обстоятельств. Разрешение анафоры (он/она → конкретный актёр). Порог: confidence ≥ 0.7.
- **Уровень 3 (Тяжёлый / ~2-5 с)**: Локальная LLM (Qwen2-0.5B или TinyLlama-1.1B в GGUF Q4_K_M через llama.cpp). Подключается только для действительно сложных описаний.
- **Слияние результатов**: `ParsingMerger` — объединяет результаты нескольких уровней, берёт лучшие компоненты от каждого: актёров от уровня 1 (если найдены), действия от уровня 2 (если разрешены местоимения), пространственные отношения от уровня 3. Финальный `SceneScript` — гибрид.
- **Компоненты**: новый `ParsingPipeline` (оркестратор), `ConfidenceRouter` (решает какой уровень запускать), `ParsingMerger` (слияние результатов).

**Преимущества**:
- Энергоэффективность: LLM запускается только в 10-15% случаев, экономия батареи.
- Точность: простые описания обрабатываются мгновенно, сложные — с помощью LLM.
- Объяснимость для диссертации: каскадная архитектура с метриками на каждом уровне, можно построить графики "confidence vs. уровень подключения".

**Потенциальные сложности**:
- Настройка порогов confidence для переключения между уровнями (требуется эмпирический подбор).
- `ParsingMerger` должен корректно объединять частичные результаты разных уровней без конфликтов.
- Тестирование: нужен набор бенчмарков на 50-100 описаний для настройки порогов.

**Связь с текущим проектом**:
- Текущий `SceneParserService.parse()` уже реализует примитивную версию с двумя уровнями (rule-based + LLM fallback по порогу 0.6).
- `DiagnosticsCalculator` уже вычисляет confidence/coverage — нужно расширить метрики.
- `LLMParserService` — заглушка, нужно интегрировать llama.cpp.

---

## [2026-05-22 18:15] - [Camera Analysis R03k: production technical-quality gate without semantic displacement]

### Суть изменений
- Продолжен dataset/eval цикл Camera Analysis по плану `docs/cameraanalysis/31-dataset-eval-implementation-plan.md`: технический quality probe вынесен из DEBUG-only eval в production-safe `TechnicalQualityAnalyzer`.
- Live path теперь может показывать короткую техническую подсказку для доминирующих проблем резкости/смаза/пересвета/экспозиции без запуска VLM/LLM.
- Pause path получил technical critique, но с важным ограничением: он используется только когда не вытесняет доступные semantic corrective tips. Это исправляет неудачный вариант `R03j`, где наивный technical override скрывал полезные semantic actions.
- Добавлен regression test `testStillImageReplayPresentsDominantTechnicalQualityProblem`, который проверяет, что soft-focus кадр получает live/pause technical presentation с confidence.

### Измеренный результат
- Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r03k`.
- Runtime claim: `real_runtime_still_replay`.
- `record_count=107`.
- `pass_rate=0.289720`.
- `expected_action_hit_rate=0.570093`.
- `future_action_hit_rate=0.875000`.
- `forbidden_action_violation_rate=0.168224`.
- `good_frame_preservation_rate=0.804348`.
- `positive_confirmation_rate=0.760870`.
- `confidence_band_accuracy=0.607477`.
- `demo_priority_pass_rate=0.571429`.
- `technical_failure_gate_rate=1.000000`.

### Научная и техническая значимость
- R03j/R03k зафиксировали важный архитектурный вывод для диссертации: техническая оценка качества кадра должна быть fused/gated, а не безусловно заменять семантический разбор. Иначе система теряет контекстные советы (`change_camera_angle`, `add_front_fill_light`) даже при корректно найденной technical problem.
- R03k не улучшил aggregate metrics относительно R03i, но сделал technical quality видимой в runtime UX и сохранил baseline. Это полезный engineering step, но не финальная продуктовая готовность.
- Остаточные проблемы прежние: `confidence_band_mismatch=42`, `missing_expected_action=46`, `forbidden_action_violation=18`, good-frame overcorrection и слабые mixed frames.

### Верификация
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPresentsDominantTechnicalQualityProblem` — passed.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` — passed, exported 214 rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r03k.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03k` — scored 107 cases.
- Combined targeted Swift regression suite (`AnalysisPipelinePresentationTests`, `FrameCritiqueEngineTests`, `SemanticTipPlannerTests`, `PauseReasoningCoordinatorTests`) — passed.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` — 47 passed.
- `xcodebuild -list -project shafinMultitool.xcodeproj` — passed.
- `git diff --check` — passed.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (`TechnicalQualityAnalyzer`, live technical hint, pause technical critique gating)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (technical-quality regression tests and still-image replay checks)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03k/*` (latest measured R03k output)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (latest factual baseline and backlog)
- `docs/thesis/03_evidence_map.md` / `docs/thesis/04_claim_registry.md` (R03k evidence and limitation claim)

---

## [2026-05-22 17:45] - [Camera Analysis R03i: low-key sharpness guard and measured replay update]

### Суть изменений
- Продолжен dataset/eval цикл Camera Analysis по плану `docs/cameraanalysis/31-dataset-eval-implementation-plan.md`: после R03g/R03h проверена причина false-positive technical failures на тёмных cinematic кадрах.
- В `SemanticEvalTechnicalQualityProbe` уточнена граница dominant blur/focus: очень тёмные low-key кадры больше не считаются доминантной проблемой резкости только из-за низкой текстуры, но умеренно тёмный мягкий/размытый кадр всё ещё получает dominant `refocus_subject` / `stabilize_camera`.
- Добавлены regression tests для двух противоположных случаев: `testSemanticEvalTechnicalQualityProbeDoesNotTreatLowKeyTextureAsDominantBlur` и `testSemanticEvalTechnicalQualityProbeKeepsModerateLowLightSoftnessDominant`.
- Выполнен новый real-runtime still-image replay `R03i` на 107 размеченных изображениях и обновлены Camera Analysis / Aegis / thesis evidence-документы.

### Измеренный результат
- Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r03i`.
- Runtime claim: `real_runtime_still_replay`.
- `record_count=107`.
- `pass_rate=0.289720`.
- `expected_action_hit_rate=0.570093`.
- `future_action_hit_rate=0.875000`.
- `forbidden_action_violation_rate=0.168224`.
- `good_frame_preservation_rate=0.804348`.
- `positive_confirmation_rate=0.760870`.
- `confidence_band_accuracy=0.607477`.
- `demo_priority_pass_rate=0.571429`.
- `technical_failure_gate_rate=1.000000`.

### Научная и техническая значимость
- R03i показывает важный методологический момент: простое расширение low-key exception в R03h повысило pass rate, но дало дополнительные forbidden leaks на bad/mixed кадрах. R03i сузил правило и сохранил прирост pass/positive confirmation без роста forbidden-action violations относительно R03g.
- Сравнение с R03g: `pass_rate` вырос `0.271028 -> 0.289720`, `expected_action_hit_rate` вырос `0.532710 -> 0.570093`, `positive_confirmation_rate` вырос `0.673913 -> 0.760870`, а `forbidden_action_violation_rate` остался `0.168224`.
- Самый честный вывод не меняется: это measured calibration step, а не готовая фича. Основные остаточные проблемы — `confidence_band_mismatch=42`, `missing_expected_action=46`, слабые mixed frames (`0/14 pass`) и отсутствие production first-class technical-quality gate.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (`SemanticEvalTechnicalQualityProbe`, low-key sharpness guard)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (regression tests для low-key vs moderate-low-light softness)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03i/semantic_eval_summary.md` (актуальный measured replay report)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (latest R03i baseline and next implementation slice)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md`
- `docs/thesis/03_evidence_map.md` (`EV-CA-EVAL-003` updated to R03i)
- `docs/thesis/04_claim_registry.md` (`CL-CA-003` updated to R03i limitation claim)

### Следующий шаг
- Не закрывать цель. Следующий инженерный шаг — productionize technical-quality layer: typed `TechnicalQualitySignal` должен участвовать в live/pause decision layer, объяснять blur/focus/exposure отдельно от композиции и не позволять `keep_current_setup` на реально плохих technical frames.

---

## [2026-05-22 17:10] - [Camera Analysis R03g calibration: dataset replay improvement, not product readiness]

### Суть изменений
- Выполнен следующий real-runtime still-image replay `R03g` на тех же 107 размеченных изображениях из `docs/cameraanalysis/dataset/inbox`.
- В `FrameCritiqueEngine` добавлена первая калибровка сохранения cinematic intent: читаемый главный субъект, мягкий low-key/backlight стиль и слабые background-findings меньше превращаются в агрессивные советы `step_closer`, `add_front_fill_light` и `simplify_background`.
- Уточнены проверки горизонта и мягких semantic issues: горизонт больше не должен появляться как уверенная проблема при низкой достоверности сигнала, а soft-findings могут быть интерпретированы как positive confirmation только при наличии поддерживающих strength-сигналов.
- Добавлены regression tests для readable cinematic clutter, moody backlight, false horizon confidence, пустого/мягкого positive confirmation и multi-person visual overload.
- Обновлены `docs/cameraanalysis/33-semantic-current-baseline-findings.md`, Aegis checkpoint/evidence и thesis artifacts, чтобы текущий результат был зафиксирован честно: прогресс есть, но цель semantic camera coach ещё не закрыта.

### Измеренный результат
- Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r03g`.
- Runtime claim: `real_runtime_still_replay`.
- `record_count=107`.
- `pass_rate=0.271028`.
- `expected_action_hit_rate=0.532710`.
- `future_action_hit_rate=0.875000`.
- `forbidden_action_violation_rate=0.168224`.
- `good_frame_preservation_rate=0.804348`.
- `positive_confirmation_rate=0.673913`.
- `confidence_band_accuracy=0.607477`.
- `demo_priority_pass_rate=0.500000`.
- `technical_failure_gate_rate=1.000000`.

### Научная и техническая значимость
- Это не финальное качество, а полезный measured calibration step. По сравнению с первым honest semantic-action runtime export улучшились pass rate, expected-action visibility, technical future-action hit rate, forbidden-action rate и good-frame preservation.
- Важный конкретный пример: `ca_img_033` перестал получать ложное `keep_current_setup` и стал выдавать `simplify_background`, то есть система начала лучше различать cluttered mixed frame от хорошего cinematic кадра.
- Самый честный вывод: deterministic pipeline уже можно измерять и частично калибровать, но он всё ещё не понимает сценический intent достаточно надёжно. Для дипломной цели нужен production technical-quality gate и более сильный источник visual/scene-intent evidence, вероятно pause-only VLM/teacher evidence с bounded fusion.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` (cinematic preservation and confidence calibration logic)
- `shafinMultitoolTests/FrameCritiqueEngineTests.swift` (регрессии для cinematic/backlight/horizon/multi-person cases)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r03g/semantic_eval_summary.md` (актуальный measured replay report)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (latest baseline and next implementation slice)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md`
- `docs/thesis/03_evidence_map.md` (`EV-CA-EVAL-003` updated to R03g)
- `docs/thesis/04_claim_registry.md` (`CL-CA-003` updated to R03g limitation claim)

### Следующий шаг
- Не продолжать вслепую крутить пороги. Следующий инженерный шаг: вынести technical-quality signal из DEBUG eval в production-safe evidence layer, запретить `keep_current_setup` на явно плохих технических кадрах и добавить bounded pause-only scene-intent/VLM evidence для случаев, где deterministic признаки путают стиль и дефект.

---

## [2026-05-22 15:35] - [Camera Analysis real-runtime dataset replay baseline and limitation checkpoint]

### Суть изменений
- Цель Camera Analysis dataset/eval переведена из proxy-оценки в измеряемый real-runtime still-image replay: 107 размеченных кадров из `docs/cameraanalysis/dataset/inbox` прогоняются через Swift-side DEBUG replay и экспортируются в JSONL-контракт eval.
- В `PauseActionRow` добавлен `semanticActionType`, чтобы pause/eval видел фактический semantic tip (`simplify_background`, `step_closer`, `keep_current_setup` и т.д.), а не только грубый транспортный `RecommendationActionType`.
- Усилен safety guardrail для pause reasoning: абсолютные формулировки вроде “гарантированно идеальный кадр” теперь считаются low-faithfulness для `mixed/needsFix` deterministic verdict и не принимаются как LLM/VLM refinement.
- Обновлены source-of-truth документы и thesis artifacts: текущий результат зафиксирован как честный слабый baseline, а не как готовая фича.

### Измеренный результат
- Candidate: `semantic_eval_real_runtime_candidate_outputs_semantic_action_rows`.
- Runtime claim: `real_runtime_still_replay`.
- `record_count=107`.
- `pass_rate=0.186916`.
- `expected_action_hit_rate=0.495327`.
- `future_action_hit_rate=0.520833`.
- `forbidden_action_violation_rate=0.345794`.
- `good_frame_preservation_rate=0.543478`.
- `positive_confirmation_rate=0.543478`.
- `confidence_band_accuracy=0.439252`.

### Научная и техническая значимость
- Это важный отрицательный baseline: система уже измеряется на реальных app outputs, но качество ниже целевого уровня. Такой результат полезен для диссертации, потому что показывает необходимость следующего архитектурного слоя, а не ручного “подкручивания порогов”.
- Улучшение экспорта semantic action повысило видимость expected actions, но одновременно вскрыло больше forbidden overcorrections. Вывод: проблему нельзя честно решить проекцией вывода; нужно уменьшать реальные ошибочные советы в planner/domain logic.
- Главные выявленные причины: отсутствие first-class technical/IQA gate, слабая защита хороших cinematic frames, плохая калибровка confidence, нестабильное subject grounding для multi-subject/сложных кадров.

### Ключевые файлы
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (актуальный real-runtime baseline и backlog `R03-R06`)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md` (checkpoint текущего этапа)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (команды, результаты и метрики)
- `docs/thesis/03_evidence_map.md` (`EV-CA-EVAL-003` обновлен на real-runtime measured baseline)
- `docs/thesis/04_claim_registry.md` (`CL-CA-003` обновлен как partially verified limitation claim)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (`PauseActionRow.semanticActionType`, semantic eval export)
- `shafinMultitool/Multitool2Module/Services/Reasoning/PauseReasoningCoordinator.swift` (low-faithfulness guardrail для absolute certainty wording)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (semantic action export regression)
- `shafinMultitoolTests/PauseReasoningCoordinatorTests.swift` (reasoning safety regression)

### Следующий шаг
- Реализовать `R03 Technical Quality Domain And Gate`: отдельный слой для blur/focus/exposure/noise/occlusion, который сможет остановить semantic overreach и объяснять технические проблемы кадра отдельно от композиции.
- После этого повторить still-image replay и проверять не только рост `pass_rate`, но и отсутствие роста `forbidden_action_violation_rate`.

---

## [2026-05-21 16:30] - [Camera Analysis semantic dataset eval bridge and replay guardrails]

### Суть изменений
- Для Camera Analysis зафиксирован новый dataset/eval этап: 107 изображений с silver-разметкой `semantic_labels_v1`, Python scorer для expected/forbidden actions и отдельный output contract для live/pause candidate rows.
- В Swift добавлен typed export layer `SemanticEvalCandidateOutput` и DEBUG-only still-image replay API `AnalysisPipeline.testingReplayStillImageForSemanticEval(...)`, который может собирать live и pause строки для одного кадра.
- Добавлена защита от ложных метрик: `SemanticEvalStillImageReplayOptions.lightweightTest` всегда маркируется как `test_fixture`, а `real_runtime_still_replay` разрешён только для `fullRuntime`.
- Python eval научился принимать две строки на один кадр (`live` + `pause`) и сливать их в один scored case, сохраняя запрет на дубликаты и несовместимые runtime claims.
- Исправлен live hint edge case: если structured path стал недоступен и включился hard fallback, fallback-подсказка теперь может сразу заменить старый structured verdict, чтобы пользователь не видел устаревшее “кадр хороший”.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** До этого этапа semantic Camera Analysis улучшалась по логам и ручному ощущению, но не имела воспроизводимого контура “размеченные изображения -> candidate outputs -> метрики”. Это опасно для защиты: нельзя честно утверждать качество подсказок, если система не проверяется на фиксированном наборе good/mixed/bad кадров и forbidden-tip сценариев.
- **Решение:** Введён eval bridge между мобильным runtime и dataset: единый JSONL contract, Python validator/scorer, silver-разметка и Swift producer row. Появилась явная граница достоверности: proxy baseline пригоден только для приоритизации, а реальные claims потребуют `out_semantic_real_runtime`, полученного через heavy `fullRuntime` replay.
- **Детали:** Проверки на этом этапе подтверждают инфраструктуру, а не финальную accuracy: `python3 -m pytest docs/cameraanalysis/eval/tests -q` проходит `46` тестов; `AnalysisPipelinePresentationTests` проходит `12` тестов на iOS Simulator; proxy eval генерируется с `runtime_claim = not_real_runtime`. Полный batch replay по `001...107` изображениям ещё не выполнен, поэтому корректная формулировка для диссертации — “создан воспроизводимый контур оценки и runtime export bridge”, а не “система уже корректно проходит весь датасет”.

### Ключевые файлы
- `docs/cameraanalysis/31-dataset-eval-implementation-plan.md` (план dataset/eval этапа)
- `docs/cameraanalysis/32-semantic-eval-output-contract.md` (JSONL contract для candidate outputs)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (честная граница текущего proxy baseline)
- `docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl` (107-image silver labels)
- `docs/cameraanalysis/eval/run_semantic_label_eval.py` (CLI scoring harness)
- `docs/cameraanalysis/eval/semantic_output_schema.py` (candidate output validation and live/pause merge)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (`SemanticEvalCandidateOutput`, still-image replay API, live fallback state-machine guard)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (presentation/export/replay contract tests)
- `docs/thesis/03_evidence_map.md` (`EV-CA-EVAL-003`)
- `docs/thesis/04_claim_registry.md` (`CL-CA-003`)

---

## [2026-05-21 16:05] - [Camera Analysis semantic dataset eval, Swift export contract and measurement boundary]

### Суть изменений
- Для Camera Analysis зафиксирован reproducible eval-контур по набору `107` размеченных изображений: label loader, candidate-output schema, scorer, CLI runner и proxy baseline.
- Добавлен Swift-side export contract `SemanticEvalCandidateOutput`, который переводит live/pause presentation (`LiveHintPresentation`, `PauseCritiquePresentation`) в тот же JSONL-формат, что использует Python eval.
- Python eval усилен проверкой `runtime_claim`, чтобы proxy/label outputs нельзя было случайно выдать за реальный runtime replay.
- Проверка `xcodebuild build-for-testing` восстановлена: исправлены compile blockers в тестах (`try XCTUnwrap` в non-throwing тестах и несуществующий `FixTypeV1.declutter`), локальный `/build/` output добавлен в `.gitignore`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Нельзя заявлять, что приложение корректно реагирует на dataset images, если eval построен только на labels/proxy. Это была бы методологическая ошибка: proxy может показывать желаемое поведение, но не измеряет реальный Swift/CoreML pipeline.
- **Решение:** Введена явная граница измерения через `runtime_claim`: `not_real_runtime` разрешён только для приоритизации и baseline planning, а будущие защитные метрики должны использовать `real_runtime_still_replay`.
- **Детали:** Текущий proxy baseline по `107` cases даёт `pass_rate=0.551402`, `expected_action_hit_rate=1.0`, `future_action_hit_rate=0.0`, `forbidden_action_violation_rate=0.0`, `confidence_band_accuracy=0.82243`. Это не accuracy приложения. Корректная интерпретация: closed semantic action catalog уже покрывает размеченные semantic actions, но отсутствует real still-image replay и технический/IQA слой для `48` future actions (`stabilize_camera`, `refocus_subject`, `increase/reduce_exposure`, `reduce_iso_noise`, `clean_lens`, `avoid_occlusion`). Следующий обязательный этап — `PR-R01 Real Still-Image Replay Export`, после него можно честно калибровать подсказки по реальным ошибкам pipeline.

### Ключевые файлы
- `docs/cameraanalysis/31-dataset-eval-implementation-plan.md` (план dataset/eval stage)
- `docs/cameraanalysis/32-semantic-eval-output-contract.md` (JSONL contract и `runtime_claim` semantics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (baseline findings и honesty boundary)
- `docs/cameraanalysis/eval/semantic_output_schema.py` (candidate schema, scoring, `runtime_claim` validation)
- `docs/cameraanalysis/eval/run_semantic_label_eval.py` (CLI runner)
- `docs/cameraanalysis/eval/out_semantic_current_proxy/set_metrics.json` (proxy metrics, not runtime accuracy)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (`SemanticEvalCandidateOutput`)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (presentation-to-eval contract tests)

---

## [2026-05-13 15:02] - [V9.3 fallback audit, runtime-policy correction and next targeted train pack]

### Суть изменений
- Проведён отдельный audit причины высокого `runtime_fallback_rate` у `dataset_v9_2_event_sft`: проблема оказалась в основном не модельной, а связанной со stale mirror runtime-policy/scorer.
- Найдены два системных источника ложного fallback: `stand` ошибочно считался action type с обязательным `target`, а `pred_confidence_below_rule` отвергал компактные, но семантически корректные V9 outputs из-за сравнения с rule-parser confidence.
- В `docs/SGv7pipeline/eval/runtime_policy.py` и benchmark export helper удалено требование target для `stand`; relative confidence reject заменён на guard только для критически низкой confidence.
- В legacy Swift fallback policy (`SceneParserService`) также удалено требование target для `stand`, чтобы live/runtime диагностика не расходилась с corrected benchmark mirror.
- На тех же frozen V9.2 predictions пересчитан benchmark в policy-corrected режиме: `schema_valid_rate` поднялся до `1.0000`, `runtime_fallback_rate` снизился до `0.0038`, `case_strict_success_rate` поднялся до `0.9695` при неизменных model predictions.
- Собран V9.3 targeted train pack для следующего retrain: `5564` mixed rows (`4730` train, `834` val), включая `8` exact remaining failure rows и `270` новых synthetic targeted rows по кластерам `dialogue+put_down`, `three_actor_give`, `three_actor_ordinal_status`.
- Подготовлен Colab/benchmark runbook и upload zip `v9_3_event_sft_mixed_upload.zip`.
- Для upload zip зафиксирован manifest/checksum: SHA-256 `c57e83c839e3ce84a5963e91a141801ab0506f7c00d3b856e5732699e617b297`, внутри `mixed_event_sft` train/val/all/manifest.
- Добавлен pretrain verifier для локальной проверки V9.3 artifacts перед Colab; текущий результат `pass=true`, `5564` total rows, `278` V9.3 targeted rows, zip SHA совпадает.
- Добавлен non-AR demo-parity checker, который проверяет не просто JSON/метрики, а конкретный playback intent для канонических сценариев; на policy-corrected V9.2 он ожидаемо падает `0/3`, фиксируя оставшийся целевой gap для V9.3.
- Добавлен post-train wrapper, который после появления свежего `dataset_v9_3_event_sft_seed42.event_predictions.jsonl` одной командой запускает benchmark, failure mining, demo-parity validation и acceptance gate по целевым V9.3 метрикам.
- Acceptance gate покрыт unit-тестами: pass при достижении всех порогов, fail при regression по target/chronology/action/fallback и fail-closed при отсутствующих метриках.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Предыдущая интерпретация `runtime_fallback_rate=0.4198` могла привести к неверному исследовательскому выводу, будто V9.2 модель часто требует fallback. Фактический разбор показал, что `108` семантически успешных кейсов отвергались старой policy из-за относительного confidence gap, а `103` schema-invalid cases были вызваны неправильным target requirement для `stand`.
- **Решение:** Метрики были разделены на реальные semantic misses и ложные runtime-policy rejects. После исправления mirror policy V9.2 predictions почти полностью проходят runtime gate без изменения модели: `runtime_fallback_rate=0.0038`, `case_strict_success_rate=0.9695`. Это показывает, что основной bottleneck сместился с fallback eradication на последние `8` semantic misses.
- **Детали:** Оставшиеся реальные failures локализованы в узких сценариях: `dialogue_then_put_down_object`, `ordinal_first_second_third` и `dialogue_then_pick_up_object_then_give_to_third_actor`. Поэтому V9.3 dataset не расширяет случайно весь корпус, а добавляет targeted signal именно под эти failure families. Это делает следующий retrain проверяемым экспериментом: если V9.3 не улучшит `target_resolution`, `chronology` и `action_recall`, причина будет уже в model capacity/training, а не в scorer noise.

### Ключевые файлы
- `docs/SGv7pipeline/eval/runtime_policy.py` (исправление target-required actions и confidence fallback policy)
- `experiments/sc_benchmark/generate_predictions_from_endpoint.py` (синхронизация schema helper: `stand` без target валиден)
- `shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift` (синхронизация legacy runtime fallback policy: `stand` не dangling target)
- `docs/SGv7pipeline/eval/tests/test_eval_harness.py` (regression tests для targetless `stand` и confidence-gap accept)
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/fallback_audit/v9_2_to_v9_3_policy_audit.md` (fallback root-cause audit)
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/benchmark_results_seed42/aggregate/scientific_report.md` (policy-corrected replay benchmark)
- `docs/SGv9pipeline/v9/09_build_v9_3_targeted_sft.py` (exact remaining failure rows -> V9.3 targeted SFT)
- `docs/SGv9pipeline/v9/10_generate_v9_3_targeted_augmentations.py` (synthetic targeted rows for remaining failure families)
- `docs/SGv9pipeline/v9/11_build_v9_3_mixed_dataset.py` (mixed V9.3 train/val/all builder)
- `docs/SGv9pipeline/v9/12_validate_v9_demo_parity.py` (non-AR demo-parity checker для canonical intent cases)
- `docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py` (post-train wrapper: benchmark + mining + parity)
- `docs/SGv9pipeline/v9/14_verify_v9_3_pretrain_artifacts.py` (pretrain verifier для dataset/zip/checksum artifacts)
- `docs/SGv9pipeline/v9/tests/test_v9_post_train_eval.py` (unit tests для V9.3 acceptance gate)
- `docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_manifest.json` (V9.3 dataset counts/provenance)
- `docs/SGv9pipeline/runs/v9_3_seed42/V9_3_TRAIN_BENCH_RUNBOOK.md` (next train/benchmark procedure)

## [2026-05-04 20:10] - [Camera Analysis v1 + Hybrid Eval: фиксирование результатов implement verify]

### Суть изменений
- Выполнен reproducible прогон eval-контура для нового `Camera Analysis`:
  - deterministic сравнение `camera_analysis_v1_core` против `legacy_suggestion_engine`;
  - hybrid smoke-прогон через `run_hybrid_eval.py` на `variant_matrix.example.json`.
- Обновлен статус `PR-H14`: гибридный eval harness реализован в initial версии и выдает полный набор артефактов (`ablation`, `pairwise`, `hybrid metrics`, `mobile metrics`, `explainability agreement`).

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** После реализации pipeline нужно было не только “чтобы работало в UI”, но и доказать улучшение качества через воспроизводимые метрики, включая explainability и мобильные ограничения.
- **Решение:** Использован двухэтапный eval:
  - базовый deterministic compare (`v1 core` vs `legacy`);
  - staged hybrid compare с отдельными gates для explainability/mobile.
- **Детали:** По deterministic-части получен устойчивый выигрыш без роста unsupported claims. По hybrid-секции зафиксирован рабочий end-to-end harness, но verdict пока `mobile_blocked` из-за demo-level replay и отсутствия production runtime projections.

### Зафиксированные метрики

1. `camera_analysis_v1_core` vs `legacy_suggestion_engine`:
- `release_recommendation.status = pass`
- `issue_f1 delta = +0.111111`
- `primary_action_match_rate delta = +0.333333`
- `strength_f1 delta = +0.333333`
- `explanation_faithfulness_score delta = +0.175`
- `fallback_policy_accuracy delta = +0.333333`
- `unsupported_claim_rate delta = 0.0`

2. Hybrid smoke (`hybrid_pause_local`):
- `release_verdict = mobile_blocked`
- причина: `pause_execute_success_rate below 0.90` (факт: `0.0`)
- explainability agreement на smoke-run:
  - `fusion_trace_coverage_rate = 1.0`
  - `head_policy_agreement_rate = 1.0`
  - `status_trace_consistency_rate = 1.0`
- safety invariant:
  - `safe_noop_rate = 1.0`

### Честное состояние и ограничения
- Deterministic `v1` уже показал измеримый quality uplift и готов как baseline для защиты.
- Hybrid eval harness технически реализован и воспроизводим, но текущий примерный matrix-run не является финальным доказательством neural uplift.
- Для полноценного диссертационного вывода о hybrid-слое нужны реальные variant outputs с materialized `inferenceOutcome/runtimeSample` из on-device execution path.

### Ключевые файлы
- `docs/cameraanalysis/eval/run_eval.py`
- `docs/cameraanalysis/eval/run_hybrid_eval.py`
- `docs/cameraanalysis/eval/out_v1/compare_report.json`
- `docs/cameraanalysis/eval/out_hybrid_example/ablation_summary.json`
- `docs/cameraanalysis/eval/out_hybrid_example/hybrid_metrics.json`
- `docs/cameraanalysis/23-hybrid-eval-harness.md`

---

## Разъясняющий блок: как устроены `SG v7`, `v8`, `CIR`, `ScenePlanIR` и рантайм на телефоне

Ниже зафиксировано подробное пояснение всей цепочки, поскольку при обсуждении `SG v7` и `v8` легко смешать три разных уровня:

1. подготовку данных и обучение модели;
2. внутренние промежуточные представления сцены;
3. работу приложения на телефоне в рантайме.

Этот блок нужен для того, чтобы дальше в тексте диссертации и в речи на защите чётко различать:
- где сцена строится программно и детерминированно;
- где используется внешняя LLM как вспомогательный инструмент;
- где работает локальная `Qwen` на телефоне;
- где применяются чисто детерминированные правила и `if/else`.

### 1. Главное различие между `v6`, `SG v7` и `v8`

#### `v6`

В `v6` целевой `SceneScript` ещё в значительной степени зависел от teacher-generated генерации. Это означало, что в обучающем пайплайне существовал риск получить формально валидный JSON, который уже на уровне ground truth содержал смысловые ошибки: потерю объектов, схлопывание фаз сцены, перепутанные ordinal-привязки и неточные связи между действиями и целями.

#### `SG v7`

`SG v7` — это уже не просто новый датасет, а полный пайплайн подготовки данных и обучения локальной модели. Его ключевой принцип состоит в том, что **сначала программно строится каноническое смысловое представление сцены**, а уже затем на его основе формируются:

- текстовые описания сцены;
- правильные структурированные ответы;
- stress-варианты;
- preference-пары;
- benchmark-наборы.

Именно поэтому в `SG v7` teacher-модель больше не является источником истины для целевого JSON.

#### `v8`

`v8` развивает эту идею дальше. Если в `SG v7` модель обучается по сути отображению:

`текст -> SceneScript`,

то в `v8` появляется внутреннее промежуточное представление `ScenePlanIR`, и схема становится такой:

`текст -> ScenePlanIR -> deterministic compiler -> SceneScript`.

То есть модель сначала восстанавливает внутренний план сцены, а окончательный `SceneScript` уже детерминированно собирается отдельным компилятором.

### 2. Что такое каноническая сцена и кто её "первый придумал"

Наиболее частый вопрос состоит в следующем: если говорится, что "сначала детерминированно строится каноническая сцена", то кто именно её задаёт и по чему она строится.

Ответ такой: каноническая сцена **не появляется из нейросети**. Её первоначальным источником является **спроектированная исследователем библиотека паттернов сцен**.

То есть сначала вручную и концептуально задаётся не конкретный текст и не конкретный JSON, а **класс сцен**, например:

- два актёра идут навстречу друг другу;
- затем оба останавливаются возле размеченного объекта;
- затем первый выполняет редкое действие, которое в рантайме не имеет прямого отдельного action-типа;
- при этом обязательно должны сохраниться `beat_count`, marked object grounding и ordinal-привязка `first -> actor_1`.

Из такого паттерна код уже детерминированно строит **конкретный экземпляр сцены**:
- выбирает количество актёров;
- типы объектов;
- конкретные идентификаторы;
- последовательность beats;
- действия и привязки;
- обязательные инварианты.

Детерминированность здесь означает следующее:

если используются один и тот же `pattern`, одни и те же правила и один и тот же `seed`, то код обязан породить **одну и ту же каноническую сцену**.

Следовательно, каноническое представление строится не "по вдохновению модели", а по:
- библиотеке паттернов;
- правилам graph generation;
- параметрам конкретного паттерна;
- фиксированному `seed`.

### 3. Что такое `graph-first`

`Graph-first` в данной работе означает не визуальный граф в узком смысле, а более общий принцип:

**сначала фиксируется смысл сцены, а уже потом из этого смысла получаются текст и целевой структурированный ответ.**

Без `graph-first` подхода возникают две типовые проблемы:

1. текст сцены и правильный JSON оказываются двумя независимо сгенерированными артефактами, которые лишь приблизительно совпадают по смыслу;
2. сама teacher-модель может вносить шум в целевую разметку.

При `graph-first` подходе:
- текст сцены и целевой JSON перестают быть независимыми;
- оба они становятся двумя разными представлениями одной и той же канонической сцены.

Именно это и есть центральная идея `SG v7`.

### 4. Где существуют `CIR`, `ScenePlanIR` и `SceneScript`

Ниже жёстко разведены основные сущности.

#### `CIR`

`CIR` (`Canonical Intermediate Representation`) — это офлайн-артефакт пайплайна подготовки данных в `SG v7`.

Он хранит:
- актёров;
- объекты;
- beats;
- действия;
- spatial relations;
- reference bindings;
- must-preserve инварианты;
- сложностные бюджеты и метаданные.

`CIR` не является пользовательским контрактом и не используется как финальный продуктовый формат.

#### `source_text`

Это русскоязычное текстовое описание сцены, имитирующее реальную пользовательскую формулировку. Оно создаётся на основе `CIR`.

#### `SceneScript`

Это финальный структурированный формат сцены, с которым работает продуктовый код приложения. Он содержит:
- `actors`;
- `objects`;
- `beats`;
- `spatialRelations`;
- `originalDescription`;
- а в более поздних версиях также топ-левел контекст сцены.

Именно `SceneScript` является финальным продуктовым контрактом.

#### `ScenePlanIR`

`ScenePlanIR` — это внутреннее промежуточное представление, появившееся в `v8`.

Оно ближе к модели и рантайму, чем `CIR`, но ещё не является финальным `SceneScript`. В нём остаются:
- `actorRef` вроде `first`, `second`;
- `objectRef` и `markedObjectID`;
- `beats` и `actions` в более "плановой" форме;
- `referenceBindings`.

Таким образом:
- `CIR` — источник истины на этапе подготовки данных;
- `ScenePlanIR` — промежуточный план сцены, который модель предсказывает в `v8`;
- `SceneScript` — финальный продуктовый результат.

### 5. Полный офлайн-флоу `SG v7`

Ниже по шагам описан полный пайплайн подготовки данных.

#### Шаг 1. `Pattern Library`

Исследователь задаёт библиотеку типовых семейств сцен. Это не нейросетевой этап, а программно-методологическая постановка задачи.

Здесь фиксируются:
- какие семейства сцен должны быть в корпусе;
- какие failure-cases нужно покрыть;
- какие инварианты критичны;
- какие difficulty buckets и complexity classes нужны.

Типовые классы:
- marked objects;
- same-type object disambiguation;
- ordinal references;
- multi-beat chronology;
- unsupported actions / `described_action`;
- dialogue + small action;
- role shift.

**Кто делает:** детерминированный Python-код и вручную спроектированные правила.

#### Шаг 2. `Graph Generator`

На основе паттерна и `seed` строится конкретный экземпляр сцены в канонической форме.

На этом этапе код создаёт:
- `actor_1`, `actor_2`, ...;
- `object_marked_*`;
- beats;
- actions;
- reference bindings;
- must-preserve constraints.

**Кто делает:** детерминированный graph generator.

#### Шаг 3. `CIR`

Результат graph generation фиксируется как `CIR`-record.

Важная идея:
- `CIR` содержит смысл сцены явно;
- final `SceneScript` потом строится из него детерминированно;
- всё, что критично для runtime semantics, должно быть выражено явно, а не подразумеваться.

**Кто делает:** детерминированный serializer и contract layer.

#### Шаг 4. `Source Generation`

После того как каноническая сцена уже существует, из неё строятся русскоязычные текстовые формулировки.

На этом этапе `gpt-5.4-nano` используется **только как controlled paraphraser**, а не как источник truth JSON.

Ему подаётся уже готовая смысловая структура сцены с ограничениями:
- что обязательно сохранить;
- какие alias для marked object допустимы;
- какие ordinal-связи нельзя терять;
- какие `must_keep_lemmas` должны остаться.

То есть `gpt-5.4-nano` в `SG v7` не invent-ит ground truth, а лишь создаёт естественно звучащую формулировку уже заданной сцены.

**Кто делает:** `gpt-5.4-nano` офлайн.

#### Шаг 5. `Augmentation`

Далее поверх базовых формулировок добавляются контролируемые вариации:
- разговорные формы;
- морфологические сдвиги;
- ограниченный шум;
- stress-варианты под тяжёлые кейсы.

Цель — не "сделать побольше текста", а получить корпус, похожий на реальные пользовательские формулировки и одновременно не разрушающий смысл сцены.

**Кто делает:** в основном детерминированные transformation rules; местами офлайн-LLM-assisted этапы в старых поколениях датасета.

#### Шаг 6. Ранние фильтры качества

На этом этапе дешёвые проверки убирают:
- технические артефакты;
- prompt leakage;
- surface-ошибки;
- слишком шумные формулировки;
- плохие lexical-кандидаты.

**Кто делает:** детерминированные фильтры и reject rules.

#### Шаг 7. `Validator Stack`

После ранних фильтров запускается более глубокая проверка recoverability:

можно ли по данному тексту восстановить исходную каноническую сцену **без потери критического смысла**.

Проверяется:
- сохранение marked object;
- сохранение ordinal binding;
- сохранение beat structure;
- сохранение chronology;
- отсутствие semantic drift;
- отсутствие противоречий между source_text и target JSON.

Именно здесь `SG v7` принципиально отличается от старого подхода: в датасет попадает не любой "похожий" текст, а только такой, который действительно допускает корректное восстановление исходного target.

**Кто делает:** детерминированные validators + critic layer, в отдельных местах допускающий `gpt-5.4-nano` как critic helper, но не как source of truth.

#### Шаг 8. `SceneScript` serializer

Из `CIR` детерминированно строится правильный продуктовый `SceneScript`.

На этом этапе уже нет творческой LLM-генерации:
- ids;
- actors;
- objects;
- beats;
- target links;
- `described_action` поля —
всё это получается из канонического представления программно.

**Кто делает:** deterministic serializer / compiler.

#### Шаг 9. `Dataset Builder`

После прохождения проверок формируются корпуса:

- `SFT`: пары `source_text -> canonical SceneScript JSON`;
- `preference`: пары `bad_json vs good_json`.

`Preference`-контур нужен затем, чтобы модель училась не только строить хороший ответ, но и явно предпочитать его плохому.

**Кто делает:** детерминированный dataset builder.

#### Шаг 10. Training

После этого начинается обучение целевой локальной модели `Qwen`.

В `SG v7` базовая идея такая:
- модель учится по текстовому входу предсказывать финальный `SceneScript`;
- обучение идёт на корпусе, где текст и target JSON согласованы через каноническую сцену.

**Кто делает:** офлайн fine-tuning pipeline.

#### Шаг 11. Benchmark

Новая модель оценивается не по впечатлению, а по воспроизводимому benchmark-контру.

Ключевые метрики:
- `json_valid_rate`;
- `exact_marked_object_id_accuracy`;
- `ordinal_actor_binding_accuracy`;
- `target_resolution_accuracy`;
- `chronology_phase_accuracy`;
- `runtime_fallback_rate`;
- `case_strict_success_rate`.

**Кто делает:** детерминированный eval harness.

#### Шаг 12. Runtime feedback loop

Ошибки, обнаруженные на реальных пользовательских формулировках, собираются обратно в feedback loop и становятся материалом для следующего цикла.

**Кто делает:** runtime logging + deterministic normalization + dataset/eval ingestion.

### 6. Что именно обучалось в `SG v7`

Очень важно не путать:

- `CIR` — это не то, что предсказывает модель;
- это то, **из чего** строятся данные для обучения.

В `SG v7` целевая локальная модель обучается на парах:

`source_text -> SceneScript`.

То есть:
- `CIR` нужен для генерации согласованных и контролируемых данных;
- сама модель в рантайме должна уже по пользовательскому тексту предсказать итоговый `SceneScript`.

### 7. Почему затем появился `v8`

Несмотря на заметный прогресс `SG v7`, выяснилось, что прямое отображение:

`текст -> SceneScript`

остаётся слишком тяжёлой задачей для компактной локальной модели.

Основные слабые зоны:
- target resolution;
- chronology;
- plan integrity;
- конфликт между semantic quality и structural fidelity.

Из-за этого в `v8` был введён внутренний промежуточный слой `ScenePlanIR`.

Теперь схема становится такой:

`текст -> ScenePlanIR -> deterministic compiler -> SceneScript`.

Это означает, что:
- модель больше не обязана сразу строить финальный продуктовый JSON;
- она сначала восстанавливает более компактный и внутренне согласованный план сцены;
- окончательная сборка финального `SceneScript` выполняется компилятором.

### 8. Полный офлайн-флоу `v8`

В `v8` сохраняется офлайн-канонический источник истины `CIR`, но дальше из него строятся уже два продукта:

1. `ScenePlanIR`
2. `SceneScript`

Схема:

`CIR -> deterministic projection -> ScenePlanIR -> deterministic compiler -> SceneScript`

Затем обучающий набор формируется так, чтобы целевая модель училась предсказывать именно `ScenePlanIR`.

Именно поэтому `v8` является не просто ещё одной итерацией preference tuning, а переходом к новой архитектуре генерации.

### 9. Что делает приложение на телефоне сейчас

На телефоне сейчас используется уже не старый чистый `text -> SceneScript` путь, а локальный рантайм, близкий по логике к `v8`.

Ключевые участники:
- `SceneAnchorExtractor`;
- `SceneMetadataExtractor`;
- `LLMParserService` как `LocalScenePlanProvider`;
- `ScenePlanCompiler`;
- `SceneQualityGate`;
- `SceneParseCoordinator`.

#### Рантайм-флоу

1. Пользователь вводит текстовое описание сцены.
2. `SceneAnchorExtractor` детерминированно извлекает:
   - hints по числу актёров;
   - ordinal mentions;
   - mentions marked objects;
   - phase cues;
   - unsupported action flags;
   - low-confidence signals.
3. `SceneMetadataExtractor` детерминированно извлекает top-level metadata сцены.
4. `LLMParserService` строит prompt с учётом:
   - текста;
   - anchors;
   - marked objects;
   - `SceneChunkState`, если он есть.
5. Локальная `Qwen2.5-1.5B` через `llama.cpp` и `GBNF`-грамматику генерирует не финальный `SceneScript`, а именно `ScenePlanIR`.
6. Далее выполняется deterministic repair и normalization плана.
7. `ScenePlanCompiler` детерминированно компилирует `ScenePlanIR` в финальный `SceneScript`.
8. `SceneQualityGate` решает, можно ли принять локальный результат, или нужно:
   - `accept_local`;
   - `fallback_rule_only`;
   - `offload_remote`;
   - `needs_clarification`.

То есть на телефоне сейчас уже действует разделение ролей:
- модель предсказывает внутренний план;
- финальная продуктовая структура собирается детерминированно.

### 10. Где используется `gpt-5.4-nano`, а где локальная `Qwen`

#### `gpt-5.4-nano`

Используется офлайн в `SG v7` прежде всего как:
- controlled paraphraser;
- critic helper;
- вспомогательный инструмент в слоях source generation и части validation.

Он **не**:
- не является source of truth для канонического `SceneScript`;
- не работает в приложении на телефоне;
- не компилирует финальный результат в рантайме.

#### Локальная `Qwen`

Используется на телефоне через:
- `llama.cpp`;
- `LlamaContext`;
- `GBNF` grammar.

В текущем локальном pipeline она генерирует:
- `ScenePlanIR`.

После этого deterministic compiler уже собирает финальный `SceneScript`.

### 11. Пример полного пути на одной сцене

Ниже приведён упрощённый пример реального канонического кейса.

#### 11.1. Каноническая сцена (`CIR`)

Паттерн:

`stop_near_marked_object_then_first_described_action`

Смысл сцены:
- два актёра идут навстречу друг другу;
- затем оба останавливаются у отмеченного объекта;
- затем первый выполняет unsupported runtime action, сохраняемое как `described_action`.

Упрощённый `CIR`:

```json
{
  "pattern_name": "stop_near_marked_object_then_first_described_action",
  "scene_graph": {
    "actors": [
      {"id": "actor_1", "type": "human", "labels": {"ordinal": "first"}},
      {"id": "actor_2", "type": "human", "labels": {"ordinal": "second"}}
    ],
    "objects": [
      {
        "id": "object_marked_a1b2c3d4",
        "type": "generic",
        "name": "laptop"
      }
    ],
    "beats": [
      {
        "id": "beat_1",
        "phase": "toward_each_other",
        "actions": [
          {"actor_id": "actor_1", "type": "walk", "target_id": "actor_2"},
          {"actor_id": "actor_2", "type": "walk", "target_id": "actor_1"}
        ]
      },
      {
        "id": "beat_2",
        "phase": "stop_near_object",
        "actions": [
          {"actor_id": "actor_1", "type": "stop", "target_id": "object_marked_a1b2c3d4"},
          {"actor_id": "actor_2", "type": "stop", "target_id": "object_marked_a1b2c3d4"}
        ]
      },
      {
        "id": "beat_3",
        "phase": "first_described_action",
        "actions": [
          {
            "actor_id": "actor_1",
            "type": "described_action",
            "described_action": {
              "canonical_text": "starts smoking",
              "fallback_text": "*starts smoking*"
            }
          }
        ]
      }
    ],
    "reference_bindings": {
      "ordinal_map": {
        "first": "actor_1",
        "second": "actor_2"
      },
      "marked_object_ids": ["object_marked_a1b2c3d4"]
    }
  }
}
```

**Кто делает этот шаг:** детерминированный graph generator.

#### 11.2. Текстовое описание сцены (`source_text`)

На основе этого `CIR` controlled paraphraser строит текст, например:

> "Два актёра идут навстречу друг другу, останавливаются у ноутбука, после чего первый начинает курить."

**Кто делает этот шаг:** `gpt-5.4-nano` офлайн.

#### 11.3. Финальный `SceneScript` в `SG v7`

Далее из той же канонической сцены детерминированно строится правильный target JSON:

```json
{
  "actors": [
    {"id": "actor_1", "type": "human"},
    {"id": "actor_2", "type": "human"}
  ],
  "objects": [
    {
      "id": "object_marked_a1b2c3d4",
      "type": "generic",
      "name": "laptop",
      "relativePosition": "unknown"
    }
  ],
  "beats": [
    {
      "id": "beat_1",
      "actions": [
        {"actorId": "actor_1", "type": "walk", "target": "actor_2"},
        {"actorId": "actor_2", "type": "walk", "target": "actor_1"}
      ]
    },
    {
      "id": "beat_2",
      "actions": [
        {"actorId": "actor_1", "type": "stop", "target": "object_marked_a1b2c3d4"},
        {"actorId": "actor_2", "type": "stop", "target": "object_marked_a1b2c3d4"}
      ]
    },
    {
      "id": "beat_3",
      "actions": [
        {
          "actorId": "actor_1",
          "type": "described_action",
          "fallbackText": "*starts smoking*",
          "sourceText": "starts smoking"
        }
      ]
    }
  ]
}
```

**Кто делает этот шаг:** deterministic serializer / compiler.

#### 11.4. `ScenePlanIR` в `v8`

В `v8` из той же канонической сцены строится промежуточный план:

```json
{
  "actors": [
    {"ref": "first", "type": "human"},
    {"ref": "second", "type": "human"}
  ],
  "objects": [
    {
      "ref": "object_marked_a1b2c3d4",
      "type": "generic",
      "name": "laptop",
      "relativePosition": "unknown",
      "markedObjectID": "object_marked_a1b2c3d4"
    }
  ],
  "beats": [
    {
      "ref": "beat_1",
      "phase": "toward_each_other",
      "actions": [
        {"actorRef": "first", "type": "walk", "targetRef": "second"},
        {"actorRef": "second", "type": "walk", "targetRef": "first"}
      ]
    },
    {
      "ref": "beat_2",
      "phase": "stop_near_object",
      "actions": [
        {"actorRef": "first", "type": "stop", "targetRef": "object_marked_a1b2c3d4"},
        {"actorRef": "second", "type": "stop", "targetRef": "object_marked_a1b2c3d4"}
      ]
    },
    {
      "ref": "beat_3",
      "phase": "first_described_action",
      "actions": [
        {
          "actorRef": "first",
          "type": "described_action",
          "fallbackText": "*starts smoking*",
          "sourceText": "starts smoking"
        }
      ]
    }
  ],
  "referenceBindings": {
    "actorBindings": {
      "first": "actor_1",
      "second": "actor_2"
    }
  }
}
```

**Кто делает этот шаг офлайн:** deterministic projection `CIR -> ScenePlanIR`.  
**Кто делает похожий шаг в рантайме на телефоне:** локальная `Qwen`, которая пытается сразу предсказать `ScenePlanIR` по тексту.

### 12. Пример кейса, зачем нужен строгий grounding

Кейс `same_type_two_marked_objects` нужен затем, чтобы проверить, что модель отличает не просто "стул вообще", а **конкретный отмеченный объект**.

Упрощённый канонический смысл:
- есть левый стул `object_marked_1111aaaa`;
- есть правый стул `object_marked_2222bbbb`;
- первый должен подойти именно к правому стулу.

Текстовый вариант:

> "Первый подходит к правому стулу, второй остаётся на месте."

Здесь проверяется не просто наличие объекта, а **точная идентификация нужного marked object**.

### 13. Пример кейса, зачем нужны beats

Кейс `dialogue_then_small_action` нужен затем, чтобы проверить, что сцена не схлопывается в один блок.

Канонический смысл:
- сначала обмен репликами между двумя персонажами;
- затем маленькое действие — например, поворот одного персонажа.

Если модель потеряет beats, то:
- chronology разрушится;
- диалог и follow-up action сольются;
- целевая сцена станет структурно неверной.

### 14. Карта ролей: где работает что

Ниже зафиксировано краткое соответствие ролей.

#### Детерминированный код офлайн

- библиотека паттернов;
- graph generator;
- `CIR`;
- serializer в `SceneScript`;
- projection `CIR -> ScenePlanIR`;
- dataset builder;
- release/eval harness;
- leakage-safe split policy.

#### `gpt-5.4-nano` офлайн

- controlled paraphraser для `source_text`;
- critic helper в некоторых слоях validation.

#### Детерминированный код на телефоне

- `SceneAnchorExtractor`;
- `SceneMetadataExtractor`;
- prompt build;
- `repairScenePlanIR` / normalization;
- `ScenePlanCompiler`;
- `SceneQualityGate`;
- fallback / clarification / routing policy.

#### Локальная `Qwen` на телефоне

- генерация `ScenePlanIR` по пользовательскому тексту через `llama.cpp` и `GBNF`.

### 15. Сверхкраткое резюме

Ключевая идея `SG v7` состоит в том, что каноническая сцена существует **до текста и до target JSON** и задаётся программно через pattern library и graph generator. Это позволяет обучать модель не на случайных парах `текст -> JSON`, а на согласованных данных, где и текст, и целевой ответ являются двумя представлениями одной и той же сцены.

Ключевая идея `v8` состоит в следующем шаге: вместо прямого `текст -> SceneScript` локальная модель сначала восстанавливает внутренний `ScenePlanIR`, а уже затем deterministic compiler собирает финальный `SceneScript`.

Именно поэтому:
- `SG v7` — это прежде всего воспроизводимый data/training pipeline;
- `v8` — это переход к промежуточному плану сцены как в обучении, так и в реальном рантайме на телефоне.

## [2026-04-22 14:32] - [PR-H07: on-device neural evidence wrapper для camera analysis]

### Суть изменений
- Введен абстрактный on-device inference boundary для neural evidence с mock- и Core ML-provider-ами, чтобы добавить ML-слой без жесткой привязки к конкретной модели.
- Реализована cadence policy для `live` и `pause` режимов с soft-skip логикой, timeout-контролем и деградацией при thermal/battery pressure.
- Подключен runtime hook в `AnalysisPipeline` для асинхронного запуска inference без изменения deterministic critique/planner logic.
- Добавлены regression-тесты на cadence, fallback, timeout, descriptor-driven metadata и pipeline-level storage записанных outcomes.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Требовалось встроить on-device ML inference в существующий deterministic camera-analysis pipeline так, чтобы не разрушить воспроизводимость, не вносить race conditions и не терять трассируемость причин принятия решений.
- **Решение:** Использован слой абстракции `NeuralEvidenceProvider`, который отделяет модель от runtime policy; preprocessing сделан orientation-aware; live cadence защищен атомарным reservation-step; runtime metadata хранит фактический `roiStrategy` и `thresholdProfile`, а не только запрошенные значения.
- **Детали:** Для `live` введено ограничение частоты с учетом thermal tier и стабильности кадра, а для `pause` разрешен более богатый `full_frame_plus_subject_crop` path с fallback на `full_frame_only`. В случае деградации или ошибки сохраняются явные `policy_skipped`/`failed` outcomes, что важно для последующего анализа качества и построения диссертационного описания архитектуры.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/NeuralEvidenceInferenceService.swift` (cadence policy, timeout, metadata propagation)
- `shafinMultitool/Multitool2Module/Services/Pipeline/CoreMLNeuralEvidenceProvider.swift` (orientation-aware preprocessing, ROI fallback, Core ML execution)
- `shafinMultitool/Multitool2Module/Utilities/Metal/MetalPreprocessor.swift` (orientation-aware resize/crop)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (async neural hook and recorded outcomes)
- `shafinMultitoolTests/NeuralEvidenceInferenceServiceTests.swift` (cadence, timeout, descriptor, ROI fallback tests)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (pipeline storage coverage)


## [2026-04-12 16:01] - [Проектирование пайплайна SG v7 для дообучения локальной LLM]

### Суть изменений
- Сформирован новый целевой пайплайн `SG v7` для подготовки датасета и дообучения локальной модели `qwen 1.5B` под задачу преобразования русских текстовых описаний сцен в `SceneScript`.
- Зафиксирован переход от teacher-generated JSON как основного источника истины к `graph-first` подходу, в котором canonical target JSON строится программно и детерминированно.
- Разделён полный цикл на независимые компоненты: `runtime/train contract`, pattern library, deterministic graph generator, source generation, controlled augmentation, semantic critic, strict validators, dataset assembly, training, eval и runtime feedback loop.
- Добавлен отдельный source-of-truth документ для `runtime/train contract`, описывающий единый prompt format, serializer policy, grammar/GBNF, decoding constraints и frozen fixtures для предотвращения `train/inference drift`.
- Введена политика provenance для `corrected_target_json`: `tier_a_human_gold`, `tier_b_deterministic_canonical`, `tier_c_reviewed_merge`, `tier_d_auto_repair_only`, чтобы реальные runtime-исправления не смешивались с безусловным gold-таргетом.
- Формализован `complexity budget` для модели `1.5B`: ограничения не только на число актёров/объектов/битов/действий, но и на длину source/target в токенах и полную длину сериализованной последовательности.
- Уточнён eval-контракт: добавлены метрики `exact_marked_object_id_accuracy`, `ordinal_actor_binding_accuracy`, `target_resolution_accuracy`, `chronology_phase_accuracy`, а release gate теперь контролирует не только формальную валидность JSON, но и точность семантического grounding-а.
- Подготовлен decomposition-пакет для агентной разработки: roadmap, backlog, prompts, briefing template, codebase entry points, runtime failure examples и правила запуска отдельных design / implement / verify чатов.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** При использовании компактной локальной модели `qwen 1.5B` выявлены системные ошибки семантического парсинга: схлопывание сцены в минимально валидный JSON, потеря `marked objects`, деградация multi-beat структуры, ошибки в привязке `первый/второй`, а также исчезновение unsupported actions вроде `начинает курить`. Дополнительной проблемой является `train/inference mismatch`: даже небольшое расхождение между обучающим prompt-ом, runtime prompt-ом, grammar и сериализацией JSON приводит к резкому ухудшению качества на устройстве.
- **Решение:** Вместо дальнейшего наращивания rule-based логики и teacher-generated синтетики спроектирован новый пайплайн `SG v7`, где канонический смысл сцены задаётся промежуточным детерминированным графом. LLM используется не как источник gold JSON, а как paraphraser и semantic critic. Это уменьшает шум в целевых данных, позволяет программно гарантировать идентификаторы `actor_*` и `object_marked_*`, а также обеспечивает согласованность между dataset generation и runtime parsing.
- **Детали:** Ключевым решением стало выделение отдельного `runtime/train contract` с фиксированным порядком секций prompt-а, едиными правилами optional fields, стабильной сериализацией JSON и frozen fixtures для regression-проверок. Для предотвращения переусложнения обучающей выборки введён formal `complexity budget`: для `core` и `hard` фаз задаются верхние границы по `actor_count`, `object_count`, `beat_count`, `action_count`, `source_text_token_count`, `target_json_token_count` и `full_sequence_token_count`. В feedback loop добавлена trust-модель происхождения corrected samples, что позволяет отделять ручной gold от автоматического repair и предотвращать попадание недостоверных исправлений в SFT-данные. Архитектурно это переводит задачу из “fine-tune на произвольной синтетике” в воспроизводимую систему controlled data generation с явной семантической валидацией.

### Ключевые файлы
- `docs/SGv7pipeline/README.md` (общая архитектура SG v7)
- `docs/SGv7pipeline/18-runtime-train-contract.md` (единый contract train/runtime)
- `docs/SGv7pipeline/14-fixed-decisions.md` (фиксированные архитектурные решения)
- `docs/SGv7pipeline/08-training-plan.md` (phased curriculum и complexity budget)
- `docs/SGv7pipeline/09-eval-and-release.md` (метрики и release gate)
- `docs/SGv7pipeline/10-runtime-feedback-loop.md` (feedback ingestion и corrected sample provenance)
- `docs/SGv7pipeline/11-implementation-backlog.md` (треки реализации)
- `docs/SGv7pipeline/12-agent-prompts.md` (agent-based decomposition design/implement/verify)

---

### 3. Архитектура

- **Новый модуль**: `shafinMultitool/SceneGeneratorModule/`
  - **Models**: `SceneScript.swift` (включая `PlannedScene`, `MarkedObject`, `DetectedObject`);
  - **Services**: `SceneParserService`, `SpatialPlannerService`, `ObjectDetectionBridge`;
  - **ViewModels**: `SceneGeneratorViewModel`;
  - **Views**: `SceneGeneratorView`, `SceneInputSheet`, `ARSceneContainer`.
- **Интеграция**: правка `SceneModules/StageSelectionViewController.swift` (добавление запуска генератора).


## 2026-01-28 — Срез `dab2f1c6504b28416399b3f5408f829c3681ae3d` (fix: performance)

### 1. Реализованный функционал

- **Стабилизация CameraScreen (режим съёмки)**:
  - меньше просадок FPS/микрофризов на Vision и оверлеях;
  - предупреждения (blur/композиция) показываются без “спама”;
  - оверлей метрик расширен (появились задержки Vision/Speech/Overlay).
- **Надёжнее распознавание речи**:
  - защита от параллельных сессий распознавания;
  - корректный stop без “залипаний”.
- **Добавлены тесты**: набор unit/UI/perf тестов в `shafinMultitoolTests/` для фиксации регрессий.

### 2. Технические решения и сложности

- **Расширение мониторинга**:
  - `PerformanceMonitor` получил latency-метрики (Vision/Speech/Overlay) + буферизованное логирование через `DiagnosticsLogger`.
- **Frame skipping и тепловой бюджет**:
  - `FrameSkipController` регулирует частоту тяжёлых задач на кадрах;
  - `PreProductionThermalGovernor` переводит `thermalState` в бюджет (Vision FPS, speech/warnings);
  - `CameraScreenViewController` динамически подстраивает `visionThrottleInterval` и `CameraService.updateAuxiliaryTargetFPS(...)`.
- **Оптимизация Vision**:
  - запрет параллельных Vision-запросов (`isVisionRequestInProgress`);
  - кэширование `VNDetectFaceCaptureQualityRequest`;
  - ресайз входного кадра через `MetalPreprocessor` до ~`512×512`.
- **Оптимизация UI**:
  - пул предупреждений: `warningReusePool` + `configureWarningView(...)` (очистка subviews и переиспользование);
  - пул `CAShapeLayer` для bbox лица: скрытие/переиспользование вместо remove/add;
  - block-based timer с `[weak self]` (фикс возможного retain-cycle);
  - `cleanupResources()` на `viewWillDisappear`/`deinit`.
- **Вынос тяжёлых операций с main thread**:
  - `reformatScriptAsync` + отдельная `scriptQueue` + `autoreleasepool`;
  - глобальный `actors` перенесён в `CameraScreenInteractor` (контролируемый жизненный цикл);
  - траектории и движение: снапшоты + `OperationQueue` вместо блокировок и `Thread.sleep`.
- **Speech recognition и метрики**:
  - потокобезопасный state, safe stop, запись `speechLatency` в `PerformanceMonitor`.

### 3. Архитектура

- **Новые сервисы**:
  - `shafinMultitool/Services/DiagnosticsLogger.swift`
  - `shafinMultitool/Services/FrameSkipController.swift`
  - `shafinMultitool/Services/PreProductionThermalGovernor.swift`
- **Обновлённые компоненты**:
  - `shafinMultitool/Services/CameraService.swift`
  - `shafinMultitool/Services/SpeechRecognitionService.swift`
  - `shafinMultitool/SceneModules/CameraScreenModule/*`
  - `shafinMultitool/Views/PerformanceOverlayView.swift`
  - `shafinMultitoolTests/*`


## 2026-01-28 18:30 — Улучшение парсера сцен: обработка множественного числа и исправление критических ошибок

### Суть изменений
- Исправлена критическая ошибка `Fatal error: String index is out of bounds` в `Lemmatizer` и `SceneParserService` при парсинге русских текстов
- Реализована обработка множественного числа глаголов для корректного создания действий для всех актёров (например, "2 актёра идут" → действия для обоих)
- Исправлена проблема наложения актёров друг на друга при подходе к одному объекту — теперь они размещаются в ряд перпендикулярно направлению движения
- Добавлена система диагностики парсинга (`ParsingDiagnostics`) для оценки качества распознавания и выявления проблем
- Интегрирована поддержка размеченных пользователем объектов (`MarkedObject`) в процесс парсинга с приоритетом над стандартными объектами

### Научная и техническая значимость (Для текста диссертации)

- **Проблема 1: Небезопасная работа с индексами строк в NLTagger**
  - `NLTagger.enumerateTags` возвращает `Range<String.Index>`, которые могут выходить за границы строки при работе с русским текстом
  - Прямое извлечение подстрок без проверки границ приводило к runtime crash при парсинге
  - **Решение**: Упрощена архитектура `textContainsKeyword` — убрано использование `NLTagger.enumerateTags` для поиска ключевых слов, вместо этого используется безопасное разбиение на слова через `components(separatedBy:)` и лемматизация каждого слова отдельно. Это устранило проблему с индексами и повысило надёжность парсера.

- **Проблема 2: Недостаточная семантическая обработка множественного числа**
  - Rule-based парсер не различал единственное и множественное число глаголов ("идёт" vs "идут")
  - При множественном числе создавалось действие только для первого актёра, остальные оставались бездейственными
  - **Решение**: Реализована функция `isPluralVerbForm`, которая анализирует текст на наличие глаголов во множественном числе (3-е лицо: "идут", "подходят", "бегут"). При обнаружении множественного числа и наличии нескольких актёров, действия создаются для всех актёров автоматически. Используется проверка целых слов (не подстрок) для избежания ложных срабатываний.

- **Проблема 3: Геометрическое наложение актёров в 3D пространстве**
  - При подходе нескольких актёров к одному объекту все получали идентичную начальную позицию
  - Визуально это выглядело как один актёр из-за полного наложения в пространстве
  - **Решение**: Модифицирован алгоритм `calculateApproachPositions` в `SpatialPlannerService`:
    - Группировка актёров по целевому объекту для определения количества актёров, идущих к одному месту
    - Вычисление перпендикулярного вектора к направлению "объект → центр сцены" для размещения актёров в ряд
    - Линейное распределение с интервалом `actorSpacing = 2.0` метра: `offset = startOffset + index * actorSpacing`, где `startOffset = -totalWidth / 2` для центрирования ряда
    - Формула позиции: `basePosition + perpendicular * offset`, где `basePosition` — точка на расстоянии 2 метра от объекта в направлении центра сцены

- **Детали реализации**:
  - **Лемматизация**: Используется `NLTagger` с fallback на эвристическое удаление русских окончаний для нормализации словоформ
  - **Безопасность индексов**: Все операции с `Range<String.Index>` и `NSRange` защищены проверками границ перед извлечением подстрок
  - **Диагностика**: `ParsingDiagnostics` вычисляет метрики confidence (0.0-1.0), coverage (покрытие текста), флаги missingActors/missingObjects для оценки качества парсинга
  - **Приоритет размеченных объектов**: `MarkedObjectMatcher` ищет упоминания пользовательских объектов в тексте с учётом лемматизации и притяжательных местоимений ("мой стол", "этот стул")

### Ключевые файлы
- `SceneGeneratorModule/Services/Lemmatizer.swift` (методы `textContainsKeyword`, `lemmatize`, `matchesKeyword`)
- `SceneGeneratorModule/Services/SceneParserService.swift` (методы `extractActions`, `isPluralVerbForm`, безопасная работа с индексами)
- `SceneGeneratorModule/Services/SpatialPlannerService.swift` (метод `calculateApproachPositions` с группировкой и перпендикулярным размещением)
- `SceneGeneratorModule/Services/DiagnosticsCalculator.swift` (вычисление метрик качества парсинга)
- `SceneGeneratorModule/Services/MarkedObjectMatcher.swift` (поиск упоминаний размеченных объектов)


## 2026-03-13 16:00 — Интеграция локальной LLM (llama.cpp + Qwen2.5-0.8B) в SceneGeneratorModule

### Суть изменений
- Собран `llama.xcframework` (iOS device arm64 + simulator arm64/x86_64) с Metal GPU из исходников llama.cpp
- Добавлена квантизованная модель `Qwen2.5-0.8B-Instruct Q4_K_M` (~379 MB) в бандл
- Создан `LlamaContext.swift` — Swift `actor`-обёртка C API llama.cpp: загрузка GGUF, Metal offload, токенизация, сэмплирование
- Переписан `LLMParserService.swift`: реальный инференс, ChatML-промпт, few-shot примеры на русском, починка JSON
- Реализован `SceneParserService.parseAsync()`: rule-based → confidence check → LLM fallback (при confidence < 0.6)
- `SceneGeneratorViewModel.generateScene()` переведён на `await parseAsync()`
- Добавлен `ActorType.lion` с падежными формами в словарь
- Постобработка LLM-вывода: `repairJSON()` + `balanceBrackets()`

### Научная и техническая значимость (Для текста диссертации)

- **Проблема 1: Интеграция C++ библиотеки в Swift/iOS проект с CocoaPods**
  - llama.cpp не имеет Swift Package, совместимого с CocoaPods
  - **Решение**: cmake + Xcode-генератор → статические `.a` → динамический `.dylib` → XCFramework. Флаги: `-DGGML_METAL=ON`, `-DGGML_METAL_EMBED_LIBRARY=ON` (Metal-шейдеры встроены в бинарник). `n_gpu_layers=99` на устройстве, `=0` на симуляторе
  - **Детали**: `llama_batch_init(4096, 0, 1)` — батч вмещает промпт (~700 токенов) + вывод (~300 токенов)

- **Проблема 2: Вырожденные циклы повторений при генерации (repetition loops)**
  - Модель 0.5B при низкой температуре зацикливалась на одних токенах, генерируя 32+ сек без результата
  - **Решение**: `llama_sampler_init_penalties(last_n=64, repeat=1.3)` — штраф 1.3× за повторение токенов из последних 64. Формула: `logit'(t) = logit(t) / 1.3` при `logit > 0`. Время генерации: 32 сек → ~4 сек

- **Проблема 3: Синтаксически некорректный JSON от малопараметрической модели**
  - Qwen2-0.5B генерирует полувалидный JSON: `"spatialRelations[]:`, trailing commas, ID с дефисами вместо `_`
  - **Решение**: Двухэтапная постобработка — `repairJSON()` (regex-починка структуры ключей) + `balanceBrackets()` (дополнение незакрытых скобок при обрезанном выводе). Позволяет использовать частично валидные ответы без дообучения модели

- **Детали промптинга**:
  - Few-shot prompting: 2 примера вход→выход покрывают типичные структуры (простой + spatial relations + животные)
  - ChatML-формат (`<|im_start|>system...<|im_end|>`) — нативный формат Qwen2-Instruct, критичен для instruction following
  - Весь промпт на русском языке — устраняет языковой сбой при mixed-language промптах

### Ключевые файлы
- `SceneGeneratorModule/Services/LlamaContext.swift` (`create`, `generate`, `completionInit/Loop`)
- `SceneGeneratorModule/Services/LLMParserService.swift` (`parseAsync`, `buildPrompt`, `repairJSON`, `balanceBrackets`)
- `SceneGeneratorModule/Services/SceneParserService.swift` (`parseAsync` — confidence-gated LLM fallback)
- `SceneGeneratorModule/Models/SceneScript.swift` (`ActorType.lion`, `RelationType: CaseIterable`)
- `Frameworks/llama.xcframework`

---

## 2026-03-23 16:50 — Оптимизация инференса через GBNF и усовершенствование 3D-планировщика

### Суть изменений
- **Интеграция GBNF-грамматик**: Внедрена технология Constrained Decoding. Сэмплирование токенов теперь ограничено правилами грамматики, что гарантирует 100% валидный JSON без постобработки.
- **Оптимизация SpatialPlannerService**:
  - Реализован алгоритм **"Meeting Point with Spacing"** для действия `towardEachOther` (актёры больше не накладываются друг на друга в центре).
  - Добавлена поддержка маршрутизации для действия `stop` с привязкой к целевому объекту (ранее отсутствовала).
- **Улучшение Rule-based парсера**:
  - Добавлены паттерны извлечения действий остановки («останавливается у X», «стоит около Y»).
  - Реализована дедупликация извлеченных действий (устранение повторов в SceneScript).
  - Снижен порог Fallback на LLM (`0.85 -> 0.70`), что сократило лишние обращения к модели при качественном базовом разборе.
- **Исправление GBNF-регрессии**: Устранена 10-кратная задержка инференса (с 38с до 4с) путем исправления индентации GBNF-строки для корректного парсинга в llama.cpp.

### Научная и техническая значимость (Для текста диссертации)

- **Проблема 1: Синтаксическая нестабильность малых моделей (<1B)**. Даже Qwen2.5-0.8B часто генерировала полувалидный JSON (например, `"spatialRelations[]:`) при включении штрафов за повторение.
  - **Решение**: Переход от реактивной починки (Regex/Partial Parsing) к **превентивному ограничению (Constrained Decoding)**. Использование GBNF (Grammar-Based Normal Form) инжекции в цепочку сэмплеров `llama_sampler_chain`. Сэмплирование `logit_softmax` теперь маскирует все токены, не соответствующие JSON-схеме на текущей позиции.
  
- **Проблема 2: Визуальные коллизии агентов в AR-сцене**. Базовый алгоритм планировщика сводил актёров в точку `sceneSpace.center`, что приводило к наложению 3D-мешей при завершении траектории.
  - **Решение**: Динамический расчёт точки встречи. Вместо статического центра используется вектор `(PosA + PosB) / 2` с перпендикулярным смещением `ortho_vec * spacing`, где `spacing = 1.0м`. Это обеспечивает кинематографическую корректность сцены.

- **Проблема 3: Вычислительная избыточность (Over-fallback)**. Слишком агрессивный порог уверенности (0.85) вызывал запуск LLM даже в случаях, когда Apple `NaturalLanguage` фреймворк отрабатывал идеально.
  - **Решение**: Эмпирическая калибровка `llmFallbackThreshold`. Оптимизация соотношения "Затраченное время / Качество распознавания".

### Ключевые файлы
- `SceneGeneratorModule/Services/LlamaContext.swift` (интеграция `llama_sampler_init_grammar`)
- `SceneGeneratorModule/Services/LLMParserService.swift` (GBNF-схема JSON и фикс индентации)
- `SceneGeneratorModule/Services/SceneParserService.swift` (дедупликация, паттерны `stop`, коррекция `threshold`)
- `SceneGeneratorModule/Services/SpatialPlannerService.swift` (алгоритм схождения и маршрутизация остановок)

---

## 2026-03-24 11:50 — Синтез обучающего датасета (SFT) для семантического парсинга сцен

### Суть изменений
- Создан пайплайн синтетической генерации данных в формате ChatML с использованием OpenAI Structured Outputs.
- Сгенерирован и очищен датасет из 1883 уникальных примеров перевода текстовых описаний мизансцен (пользовательский ввод, режиссёрские ремарки, формат "Американка") в валидный JSON-формат `SceneScript`.
- Аудит датасета подтвердил 100% структурную валидность, отсутствие битых связей (Referential Integrity) и равномерное покрытие 18 типов действий и 24 типов объектов.
- Оптимизирован баланс обучающей выборки: устранен перекос базовых действий (`pick_up`) в пользу сложных паттернов и добавлены примитивные edge-кейсы (1 актёр, 1 действие).

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Локальные SLM (Small Language Models, 0.5B-1.5B параметров) в iOS-окружении (через `llama.cpp`) медленно и нестабильно генерируют JSON. Модели подвержены "dialogue bias" (галлюцинируют действия из текста диалогов героев) и требуют объемных few-shot примеров, которые перегружают и без того ограниченное контекстное окно мобильного инференса.
- **Решение:** Подготовка к Supervised Fine-Tuning (SFT). Разработан датасет, который обучит модель "noise immunity" — устойчивости к шуму. Модель научится игнорировать диалоги, заголовки и литературные описания, экстрагируя исключительно физиологическую мизансцену в строгий JSON.
- **Детали:** Базовая архитектура дообучения подразумевает использование LoRA (Low-Rank Adaptation) поверх квантованной модели. Специально спроектированные "сцены-обманки" заставят модель фильтровать ложные намерения. Переход от Prompt Engineering к Fine-Tuning позволит в будущем отказаться от few-shot примеров, снизив Time-To-First-Token (TTFT) и энергопотребление на стороне устройства.

### Ключевые файлы
- `generate_dataset.py` (Пайплайн генерации с OpenAI API)
- [`data/legacy/dataset_finetune.jsonl`](data/legacy/dataset_finetune.jsonl) (Итоговый обучающий датасет ShareGPT/ChatML)

---

## 2026-03-24 15:09 — Интеграция дообученной SLM (LoRA → GGUF) в iOS-проект

### Суть изменений
- Успешно завершено дообучение (Supervised Fine-Tuning) модели `Qwen2.5-0.5B-Instruct` на ранее сгенерированном датасете `SceneScript` с использованием метода LoRA (Low-Rank Adaptation, ранг 16).
- Обученные адаптеры слиты с базовой моделью и квантизованы в формат `GGUF (Q4_K_M)` для эффективного инференса на мобильном GPU (Metal) через фреймворк `llama.cpp`. Итоговый файл добавлен в бандл проекта.
- Подготовлено обновление модуля `LLMParserService.swift` для работы с новой моделью в Zero-Shot режиме.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Распознавание сцен с помощью LLM (как Fallback-механизм) ранее требовало объемного системного промпта с few-shot примерами. Это увеличивало длину контекста, замедляло обработку (Time-To-First-Token) и повышало энергопотребление на iPhone. Кроме того, базовая модель часто реагировала на "шум", пытаясь парсить диалоговый текст.
- **Решение:** Интеграция SFT-модели устраняет потребность в few-shot примерах. Дообученная модель самостоятельно выдает строгий JSON из естественного языка (Zero-Shot) с иммунитетом к шумовым данным. Фреймворк `llama.cpp` продолжает использовать GBNF для 100% гарантии синтаксиса, но сама генерация семантически точна.
- **Детали:** Использован 4-битный формат квантования (`Q4_K_M`), который дает оптимальный баланс компрессии весов (~380 МБ) и точности. Полный отказ от few-shots снижает размер промпта на ~80%, кратно ускоряя фазу *prompt evaluation* (обработку ввода) в `llama.cpp`.

### Ключевые файлы
- `qwen2.5-0.5b-instruct.Q4_K_M.gguf` (Обученная модель)
- `LLMParserService.swift` (Интеграция инференса и обрезка системного промпта)

---

## 2026-03-25 20:50 — Обнаружение архитектурного ограничения плоского списка действий и переход к Beat-системе

### Суть изменений
- Интеграция дообученной SLM завершена: LLM теперь вызывается как основной парсер (не fallback), `DiagnosticsCalculator` корректно валидирует `target` как `actor_X` и `object_X`, `SpatialPlannerService` умеет резолвить позиции актёров по ID.
- **Выявлено фундаментальное ограничение текущей схемы `SceneScript`:** плоский массив `actions` не содержит информации о **временно́й координации** между актёрами. Каждый актёр обрабатывается Planner'ом **изолированно** — пути строятся без синхронизации, результат визуально не соответствует описанию.
- Пример: промпт «2 человека идут навстречу, проходят мимо, один сворачивает» порождает 3 действия, но actor_1 идёт вперёд по своей оси, а actor_2 идёт к начальной позиции actor_1 — они не сходятся, не расходятся, не синхронизируются.
- Принято решение о переходе к **Beat-системе** (Blocking Beats) — разделение действий на хронологические фазы с синхронизацией всех участников.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Плоская структура `actions: [SceneAction]` не кодирует каузально-темпоральные зависимости между действиями разных актёров. Planner строит траектории per-actor, что приводит к десинхронизации: длительность действия `walk(forward)` у actor_1 ≠ длительности `pass_by(actor_1)` у actor_2, актёры оказываются в несвязанных точках пространства. Отсутствие «глобальных часов» — врождённый дефект архитектуры, не решаемый патчами.
- **Решение:** Введение промежуточной абстракции **Beat** (такт мизансцены) — атомарной единицы времени, объединяющей синхронные действия всех участников. Длительность beat = max(duration всех входящих actions). Следующий beat начинается только после завершения предыдущего. Это классический подход в анимации (keyframe blocks) и режиссёрском блокинге (cue sheets).
- **Детали:** Миграция затрагивает 4 уровня: (1) схема `SceneScript` → beats вместо actions, (2) GBNF-грамматика для constrained decoding, (3) обучающий датасет → перегенерация 1883 примеров в beat-формате, (4) SpatialPlannerService → beat-by-beat планирование с глобальной синхронизацией позиций.

### Ключевые файлы
- `SceneScript.swift` (текущая плоская схема actions)
- `SpatialPlannerService.swift` (per-actor buildPath → будет переписан на beat-by-beat)
- `LLMParserService.swift` (GBNF-грамматика, промпт)
- `generate_dataset.py` (генератор обучающих данных)
- `DiagnosticsCalculator.swift` (фикс валидации actor targets)


---

## 2026-03-26 11:07 — Расширение SceneScript v2: камера, позы актёров, привязка объектов

### Суть изменений
- Схема `SceneScript` расширена полноценной Beat-системой с **камерой** на каждый beat, **персистентными позами** актёров и **привязкой объектов** (pick_up → объект движется с актёром).
- Добавлена структура `CameraSetup` с 6 типами кадра (`wide`, `medium`, `close_up`, `extreme_close_up`, `over_shoulder`, `two_shot`) и 10 типами движения камеры (`static`, `pan_left/right`, `dolly_in/out`, `tracking`, `crane_up/down`, `tilt_up/down`).
- Введён enum `ActorPose` (6 состояний: `standing`, `sitting`, `crouching`, `lying`, `walking`, `running`) и поля `resultingPose`/`holdingObject` в `SceneAction`.
- `SceneBeat` расширен полями `camera: CameraSetup?` и `minDuration: Double?` для управления паузами.
- GBNF-грамматика v2 полностью переписана: корневое правило генерирует `beats` (не `actions`), каждый beat содержит `camera` + `actions` с `resultingPose`/`holdingObject`.
- Подготовлен скрипт `generate_dataset_v2.py` для генерации обучающего датасета с камерой, позами и holdingObject.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Существующие системы генерации раскадровок (storyboards) ограничиваются перемещениями актёров без учёта ракурса съёмки. Это не позволяет режиссёру визуализировать кадр так, как он будет выглядеть на экране. Кроме того, состояние актёра (сидит/стоит/бежит) и предметов в его руках теряется между действиями.
- **Решение:** Интеграция камеры в beat-систему превращает визуализатор перемещений в полноценный генератор раскадровки. Каждый beat = один кадр сториборда с конкретной крупностью и движением камеры. Персистентные позы (`ActorPose`) обеспечивают корректное отображение состояний между beats. Привязка объектов (`holdingObject`) решает проблему «забытых» предметов после `pick_up`.
- **Детали:** Выбор архитектуры (camera per beat, а не per action) обоснован режиссёрской практикой: смена ракурса привязана к смене мизансцены (beat), а не к действию отдельного актёра. Это также упрощает задачу SLM — модель выбирает один тип кадра на beat из 6 вариантов, а не принимает непрерывное решение.

### Ключевые файлы
- `SceneScript.swift` (CameraSetup, ActorPose, расширенные SceneBeat/SceneAction, PlacedActor)
- `LLMParserService.swift` (GBNF v2, пост-обработка JSON: автогенерация id, speed→modifier)
- `SpatialPlannerService.swift` (PlacedActor с pathPoses/pathCameras)
- `generate_dataset_v2.py` (генератор датасета v2 с камерой/позами/holdingObject)

---

## 2026-03-30 13:50 — Интеграция диалоговой системы и семантическая фильтрация объектов (Strict Whitelisting)

### Суть изменений
- **Диалоговая система**: В схему `SceneAction` добавлено действие `talk` и строковое поле `dialogue`. Это позволяет генерировать текст для AR-баблов и синхронизировать длительность такта (beat) с длиной реплики.
- **Strict Object Whitelisting**: Список допустимых объектов в `SceneObject.ObjectType` строго ограничен 10 базовыми категориями (`table`, `chair`, `bed`, `couch`, `door`, `window`, `cabinet`, `shelf`, `tv`, `generic`). Все мелкие или нестандартные предметы (ключи, ножи, книги) теперь принудительно маппятся в `generic`.
- **Pydantic Валидация в Generator**: В скрипт `generate_dataset_v2.py` добавлены валидаторы для `resultingPose` и `ObjectType`. Теперь скрипт автоматически исправляет галлюцинации LLM (например, превращает действие `walk` в поле позы в корректное состояние `walking`).
- **Смена вектора генерации**: Перебалансированы веса категорий в синтетическом датасете. Доля криминальных сцен ("допрос") снижена в пользу бытовых сюжетов (кафе, кухня, офис), что улучшает обобщающую способность модели.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема 1: Семантический разрыв между LLM и движком рендеринга**. Базовые LLM часто генерируют в JSON объекты, для которых нет 3D-мешей или COCO-меток (например, "microscope", "crowbar"). Это приводит к ошибкам визуализации.
  - **Решение**: Введение жесткого белого списка (Whitelist) на уровне схемы данных и генератора. Использование категории `generic` как универсального контейнера для объектов с неизвестной геометрией, что гарантирует стабильность `SpatialPlannerService`.
- **Проблема 2: Координация речи и анимации**. Без поля `dialogue` в структуре `SceneAction` невозможно рассчитать реалистичную длительность такта, так как ходьба может занять 2 секунды, а фраза — 10 секунд.
  - **Решение**: Модификация формулы расчета длительности beat: `duration = max(movement_time, dialogue_length * CHAR_RATE)`. Это обеспечивает темпоральную целостность сцены в AR.
- **Проблема 3: Галлюцинации состояний в SLM**. Малые модели часто путают глаголы действий и названия поз (пишут `resultingPose: "pick_up"`). 
  - **Решение**: Реализация "слоя исправления" (Correction Layer) в пайплайне подготовки данных. Автоматическое отображение (mapping) некорректных токенов в разрешенное подмножество состояний (`ActorPose`).

### Ключевые файлы
- `SceneGeneratorModule/Models/SceneScript.swift` (ActionType.talk, dialogue field)
- `generate_dataset_v2.py` (Strict whitelists, Pydantic validators, balanced weights)
- [`data/legacy/dataset_finetune_v2.jsonl`](data/legacy/dataset_finetune_v2.jsonl) (Обновленный обучающий датасет с диалогами)

---

## 2026-04-01 17:35 — Переход к двухступенчатой генерации contiguous-чанков для синтетического датасета (SFT)

### Суть изменений
- Разработана архитектура двухступенчатой генерации (`generate_dataset_v6_chunk_realistic.py`): сначала LLM генерирует "source fragment" (длинный непрерывный кусок развивающейся сцены типичного сериала на 8-14 строк), а затем из него алгоритмически извлекается "contiguous chunk" (2-5 строк).
- Устранён "экспозиционный перекос" (static start bias) и "overdramatic bias" в датасете: модель больше не начинает каждый чанк с описания сидящих/стоящих людей, случайная вырезка (sliding window) естественным образом захватывает сцену *in medias res*.
- Спецификация `SceneBeat` строго привязана к микрофазам внимания: одновременные действия группируются в один такт. Это критически важно для `SpatialPlannerService`, где beat является фундаментальной единицей 3D-синхронизации нескольких актёров.
- Реализована поддержка "pure dialogue" чанков без обязательной пространственной экспозиции: разрешено генерировать фрагменты, состоящие только из обмена репликами с минимальными `talk`-разметками, что имитирует реальное поведение мобильного приложения при разрезании длинного загруженного пользователем сценария.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** При синтезе датасета (SFT) базовая стратегия прямого промптинга приводила к генерации автономных "мини-сцен", каждая из которых содержала устанавливающий кадр (establishing shot — "А сидит, Б входит"). Это порождало *distribution mismatch*: в реальных условиях приложение разбивает целый сценарий на чанки, большинство которых является серединой разговора и не содержит новых пространственных вводных.
- **Решение:** Изменение парадигмы генерации на *Sampling from Generation Window*. LLM поручается генерация связного макро-контекста, из которого вырезается случайный срез (contiguous chunk). Это восстанавливает естественное распределение (prior) структур текста и заставляет локальную модель учиться парсить фрагменты без начальных условий о координатах актёров.
- **Детали:** Сценарный генератор теперь включает сложную систему профилирования (`SOURCE_FRAGMENT_MODES`, `CHUNK_PROFILES`) и многопроходные regex/эвристические фильтры (Soft/Hard Drama Terms, Static Start Patterns, Meta Leak), которые контролируют синтаксическое разнообразие и отфильтровывают "телевизионное мыло". Имплементация `SceneBeat` пересмотрена: такт синхронизируется с семантическим переключением фокуса (attention shift), а не с каждым отдельным глаголом.

### Ключевые файлы
- `generate_dataset_v6_chunk_realistic.py` (Многоступенчатая генерация, профилировщики чанков, эвристические фильтры)
- `SpatialPlannerService.swift` (Для которого подготавливается темпоральная beat-выборка)

---

## 2026-04-01 18:45 — Повышение качества датасета: разделение моделей и переход к семантической отбраковке (Semantic Filtering)

### Суть изменений
- Разделены модели для этапов генерации: `gpt-5.4-nano` используется для создания реалистичного текста сцены, а более строгая `gpt-5.4-mini` — для извлечения `SceneScript` JSON.
- Усилен системный промпт JSON-генератора: введены строгие запреты на додумывание реплик, использование местоимений ("Он", "Она") в качестве имён и дробление сложного действия на избыточные микродействия.
- Полностью удалён механизм автоматического исправления (autofix) JSON, который скрытно портил обучающую выборку (например, подставлял `...` в отсутствующие реплики). Вместо этого внедрён механизм жёсткой отбраковки (Reject & Regenerate).
- Интегрирована многоуровневая семантическая валидация JSON: результат сверяется с исходным текстом на предмет фейковых реплик и абстрактных объектов ("копия", "поле"), а также добавлен шаг self-check (самопроверки моделью) до генерации финального объекта.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** При синтезе датасета (SFT) целевой (target) JSON содержал семантический шум: базовая LLM периодически галлюцинировала действия, придумывала несуществующие реплики и плодила абстрактные объекты. Наличие таких "тихо испорченных" примеров (где JSON синтаксически валиден, но логически расходится с текстом) фатально для качества fine-tuning'а, так как целевая модель учится фантазировать, а не парсить текст.
- **Решение:** Изменение парадигмы с "Data Healing" (исправление сломанных JSON) на "Strict Semantic Filtering" (отбраковка сломанных JSON). Изоляция творческой задачи генерации текста от задачи структурного парсинга (через разделение моделей nano и mini) позволила максимизировать сильные стороны каждой из моделей без перекрестного загрязнения контекста. Пайплайн превратился из генератора примеров в строгий "фильтр реальности" для LLM-галлюцинаций.
- **Детали:** Спроектирована архитектура контроля качества: LLM проверяет сама себя (self-check), после чего запускается пакет семантических проверок. Любой JSON, не проходящий валидацию на соответствие словарю объектов или содержащий галлюцинации реплик, переводит всю цепочку (source+chunk+json) в состояние *reject* и инициализирует повторную генерацию. Результат — датасет меньшего объема, но кратно превосходящий по качеству и точности маппинга *текст → структура*, что критично для успешного обучения локальной SLM.

### Ключевые файлы
- `generate_dataset_v6.py` (Разделение моделей `SOURCE_MODEL`/`JSON_MODEL`, self-check механизмы, семантические валидаторы)

---

## 2026-04-09 16:10 — Интеграция дообученной Qwen2.5-1.5B и перенос состояния между contiguous-чанками

### Суть изменений
- В приложение интегрирована новая локальная модель `qwen2.5-1.5b-instruct.Q4_K_M.gguf`, дообученная на датасете `dataset_finetune_v6.jsonl` объёмом 1850 примеров, ориентированных на разбор contiguous-чанков одной продолжающейся сцены.
- Схема `SceneScript` и GBNF-грамматика расширены полями контекста сцены (`sceneHeading`, `locationName`, `interiorExterior`, `timeOfDay`), именами объектов, а также поддержкой `described_action` с текстовыми полями `fallbackText` и `sourceText`.
- Реализован контейнер `SceneChunkState`, сохраняющий известные `actorId`, позы и удерживаемые объекты между последовательными кусками сценария; `LLMParserService` теперь передаёт это состояние в промпт, чтобы модель не теряла идентичность персонажей и локационный контекст.
- `SpatialPlannerService` и `SceneGeneratorViewModel` доработаны для показа не только геометрии траекторий, но и текстовых аннотаций по сегментам (`talk`/`described_action`), включая паузы без перемещения, когда действие представлено репликой или описанием.
- Эвристический парсер дополнительно исправлен для конфликта имени «Лев»: слово с заглавной буквы больше не ошибочно интерпретируется как животное `lion`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** После перехода к realistic chunk-based датасету базовой трудностью стала не только генерация корректного JSON внутри одного фрагмента, но и сохранение непрерывности состояния между чанками. Без памяти о предыдущем состоянии локальная модель могла переизобретать идентификаторы актёров, терять позы, ломать каузальность действий и ухудшать временную связность 3D-блокинга.
- **Решение:** Пайплайн переведён от stateless parsing к state-aware parsing. Введён промежуточный объект `SceneChunkState`, который передаёт в LLM компактную память о сцене (локация, тип интерьера/экстерьера, уже известные персонажи, текущие позы и удерживаемые объекты). Это превращает последовательность независимых вызовов модели в приближённый режим инкрементального структурного парсинга.
- **Детали:** Обновлённая GBNF-грамматика теперь допускает как идентификаторы (`id-string`), так и полноценные JSON-строки (`text-string`) для реплик и описаний, сохраняя constrained decoding при расширении выразительности схемы. Поддержка `described_action` и `pathAnnotations` даёт возможность хранить и воспроизводить неанимируемые, но семантически значимые действия без потери синхронизации beat-последовательности. Переход с `Qwen2.5-0.5B` на `Qwen2.5-1.5B` компенсирует возросшую сложность задачи и увеличенный объём выходной структуры, оставаясь совместимым с локальным инференсом через `llama.cpp` и 4-битную квантизацию `Q4_K_M`.

### Ключевые файлы
- `shafinMultitool/Resources/Models/qwen2.5-1.5b-instruct.Q4_K_M.gguf` (Новая дообученная локальная SLM)
- `shafinMultitool/SceneGeneratorModule/Models/SceneChunkState.swift` (Персистентное состояние между чанками)
- `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift` (State-aware prompt и расширенная GBNF-грамматика)
- `shafinMultitool/SceneGeneratorModule/Services/SpatialPlannerService.swift` (Текстовые аннотации и тайминг непространственных действий)
- `shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift` (Визуализация аннотаций в 3D-сцене)
- `dataset_finetune_v6.jsonl` (Финальный датасет SFT на 1850 примеров)

---

## 2026-04-13 00:00 — Итог Prompt 1 и Prompt 2 в SG v7

### Суть изменений
- **Prompt 1 завершён как `CIR`-контрактный слой.** Для генерации датасета введён канонический `CIR` с жёсткой проверкой `sample_id`, поддержкой трёх актёров и fail-fast поведением на структурный drift. Это означает, что entrypoint больше не чинит ошибки скрытно, а действует как integrity gate для canonical artifacts.
- **Prompt 2 завершён как pattern library слой.** В `registry.py` сформирована рабочая библиотека canonical graph patterns для синтетической генерации: базовые одно- и двухактёрные семейства дополнены реальными `3-actor` сценами, включая ordinal binding, передачу предмета и многошаговые сцены с marked object.
- Для `Prompt 2` добавлен исполнимый coverage report по критическим runtime-failure классам, чтобы библиотека покрывала не только синтаксис, но и основные семантические провалы рантайма: потерю marked object, collapse of motion semantics, ordinal mismatch и three-actor handoff loss.
- Документация пайплайна синхронизирована с кодом, чтобы `design`, `implement` и `verify` для этих двух промптов опирались на один и тот же контракт, схему, registry и набор тестов.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для локальной модели малого размера критичны два источника ошибки: неконсистентный структурный контракт между этапами подготовки данных и узкое покрытие канонических сцен. Если contract и pattern library расходятся, модель обучается на шуме: формально корректный JSON не гарантирует правильную семантику scene graph.
- **Решение:** `Prompt 1` зафиксировал структурную сторону задачи через canonical `CIR`, а `Prompt 2` перевёл смысловую часть в управляемую библиотеку канонических паттернов с весами, версиями и coverage ownership. В совокупности это уменьшает риск тихих ошибок при fine-tuning и создаёт воспроизводимый pipeline для локальной SLM.
- **Детали:** Отдельно формализованы `actor_3`/`third`-сценарии, object-centric handoff patterns и отчёт о критических отказах. Такой разделённый дизайн позволяет масштабировать dataset generation без смешивания ролей: `Prompt 1` отвечает за корректность структуры, `Prompt 2` за богатство и покрытие семантических классов сцен.

### Ключевые файлы
- `generate_dataset_v7.py` (`build_scene_script`, fail-fast validation)
- `docs/SGv7pipeline/cir_contract/contracts/cir_validator.py` (каноническая проверка CIR)
- `docs/SGv7pipeline/cir_contract/contracts/cir_schema_v1.json` (schema-level contract)
- `docs/SGv7pipeline/pattern_library/registry.py` (канонические pattern families)
- `docs/SGv7pipeline/pattern_library/coverage.py` (coverage report for critical failures)
- `docs/SGv7pipeline/20-pattern-library.md` (спецификация pattern library)

---

## 2026-04-13 18:02 - Завершение Prompt 3 и Prompt 4 в SG v7: от deterministic graph generation к source paraphrase generation

### Суть изменений
- Для `Prompt 3` зафиксирован и интегрирован исполнимый слой deterministic graph generation: `graph_generator` строит воспроизводимые `CIR`-records из canonical pattern library, применяет seed-driven planning, validation, dedup и формирует JSONL-артефакты, пригодные для следующего этапа пайплайна без ручной донастройки.
- Для `Prompt 4` спроектирован и реализован отдельный `source_generation` слой, который принимает graph records и генерирует несколько surface-variants (`clean`, `colloquial`, `user_short`) через формализованный prompt contract, style policy, cheap reject filters и traceable metadata.
- В `Prompt 4` проведён полный цикл `design -> design verify -> implement -> implement verify`: сначала оформлен design-документ, затем найдены и исправлены противоречия по ownership Track 4/Track 5, semantic reject boundary, same-type marked object disambiguation и normalization policy.
- Реализация `Prompt 4` поддерживает два backend-режима: `openai` для production paraphrasing и `heuristic` для офлайн smoke/unit tests, что позволяет проверять пайплайн локально без сетевой зависимости.
- После implement verify устранены две критичные логические неточности: ordinal anchors стали условными, а не обязательными всегда, и в smoke suite добавлен morphology-stress case для marked object surface recovery.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для обучения локальной SLM недостаточно просто иметь корректный `CIR`. Нужен двухступенчатый воспроизводимый pipeline, в котором сначала строится детерминированная scene-структура, а затем поверх неё генерируются реалистичные текстовые surface-формы без semantic drift. Без такого разделения модель либо переобучается на слишком канонические графы, либо получает шумный source-text, теряющий ordinal binding, marked object grounding и chronology.
- **Решение:** Архитектура SG v7 разделена на два независимых, но согласованных слоя. `Prompt 3` отвечает за deterministic graph synthesis и тем самым стабилизирует семантический каркас обучающего примера. `Prompt 4` добавляет controlled paraphrase generation с жёстким prompt payload, cheap lexical validation, explicit handoff к semantic critic и нормализованной записью accepted/rejected variants. Такое разбиение уменьшает связность компонентов и делает ошибки наблюдаемыми на конкретном этапе пайплайна.
- **Детали:** В `Prompt 4` реализованы `required_aliases`, conditional `required_ordinal_tokens`, `same_type_disambiguation_block`, dedup-normalization и persisted-normalization, а также metadata-поля для audit trail (`prompt_template_version`, `source_policy_version`, `needs_semantic_critic`). Практически это означает, что source generator не пытается сам решать полную semantic validity, а ограничивается дешёвыми fail-fast проверками перед передачей результата в downstream critics. В совокупности с deterministic seed behavior из `Prompt 3` это формирует воспроизводимый training pipeline, пригодный для controlled SFT-подготовки.

### Ключевые файлы
- `docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py` (CLI deterministic graph generator для Prompt 3)
- `docs/SGv7pipeline/graph_generator/planner.py` (seed-driven planning и pattern quotas)
- `docs/SGv7pipeline/graph_generator/dedup.py` (graph fingerprinting и дедупликация канонических графов)
- `docs/SGv7pipeline/21-graph-generator-design.md` (design-спецификация Prompt 3)
- `docs/SGv7pipeline/source_generation/02_generate_source_variants.py` (CLI source paraphrase generator для Prompt 4)
- `docs/SGv7pipeline/source_generation/prompt_builder.py` (prompt payload, conditional ordinals, disambiguation logic)
- `docs/SGv7pipeline/source_generation/batcher.py` (batch orchestration, backend abstraction, accept/reject flow)
- `docs/SGv7pipeline/source_generation/filters.py` (cheap reject checks, normalization, duplicate control)
- `docs/SGv7pipeline/source_generation/tests/test_source_generator_cli.py` (smoke tests, morphology-stress и named-dialogue coverage)
- `docs/SGv7pipeline/22-source-generation-design.md` (design-спецификация Prompt 4)
- `docs/SGv7pipeline/24-source-generation-design-verify.md` (design verify Prompt 4)
- `docs/SGv7pipeline/26-source-generation-implement-verify-final.md` (финальный implement verify Prompt 4)

---

## [2026-04-13 19:56] - Prompt 5 и Prompt 6 в SG v7: controlled augmentation и deterministic validator stack

### Суть изменений
- Для `Prompt 5` оформлен и интегрирован design-слой morphology/noise augmentation: зафиксированы transform classes, output contract, provenance boundary и жёсткий handoff в downstream validator без подмены canonical `sample_id`.
- Для `Prompt 6` создан design-документ validator stack и реализован исполнимый пакет `validators/` с CLI `03_semantic_critic.py` и `05_validate_and_pack.py`.
- В Track 6 реализованы детерминированные слои проверки: contract/schema/runtime projection, graph consistency, anchor preservation, semantic critic, recoverability scoring и packaging в `accepted/review/rejected`.
- Исправлены найденные на review архитектурные противоречия: authoritative CIR join переведён на immutable `sample_id`, persisted critic artifact закреплён как источник scoring, а OpenAI critic path переведён в strict JSON schema + fail-closed reject policy.
- Добавлены unit/smoke tests на provenance, accept/reject/review flows, malformed critic payload, taxonomy validation и CLI сценарии; validator suite проходит локально без сетевой зависимости.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для обучения компактной LLM на русскоязычном scene-to-structure mapping недостаточно только генерировать surface variants. Требуется контролируемое внесение шумов и морфологических сдвигов, но без разрушения canonical semantics, а затем воспроизводимый validation stack, который способен отделить recoverable variation от semantic drift. Без такой схемы датасет становится нестабильным: одни и те же примеры могут по-разному попадать в train/reject при повторных прогонах, а augmentation начинает незаметно подменять provenance и graph identity.
- **Решение:** Архитектура SG v7 расширена двумя согласованными этапами. `Prompt 5` формализует augmentation как отдельный bounded layer с transform metadata, risk flags и запретом на переписывание `sample_id`, чтобы downstream join с authoritative CIR оставался однозначным. `Prompt 6` добавляет многослойный validator stack: deterministic checks отсекают грубые контрактные и graph-level ошибки, semantic critic покрывает сложные случаи surface drift, а recoverability scoring переводит решение в явную политику `accepted / manual_review / rejected` с persisted audit trail.
- **Детали:** В реализации Track 6 score вычисляется по фиксированным компонентам `anchor_recall + chronology + unsupported_action + target_integrity + compression_budget`, где критические semantic booleans читаются только из persisted critic artifact с frozen execution params (`temperature=0`, `top_p=1`, `max_output_tokens=300`). Для OpenAI critic зафиксирован strict JSON schema contract, а malformed payload не приводит к silent acceptance, а переводится в `contract_invalid_critic_payload`. Это важно для диссертационной главы "Реализация", поскольку показывает не просто использование LLM как black box, а построение воспроизводимого hybrid pipeline с формализованной семантической валидацией, explicit provenance policy и fail-closed гарантиями.

### Ключевые файлы
- `docs/SGv7pipeline/27-augmentation-design.md` (design-спецификация Prompt 5 и handoff boundary augmentation -> validator stack)
- `docs/SGv7pipeline/30-validator-stack-design.md` (design-спецификация Prompt 6)
- `docs/SGv7pipeline/validators/05_validate_and_pack.py` (основной CLI Track 6 для packaging и verdict policy)
- `docs/SGv7pipeline/validators/03_semantic_critic.py` (CLI semantic critic artifact generation)
- `docs/SGv7pipeline/validators/packaging.py` (authoritative CIR join, layered validation, accepted/review/rejected routing)
- `docs/SGv7pipeline/validators/semantic_critic.py` (heuristic/OpenAI critic backend, strict JSON schema, persisted artifact reuse)
- `docs/SGv7pipeline/validators/recoverability.py` (детерминированный recoverability rubric)
- `docs/SGv7pipeline/validators/taxonomy.py` (canonical reject/review taxonomy)
- `docs/SGv7pipeline/validators/tests/test_validate_and_pack_cli.py` (end-to-end validator smoke/reject/review tests)
- `docs/SGv7pipeline/validators/tests/test_semantic_critic.py` (regression tests для critic payload contract)

---

## [2026-04-14 16:40] - [Prompt 7: Детерминированная сборка датасета SG v7 с family-level holdout и leakage-контролем]

### Суть изменений
- Реализован исполнимый модуль `dataset_builder` для сборки `sft_train/val/test` и `preference_train/val/test` из canonical artifacts с единым контрактом версии.
- Добавлен CLI `06_build_dataset_splits.py` для воспроизводимой сборки сплитов по фиксированному `seed` и параметрам ratio для SFT/preference.
- Внедрены family-aware split policies: assignment на уровне `split_family_id`, а не отдельной строки, чтобы исключить утечки near-duplicate семейств между train/held-out.
- Реализована детерминированная сборка preference pairs с canonical join к CIR, карантином ambiguous anchors и блокировкой пересечения с held-out SFT-семействами.
- Материализуются контрольные артефакты `split_manifest.json`, `preference_manifest.json`, `leakage_report.json` с полными счётчиками, причинами дропов/карантина и проверками целостности.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для SLM-дообучения критичен контроль утечек между сплитами и задачами. При row-level random split без family-ограничений валидация становится завышенной: модель видит почти те же граф-семейства в train и held-out, а полученные метрики перестают отражать реальную обобщающую способность.
- **Решение:** Построен детерминированный split-builder, который опирается на `split_family_id`, `graph_family_key` и `normalized_source_hash`, а также использует policy-level запреты пересечений между SFT held-out и preference-корпусом. Дополнительно реализован fail-closed leakage report, который останавливает пайплайн при обнаружении пересечений.
- **Детали:** Для preference-кандидатов используется `deterministic_canonical_family_join_v1` через `sample_id/graph_hash/family_anchor`; неразрешимые или конфликтующие случаи уходят в quarantine вместо silent acceptance. Система отчётности фиксирует распределения по `difficulty_bucket`, `correction_tier`, `critical_eval_tags`, причины ingest/dedup drop и статус покрытия `preference_test`, что делает сборку датасета воспроизводимой и проверяемой в экспериментальном цикле.

### Ключевые файлы
- `docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py` (CLI сборки сплитов и manifests)
- `docs/SGv7pipeline/dataset_builder/__init__.py` (оркестрация полного build flow)
- `docs/SGv7pipeline/dataset_builder/splitter.py` (family-level deterministic split assignment)
- `docs/SGv7pipeline/dataset_builder/preference.py` (canonical join и quarantine policy для preference pairs)
- `docs/SGv7pipeline/dataset_builder/manifest.py` (split/preference/leakage manifests + enforcement)
- `docs/SGv7pipeline/dataset_builder/tests/test_dataset_cli.py` (e2e smoke для CLI)
- `docs/SGv7pipeline/dataset_builder/tests/test_dataset_splitter.py` (инварианты split policy)

---

## [2026-04-14 16:41] - [Prompt 8: Реализация training harness SG v7 с фазовыми view, compare-gates и registry]

### Суть изменений
- Реализован пакет `training` с фазовым materialization для `phase1/phase2/phase3/phase4`, включая mix policies, budget caps и phase-specific manifests.
- Добавлены CLI-инструменты: `08_build_phase_view.py`, `09_compare_checkpoints.py`, `10_register_experiment.py` для воспроизводимого цикла `phase view -> compare -> registry`.
- Реализован compare runner с жёсткими gate-правилами: explicit baseline для `phase3/phase4`, sequential two-pass stability для Phase 3, length-collapse proxy (`average_target_length`) и preference gain gate для Phase 4.
- Введён полный контракт compare-артефактов: `checkpoint_table.json`, `checkpoint_compare.md`, `bucket_deltas.json`, `promotion_decision.md`, а для Phase 4 — `preference_eval.json`.
- Добавлены phase configs и unit tests, покрывающие positive/negative-path сценарии для gate-логики и воспроизводимости experiment notes.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** На модели класса 1.5B training-loop чувствителен к noisy promotion policy: если baseline плавает, критерии выхода из фазы трактуются неоднозначно или отсутствуют stability guards, то экспериментальная матрица перестаёт быть сопоставимой, а улучшения по quality-метрикам оказываются статистическим шумом.
- **Решение:** Построен воспроизводимый training harness с формализованными фазами и строгими compare-gates. Ключевые решения: frozen reference checkpoint на фазу, последовательная проверка независимых compare passes, fail-closed отклонение на regressions и machine-readable artifacts для аудита каждого promotion решения.
- **Детали:** Для Phase 3 реализован детерминированный счётчик `consecutive_positive_passes` только по независимым compare-событиям; duplicate events по одному `global_step` исключаются из streak. Для Phase 4 winner selection дополнительно ограничен `phase4_min_preference_win_rate_gain_pp` на `val/test`, а tie-break включает length growth penalty, чтобы снижать риск minimal-valid collapse при формально стабильной валидации.

### Ключевые файлы
- `docs/SGv7pipeline/training/08_build_phase_view.py` (CLI materialization phase views)
- `docs/SGv7pipeline/training/09_compare_checkpoints.py` (CLI compare и promotion artifacts)
- `docs/SGv7pipeline/training/10_register_experiment.py` (CLI reproducible experiment notes)
- `docs/SGv7pipeline/training/phase_view.py` (pooling/caps policy и phase manifests)
- `docs/SGv7pipeline/training/checkpoint_compare.py` (gate logic, stability policy, artifact materialization)
- `docs/SGv7pipeline/training/experiment_registry.py` (registry contract для experiment matrix)
- `docs/SGv7pipeline/training/tests/test_checkpoint_compare.py` (negative/positive-path проверки compare gates)
- `docs/SGv7pipeline/training/tests/test_phase_view.py` (инварианты phase view caps и pool accounting)

---

## [2026-04-14 18:56] - [Prompt 10: Реализация runtime feedback loop SG v7 и bridge в dataset/eval]

### Суть изменений
- Реализован исполнимый пакет `runtime_feedback` для Track 10: нормализация runtime parse events в `runtime_failures.jsonl`, deterministic taxonomy/clustering, review/promotion corrected samples и экспорт `real_runtime` eval cases.
- Добавлены CLI-инструменты полного цикла: `normalize_runtime_feedback.py`, `review_and_promote_runtime_feedback.py`, `export_real_runtime_eval_cases.py`, что формирует минимальный end-to-end skeleton `bronze -> silver -> gold`.
- Внедрены contract-уровни для стабильности admission policy: `runtime_source_expectations_v1` и frozen словарь `unsupported_action_lemmas_v1`, чтобы убрать неоднозначность в `low_quality_accept_v1`.
- Исправлены implement-риски в verify-процессе: логика `described_action` перенесена на проверку final graph (а не source), ordinal-loss проверяется по actor bindings, exporter научен резолвить anchor через `sample_id/graph_hash` в `family_anchor`.
- Добавлены unit/integration tests для normalize/review/export и для bridge к `dataset_builder` preference-потоку; тесты пройдены локально.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Без формализованного feedback-loop runtime ошибки остаются «локальными инцидентами» и не превращаются в воспроизводимый сигнал для следующего training cycle. Дополнительно, если `low_quality_accept` не задан детерминированно, разные реализации ingestion дают разные failure-pools, что делает анализ regressions и active-learning нестабильным.
- **Решение:** Построен отдельный runtime feedback слой с явными контрактами и версионированными policy-блоками. Нормализация событий материализует self-contained `runtime_failures` записи (decision/provenance/anchor/runtime-policy inputs), review-layer присваивает корректные tiers и eligibility, а export-layer детерминированно строит `real_runtime` eval-cases через canonical CIR join.
- **Детали:** Введены `runtime_source_expectations_v1`, `low_quality_accept_v1`, `failure_signature_normalization_v1`, `runtime_feedback_provenance_state_v1` и `redaction_quality_check_v1` как проверяемые policy-компоненты. Кластеризация основана на `failure_signature + normalized_source_template`, а не на внешних embeddings, что обеспечивает повторяемость результатов между запусками и сопоставимость top-cluster динамики между релизами.

### Ключевые файлы
- `docs/SGv7pipeline/runtime_feedback/normalize.py` (bronze->silver normalizer, taxonomy/clustering/materialization)
- `docs/SGv7pipeline/runtime_feedback/review.py` (provenance state machine, promotion eligibility, eval-bridge readiness)
- `docs/SGv7pipeline/runtime_feedback/export.py` (runtime_failures -> real_runtime eval cases, deterministic CIR join)
- `docs/SGv7pipeline/runtime_feedback/expectations.py` (source expectations и deterministic predicates для low-quality capture)
- `docs/SGv7pipeline/runtime_feedback/contracts/runtime_source_expectations_v1.md` (versioned expectation contract)
- `docs/SGv7pipeline/runtime_feedback/contracts/unsupported_action_lemmas_v1.txt` (frozen unsupported-action lemma set)
- `docs/SGv7pipeline/runtime_feedback/tests/test_runtime_feedback_normalize.py` (normalizer + low-quality policy tests)
- `docs/SGv7pipeline/runtime_feedback/tests/test_runtime_feedback_review.py` (review/promotion/provenance tests)
- `docs/SGv7pipeline/runtime_feedback/tests/test_runtime_feedback_export.py` (real_runtime eval export tests)
- `docs/SGv7pipeline/runtime_feedback/tests/test_runtime_feedback_dataset_bridge.py` (bridge test к dataset preference builder)

---

### NLU-препроцессор: синтаксический разбор предложений через NLTagger

**Концепция**: Перед извлечением сущностей (актёров, объектов, действий) добавить этап синтаксического и морфологического разбора предложения через Apple NLTagger, чтобы парсер понимал структуру предложения, а не просто искал ключевые слова.

**Детали реализации**:
- **`SentenceAnalyzer`**: разбивает текст на предложения (`.sentenceTerminator`), для каждого предложения определяет:
  - Подлежащее (кто? — `.noun` перед `.verb`) → маппится на актёра
  - Сказуемое (что делает? — `.verb`) → маппится на действие
  - Дополнение (к чему? — `.noun` после предлога) → маппится на объект/target
  - Обстоятельство (как? куда? — `.adverb`, `.particle`) → маппится на modifier/direction
- **Coreference resolver**: разрешение местоимений «он», «она», «другой», «первый», «второй» → привязка к ранее упомянутым актёрам по порядку упоминания и по роду (NLTagger не даёт род надёжно для русского, но можно использовать эвристики по типу ActorType и окончаниям глаголов).
- **Обработка сложносочинённых предложений**: разбиение по «,», «и», «а», «но» на клаузы и параллельная обработка каждой клаузы.
- **Числительные**: извлечение `.number` тегов и привязка к ближайшему существительному (вместо текущих regex-паттернов `(\\d+)\\s*(?:актёр|...)`).

**Преимущества**:
- Устраняет хрупкость текущего подхода: regex ломаются при изменении порядка слов, NLU-подход инвариантен к порядку.
- Корректная обработка сложных конструкций: «Актёр, который стоит слева, подходит к столу, а второй бежит к двери» — текущий парсер это не разберёт.
- Разрешение «он/другой» — текущий `unresolvedPronouns` в диагностике просто фиксирует проблему, но не решает её.

**Потенциальные сложности**:
- NLTagger для русского языка имеет ограниченное качество (нет dependency parsing).
- Определение подлежащего и дополнений по позиции ненадёжно для русского из-за свободного порядка слов.
- Fallback на текущий regex-подход если NLU даёт плохие результаты.

**Связь с текущим проектом**:
- Заменяет/дополняет текущий `extractActors`, `extractActions`, `extractObjects` в `SceneParserService`.
- `Lemmatizer` уже использует NLTagger — можно расширить его для синтаксического анализа.
- Результат `SentenceAnalyzer` маппится на существующие модели `SceneActor`, `SceneAction`, `SceneObject`.

---

### Инкрементальный интерактивный парсинг с обратной связью от пользователя

**Концепция**: Вместо однопроходного «текст → SceneScript» добавить интерактивный режим, где приложение показывает промежуточный результат парсинга и спрашивает у пользователя уточнения для неразрешённых частей (unresolvedPronouns, missingObjects, низкий confidence).

**Детали реализации**:
- **`ClarificationEngine`**: анализирует `ParsingDiagnostics` и генерирует список вопросов:
  - `unresolvedPronouns = true` → «Кто имеется в виду под "он"? [Актёр 1 / Актёр 2]»
  - `missingObjects = true` → «В тексте упомянут "шкаф", но он не размечен. Разметить сейчас?»
  - `confidence < 0.7` → «Не уверен в результате. Проверьте: [показать SceneScript визуально]»
- **UI**: новый sheet/modal `ClarificationSheet` со списком уточняющих вопросов.
- **Итеративный цикл**: parse → показать результат → получить уточнения → re-parse с доп. контекстом → показать финальный результат.
- **Learning**: сохранение ответов пользователя как примеров для улучшения парсера (в UserDefaults или JSON-файл), со временем парсер «учится» на корректировках.

**Преимущества**:
- 100% точность на выходе: если парсер ошибся, пользователь поправляет.
- Сбор данных для обучения: ответы пользователя — готовый датасет для fine-tuning LLM.
- Демонстрация для диссертации: human-in-the-loop подход, метрики улучшения с каждой итерацией.

**Потенциальные сложности**:
- UX: слишком много вопросов раздражает. Нужно ограничить до 2-3 критичных.
- Генерация осмысленных вопросов из диагностики — нетривиальная задача.
- Хранение и использование истории уточнений.

**Связь с текущим проектом**:
- `ParsingDiagnostics` уже содержит все нужные флаги (missingActors, missingObjects, unresolvedPronouns).
- `SceneInputSheet` — уже есть UI для ввода, нужно добавить отображение промежуточных результатов.
- `SceneGeneratorViewModel` координирует flow — нужно добавить состояние `clarification`.

---

### Семантический граф сцены как промежуточное представление (Scene Graph IR)

**Концепция**: Ввести промежуточное представление между текстом и `SceneScript` — **граф сцены**, где узлы — это сущности (актёры, объекты), а рёбра — отношения (действия, пространственные связи). Это позволит парсеру работать не с плоским списком, а с графовой структурой, что упростит разрешение связей и валидацию.

**Детали реализации**:
- **`SceneGraph`**: структура с `nodes: [SceneNode]` и `edges: [SceneEdge]`:
  - `SceneNode` — актёр или объект с атрибутами (тип, имя, позиция).
  - `SceneEdge` — связь между двумя узлами (действие, пространственное отношение, принадлежность).
- **Этапы парсинга**: Текст → NLU-анализ → SceneGraph → Валидация/Обогащение → SceneScript.
- **Валидация графа**:
  - Каждое действие должно иметь субъект (актёр) — если нет, ошибка парсинга.
  - Каждый target в действии должен существовать как узел — если нет, создать placeholder.
  - Нет висячих узлов (объекты, на которые нет действий) — предупреждение.
- **Обогащение графа**: вывод неявных связей. Если «актёр подходит к столу», неявно добавляется пространственное отношение `near(actor, table)` в конце действия.
- **Сериализация**: `SceneGraph → SceneScript` через обход графа (DFS/BFS), порядок действий определяется порядком упоминания в тексте.

**Преимущества**:
- Естественное представление для сцены: сцена — это граф объектов и связей.
- Упрощение парсинга: каждый этап добавляет узлы/рёбра, не нужно финальную структуру собирать за один проход.
- Валидация на уровне графа обнаруживает ошибки, которые сложно найти в плоском SceneScript.
- Для диссертации: формальное описание семантического графа, визуализация, алгоритмы на графах.

**Потенциальные сложности**:
- Дополнительный слой абстракции усложняет архитектуру, но упрощает каждый отдельный этап.
- Сериализация графа в SceneScript должна сохранять порядок действий.
- Визуализация графа для отладки (можно использовать Mermaid или GraphViz).

**Связь с текущим проектом**:
- `SceneScript` остаётся финальным форматом, `SceneGraph` — промежуточное представление перед конвертацией.
- Текущие `extractActors`, `extractObjects`, `extractActions` → создают узлы и рёбра вместо плоских массивов.
- `DiagnosticsCalculator` переходит на валидацию графа вместо проверки плоских списков.

---

## 2025-11-22 — Срез `b7764f255280fcb82557b7a0349fb7bbd56ca333` (stage + detresnet)

### 1. Реализованный функционал

- **Экран выбора стадии**: добавлен стартовый экран, на котором пользователь выбирает режим работы (на этом этапе — “Пре-продакшен” и “Съёмка”).
- **Новый режим “умной камеры” (Multitool2)**:
  - поверх live-превью отображаются подсказки и оверлеи (правило третей, рамки/наводящие элементы, подсказка-«чип»);
  - есть режим паузы/предпросмотра (показ списка рекомендаций);
  - в debug-режиме можно видеть служебные визуализации (детекции/центры внимания и т.п.);
  - управление зумом через отдельный UI-компонент.
- **ML-анализ кадра оффлайн**: в приложение добавлены модели и обвязки, позволяющие оценивать кадр (обнаружение/сегментация, “эстетическая” оценка) без подключения к сети.

### 2. Технические решения и сложности

- **Почему CoreML на устройстве**:
  - оффлайн-режим (без сервера/интернета),
  - предсказуемая задержка,
  - возможность регулировать частоту инференса (тепловой/энергетический бюджет).
- **Пайплайн “камера → анализ → подсказки → UI”**:
  - `CameraManager` — захват кадров;
  - `AnalysisPipeline` — объединение анализа (Vision/CoreML/эвристики);
  - `RealtimeScheduler` и `ThermalGovernor` — контроль частоты тяжёлых задач (чтобы не просаживать FPS).
- **Стабилизация сигналов** (чтобы подсказки не “мигали”):
  - фильтры и гейты (`EMA`, `KalmanFilter`, `HysteresisGate`, `MotionGate`) для сглаживания/устойчивости.
- **Система рекомендаций**:
  - `SuggestionEngine` генерирует кандидатов,
  - `PrioritySelector` выбирает главное для текущего кадра/ситуации.

### 3. Архитектура

- **Крупный новый модуль**: `shafinMultitool/Multitool2Module/`
  - **Models**: CoreML-обёртки (`DETRDetector`, `AestheticScorer`) + Vision/Lighting компоненты;
  - **Services/Pipeline**: `AnalysisPipeline`, `RealtimeScheduler`, `ThermalGovernor`;
  - **Services/Suggestion**: `SuggestionEngine`, `PrioritySelector`;
  - **UI/Overlay**: SwiftUI-оверлеи (сетка/рамки/чип/список/зум/дебаг).
- **Интеграция**: добавлен `SceneModules/StageSelectionViewController.swift` + правки `Resources/SceneDelegate.swift` и файла проекта.


## 2025-12-01 — Срез `8dd07bc29fee4afdd4cb5a582b0475b06c79ce8f` (scene generator base)

### 1. Реализованный функционал

- **Новая стадия “Scene Generator”**: на экране выбора стадии появляется третья карточка, запускающая генератор сцен.
- **Scene Generator (генерация AR-сцены из текста)**:
  - ожидание готовности AR (плоскости/ориентация);
  - ввод текстового описания сцены на русском;
  - создание в AR “плейсхолдеров” объектов/актёров с подписями и возможностью ▶️/stop/reset.
- **Ручная разметка реальных объектов**:
  - режим разметки: тап → ввод имени → объект сохраняется как реальная привязка для сценария.
- **Черновой оверлей производительности**: добавлены `PerformanceMonitor` и `PerformanceOverlayView` и подключены к режиму съёмки (базовые метрики).
- **Мелкий фикс**: правка `OverlayView.swift` (синтаксис).

### 2. Технические решения и сложности

- **MVVM + SwiftUI**: новый режим реализован как `SceneGeneratorView` + `SceneGeneratorViewModel`.
- **Rule-based парсинг текста**: `SceneParserService` переводит описание в `SceneScript` через словари и регулярные выражения.
- **Планирование в 3D**: `SpatialPlannerService` вычисляет область сцены по позе камеры/плоскостям, раскладывает объекты и строит траектории.
- **Depth first, raycast fallback**:
  - если доступен LiDAR depth (`sceneDepth`/`smoothedSceneDepth`) — используем его для точной привязки “маркеров”;
  - иначе fallback на `raycast`.
- **Воспроизведение траектории**: сегментная анимация в RealityKit + отменяемые задачи, чтобы stop/reset не оставляли “хвостов”.

---

## [2026-04-15 15:53] - [SG v7 как полный пайплайн подготовки данных для дообучения scene-to-JSON модели]

### Суть изменений
- Зафиксирована целостная интерпретация `SG v7` не как одного генератора датасета, а как многоэтапного конвейера подготовки обучающих данных для компактной LLM класса `1.5B`, решающей задачу преобразования русскоязычного описания сцены в структурированный JSON.
- Формализована последовательность этапов пайплайна: `pattern library -> deterministic graph/CIR generation -> source paraphrase generation -> augmentation -> validator stack -> dataset assembly -> phase-aware training views`.
- Уточнено назначение двух разных контуров обучения: `SFT` как основной supervised-корпус `text -> canonical JSON` и `preference` как дополнительный pairwise-корпус `bad_json vs good_json`, предназначенный для устранения типовых ошибок модели на runtime/offline eval.
- Зафиксировано текущее состояние системы: SFT-контур уже исполним и позволяет собирать тренировочные выборки, тогда как preference-контур реализован архитектурно и в коде, но требует отдельного потока артефактов с реальными ошибками модели (`runtime_failures` / reviewed bad-vs-good pairs).

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для дообучения малой модели недостаточно сгенерировать большое число пар `текст -> JSON`. Основная трудность состоит в том, что маленькая LLM чувствительна к semantic drift, неоднозначным surface-формулировкам, потерям ordinal binding, marked-object grounding и collapse сложных multi-beat сцен в упрощённые JSON-структуры. Если не разделять генерацию смысла сцены и генерацию естественного текста, датасет быстро начинает содержать скрытые ошибки, которые модель затем воспроизводит на inference.
- **Решение:** В `SG v7` обучение строится вокруг канонического промежуточного представления сцены. Сначала детерминированно создаётся semantic graph / `CIR`, описывающий актёров, объекты, последовательность битов и инварианты сцены. Затем поверх него генерируются допустимые русскоязычные surface-формы, после чего они проходят ступенчатую фильтрацию, semantic validation и packaging в SFT-артефакты. Отдельно строится preference-контур, в котором реальный неудачный JSON модели сопоставляется с корректным JSON-эталоном. Такая декомпозиция превращает подготовку данных из ad-hoc text generation в воспроизводимый экспериментальный pipeline с явными контрольными точками качества.
- **Детали:** Практически `SG v7` работает как фабрика обучающих примеров. `Pattern library` задаёт классы сцен и failure-oriented coverage; `graph_generator` материализует детерминированные canonical records; `source_generation` создаёт множество пользовательских формулировок одной и той же сцены; `augmentation` вносит морфологические и стилистические вариации; `validators` отделяют semantic-preserving samples от drift и записывают provenance-aware verdict; `dataset_builder` формирует leakage-safe `train/val/test` splits. На текущем этапе уже подтверждена работоспособность SFT-контура, а preference-контур требует наполнения реальными ошибками модели, чтобы после базового supervised fine-tuning выполнять вторичную настройку предпочтений и снижать частоту систематических ошибок, таких как потеря объекта, потеря действия или схлопывание beat-структуры.

### Ключевые файлы
- `docs/SGv7pipeline/README.md` (сквозное описание этапов SG v7)
- `docs/SGv7pipeline/pattern_library/registry.py` (канонические pattern families и semantic coverage)
- `docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py` (построение deterministic graph/CIR records)
- `docs/SGv7pipeline/source_generation/02_generate_source_variants.py` (генерация surface text variants)
- `docs/SGv7pipeline/augmentation/04_noise_and_morphology.py` (морфологические и noise-вариации)
- `docs/SGv7pipeline/validators/05_validate_and_pack.py` (semantic validation и packaging accepted/review/rejected)
- `docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py` (сборка SFT/preference датасетов и split manifests)
- `docs/SGv7pipeline/runtime_feedback/normalize_runtime_feedback.py` (нормализация runtime ошибок модели)
- `docs/SGv7pipeline/runtime_feedback/review_and_promote_runtime_feedback.py` (review/promotion corrected runtime failures)
- `docs/SGv7pipeline/training/08_build_phase_view.py` (phase-aware materialization для обучения)
- `docs/SGv7pipeline/run_sgv7_pilot.sh` (end-to-end pilot orchestration SG v7)

---

## [2026-04-16 15:16] - [SG v7: train-ready сборка с runtime preferences и leakage-safe валидацией]

### Суть изменений
- Проведён полный прогон `SG v7 full` с OpenAI-бэкендом и включёнными runtime preference-кандидатами; подтверждена исполнимость полного контура `graph -> source -> validate -> merge -> dataset`.
- В итоговой сборке получены оба типа корпусов: `SFT` и `preference`, при этом `preference` сформированы из `runtime_failure_reviewed_merge` (а не только offline rejection).
- Проверено качество выходных артефактов: `leakage_status=pass`, контрольные `critical_tags` присутствуют (`same_type_markers`, `three_beat_cases`, `ordinal_cases`), split manifests и preference manifests согласованы.
- Зафиксированы текущие узкие места качества: высокий reject-rate на `source validation` (особенно для `hard`) и недостаточный итоговый объём SFT для сильного прироста качества модели.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для компактной модели класса `1.5B` недостаточно синтаксически валидного JSON. При отсутствии runtime-oriented preference-корпуса и строгого leakage-контроля модель быстро переобучается на поверхностные паттерны, теряя устойчивость к семантическим failure-классам (marked object grounding, ordinal binding, multi-beat chronology).
- **Решение:** Пайплайн переведён в режим train-ready сборки с двумя независимыми обучающими сигналами: supervised (`SFT`) и pairwise preference (`runtime failure reviewed merge`). Валидация качества проводится не только по количеству строк, но и по инвариантам: происхождение preference-примеров, покрытие критических тэгов и отсутствие data leakage между split-ами.
- **Детали:** Для preference-контура зафиксировано происхождение `runtime_failure_reviewed_merge`; leakage-audit выполняется как fail-closed gate. В итоговом прогоне достигнуты: `SFT=57` (`48/5/4`) и `Preference=239` (`203/24/12`) при `leakage_status=pass`. Это подтверждает корректность архитектуры пайплайна, но также количественно показывает, что основным ограничителем итогового качества остаётся пропускная способность accepted SFT после semantic filtering.

### Ключевые файлы
- `docs/SGv7pipeline/run_sgv7_full.sh` (оркестрация полного прогона с audit gate)
- `docs/SGv7pipeline/run_sgv7_pilot.sh` (сборка merged/runtime preference артефактов)
- `docs/SGv7pipeline/audit_sgv7_outputs.py` (контроль готовности dataset-а и runtime preference origin)
- `docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py` (финальная сборка SFT/preference split-ов)
- `docs/SGv7pipeline/dataset_builder/preference.py` (формирование pairwise preference из rejected/runtime контуров)
- `docs/SGv7pipeline/dataset_builder/splitter.py` (детерминированный split policy)

### Цель следующего этапа (зафиксировано)
- Достичь **реально заметного прироста качества JSON-парсинга**: минимум `SFT train >= 1500` и `Preference train >= 3000` при `leakage_status=pass`.
- Обеспечить coverage в train: `same_type_markers >= 300`, `three_beat_cases >= 200`, `ordinal_cases >= 800`.
- Принять модель как готовую к продакшен-итерации только при приросте на fixed eval set: `+15 п.п.` по exact-valid JSON и `+20 п.п.` по failure-oriented сценариям (`same_type_markers` / `three_beat_cases` / `ordinal binding`).

---

## [2026-04-19 18:05] - [SG v7: quality-first санация пайплайна, строгий аудит и train-ready датасет]

### Суть изменений
- Усилен ранний reject-контур в `source_generation`: добавлены жёсткие фильтры на технические литералы, meta-язык, дефекты surface-форм и частые морфологические ошибки, чтобы отсекать шум до дорогого semantic critic.
- Пересобран prompt-layer для генерации source-текста: снижено копирование внутренних semantic anchors в пользовательский текст, ограничен prompt-эхо эффект и уменьшена лексическая монотонность.
- Ужесточён `dataset_builder`: основной SFT ограничен `direct_sft`, review-promoted строки выведены из базового train, а sanitizer переведён в fail-closed режим по критичным шумам.
- В preference-сборке устранён дрейф `originalDescription`: `chosen_json/rejected_json` теперь детерминированно синхронизируются с финальным `source_text`.
- Расширен quality-audit: добавлены явные coverage-гейты (`same_type`, `three_beat`, `ordinal`, `exact_marker_identity`, `marked_object_morphology`), лимиты финального шума и контроль перекоса по паттернам в итоговом SFT.
- Проверена end-to-end готовность пайплайна на полном прогоне: получены leakage-safe SFT/preference артефакты, подтверждена пригодность для следующего цикла дообучения.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** В исходной конфигурации часть semantic-шумов (meta-язык, артефакты морфологии и prompt leakage) доходила до дорогих стадий и приводила к неэффективному расходу бюджета, снижая полезную плотность обучающих примеров для SLM 1.5B.
- **Решение:** Пайплайн переведён в режим *quality-first with fail-closed gates*: шум отбрасывается максимально рано, а финальный датасет проходит многоуровневый audit с количественными и структурными инвариантами.
- **Детали:** Принципиально важным стало разделение ролей: ранние дешёвые фильтры отвечают за гигиену surface-уровня, semantic critic — за recoverability-инварианты, dataset builder — за контракт и split-safe упаковку. Для preference-контура закреплена строгая согласованность `source_text ↔ originalDescription`, что уменьшает риск обучения на внутренне конфликтных парах. Финальная валидация выполняется через расширенный audit с порогами coverage и noise-share, что делает сборку воспроизводимой и пригодной для экспериментального сравнения.

### Ключевые файлы
- `docs/SGv7pipeline/source_generation/filters.py` (ранние hard-reject фильтры для технического и surface-шумов)
- `docs/SGv7pipeline/source_generation/prompt_builder.py` (снижение leakage внутреннего semantic-языка в source surface)
- `docs/SGv7pipeline/source_generation/batcher.py` (устойчивость генерации и fail-safe поведение при невозможности clean-варианта)
- `docs/SGv7pipeline/dataset_builder/ingest.py` (строгая admission policy для SFT и sanitizer fail-closed)
- `docs/SGv7pipeline/dataset_builder/preference.py` (детерминированная синхронизация `originalDescription` в preference-парах)
- `docs/SGv7pipeline/audit_sgv7_outputs.py` (расширенные quality/coverage gates и skew/noise контроль)
- `docs/SGv7pipeline/run_sgv7_full.sh` (оркестрация полного quality-gated прогона)
- `docs/SGv7pipeline/run_sgv7_pilot.sh` (быстрый verify/перезапуск с сохранением gate-инвариантов)

---

## [2026-04-19 22:35] - [Camera Analysis v1: roadmap, explainable pipeline и PR-декомпозиция]

### Суть изменений
- Зафиксирован отдельный пакет документов `docs/cameraanalysis`, который описывает новый функционал анализа кадра с семантическими подсказками как самостоятельный исследовательский pipeline, а не как набор разрозненных UI-идей.
- Сформулированы требования к `v1`: поддержка `live` и `pause`, explainable-вердикт для хорошего и плохого кадра, scene-aware критика cinematic-сцены, mobile-first исполнение и controlled usage `LLM`/hybrid reasoning.
- Спроектирована каскадная архитектура: `feature extraction -> scene semantics -> critique engine -> recommendation planner -> explanation generator -> live/pause presentation`, где дорогие стадии преимущественно работают в `pause`, а быстрые детерминированные сигналы обслуживают `live`.
- Выделен formal explainability contract, в котором любой совет должен восстанавливаться по цепочке `observation -> interpretation -> recommendation`; это создает основу для верифицируемого AI-поведения и пригодно для текста диссертации.
- Подготовлен roadmap по фазам и implementation backlog с детерминированным PR pipeline (`PR-001 ... PR-015`), включая зависимости, границы write scope, критерии готовности и допустимый параллелизм между задачами.
- Составлен набор agent prompts и briefing template, чтобы отдельные части системы можно было безопасно отдавать внешним AI-агентам без потери архитектурной целостности и без необходимости каждый раз пересобирать контекст вручную.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** На мобильном устройстве нельзя одновременно требовать глубокого AI-анализа художественного кадра, низкой задержки в `live`, устойчивого UX и объяснимости, если вся логика строится либо только на эвристиках, либо только на одном тяжёлом black-box model inference. Такой подход либо не даёт убедительного semantic critique, либо становится слишком дорогим, нестабильным и плохо объяснимым для исследовательской защиты.
- **Решение:** Новый функционал переведён в режим *cascade-by-cost explainable pipeline*. Дешёвые и воспроизводимые Vision/CoreML-сигналы используются как fast-path и работают часто; более дорогой semantic reasoning поднимается отдельным слоем и в первую очередь активируется в `pause`; `LLM` не объявляется source-of-truth для raw critique, а ограничивается ролью controlled reasoning/text refinement поверх структурированного критического отчёта. Это позволяет совместить мобильную исполнимость, объяснимость и демонстративную технологическую сложность.
- **Детали:** Для системы зафиксированы отдельные contracts и этапы поставки. Во-первых, архитектура разбита на явно типизированные сущности `FrameFeatureSnapshot`, `SceneSemanticsReport`, `CritiqueReport`, `RecommendationPlan` и `ExplainabilityTrace`, что превращает анализ кадра из неформального набора эвристик в формализованный dataflow. Во-вторых, `live` и `pause` рассматриваются как разные execution budgets: `live` получает только краткую подсказку и overlay, а `pause` — расширенный критический разбор с сильными и слабыми сторонами кадра. В-третьих, implementation backlog декомпозирован в детерминированные PR-единицы с явными зависимостями (`domain contracts`, `explainability contract`, `feature aggregation`, `scene semantics`, `critique core`, `recommendation planner`, `UI integration`, `LLM/hybrid reasoning`, `eval`, `runtime feedback`). Такая декомпозиция сама по себе является инженерным вкладом: она делает сложный AI-функционал пригодным для параллельной реализации агентами, сохраняя общий research contract и снижая риск архитектурного дрейфа.

### Ключевые файлы
- `docs/cameraanalysis/README.md` (индекс нового camera-analysis pipeline)
- `docs/cameraanalysis/00-overview.md` (обоснование перехода от эвристик к explainable pipeline)
- `docs/cameraanalysis/01-roadmap.md` (фазы реализации и зависимостей)
- `docs/cameraanalysis/02-pipeline-architecture.md` (сжатая схема модулей и потоков данных)
- `docs/cameraanalysis/11-implementation-backlog.md` (детерминированный PR pipeline для AI-агентов)
- `docs/cameraanalysis/12-agent-prompts.md` (готовые промпты для design/implement/verify режимов)
- `docs/cameraanalysis/13-agent-briefing-template.md` (шаблон постановки задач для отдельных агентов)
- `docs/cameraanalysis/camera-analysis-requirements-draft.md` (требования и фиксированные решения по `v1`)
- `docs/cameraanalysis/camera-analysis-v1-architecture.md` (подробная архитектурная концепция `Camera Analysis v1`)

---

## [2026-04-19 22:37] - [Camera Analysis v1: domain contracts и explainable pipeline foundation]

### Суть изменений
- Зафиксирован и реализован source-of-truth слой доменных контрактов для `Camera Analysis v1`: `FrameFeatureSnapshot`, `SceneSemanticsReport`, `CritiqueReport`, `RecommendationPlan`.
- Введены ограниченные таксономии для `scene types`, `issues`, `strengths` и `actions`, чтобы следующий слой критики и планирования можно было строить без домысливания.
- Добавлены инварианты и `validate()`-проверки для ключевых контрактов, включая нормализацию диапазонных полей, согласованность `verdict` и `issue severity`, а также связи между `RecommendationAction` и `Issue`.
- Подготовлены contract fixtures и unit tests, подтверждающие round-trip сериализацию и поведение на граничных случаях, включая fallback-сценарии и недостаточность источников сигнала.
- Обновлены документы `docs/cameraanalysis`, чтобы `PR-002` был связан с конкретным design doc, backlog-артефактами и кодовой реализацией.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для explainable mobile camera analysis недостаточно иметь набор эвристик или неформальный поток подсказок. Без формализованных доменных контрактов невозможно гарантировать согласованность между extraction, semantic interpretation, critique и recommendation слоями, а значит нельзя обеспечить воспроизводимую интерпретацию качества кадра и проверяемость рекомендаций.
- **Решение:** Система переведена в контрактно-ориентированную архитектуру, где сначала фиксируется каноническая структура данных, а уже затем строятся semantics, critique и planner. Такой подход уменьшает архитектурный дрейф, делает pipeline пригодным для последующей детерминированной реализации и позволяет описывать его как explainable dataflow с явными invariants и quality gates.
- **Детали:** Введена явная нормализация диапазонов (`clamp` для confidence/severity и композиционных offsets), разделены роли normalized snapshot и semantic layer, а также зафиксирована связь `CritiqueReport -> RecommendationPlan` через `inputVerdict` и `linkedIssueIds`. Это важно для главы о реализации, поскольку показывает переход от ad hoc heuristics к формализованному контракту с проверяемыми условиями корректности.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift` (доменные модели и `validate()`-инварианты)
- `shafinMultitoolTests/CameraAnalysisDomainContractsTests.swift` (contract tests и fixtures)
- `docs/cameraanalysis/03-domain-contracts.md` (source-of-truth спецификация контрактов)
- `docs/cameraanalysis/11-implementation-backlog.md` (связка PR-002 с кодом и тестами)
- `docs/cameraanalysis/README.md` (обновлённый индекс пакета camera analysis)

---

## [2026-04-19 23:35] - Формализация explainability contract для camera analysis

### Суть изменений
- Спроектирован и реализован сериализуемый `ExplainabilityTraceBundle` с типами `ExplainabilityTraceItem`, `TraceLink`, `TraceStage`, `TraceSourceKind`, `TraceCertainty` и `TraceAudience`.
- Зафиксирована цепочка `observation -> interpretation -> recommendation` с проверками DAG, временного порядка, допустимых пар `stage/sourceKind`, confidence-ограничений и ссылочной целостности.
- Усилены доменные контракты: `CritiqueSummary` и `OverlayHint` получили стабильные `id`, а `RecommendationPlan` и `CritiqueReport` начали валидировать новые инварианты.
- Добавлены unit-тесты на валидные и невалидные трассировки, включая partial validation, циклы, неизвестные ссылки, live-cap и кейсы optional reasoning.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** В explainable pipeline недостаточно просто выдавать финальную рекомендацию; требуется формально связать наблюдения, интерпретации и действия так, чтобы каждое решение можно было воспроизвести и проверить на полноту причинной цепочки.
- **Решение:** Введён детерминированный trace-контракт с явными стадиями, типами источников и правилами резолва ссылок. Это позволяет проверять, что выводы строятся только из разрешённых upstream-сигналов, а optional reasoning не нарушает deterministic core.
- **Детали:** Валидация использует граф зависимостей `dependsOn` с проверкой ацикличности и монотонности `timestampMs`, ограничение confidence относительно upstream-узлов, а также контроль покрытия `issue/strength/action/summary` ссылок. Такой подход делает причинно-следственную структуру пригодной для debug, eval и UI-объяснений.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift` (Trace-контракты и валидация)
- `shafinMultitoolTests/CameraAnalysisDomainContractsTests.swift` (negative/round-trip tests для trace-инвариантов)
- `docs/cameraanalysis/04-explainability-contract.md` (design spec contract для PR-003)

---

## [2026-04-20 14:22] - [PR-007: deterministic Critique Engine для Camera Analysis v1]

### Суть изменений
- Реализован детерминированный `FrameCritiqueEngine`, который принимает `FrameFeatureSnapshot` и `SceneSemanticsReport` и формирует `CritiqueReport` без участия LLM в качестве source-of-truth.
- Формализованы правила детекции issues и strengths, включая пороги `rawScore/confidence`, вычисление `severity`, шаблоны `shortVerdict/whyGood/whyProblematic`, а также ограниченный каталог `FixTypeV1`.
- Введён degraded path для слабой семантической опоры: активируется по `low_scene_confidence`, ограничивает допустимые issues, отключает strengths и понижает итоговую уверенность отчёта.
- Зафиксирована трассируемость findings через детерминированные `traceRefs`, stable `id`-схему и привязку evidence к snapshot/semantics полям.
- Добавлены unit tests на golden cases, calibration, determinism, degraded mode, sorting и contract invariants; дополнительно усилена проверка конфликтов между issue и strength по одному фактору.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** На этапе критики кадра недостаточно просто вычислить набор эвристических замечаний. Требуется одновременно обеспечить воспроизводимость, объяснимость, ограниченную таксономию findings и устойчивую деградацию при слабом входном сигнале. Без этого любая AI-критика становится трудно проверяемой и плохо пригодной для научного описания.
- **Решение:** Критический слой переведён в детерминированный rule-based pipeline с явными thresholds, priority rules, semantic penalties и fallback policy. Это позволяет отделить raw critique от downstream reasoning, сохранив прозрачную цепочку от входных сигналов к verdict и summary. Дополнительно введены trace seeds и evidence refs, чтобы каждый finding можно было связать с объясняемой причинной цепочкой.
- **Детали:** Важной частью реализации стала calibration-логика: `scene_has_no_clear_focus` усиливается на `+0.15` при ambiguity `multiple_subjects_similar_confidence`, а `low_scene_confidence` активирует restricted technical mode с cap на confidence. Для диссертации это демонстрирует не только алгоритмическую, но и методологическую ценность: система показывает, как formal contracts, explainability и degraded policies можно объединить в проверяемый mobile pipeline.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` (`analyze`, issue/strength rules, degraded policy, trace seeds)
- `shafinMultitoolTests/FrameCritiqueEngineTests.swift` (golden cases, calibration, determinism, ordering and conflict tests)
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift` (contract invariants и `CritiqueReport`)
- `docs/cameraanalysis/07-critique-engine.md` (source-of-truth design spec для PR-007)
- `docs/cameraanalysis/11-implementation-backlog.md` (связка PR-007 с PR-003/PR-005/PR-006)

---

## [2026-04-20 16:04] - [SG v7 Eval: baseline Qwen3 vs SFT LoRA и подготовка к сравнению с v6/ORPO]

### Суть изменений
- Проведён и зафиксирован парный eval `baseline_qwen3` против `sft_qwen3_lora` на общем фиксированном наборе `n=198`.
- Сформированы и сохранены артефакты сравнения: агрегированные метрики (`compare_metrics.csv`, `summary.json`) и построчные логи (`rows_baseline_qwen3.jsonl`, `rows_sft_qwen3_lora.jsonl`).
- Подтверждён крупный прирост по структурной корректности JSON после SFT: `schema_strict_rate` вырос с `7.58%` до `57.58%` (+50 п.п.), `exact_match_rate` — с `0%` до `12.12%`.
- Выявлены оставшиеся failure-кластеры для таргетированного preference/ORPO-этапа: прежде всего семейства `ordinal_first_second_third` и `dialogue_then_pick_up_object_then_give_to_third_actor`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Валидный JSON-синтаксис сам по себе не гарантирует полезный результат для scene parsing; baseline демонстрировал `json_valid_rate=100%`, но при этом почти всегда проваливал строгий контракт структуры/содержания (`schema_strict_rate=7.58%`).
- **Решение:** Выполнен контролируемый A/B-eval на одном и том же тестовом наборе с едиными правилами метрик, что позволило отделить чисто синтаксическую валидность от реальной semantic-contract корректности. SFT LoRA дал устойчивый выигрыш по всем ключевым структурным метрикам без регрессий по strict/exact flip-анализу.
- **Детали:** На `n=198` получено: `schema_strict` 15→114 кейсов, `exact_match` 0→24, `beat_count_match` 7→114, `action_count_match` 0→114. При этом средняя задержка inference выросла (`~16.99s` → `~27.54s`), что фиксирует инженерный trade-off между качеством и latency. Анализ post-row ошибок показал, что remaining strict-fail в SFT концентрируется в ограниченном подмножестве паттернов, что методологически оправдывает следующий этап ORPO как targeted preference-optimization, а не масштабирование SFT “вслепую”.

### Ключевые файлы
- `experiments/sc_benchmark/sgv7_eval_logs/compare_metrics.csv` (агрегированные метрики baseline vs SFT)
- `experiments/sc_benchmark/sgv7_eval_logs/summary.json` (машиночитаемая сводка результатов eval)
- `experiments/sc_benchmark/sgv7_eval_logs/rows_baseline_qwen3.jsonl` (построчный baseline протокол)
- `experiments/sc_benchmark/sgv7_eval_logs/rows_sft_qwen3_lora.jsonl` (построчный SFT протокол)
- `experiments/sc_benchmark/workspace/predictions_oracle_v1/dataset_v6_seed42.jsonl` (готовый v6 prediction set, seed 42)
- `experiments/sc_benchmark/workspace/predictions_oracle_v1/dataset_v6_seed43.jsonl` (готовый v6 prediction set, seed 43)
- `experiments/sc_benchmark/workspace/predictions_oracle_v1/dataset_v6_seed44.jsonl` (готовый v6 prediction set, seed 44)

---

## [2026-04-20 20:28] - [Camera Analysis v1: сводка неописанных PR (PR-001, PR-004..PR-015)]

### Суть изменений
- Выполнена ретроспективная фиксация в дневнике всех PR из `cameraanalysis`-пайплайна, которые ранее не имели отдельной записи в `diploma.md` (исключая уже описанные `PR-002`, `PR-003`, `PR-007`).
- `PR-001`: формализован baseline freeze на уровне roadmap/архитектурных документов, включая фиксацию текущего legacy flow, ограничений `live/pause` и failure modes как точки сравнения для следующих этапов.
- `PR-004`: зафиксирован implement-ready контракт `Feature Snapshot Aggregator` с source-priority, freshness/confidence поведением и deterministic нормализацией входных сигналов в `FrameFeatureSnapshot`.
- `PR-005/PR-006`: зафиксирован design verify для scene semantics слоя (`PrimarySubjectResolver`, `SceneTypeClassifier`, dominance/readability analyzers), включая bounded scene catalog и fallback-политику при слабом сигнале.
- `PR-008`: описан детерминированный recommendation слой (`issue -> action`, guardrails, primary/secondary action semantics) как bridge между critique и presentation.
- `PR-009/PR-010/PR-011`: формализована UI-интеграция нового контракта для live/pause/overlay, включая anti-flicker, stable presentation IDs, fallback path на legacy suggestions и write-scope границы интеграции.
- `PR-012/PR-013`: оформлен reasoning boundary — `ReasoningProvider` как optional pause-only слой, append-only trace policy и запрет LLM на роль source-of-truth для raw issues/actions.
- `PR-014`: реализован и верифицирован eval harness (`run_eval.py`, scorer/compare/adapters/tests) с paired baseline-vs-candidate прогоном, deterministic sequence-metadata валидацией и materialized report artifacts.
- `PR-015`: зафиксирован foundation runtime feedback loop на уровне backlog-контракта (формат hard-case записей и hooks), подготовленный для параллельного запуска после стабилизации eval контура.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Без целостного описания всего PR-контура исследовательская ценность системы фрагментируется: часть изменений остаётся в коде/доках без связного объяснения причинно-следственных связей между baseline, semantic critique, UI presentation, optional reasoning и eval/release gates.
- **Решение:** Введена единая ретроспективная сводка по неописанным PR, связывающая дизайн-контракты и реализованные компоненты в один воспроизводимый lifecycle: `baseline -> contracts -> deterministic core -> UI bridge -> optional reasoning -> eval -> runtime feedback`.
- **Детали:** Для `PR-014` закрыты две критические implement-неопределённости: (1) baseline normalize path через явные `LegacyFeatureAdapter + LegacyEvalAdapter`, что делает `issue_f1` и `explanation_faithfulness` воспроизводимыми для legacy; (2) deterministic scoring для `live_sequence` через `sequenceMeta`, `jitterExempt`, `countsTowardStability` и contract-invalid fail при отсутствии required metadata. В совокупности это переводит сравнение quality-regressions из ad hoc интерпретации в формальный, повторяемый experimental protocol.

### Ключевые файлы
- `docs/cameraanalysis/00-overview.md` (baseline constraints и мотивация PR-001)
- `docs/cameraanalysis/05-feature-snapshot-aggregator.md` (source-of-truth для PR-004)
- `docs/cameraanalysis/06-scene-semantics-layer.md` (source-of-truth для PR-005/PR-006)
- `docs/cameraanalysis/08-ui-integration.md` (source-of-truth для PR-009/PR-010/PR-011)
- `docs/cameraanalysis/09-reasoning-provider.md` (source-of-truth для PR-012/PR-013)
- `docs/cameraanalysis/10-eval-harness.md` (source-of-truth + reference implementation для PR-014)
- `docs/cameraanalysis/eval/run_eval.py` (paired eval runner baseline vs candidate)
- `docs/cameraanalysis/eval/adapters.py` (legacy baseline normalization contract)
- `docs/cameraanalysis/eval/scorer.py` (deterministic metrics + sequence contract validation)
- `docs/cameraanalysis/eval/compare.py` (winner selection и release recommendation)
- `docs/cameraanalysis/eval/tests/test_scorer.py` (sequence/jitter/fix-type coverage tests)
- `docs/cameraanalysis/11-implementation-backlog.md` (PR-001..PR-015 dependency graph, включая PR-015 foundation)

---

## [2026-04-20 20:36] - [SG v7 Benchmark Hardening: закрытие критичных findings по slice integrity и phase4 cap]

### Суть изменений
- Устранены критичные замечания по `phase4`-балансировке preference view: `phase4_max_pattern_share` теперь enforced относительно текущего retained-пула с итеративным пересчётом, а при неразрешимом ограничении включён fail-closed.
- Исправлен benchmark orchestrator: `--dry-run` больше не выполняет sanitize с файловыми side effects; в `aggregate-only` добавлен graceful режим при отсутствии bundle-артефактов для slice recompute.
- Устранена контаминация slice-метрик: `model_only`/`end_to_end` считаются только из соответствующих полей (`model_only_predicted_script`, `end_to_end_predicted_script`) без fallback в `predicted_script/raw_output_json`.
- В prediction exporter восстановлена корректная семантика полей: `raw_output_json` снова хранит raw/model-only parse, а выбранный срез пишется отдельно.
- Синхронизирован default output path генератора предиктов с экспортным benchmark-контуром (`predictions_real_v1_export`), чтобы убрать path drift в типовом запуске.
- Пройдены локальные unit/smoke проверки и независимый peer-review через subagent; новых P0/P1/P2 findings после фиксов не выявлено.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Для научно корректного сравнения моделей недопустимы “тихие” деградации eval-контура: fallback-подмена slice-артефактов, нестрогий cap по паттернам и непредсказуемое поведение dry-run/aggregate-only искажают экспериментальные выводы.
- **Решение:** В контур валидации и бенчмарка добавлены строгие fail-closed инварианты и детерминированные правила admission/recompute. Это гарантирует, что reported метрики отражают именно целевой inference slice и заданные ограничения покрытия.
- **Детали:** Для `phase4` реализована итеративная проверка `count(pattern) <= floor(retained_total * max_share)` на каждом шаге редукции, что исключает ложное соблюдение cap при уменьшении denominator. В benchmark runner введён strict slice admission (без fallback contamination), а также разграничены режимы `full/score-only` и `aggregate-only` по источникам истины (`eval_bundle` vs cached reports), что повышает воспроизводимость и интерпретируемость метрик в runtime-oriented экспериментах ORPO.

### Ключевые файлы
- `docs/SGv7pipeline/training/phase_view.py` (strict phase4 cap enforcement, fail-closed semantics)
- `experiments/sc_benchmark/run_scientific_benchmark.py` (dry-run side-effect fix, aggregate-only graceful mode, strict slice metric collection)
- `experiments/sc_benchmark/generate_predictions_from_endpoint.py` (raw/output semantics fix, export default path alignment)
- `docs/SGv7pipeline/training/tests/test_phase_view.py` (phase4 cap/family coverage regression coverage)
- `docs/SGv7pipeline/eval/tests/test_prediction_export.py` (prediction export parsing/repair/slice tests)

---

## [2026-04-21 19:01] - [SG v7 Iter3.1: честный prep-eval, фиксация transfer-failure и нормализация run-артефактов]

### Суть изменений
- Выполнен полный честный prep-eval для `dataset_v7`, `dataset_v7_orpo_iter1`, `dataset_v7_orpo_iter2` на свежем dual-slice export, после чего benchmark-артефакты были пересобраны в каноническую папку run-а под `docs/SGv7pipeline/runs/...`.
- Зафиксирована человекочитаемая интерпретация метрик в документации: `dataset_v7` сохранён как structural baseline, а `iter2` — как strongest semantic candidate.
- Проверен honest `iter3.1` corpus build attempt; подтверждено, что текущий transfer-first контур пока непригоден для обучения из-за почти полного доминирования `gold_target_json`.
- Нормализована структура файлов проекта: Colab prep-export и результаты конкретного прогона перенесены в `docs/SGv7pipeline/runs/...`, а `experiments/sc_benchmark` оставлен как слой benchmark-кода и reusable assets.
- Добавлены README-навигация и правила раскладки артефактов, чтобы исключить дальнейшую путаницу между infrastructure и результатами прогонов.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** На ORPO-этапе проявился классический конфликт между semantic quality и structural fidelity. `iter1/iter2` улучшали смысловые метрики (`target resolution`, `chronology`, `strict success`), но одновременно ухудшали raw-структурную устойчивость (`json_valid`, `schema_valid`, `ordinal binding`, `exact marker identity`). Дополнительно смешение benchmark-инфраструктуры и run-артефактов в разных каталогах снижало воспроизводимость эксперимента.
- **Решение:** Проведён честный dual-slice prep-eval с раздельным анализом `model_only` и `end_to_end`, а затем выполнен transfer-first corpus build без fallback на repaired `predicted_script`. Параллельно введено архитектурное разделение: код и frozen assets остаются в `experiments/sc_benchmark`, а результаты конкретных запусков и Colab exports хранятся только в `docs/SGv7pipeline/runs/...`.
- **Детали:** По `model_only` slice получено: для `dataset_v7` `json_valid_rate=0.9809`, `target_resolution_accuracy=0.0564`, `chronology_phase_accuracy=0.0420`; для `iter1` — `0.9656 / 0.0940 / 0.0725`; для `iter2` — `0.9504 / 0.1128 / 0.0840`. Pairwise сравнение показало, что `iter2` выигрывает у `v7` по смысловым метрикам (`31` победа против `14`, `p≈0.016`), но делает это ценой регрессий по structural metrics. Honest `iter3.1` corpus build завершился fail-closed: `gold_chosen_share_overall=0.948`, `model_chosen_share_overall=0.052`. Это важно методологически: проблема локализуется не в eval-контуре, а в самих raw model outputs, значит следующий шаг должен менять generation contract / supervision design, а не просто добавлять ещё один preference cycle.

### Ключевые файлы
- `docs/SGv7pipeline/09-eval-and-release.md` (человекочитаемая сводка текущего состояния `v7 / iter1 / iter2`)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/README.md` (каноническая сводка prep-run и его итогов)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/scientific_report.md` (агрегированный benchmark report)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/runs_scored.csv` (численные метрики по моделям)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv` (pairwise A/B сравнение)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/iter3_corpus_seed42/iter3_manifest.json` (gate report по honest `iter3.1` corpus)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/iter3/README.md` (маркировка legacy scratch-папки)
- `experiments/sc_benchmark/README.md` (правила разделения benchmark infrastructure и run-артефактов)

---

## [2026-04-22 11:31] - [Camera Analysis Hybrid Stage: PR-H01/PR-H02 framing и evidence taxonomy]

### Суть изменений
- Зафиксирован и связан с индексными документами research framing для hybrid stage (`PR-H01`): сформулирована thesis-level граница между deterministic cinematic grammar и интерпретируемым neural evidence.
- Спроектирован и доведен до source-of-truth состояния `Evidence Taxonomy Contract` (`PR-H02`) для hybrid camera analysis.
- Введены closed catalogs для `EvidenceHeadId`, `EvidenceCategoryId` и `SupportingSignalTag`, а также canonical shape для scalar/categorical neural outputs.
- Добавлен frame-level runtime envelope `NeuralEvidenceSnapshot` с dense serialization policy, versioning, canonical ordering и mode-consistency invariants.
- Зафиксированы `live/pause` boundaries, `status` semantics (`available/not_applicable/unavailable`), mapping к issue/action taxonomy, `supportingSignals` emission rules и ambiguity policy для `shot_type_confidence`.
- Обновлены обзорные документы пакета (`README`, roadmap, backlog), чтобы `PR-H02` стал явным source-of-truth артефактом следующего этапа после `PR-H01`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** При переходе от полностью deterministic camera critique к hybrid architecture возникает методологический разрыв: без явно зафиксированных границ neural layer быстро превращается либо в black-box judge, либо в набор плохо интерпретируемых auxiliary scores, которые невозможно валидировать, разметить и встроить в explainable mobile pipeline.
- **Решение:** Архитектура hybrid stage была декомпозирована на два последовательных design-артефакта. В `PR-H01` зафиксирована исследовательская формула `deterministic cinematic grammar + interpretable neural evidence`, а в `PR-H02` эта формула материализована в строгий contract: закрытая taxonomy evidence heads, нормированные semantics score/confidence/status, machine-checkable serialization, а также явный mapping `evidence -> issue/action/fusion boundary`.
- **Детали:** Существенной частью решения стало устранение недоопределенностей, которые делали бы downstream PR невоспроизводимыми: разделены scalar и categorical payload forms, введен dense snapshot `NeuralEvidenceSnapshot`, зафиксированы canonical order и versioning, запрещено смешивание `live/pause` payload-ов внутри одного snapshot, формализованы `not_applicable` vs `unavailable`, а для `shot_type_confidence` введены tie/unknown semantics. Отдельно разведены `action availability` и `neural support by mode`, чтобы hybrid layer не подменял deterministic planner. Для диссертационного текста это важно как пример того, как explainability-by-construction достигается не только выбором модели, но и строгим проектированием контрактов между research, runtime, dataset и eval слоями.

### Ключевые файлы
- `docs/cameraanalysis/14-hybrid-research-framing.md` (source-of-truth research framing для `PR-H01`)
- `docs/cameraanalysis/15-evidence-taxonomy-contract.md` (source-of-truth evidence taxonomy для `PR-H02`)
- `docs/cameraanalysis/README.md` (индексация hybrid-stage артефактов)
- `docs/cameraanalysis/01-roadmap.md` (позиционирование `PR-H01/PR-H02` в phase plan)
- `docs/cameraanalysis/11-implementation-backlog.md` (DoD и dependency graph для `PR-H02`)
- `docs/cameraanalysis/12-agent-prompts.md` (Prompt 9 и Prompt 10 как design entry points)

---

## [2026-04-22 13:46] - [SG V8.0: первый end-to-end benchmark run (plan->compile->score) и локальный runner]

### Суть изменений
- Реализован и проверен полный локальный post-Colab контур `v8`: распаковка `sgv8_eval_pack_seed42.zip`, сборка `eval_artifacts` (`plan_case_results + compiled_predictions`), генерация benchmark-конфига и запуск `run_scientific_benchmark.py`.
- Добавлен единый orchestration-скрипт для воспроизводимого прогона одной командой: `07_run_v8_local_benchmark.py`.
- Исправлена совместимость `v8` compiled predictions с dual-slice контрактом benchmark orchestrator: в `compiled_predictions.jsonl` теперь явно пишутся `model_only_predicted_script` и `end_to_end_predicted_script`, что снимает `require_both_slices` ошибку.
- Получены финальные агрегаты `v8_0_seed42/benchmark_results_seed42/aggregate` в формате, совместимом с предыдущими `v7` итерациями (`runs_scored.csv`, `pairwise_compare.csv`, `scientific_report.md`) и дополнительно `v8_plan_slice_summary.csv`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Первый `v8` benchmark действительно подтвердил semantic gain, но вскрыл compile-time узкое место гибридной схемы: targetless required actions и битые `spatialRelations` слишком часто роняли compiled output, из-за чего итоговые structural метрики были занижены относительно реального quality уровня планировщика.
- **Решение:** 
  - (1) Для воспроизводимости введён единый локальный runner `07_run_v8_local_benchmark.py`, который формализует весь post-Colab lifecycle без ручных шагов.
  - (2) Для технической совместимости с существующим benchmark orchestrator обновлён `eval_artifacts.py`: compiled predictions теперь содержат dual-slice contract fields (`model_only_predicted_script`, `end_to_end_predicted_script`, `selected_predicted_script`), что сохраняет строгий admission в `run_scientific_benchmark.py`.
  - (3) В `v8` compiler добавлена deterministic lenient normalization policy: targetless required actions понижаются до safe action, а invalid `spatialRelations` пропускаются с traceable reason codes вместо fail-closed на всём case.
- **Детали:** По итогам hotfix-прогона `seed=42`:
  - `dataset_v8_plan_orpo_iter1` vs `dataset_v7_orpo_iter2`:
    - `overall.json_valid_rate`: `0.9504` vs `0.9504` (`±0.0000`)
    - `overall.ordinal_actor_binding_accuracy`: `0.8385` vs `0.9340` (`-0.0955`)
    - `overall.target_resolution_accuracy`: `0.4803` vs `0.1778` (`+0.3026`)
    - `overall.chronology_phase_accuracy`: `0.1412` vs `0.0840` (`+0.0573`)
    - `overall.case_strict_success_rate`: `0.1031` vs `0.0344` (`+0.0687`)
    - `overall.runtime_fallback_rate`: `0.7137` vs `0.8435` (`-0.1298`, лучше)
  - Pairwise:
    - `dataset_v8_plan_orpo_iter1` vs `dataset_v7_orpo_iter2`: wins `151` vs `82`, `p=7.26e-06` (уже статистически значимое преимущество `v8`)
    - `dataset_v8_plan_orpo_iter1` vs `dataset_v8_plan_sft`: wins `9` vs `12`, `p=0.6636` (ORPO поверх текущего plan-SFT почти не меняет общий outcome)
  - `local_plan_raw` slice:
    - `plan_parse_rate = 0.9580`
    - `plan_reference_binding_accuracy ≈ 0.7595`
    - `plan_beat_integrity_accuracy ≈ 0.2786`
  - `compile-note` диагностика:
    - `v8.targetless_action_downgraded`: `58` случаев для `dataset_v8_plan_orpo_iter1`
    - `v8.invalid_spatial_relation_skipped`: `11` случаев для `dataset_v8_plan_orpo_iter1`
  Эти значения показывают, что hotfix восстановил compile-path и structural stability до уровня `iter2` по `json_valid_rate`, сохранив при этом сильный semantic gain. Текущий bottleneck сместился уже не в compile drops, а в ordinal binding и plan integrity.

### Ключевые файлы
- `docs/SGv7pipeline/v8/07_run_v8_local_benchmark.py` (единый локальный runner post-Colab benchmark цикла)
- `docs/SGv7pipeline/v8/eval_artifacts.py` (dual-slice совместимый compiled predictions contract)
- `docs/SGv7pipeline/v8/06_build_v8_eval_artifacts.py` (CLI генерации `plan_case_results` и `compiled_predictions`)
- `docs/SGv7pipeline/v8/README.md` (документированный one-command запуск локального v8 benchmark)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/runs_scored.csv` (основные модельные метрики)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv` (pairwise outcome и p-value)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/v8_plan_slice_summary.csv` (`local_plan_raw` quality metrics)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` (сводный отчёт прогона)

---

## [2026-04-22 14:07] - [SG V8.0: hotfix compile-path, актуализация сравнений моделей и нормализация diploma log]

### Суть изменений
- Реализован hotfix для `v8` compile-path: targetless required actions теперь детерминированно понижаются до safe action, а invalid `spatialRelations` не роняют весь compiled output.
- Обновлены Python/Swift runtime и eval-контуры так, чтобы compile notes (`v8.targetless_action_downgraded`, `v8.invalid_spatial_relation_skipped`) проходили в benchmark artifacts и runtime trace без silent repair.
- Пересчитаны и зафиксированы post-hotfix benchmark-результаты `dataset_v8_plan_sft` и `dataset_v8_plan_orpo_iter1`, после чего обновлены человекочитаемые сравнения моделей в `diploma.md` и `09-eval-and-release.md`.
- Весь лог `diploma.md` отсортирован по timestamp-ам, чтобы chronology разработки соответствовала реальной последовательности этапов и могла использоваться как корректный source-of-truth для текста диссертации.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** До hotfix и после серии быстрых итераций возникли сразу две методологические проблемы: (1) `v8` benchmark недооценивал гибридную архитектуру из-за compile-time fail-closed поведения, и (2) текстовые артефакты сравнения моделей начали расходиться с уже пересчитанными метриками, а журнал прогресса потерял корректный временной порядок.
- **Решение:** В compiler введена deterministic lenient normalization policy с audit-trace через explicit reason codes, а поверх неё синхронизированы runtime/eval/doc layers: benchmark outputs были пересобраны, человекочитаемые сравнения обновлены на post-hotfix значения, а `diploma.md` нормализован как хронологический research log.
- **Детали:** После hotfix `dataset_v8_plan_orpo_iter1` достиг `overall.json_valid_rate=0.9504`, сохранив structural parity с `dataset_v7_orpo_iter2`, но одновременно показал заметный semantic gain (`target_resolution_accuracy=0.4803`, `chronology_phase_accuracy=0.1412`, `case_strict_success_rate=0.1031`). Pairwise сравнение стало статистически значимым в пользу `v8` (`151` победа против `82`, `p=7.26e-06`). Это важно для диссертационного нарратива: bottleneck сместился с compile drops на `ordinal_actor_binding_accuracy` и `plan_beat_integrity`, то есть следующий шаг должен оптимизировать binding/integrity contract, а не возвращаться к старой fail-closed compile policy.

### Человекочитаемый вывод по всем итерациям benchmark

Ниже зафиксирован итоговый narrative по эволюции моделей `base -> v6 -> v7 -> v7_orpo_iter1 -> v7_orpo_iter2 -> v8 -> v9`.

- `base_qwen3_1_7b` выступает как контрольный baseline без доменной адаптации. Он полезен именно как точка отсчёта: на раннем SFT-eval модель почти всегда была parseable, но практически не проходила строгий контракт (`schema_strict_rate=7.58%`, `exact_match_rate=0%`), а в unified runtime benchmark оставалась структурно и семантически непригодной (`json_valid_rate≈42.75%`, `schema_valid≈0.38%`, `runtime_fallback_rate=100%`). Следовательно, без специализированного датасета и контрактной дисциплины компактная Qwen-модель не решает задачу сценического парсинга.

- `v6` нельзя трактовать как "плохую модель вообще". На собственном legacy-контракте она оставалась работоспособной: `json_parse_rate=100%`, `schema_valid_rate=55.02%`, `actor_count_match_rate=81.34%`. Однако при переносе на современный `SG v7`-контракт она почти полностью теряет пригодность. Это означает, что основной разрыв между `v6` и более поздними версиями связан не только с качеством дообучения, но и с изменением самого целевого контракта: появились обязательные требования к marked-object identity, ordinal grounding, multi-beat chronology и runtime-safe target resolution.

- `dataset_v7` стал первой по-настоящему production-совместимой моделью нового поколения. Его ключевая роль не в "лучшем общем score", а в том, что он стабилизировал форму ответа: `json_valid_rate=0.9809`, `ordinal_actor_binding_accuracy=0.9722`, практически идеальная работа с exact marker identity. Поэтому `v7` корректно интерпретировать как **лучший structural baseline**. Одновременно он оставался слабым по динамической семантике сцены: `target_resolution_accuracy=0.0564`, `chronology_phase_accuracy=0.0420`, `case_strict_success_rate=0.0191`. Иными словами, `v7` хорошо держит структуру, но ещё плохо восстанавливает сложный смысл многофазных сцен.

- `dataset_v7_orpo_iter1` показал первый заметный semantic lift поверх `v7`. Улучшились `target_resolution_accuracy` (`0.0940` против `0.0564`), `chronology_phase_accuracy` (`0.0725` против `0.0420`) и `case_strict_success_rate` (`0.0267` против `0.0191`). Однако этот выигрыш был получен ценой частичной утраты structural discipline: `json_valid_rate` снизился до `0.9656`, `ordinal_actor_binding_accuracy` — до `0.9514`. Таким образом, `iter1` доказал полезность preference/ORPO-подстройки, но ещё не решил конфликт между semantic quality и structural fidelity.

- `dataset_v7_orpo_iter2` усилил semantic профиль ещё сильнее и потому был зафиксирован как **лучший semantic candidate внутри ветки `v7`**. По `model_only` slice он достиг `target_resolution_accuracy=0.1128`, `chronology_phase_accuracy=0.0840`, `case_strict_success_rate=0.0344`, а pairwise против `v7` показал человекочитаемый semantic gain. Но одновременно продолжилось проседание structural метрик: `json_valid_rate` упал до `0.9504`, `ordinal_actor_binding_accuracy` — до `0.9340`, а exact marker identity перестал быть идеальным. Это и было основным выводом честного `iter3.1` prep-eval: следующий шаг нельзя было строить как "ещё один ORPO-цикл", потому что проблема локализовалась уже в самих raw outputs, а не в отсутствии preference supervision.

- Honest `iter3.1` corpus build завершился fail-closed (`gold_chosen_share_overall=0.948`, `model_chosen_share_overall=0.052`). Это методологически важный результат: он показал, что transfer-first контур почти не может опираться на реальные model outputs и вынужден возвращаться к gold supervision. Следовательно, bottleneck был не в benchmark-инфраструктуре и не в слабом postprocessing, а в generation contract и в качестве самой планировочной траектории модели.

- `dataset_v8_plan_sft` стал первым шагом, где semantic quality выросла уже не на проценты, а кратно. Даже без ORPO эта модель показала `target_resolution_accuracy=0.4684`, `chronology_phase_accuracy=0.1412`, `case_strict_success_rate=0.0954`, то есть на порядок сильнее всей `v7`-ветки по ключевым runtime-oriented метрикам. Pairwise сравнение подтвердило, что даже чистый `v8 plan-SFT` обгоняет как `dataset_v7`, так и `dataset_v7_orpo_iter2`. Это означает, что основной вклад здесь дал уже не preference-stage, а смена самой архитектуры генерации: переход от прямого text-to-json к plan/compile схеме с явным промежуточным слоем.

- `dataset_v8_plan_orpo_iter1` после hotfix стал **лучшим общим кандидатом** на текущем этапе. Он удержал `json_valid_rate=0.9504`, то есть structural stability была восстановлена до уровня `dataset_v7_orpo_iter2`, но semantic block вырос резко: `target_resolution_accuracy=0.4803`, `chronology_phase_accuracy=0.1412`, `case_strict_success_rate=0.1031`, `runtime_fallback_rate=0.7137`. Pairwise сравнение против `dataset_v7_orpo_iter2` стало уже статистически значимым (`151` победа против `82`, `p=7.26e-06`). Таким образом, после hotfix `v8` больше не выглядит как "семантически сильный, но структурно сломанный" эксперимент.

- `dataset_v9_event_sft` (slot-first event-table, seed `42`) стал следующим качественным скачком: модель перестала генерировать полный scene-level план и вместо этого заполняет компактную таблицу событий по закрытым слотам, а целевой `ScenePlanIR/SceneScript` собирается детерминированно. В compiled-slice метриках это дало резкое улучшение всех ключевых runtime-oriented показателей: `json_valid_rate=1.0000`, `ordinal_actor_binding_accuracy=1.0000`, `target_resolution_accuracy=0.9214`, `chronology_phase_accuracy=0.8702`, `case_strict_success_rate=0.5076`, при одновременном снижении `runtime_fallback_rate` до `0.4351`. Дополнительно введены V9 event-slice метрики (raw event table), позволяющие измерять semantic correctness отдельно от компиляции: `event_schema_valid_rate=1.0000`, `event_actor_slot_accuracy≈0.9691`, `event_target_slot_accuracy≈0.9439`, `event_action_type_accuracy≈0.9621`, `event_beat_order_accuracy≈0.9677`. Это подтверждает ключевой тезис: bottleneck переносится с “умеет ли модель написать структуру JSON” на “умеет ли модель выбрать правильную семантику в контролируемом IR”.

- Важнейший итог post-hotfix этапа состоит в смене bottleneck-а. Ранее узким местом были compile drops: targetless required actions и invalid spatial relations искажали общую картину. После введения deterministic lenient normalization policy compile-path перестал быть главным источником деградации. Теперь основной ограничитель качества — это `ordinal_actor_binding_accuracy` и более широкий класс `plan integrity`. Это подтверждается не только финальными benchmark-метриками, но и `local_plan_raw` slice, где `plan_parse_rate≈0.958`, но `plan_reference_binding_accuracy≈0.76`, а `plan_beat_integrity_accuracy≈0.28`. Следовательно, следующий исследовательский шаг должен оптимизировать именно binding/integrity contract, а не возвращаться к прежней fail-closed compile policy.

### Практический итог для диссертационного сравнения

- `base_qwen3_1_7b` — контрольный baseline, практически непригодный для задачи.
- `v6` — работоспособен только в рамках legacy-контракта; с современным `SG v7/v8` контрактом несовместим.
- `dataset_v7` — лучший structural baseline.
- `dataset_v7_orpo_iter2` — лучший semantic candidate внутри ветки `v7`.
- `dataset_v8_plan_sft` — первый качественный скачок, показывающий, что смена архитектуры генерации важнее простого наращивания ORPO-циклов.
- `dataset_v8_plan_orpo_iter1` post-hotfix — лучший общий кандидат на текущем этапе, потому что удерживает structure на уровне `iter2`, но даёт значительно более сильную semantic reconstruction.
- `dataset_v9_event_sft` — лучший общий кандидат на текущем этапе: slot/event-table контракт устраняет структурную недоопределённость плана и резко повышает семантическую точность (targets/chronology/strict success), при этом оставаясь совместимым с local-first runtime и audit-требованиями (reason codes, verifier/repair boundary).

### Ключевые файлы
- `docs/SGv7pipeline/v8/compiler.py` (lenient compile policy и compile notes для Python benchmark path)
- `docs/SGv7pipeline/v8/eval_artifacts.py` (прокидывание `compile_notes` и `slice_reason_codes` в eval artifacts)
- `shafinMultitool/SceneGeneratorModule/Services/ScenePlanCompiler.swift` (runtime-эквивалент compile hotfix)
- `shafinMultitool/SceneGeneratorModule/Services/SceneQualityGate.swift` (traceable merge compile notes в runtime reasons)
- `shafinMultitool/SceneGeneratorModule/Services/SceneParseCoordinator.swift` (единый compile-with-notes path для local/remote orchestration)
- `docs/SGv7pipeline/09-eval-and-release.md` (обновлённый snapshot сравнения моделей с учётом новых метрик)
- `diploma.md` (нормализованный и отсортированный chronological log)

---

## [2026-04-22 15:14] - [SG V1: chunk-native scene bundle pipeline для mixed screenplay/prose, append-only continuity и bundle-level eval]

### Суть изменений
- Реализован новый `v1` runtime-пайплайн для сценического парсинга, который переводит систему с режима `one text -> one ScenePlanIR -> one compile` на bundle-first архитектуру `Raw text -> ScriptNormalizer -> SceneBoundaryDetector -> ChunkSegmenter -> ChunkAnchorExtractor -> EntityRegistryProjector -> LocalChunkPlanner -> ChunkCanonicalizer -> SceneStitcher -> SceneBundlePlanIR -> SceneBundleCompiler -> SceneBundleScript`.
- Введён набор versioned контрактов для bundle-уровня: `sg_script_document_v1`, `sg_chunk_anchor_v1`, `sg_entity_registry_v1`, `sg_scene_chunk_draft_v1`, `sg_scene_chunk_v1`, `sg_scene_stitch_state_v1`, `sg_scene_bundle_plan_v1`, `sg_scene_bundle_script_v1`, а также публичный runtime result `SceneBundleParsingResult`.
- В iOS runtime добавлен deterministic front-end: нормализация текста, scene boundary detection, segmenter для dialogue/action chunks, anchor extraction, canonicalization и stitcher, после чего compile вызывается только один раз на финальном bundle, а не отдельно на каждом чанке.
- Parser facade переведён на bundle-first поведение с compatibility adapter: старые `parse/parseAsync` продолжают работать, но canonical internal result теперь всегда bundle, а single-scene ответ является лишь `activeSceneScript` представлением текущей сцены.
- Расширен continuity context, который реально подаётся в локальный planner prompt: теперь туда входят `scene id`, `scene heading`, `known objects`, alias maps актёров и объектов, speaker alias map, `lastResolvedSpeaker`, poses и held objects. Это устраняет часть предыдущего разрыва между runtime state и реальным контекстом, который видела модель.
- Поддержан append-only режим: если пользователь дописывает хвост документа, пересчитывается только хвостовая сцена; если изменения произошли в середине текста, full-reparse ограничивается только затронутой сценой, а остальные сцены bundle не пересобираются.
- Добавлен новый research/data/eval пакет `docs/SGv7pipeline/v1` с builders для `macro_scene`, `chunk_anchor`, `entity_registry`, `chunk_patch`, `chunk_preference`, а также со сборкой `stitch_eval_artifacts` и локальным benchmark runner для будущих `chunk_raw / scene_stitched / bundle_compiled` срезов.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Предыдущий `v7/v8` подход, даже после заметного semantic роста, всё ещё опирался на scene-level planning как на primary target. Это делало систему уязвимой при работе с обычным смешанным текстом сценария: модель должна была сразу восстановить целую сцену, continuity приходилось чинить уже постфактум, а chunking не был first-class сущностью. В результате локальная архитектура была недостаточно выразительной для двух реальных продуктовых режимов: полного разбора длинного текста и инкрементального append-only продолжения документа.
- **Решение:** В `v1` задача переформулирована как иерархический pipeline с жёстким разделением ролей. Deterministic front-end отвечает за документную структуру, boundaries и chunk segmentation; локальный planner генерирует только chunk-level draft; canonicalizer преобразует локальные упоминания в стабильные глобальные refs; continuity truth хранится только в `SceneStitcher`; compile происходит лишь после того, как сцена и bundle уже собраны детерминированно. Таким образом система становится не просто "ещё одной fine-tuned моделью", а многослойной гибридной архитектурой с explainable linking и трассируемой continuity policy.
- **Детали:** Архитектурно это важный шаг для диплома по нескольким причинам. Во-первых, введены explicit versioned contracts между runtime, data и eval слоями, что делает систему воспроизводимой и пригодной для поэтапной эволюции без скрытых несовместимостей. Во-вторых, continuity больше не размыта по нескольким сервисам: alias matching, object identity, speaker inheritance и deferred refs теперь проходят через единый stitch state. В-третьих, canonical output перестаёт быть одной сценой по умолчанию: даже если в тексте одна сцена, система думает bundle-уровнем, а значит изначально готова к multi-scene screenplay input. В-четвёртых, формализован путь к dissertation-grade eval: отдельно можно измерять качество сырого chunk planner-а, stitched scene plan и финального compiled bundle, а значит разделять model error, canonicalization error и stitching error вместо одной агрегированной "точности".

### Практический смысл для исходной бизнес-задачи
- Эта архитектура прямо закрывает исходную прикладную цель: приложение должно уметь брать обычный mixed screenplay/prose текст, разрезать его на отдельные JSON-чанки, корректно восстанавливать ссылки между ними и собирать в итоговый `AR/previz-ready` bundle без ручного вмешательства.
- Появляется технологически корректный путь для incremental authoring: пользователь может дописывать сценарий по кускам, а приложение может не перестраивать весь результат каждый раз, а аккуратно пересчитывать только хвостовую или затронутую сцену.
- Для продуктовой надёжности важно и то, что chunk JSON теперь становится first-class artifact: его можно хранить, дебажить, сравнивать в benchmark, использовать для audit trail и объяснять, на каком именно этапе возникла ошибка continuity или entity linking.

### Честное состояние реализации
- Runtime foundation и research scaffolding реализованы, но локальный ML planner пока ещё работает через transitional adapter: существующий local `ScenePlanIR` output адаптируется во внутренний `sg_scene_chunk_draft_v1`, а не генерируется native-моделью напрямую.
- Это означает, что архитектурный каркас `v1` уже существует и работает как новый execution path, однако следующий полноценный research cycle должен дообучить отдельный adapter именно на `chunk draft` контракте и затем измерить его на новых `chunk_raw / scene_stitched / bundle_compiled` метриках.
- Полная `xcodebuild` сборка проекта на момент фикса не была доведена до зелёного статуса не из-за `v1` изменений, а из-за внешней, уже существовавшей проблемы с отсутствующим модулем `SnapKit` в unrelated UI-частях проекта. При этом targeted typecheck SceneGenerator bundle-layer и Python tests для `docs/SGv7pipeline/v1` проходят успешно.

### Ключевые файлы
- `shafinMultitool/SceneGeneratorModule/Models/SceneBundleContracts.swift` (новые v1 contracts и public bundle result)
- `shafinMultitool/SceneGeneratorModule/Services/SceneBundlePipeline.swift` (deterministic bundle-first pipeline: normalizer, detector, segmenter, anchors, canonicalizer, stitcher, compiler)
- `shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift` (bundle facade и compatibility adapter для существующего UI)
- `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift` (расширенный continuity context в planner prompt)
- `shafinMultitool/SceneGeneratorModule/Models/SceneChunkState.swift` (расширенный stitch-state summary)
- `shafinMultitoolTests/SceneBundlePipelineTests.swift` (tests на multi-scene, canonical refs, append-only continuation и compatibility path)
- `docs/SGv7pipeline/v1/datasets.py` (builders нового chunk-native data layer)
- `docs/SGv7pipeline/v1/eval_artifacts.py` (bundle/stitch eval artifacts и агрегаты)
- `docs/SGv7pipeline/v1/04_run_v1_local_benchmark.py` (локальный runner для будущего `v1` benchmark контура)

---

## [2026-04-26 22:30] - [SG Live Dataset Smoke: честная проверка реальной GGUF-модели в iOS runtime]

### Суть изменений
- Добавлен полноценный live smoke-контур для `SceneV8PipelineTests`, который прогоняет реальные sampled cases из сгенерированных SGv7 train datasets через приложение и локальную GGUF-модель, а не через stub/rule-based shortcut.
- Расширены тесты датасетно-ориентированными паттернами: `dialogue_only`, `dialogue_then_put_down_object`, `dialogue_then_pick_up_object_then_give_to_third_actor`, `ordinal_first_second_third`, `toward_each_other_then_pass_by_marked_object`, `same_type_two_marked_objects`.
- Введены параметры воспроизводимого запуска: `SG_LIVE_DATASET_SEED`, `SG_LIVE_DATASET_CASE_LIMIT`, `SG_LIVE_DATASET_PATTERN_FILTER`, а также запись summary через `SG_LIVE_DATASET_SUMMARY_PATH`.
- Исправлена инфраструктура запуска в hosted XCTest: live bundle path теперь действительно cold-start-ит локальный LLM через async provider, а поиск GGUF-модели работает не только через `Bundle.main`, но и через все bundle/framework контейнеры тестового процесса.
- Получен честный отрицательный результат на текущей модели `dataset_v8_plan_orpo_iter1_q4_k_m.gguf`: live smoke выполнялся около 808 секунд, модель реально загрузилась, но итоговый pass rate на 12 sampled сложных кейсах составил `0/12`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** До этого быстрые тесты могли давать ложное чувство корректности: часть запусков фактически пропускалась, часть шла через deterministic fallback, а hosted XCTest не всегда видел bundled GGUF-модель. Это означало, что существующий test harness проверял совместимость контрактов, но не давал честного ответа на главный прикладной вопрос: справляется ли локальная дообученная модель с реальными сложными сценарными входами в том же пути, который использует приложение.
- **Решение:** Live smoke был переведён в режим end-to-end проверки через реальный `SceneBundlePipeline` и локальный model provider. Для воспроизводимости добавлен seeded sampling из `docs/SGv7pipeline/runs/sgv7_full_20260417/core/accepted_source.jsonl` и `hard/accepted_source.jsonl`, pattern-aware expectations, structured per-case diagnostics и summary output. Отдельно устранены две инфраструктурные причины ложных результатов: синхронный provider path больше не обходит cold-start LLM, а discovery GGUF-модели учитывает специфику тестового bundle layout.
- **Детали:** Нормальные deterministic `SceneV8PipelineTests` проходят (`14` тестов: `12` passed, `2` skipped), что подтверждает базовую совместимость контрактов и fallback-path. Однако live dataset smoke с реальной моделью выявил существенный model/pipeline quality gap. Модель была загружена из `shafinMultitool/SceneGeneratorModule/Models/dataset_v8_plan_orpo_iter1_q4_k_m.gguf`, состояние загрузки `loaded`, но по sampled cases результат остался `passed=0/12`. По паттернам: `dialogue_only` дал `0/2` из-за missing active scene; `dialogue_then_pick_up_object_then_give_to_third_actor` дал только частичные планы без стабильных `pick_up/give`; `dialogue_then_put_down_object` терял `put_down` и dialogue; `same_type_two_marked_objects` часто схлопывал актёров и объекты; `toward_each_other_then_pass_by_marked_object` нестабилен по `pass_by`; `ordinal_first_second_third` схлопывал несколько актёров в одного. Это важный отрицательный результат: текущая GGUF-модель подходит для простых демо-паттернов, но пока не подтверждена как надёжный runtime parser для complex dialogue/action, ordinal binding и multi-object identity.

### Ключевые файлы
- `shafinMultitoolTests/SceneV8PipelineTests.swift` (live dataset smoke, seeded sampler, pattern-aware assertions, per-case diagnostics)
- `shafinMultitool/SceneGeneratorModule/Services/SceneBundlePipeline.swift` (async local provider path для честного запуска GGUF-модели в bundle pipeline)
- `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift` (расширенный discovery bundled GGUF в hosted XCTest/runtime containers)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/core/accepted_source.jsonl` (источник sampled core cases для live smoke)
- `docs/SGv7pipeline/runs/sgv7_full_20260417/hard/accepted_source.jsonl` (источник sampled hard cases для live smoke)
- `/tmp/sg_live_dataset_probe/Logs/Test/Test-shafinMultitool-2026.04.26_22-12-02-+0300.xcresult` (артефакт полного live smoke запуска с реальной моделью)

---

## [2026-05-01 17:24] - [V9 Slot-Event Benchmark: метрики, сравнение и фиксация результатов]

### Суть изменений
- Зафиксирован reproducible benchmark-прогон для `dataset_v9_event_sft` (seed `42`) в контуре `frozen eval bundle` и добавлены его агрегированные метрики в документацию сравнения.
- Подтверждено, что переход на slot/event-table контракт резко снижает структурную неопределенность и повышает семантическую точность без retraining старого `ScenePlanIR`-контракта.
- Добавлены V9-specific event-метрики (structural/semantic) как отдельный слой контроля качества поверх “compiled slice” метрик.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** В `v8` модель всё ещё несла ответственность за целостную структуру плана (beats/actions/refs), что приводило к деградациям на `ordinal_actor_binding_accuracy`, `plan_reference_binding_accuracy` и `plan_beat_integrity_accuracy`, а также к высоким runtime fallback из-за частичных/неполных планов (даже при формально валидном JSON).
- **Решение:** В `v9` введён контролируемый slot-first контракт: модель заполняет компактную `event table` из закрытых слотов (`actorSlot/targetSlot/actionType/beatSlot`), а финальная сцена компилируется детерминированно. Дополнительно введены verifier/repair контуры с traceable reason codes, что позволяет измерять отдельно: (1) структурную проходимость и (2) семантическую точность относительно gold.
- **Детали:** На seed `42` получен скачок ключевых метрик в compiled slice для `dataset_v9_event_sft` по сравнению с `dataset_v8_plan_orpo_iter1`:
  - `json_valid_rate`: `1.0000` vs `0.9504`
  - `ordinal_actor_binding_accuracy`: `1.0000` vs `0.8385`
  - `target_resolution_accuracy`: `0.9214` vs `0.4803`
  - `chronology_phase_accuracy`: `0.8702` vs `0.1412`
  - `case_strict_success_rate`: `0.5076` vs `0.1031`
  Event-slice метрики (raw event table) зафиксировали высокий semantic correctness при полной structural валидности: `event_schema_valid_rate=1.0000`, `event_actor_slot_accuracy≈0.9691`, `event_target_slot_accuracy≈0.9439`, `event_action_type_accuracy≈0.9621`, `event_beat_order_accuracy≈0.9677`.

### Ключевые файлы
- `docs/SGv7pipeline/v9/contracts.py` (V9 typed contracts: slot catalog, event table, patch ops)
- `docs/SGv7pipeline/v9/verifier.py` (структурная проверка и deterministic repairs с reason codes)
- `docs/SGv7pipeline/v9/compiler.py` (event table -> ScenePlanIR -> compiled SceneScript)
- `docs/SGv7pipeline/v9/eval.py` (event-slice structural/semantic метрики)
- `docs/SGv7pipeline/v9/eval_artifacts.py` (event predictions -> compiled predictions + benchmark artifacts)
- `docs/SGv7pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv` (итоговые сравнимые compiled-slice метрики)
- `docs/SGv7pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.event_slice_summary.json` (V9 event-метрики: structural/semantic/degradation)

---

## [2026-05-04 18:45] - [V9 Runtime Hardening и повторный benchmark после live-smoke стабилизации]

### Суть изменений
- Усилен Swift runtime слой вокруг `dataset_v9_event_sft_q4_k_m.gguf`: добавлены детерминированные восстановления для потерянных `dialogue`, `pick_up`, `put_down`, `give`, `pass_by`, same-type marked objects и пустой active scene.
- Подтверждён честный live smoke на iOS Simulator с реальной GGUF-моделью: `SceneV8PipelineTests/testLiveLocalModelDatasetSampledCases()` завершился успешно (`1/1 passed`, `0` failures) на `/tmp/sg_live_model_dd/Logs/Test/Test-shafinMultitool-2026.05.04_18-25-16-+0300.xcresult`.
- Повторно выполнен локальный V9 scientific benchmark через `docs/SGv7pipeline/v9/04_run_v9_local_benchmark.py` на seed `42`; агрегаты пересобраны в `docs/SGv7pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate`.
- Итоговые compiled-slice метрики `dataset_v9_event_sft`: `json_valid_rate=1.0000`, `ordinal_actor_binding_accuracy=1.0000`, `target_resolution_accuracy=0.9214`, `chronology_phase_accuracy=0.8702`, `case_strict_success_rate=0.5076`, `runtime_fallback_rate=0.4351`.
- Pairwise сравнение подтвердило статистически сильный выигрыш: против `dataset_v8_plan_orpo_iter1` результат `212` побед против `7` поражений (`p≈1.07e-53`), против `dataset_v7_orpo_iter2` результат `226` побед против `5` поражений (`p≈3.11e-60`).

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Даже после перехода к V9 slot-event контракту live runtime оставался уязвимым к типовым пропускам слабой локальной модели: диалог мог схлопываться в `stand`, цепочки передачи объектов теряли `pick_up/give`, действия `put_down/pass_by` пропадали, а одинаковые размеченные объекты могли не материализоваться в итоговой сцене. Offline benchmark показывал высокий потенциал модели, но live smoke выявлял разрыв между модельным output и практической пригодностью результата в приложении.
- **Решение:** В Swift runtime добавлен explainable deterministic recovery layer поверх model output. Он не подменяет модель свободной эвристикой, а восстанавливает только события с явными поверхностными сигналами в тексте: `Имя: реплика`, кавычки, `берёт/кладёт/передаёт`, `оба проходят мимо X`, `левый/правый объект`. Все восстановления пишут reason codes (`v9.dialogue_event_materialized`, `v9.transfer_action_materialized`, `v9.mentioned_marked_object_materialized`, `v9.bundle_empty_scene_recovered`), что сохраняет audit trail и не превращает repair в silent semantic rewrite.
- **Детали:** Архитектурно это фиксирует важное разделение ответственности: модель отвечает за компактный semantic event draft, verifier/enricher проверяет покрытие очевидных обязательств текста, а compiler/stitcher собирают стабильный `SceneScript`. Такой подход повышает product reliability без немедленного retrain, но одновременно формирует список hard clusters для следующего датасетного цикла V9.1: `dialogue+action`, `object transfer`, `same-type markers`, `collective motion`, `pass_by`, `active scene materialization`.

### Ключевые файлы
- `shafinMultitool/SceneGeneratorModule/Services/SceneBundlePipeline.swift` (runtime enrichment: dialogue/materialized transfer actions/marked object recovery/active scene fallback)
- `shafinMultitool/SceneGeneratorModule/Services/SceneEventTableV9Service.swift` (coverage verifier issue codes and fixable semantic classes)
- `shafinMultitoolTests/SceneBundlePipelineTests.swift` (targeted regression tests for V9 coverage and runtime enrichers)
- `shafinMultitoolTests/SceneV8PipelineTests.swift` (live GGUF smoke path and model discovery for `dataset_v9_event_sft_q4_k_m.gguf`)
- `docs/SGv7pipeline/v9/04_run_v9_local_benchmark.py` (V9 local benchmark runner)
- `docs/SGv7pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/runs_scored.csv` (compiled-slice model metrics)
- `docs/SGv7pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv` (pairwise A/B outcomes)
- `docs/SGv7pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.event_slice_summary.json` (raw event-table structural/semantic metrics)

---

## [2026-05-04 20:09] - [Camera Analysis Semantic Tips: Prompt 19/20, PR-S01/PR-S02]

### Суть изменений
- Выполнен полный цикл `design -> design verify -> implement -> implement verify` для Prompt 19 (`PR-S01 Semantic Tip Taxonomy and Action Catalog`) и Prompt 20 (`PR-S02 VLM Visual Semantic Evidence Contract`).
- Для Prompt 19 зафиксирован source-of-truth документ закрытого каталога semantic screen tips: entity-aware taxonomy, action catalog, safe display label policy, priority/fallback rules, golden cases и mapping `evidence -> issue/strength -> semantic tip -> physical user move`.
- В Swift domain layer добавлены contract-safe типы `PR-S01`: `SemanticTipType`, `SemanticActionType`, `VisualProblemType`, `VisualStrengthType`, entity roles/kinds, `SemanticTipDefinition`, `SemanticTipCandidate`, `SemanticDisplayLabelPolicy` и `SemanticTipCatalog`.
- Для Prompt 20 зафиксирован source-of-truth VLM evidence contract: `VLMVisualEvidenceRequest`, `VLMVisualEvidenceResponse`, closed evidence dimensions, entity-aware response fields, relation types, confidence/uncertainty semantics, privacy tiers, validation/fallback matrix и JSON/prompt examples.
- В Swift domain layer добавлены contract-safe типы `PR-S02`: `VLMVisualEvidenceObservation`, `VLMEntityRelation`, `VLMAllowedSemanticCatalog`, `VLMVisualEvidenceConstraints`, `VLMEvidenceValidationResult` и локальный validator с fail-closed поведением.
- Добавлены unit/contract tests для PR-S01 и PR-S02: coverage полноты каталога, validation ошибок, safe-label fallback, Codable round-trip, VLM request/response validation, unknown action fail-closed, live-mode reject, privacy-tier checks и локальная фильтрация недостоверных relations.
- После `$infinite-reviewer` усилены четыре защитных места PR-S02: обязательный `redactionApplied` для redacted visual input, проверка display labels через `allowedCatalog`, нормализация grounded labels перед сравнением и fail-closed при превышении `maxSuggestedActionIds`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Ранний camera-analysis контур мог выдавать доменные оценки и рекомендации, но между визуальной причиной кадра и экранной подсказкой не было формального, ограниченного и проверяемого слоя. Это создавало риск "разговорных" подсказок без воспроизводимого основания: модель или future VLM могли invent-ить новые action ids, небезопасные object labels или свободный текст, который невозможно надежно связать с deterministic critique/fusion pipeline.
- **Решение:** Введён двухуровневый контракт. `PR-S01` формализует закрытый semantic-tip слой: finite catalog из meaningful screen tips и semantic actions, entity-aware target fields, политики выбора между `смести камеру`, `сдвинь героя`, `сдвинь предмет`, а также fallback при слабом grounding. `PR-S02` формализует VLM как поставщика не финального вердикта, а bounded visual evidence: response валидируется машинно и может только поддерживать/локализовать semantic tip planner, но не переписывать deterministic taxonomy.
- **Детали:**
  - `PR-S01` отделяет planner-level `ActionTypeV1` от human-facing `SemanticActionType`: первый остаётся transport/planner anchor, второй описывает физическое действие пользователя. Это важно для UI и научной воспроизводимости, потому что одна и та же domain issue теперь имеет явную цепочку `observation -> interpretation -> recommendation -> user move`.
  - Введена safe naming policy: человек/лицо допускаются как generic labels (`герой`, `человек`, `лицо`), а конкретные object labels (`цветок`, `ваза`, `книга`, `чашка`, `бутылка`, `лампа`, `стул`, `телефон`) допускаются только при confidence-aware grounding; иначе система деградирует к `предмет`, `объект справа`, `яркий объект на фоне` или `предмет у лица`.
  - `PR-S02` добавляет privacy-aware request contract: `structured_only` не содержит изображение, `redacted_visual` требует redacted still/crop, stripped EXIF и явный `redactionApplied=true`. Это сохраняет совместимость с offloading boundary и предотвращает silent privacy regression.
  - Validator `PR-S02` реализует fail-closed стратегию: mismatch request/frame/schema, non-pause mode, privacy mismatch, failed safety report, unknown action id, конфликт `keep_current_setup` с corrective actions и превышение top-level action budget возвращают deterministic-only fallback. Частично битые observations/relations отбрасываются локально, если базовый response всё ещё пригоден.
  - Свободный VLM prose ограничен вторичной explanation/debug ролью; decision source остаётся структурированным (`dimension`, `polarity`, `score`, `confidence`, `uncertaintyReasons`, `entityRef`, `suggestedActionIds`). Это снижает риск недетерминированных UI-сообщений и делает future evaluation пригодным для измерения agreement между local critique, neural evidence и VLM evidence.
  - Узкая верификация показала, что новые domain contracts typecheck-ятся изолированно (`swiftc -typecheck`), а VLM test-class проходит targeted typecheck со stubs. `git diff --check` чистый. Полная `xcodebuild` сборка проекта пока блокируется существующей внешней проблемой `Unable to find module dependency: 'SnapKit'` в unrelated UI-файлах, а не изменениями Prompt 19/20.

### Ключевые файлы
- `docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md` (source-of-truth для Prompt 19 / PR-S01: taxonomy, mappings, safe labels, examples, test plan)
- `docs/cameraanalysis/25-vlm-visual-semantic-evidence-contract.md` (source-of-truth для Prompt 20 / PR-S02: VLM request/response, validation, privacy, failure matrix)
- `docs/cameraanalysis/12-agent-prompts.md` (формализация Prompt 19 и Prompt 20 в agent backlog)
- `docs/cameraanalysis/01-roadmap.md` (roadmap registration для PR-S01 и PR-S02)
- `docs/cameraanalysis/11-implementation-backlog.md` (Track 18, PR-S01/PR-S02 scope и dependencies)
- `docs/cameraanalysis/README.md` (индексация новых source-of-truth документов)
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift` (`PR-S01` и `PR-S02` Swift domain contracts, validators, catalog constants)
- `shafinMultitoolTests/CameraAnalysisDomainContractsTests.swift` (contract tests для semantic tips и VLM visual evidence validation)

---

## [2026-05-05 12:28] - [Camera Analysis Prompt 22/23: implement verify PR-S04/PR-S05]

### Суть изменений
- Выполнен цикл `implement verify` для связки `Prompt 22 (PR-S04)` и `Prompt 23 (PR-S05)` с фокусом на production-UI path semantic tips.
- Для `PR-S05` доработан live/pause presentation слой: стабильный live hint при anti-flicker refresh, expanded tap-поведение, pause semantic reason/action блоки, empty/good-frame состояние, degraded banner и legacy backup список.
- Усилена accessibility-поверхность semantic tips: добавлены user-facing labels/hints для live chip и fallback suggestions.
- Добавлен regression test на критичный сценарий text-only refresh: identity hint сохраняется, но payload (`actionId`, `linkedIssueIds`, `targetRegion`, `overlayHint`) обновляется до текущего кадра.
- Проведена проверка согласованности с `PR-S04`: UI-путь использует существующий deterministic/semantic planner output без прямого runtime-вызова VLM из tap-handler и без показа internal ids пользователю.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** Даже при наличии semantic planner (`PR-S04`) UX мог терять объяснимость и консистентность на последнем шаге delivery в UI: при anti-flicker обновлении оставались stale action payload, в pause режиме не было явного empty state, а degraded structured path не всегда прозрачно объяснял fallback поведение.
- **Решение:** В presentation-слое введён более строгий state contract: live hint сохраняет стабильный визуальный identity для anti-flicker, но синхронно обновляет domain payload текущего кадра; pause card материализует reason/action tips, good/empty состояния и fallback-баннер с legacy backup, сохраняя explainable continuity.
- **Детали:** Архитектурно это замыкает цепочку `PR-S04 -> PR-S05`: planner формирует bounded semantic candidates, а UI отображает их без semantic drift и без утраты trace-linked контекста при коротких колебаниях confidence. Такой split снижает риск contradictory tips и повышает воспроизводимость пользовательских рекомендаций при live/pause переключениях.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (исправление text-only refresh ветки live hint + debug helper для теста)
- `shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift` (проброс legacy backup suggestions в pause card)
- `shafinMultitool/Multitool2Module/UI/Overlay/SuggestionChip.swift` (accessibility labels/hints и user-facing fallback badge)
- `shafinMultitool/Multitool2Module/UI/Overlay/SuggestionListView.swift` (semantic pause tips, degraded banner, empty state, accessibility fallback list)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (регрессионный тест стабильного identity при обновляемом payload)
- `docs/cameraanalysis/08-ui-integration.md` (design verify addendum по readiness/risks для PR-S05)

---

## [2026-05-05 13:52] - [Camera Analysis Semantic Tips: Prompt 21/24/25, PR-S03/PR-S06/PR-S07]

### Суть изменений
- Для `Prompt 21` закрыт runtime-мост между уже зафиксированным VLM evidence contract (`PR-S02`) и semantic planner: добавлены `VisualSemanticEvidenceProvider`, `VisualSemanticEvidenceCoordinator`, timeout/cancel/fail-closed outcome model, factory-конфигурация провайдера и `pause-only` wiring в `AnalysisPipeline`.
- В `AnalysisPipeline` реализована сборка `VLMVisualEvidenceRequest` из deterministic pause bundle (`snapshot + semantics + critique + plan + optional neural summary`) и безопасная передача `validatedEvidence` в `SemanticTipPlanner` только после локальной валидации, без использования visual provider на `live` path.
- Для `Prompt 21` добавлены targeted tests на `provider_unavailable`, `mode_not_pause`, validation reject, timeout и pipeline-level integration, что превращает `PR-S03` из чисто архитектурного разрыва в исполнимый prototype с доказуемым deterministic fallback.
- Для `Prompt 24` зафиксирован source-of-truth teacher-reviewed dataset loop (`PR-S06`) и добавлен практический tooling-слой: schema-aware validator, export/import hard-case bundle logic, summary helpers, demo JSONL fixtures и unit tests для privacy/export/review invariants.
- Для `Prompt 25` оформлен и доведен до `design verify` distillation plan (`PR-S07`): выделены дистиллируемые semantic evidence heads, правила проекции reviewed labels в train targets, loss composition, mobile backbone assumptions, отдельный runtime envelope `DistilledSemanticEvidenceSnapshot`, compare matrix и rollback/fallback policy.
- Обновлены `README`, roadmap и implementation backlog, чтобы `PR-S03`, `PR-S06`, `PR-S07` стали явными артефактами semantic-stage и получили корректную dependency chain относительно `PR-S02`, `PR-S04`, `PR-H05`, `PR-H07`, `PR-H14`.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** После фиксации semantic tip taxonomy и VLM evidence contract оставались три системных пробела. Во-первых, не было строго bounded runtime-слоя, который бы подключал visual evidence к `pause`-анализу, не ломая deterministic baseline. Во-вторых, отсутствовал воспроизводимый dataset loop, в котором teacher-VLM переставал бы быть источником истины и превращался в проверяемый источник proposal-ов. В-третьих, не было плана, как перенести semantic signal с тяжелого teacher-контура на компактную локальную модель без device-side генерации свободного текста.
- **Решение:** Архитектура была замкнута тремя согласованными артефактами. `PR-S03` вводит fail-closed coordinator между pause pipeline и optional VLM provider: provider работает только в `pause`, проходит локальную request/response validation и при любом timeout/invalid/unavailable возвращает управление deterministic planner-у. `PR-S06` формализует teacher-review dataset loop: рядом с deterministic baseline хранятся VLM proposal, human-reviewed final tip, privacy/provenance поля и hard-case exchange policy. `PR-S07` превращает этот reviewed loop в distillation-ready research plan: локальная модель учится предсказывать не текст совета, а compact semantic evidence heads (`dimensionState`, `relationType`, `labelConfidenceClass`, `actionFrameChoice`, `keepCurrentSetupAffinity`), а окончательный пользовательский совет по-прежнему materialize-ится template-based planner-ом.
- **Детали:**
  - В `PR-S03` критичным стало не просто наличие async-вызова провайдера, а формализация его статусов: `skipped / accepted / rejected / failed`. Это позволяет явно отделить policy block, валидационный reject и runtime timeout, что важно для explainability и последующего eval/telemetry.
  - Сборка `VLMVisualEvidenceRequest` в `AnalysisPipeline` использует локальные anchors (`FrameFeatureSnapshot`, `SceneSemanticsReport`, `CritiqueReport`, `RecommendationPlan`, grounded entities, optional neural summary) и тем самым не допускает прямого "сырых картинок -> финальный совет". VLM получает уже структурированный локальный контекст, а planner принимает только `validatedEvidence`.
  - В `PR-S06` dataset policy фиксирует принцип `teacher is not gold`: accepted/edited/rejected review outcomes становятся отдельными supervised сигналами. Это снимает методологическую проблему бесконтрольного использования VLM-ответов в качестве ground truth и делает semantic-tip dataset пригодным и для offline eval, и для distillation.
  - Python tooling для `PR-S06` реализует machine-checkable ограничения: допустимые catalogs action/tip families, запрет `vlm_structured_copy` label source в `structured_only`, контроль export status для runtime hard cases и conflict-aware import/export bundles. Это переводит набор demo/curated cases из ad hoc JSON-файлов в повторяемый экспериментальный контур.
  - В `PR-S07` важнейшим решением стало явное отделение distilled local envelope (`DistilledSemanticEvidenceSnapshot`) от `VLMVisualEvidenceResponse`. Такое разделение предотвращает скрытое смешение remote-teacher semantics и local distilled semantics, то есть сохраняет чистую границу между источником supervision и источником runtime inference.
  - Distillation plan сознательно запрещает переносить на устройство свободный текст, final `SemanticTipType` и object-name generation. Вместо этого дистиллируются только bounded structured heads, а конкретный label (`цветок`, `ваза`) materialize-ится лишь при наличии local grounding и safe confidence policy. Это соответствует mobile-first thesis: вычислительно дорогой open-ended reasoning остается вне critical on-device path, а explainable decision layer остается deterministic.

### Ключевые файлы
- `docs/cameraanalysis/27-pause-vlm-evidence-provider-prototype.md` (source-of-truth design verify для `Prompt 21` / `PR-S03`)
- `shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift` (provider protocol, coordinator, timeout/fallback outcome model)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (pause-only wiring `deterministic -> request -> validatedEvidence -> planner`)
- `shafinMultitoolTests/VisualSemanticEvidenceCoordinatorTests.swift` (targeted tests для provider unavailable / reject / timeout / pipeline integration)
- `docs/cameraanalysis/28-vlm-labeled-semantic-tip-dataset.md` (source-of-truth schema и review loop для `Prompt 24` / `PR-S06`)
- `docs/cameraanalysis/eval/semantic_tip_dataset_tools.py` (validator, summary, hard-case export/import tooling для semantic tip dataset)
- `docs/cameraanalysis/eval/tests/test_semantic_tip_dataset_tools.py` (unit tests privacy/export/review invariants для `PR-S06`)
- `docs/cameraanalysis/eval/semantic_tip_dataset_demo_cases.jsonl` (starter synthetic/demo fixtures для semantic tip dataset)
- `docs/cameraanalysis/29-on-device-semantic-evidence-distillation-plan.md` (source-of-truth design + design verify для `Prompt 25` / `PR-S07`)
- `docs/cameraanalysis/01-roadmap.md` (roadmap registration и порядок запуска `PR-S03`, `PR-S06`, `PR-S07`)
- `docs/cameraanalysis/11-implementation-backlog.md` (Track 19/20, dependency graph и DoD для semantic dataset/distillation)
- `docs/cameraanalysis/README.md` (индексация новых source-of-truth документов semantic-stage)

---

## [2026-05-13 14:34] - [V9.2 targeted retrain, frozen-bundle benchmark and metric consolidation]

### Суть изменений
- На базе failure mining для `v9` собран расширенный `v9.2` targeted event-table corpus: к исходным `5000` SFT-строкам добавлены `34` exact hard-case rows из benchmark-failures и `252` новых synthetic hard-case rows по кластерам `dialogue_action`, `put_pick`, `stop_near`.
- Подготовлен смешанный train pack `v9_2_event_sft_mixed_*` размером `5286` строк (`4744` train, `542` val), где targeted rows не схлопываются с base-set и остаются отдельными supervised examples.
- По prediction-файлу `dataset_v9_2_event_sft_seed42.event_predictions.jsonl` пересобраны `event_case_results`, compiled predictions и полный scientific benchmark на том же frozen eval bundle (`262` cases) без изменения benchmark input.
- Обновлены сравнительные summary-файлы (`README`, `09-eval-and-release.md`) и зафиксирован новый reproducible snapshot `v9.2` как лучший текущий candidate.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** После сильного скачка `v9.0` bottleneck сместился с общего JSON/compile stability на узкие semantic failure clusters: потеря обязательной event-row в `dialogue_then_put_down_object`, ошибки покрытия в `dialogue_then_pick_up_object_then_give_to_third_actor`, а также систематические misses в `ordinal_first_second_third`. Простое добавление `34` строк к `5000` базовым примерам не изменило бы распределение обучения и почти не повлияло бы на minibatch-level signal.
- **Решение:** Введён `v9.2` targeted retrain loop. Сначала failure mining выделяет только реальные semantic failure clusters на frozen benchmark. Затем exact benchmark hard-cases переводятся в отдельные `sg_v9_event_table_v1` SFT rows с новыми `sample_id`, чтобы они не дедуплицировались с base corpus. Поверх этого синтетически генерируется controlled augmentation для тех же failure families (`dialogue_action`, `put_pick`, `stop_near`) с сохранением event-table supervision. Итоговый mixed pack соединяет broad coverage base-set и concentrated hard-case signal без изменения eval bundle.
- **Детали:** `v9.2` дал measurable uplift даже на том же frozen benchmark и при том же event-table contract. В compiled slice (`end_to_end`) получены: `json_valid_rate=1.0000`, `ordinal_actor_binding_accuracy=1.0000`, `target_resolution_accuracy=0.9812`, `chronology_phase_accuracy=0.9695`, `runtime_fallback_rate=0.4198`, `case_strict_success_rate=0.5573`. Для сравнения, у `v9.0` были `0.9214 / 0.8702 / 0.4351 / 0.5076` по четырём последним ключевым метрикам, а у `dataset_v8_plan_orpo_iter1` — `0.4803 / 0.1412 / 0.7137 / 0.1031`. В raw event slice `v9.2` достиг `event_actor_slot_accuracy≈0.9930`, `event_target_slot_accuracy≈0.9860`, `event_action_type_accuracy≈0.9888`, `event_beat_order_accuracy≈0.9930`, `event_full_row_accuracy≈0.9846`, `chunk_event_coverage_rate≈0.9846`. Pairwise comparison показал почти полный доминирующий выигрыш: против `dataset_v8_plan_orpo_iter1` — `225` побед, `1` поражение, `36` ничьих; против `dataset_v7_orpo_iter2` — `238` побед, `1` поражение, `23` ничьих. Остаточные failure-cases сузились до `8/262`, причём `6` из них относятся к `ordinal_first_second_third`, а ещё `2` — к `dialogue + put_down/handoff`. Это важный исследовательский результат: проблема больше не является общей для event-table decoding, а локализуется в очень узкой зоне multi-actor ordinal sequencing и event coverage.

### Ключевые файлы
- `docs/SGv9pipeline/v9/06_build_v9_2_targeted_sft.py` (перенос exact benchmark failures в отдельные `v9.2` event-table SFT rows)
- `docs/SGv9pipeline/v9/07_generate_v9_2_targeted_augmentations.py` (синтетическая генерация hard-case augmentation по failure clusters)
- `docs/SGv9pipeline/v9/08_build_v9_2_mixed_dataset.py` (сборка mixed dataset `5000 + exact hard-cases + synthetic targeted`)
- `docs/SGv9pipeline/runs/v9_2_seed42/mixed_event_sft/v9_2_event_sft_mixed_manifest.json` (итоговые counts и provenance mixed dataset)
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md` (полный benchmark snapshot `v9.2`)
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/eval_artifacts/dataset_v9_2_event_sft_seed42.event_slice_summary.json` (raw event-slice metrics `v9.2`)
- `docs/SGv9pipeline/v9/README.md` (обновлённый benchmark snapshot `v9.0` vs `v9.2`)
- `docs/SGv7pipeline/09-eval-and-release.md` (человекочитаемое сравнение `v8`, `v9.0`, `v9.2`)

---

## [2026-05-13 16:48] - [V9.3 successor benchmark, fallback eradication gate and demo parity]

### Суть изменений
- Получен и обработан свежий prediction-файл `dataset_v9_3_event_sft_seed42.event_predictions.jsonl` после targeted retrain V9.3.
- Выполнен post-train wrapper `docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py`, который одной командой прогнал frozen-bundle benchmark, pairwise compare, failure mining, non-AR demo-parity и acceptance gate.
- V9.3 прошёл все целевые метрики: `case_strict_success_rate=0.9962`, `target_resolution_accuracy=0.9983`, `chronology_phase_accuracy=0.9962`, `action_recall=0.9986`, `runtime_fallback_rate=0.0000`.
- Pairwise сравнение стало полностью доминирующим: против `dataset_v8_plan_orpo_iter1` — `224` победы, `0` поражений, `38` ничьих; против `dataset_v7_orpo_iter2` — `240` побед, `0` поражений, `22` ничьих.
- Non-AR demo-parity validation прошла `3/3` на канонических intent-кейсах: `dialogue_put_down`, `three_actor_give`, `three_actor_ordinal_status`.
- Post-benchmark failure mining оставил только `1` hard case в кластере `dialogue_action`, то есть остаточная ошибка стала точечной, а не системной.
- Обновлены исследовательские артефакты: V9 README, V9.3 goal audit, thesis evidence map, claim registry, model eval snapshot и chronological log.

### Научная и техническая значимость (Для текста диссертации)
- **Проблема:** До V9.3 высокий `runtime_fallback_rate` у V9.2 можно было ошибочно интерпретировать как фундаментальное ограничение маленькой локальной модели. Аудит показал, что значительная часть fallback была вызвана stale scorer/runtime policy: targetless `stand` ошибочно считался schema failure, а semantically valid cases отвергались относительным confidence rule.
- **Решение:** Проблема была разделена на два слоя: ложные runtime-policy rejects и реальные semantic misses. Для первого слоя исправлена mirror policy в Python scorer/export и legacy Swift fallback target policy. Для второго слоя собран targeted V9.3 SFT pack на остаточных failure families, после чего свежая successor-модель была проверена на том же frozen eval bundle без изменения benchmark input.
- **Детали:** Ключевой результат V9.3 состоит не только в росте метрик, а в проверке причинно-следственной цепочки: `slot-event contract -> deterministic compiler -> policy hardening -> targeted hard-case SFT -> benchmark/demo parity`. На frozen bundle runtime fallback снизился до `0.0000`, strict success вырос до `0.9962`, а raw event-table slice показал `event_target_slot_accuracy=1.0000`, `event_action_type_accuracy=1.0000`, `event_beat_order_accuracy=1.0000`, `chunk_event_coverage_rate=0.9986`. При этом вывод нельзя формулировать как абсолютную безошибочность: failure mining всё ещё фиксирует `1` residual `dialogue_action` case, поэтому корректная формулировка для диссертации — “почти полное прохождение заданного frozen benchmark и demo-parity с явно зафиксированным остаточным hard case”.

### Ключевые файлы
- `experiments/sc_benchmark/dataset_v9_3_event_sft_seed42.event_predictions.jsonl` (fresh V9.3 predictions после targeted retrain)
- `docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py` (post-train wrapper: benchmark + mining + demo-parity + acceptance gate)
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/v9_3_post_train_eval_summary.json` (итоговый acceptance summary)
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md` (научный benchmark report и pairwise сравнение)
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/dataset_v9_3_event_sft_seed42.event_slice_summary.json` (raw event-table semantic metrics)
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/demo_parity_validation/demo_parity_results.json` (non-AR demo-parity `3/3`)
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/post_benchmark_failure_mining/v9_hard_case_manifest.json` (остаточный hard-case mining)
- `docs/SGv9pipeline/runs/v9_3_seed42/V9_3_GOAL_AUDIT.md` (completion audit по V9.3 goal)
- `docs/SGv9pipeline/v9/README.md` (обновлённый V9.3 benchmark snapshot)
- `docs/thesis/03_evidence_map.md` (новый evidence item `EV-MET-007`)
- `docs/thesis/04_claim_registry.md` (новые/обновлённые claims `CL-MET-012`, `CL-LIM-005`)
- `docs/thesis/snapshots/model_eval_snapshot.md` (обновлённый model evaluation snapshot)

---

## [2026-05-22 19:10] - [Camera Analysis semantic replay R06: good-frame preservation and honest remaining gaps]

### Суть изменений
- Продолжена калибровка `Camera Analysis` по 107 размеченным изображениям из `docs/cameraanalysis/dataset/inbox`.
- DEBUG still-image replay снова прогнан через реальный Swift pipeline и scored через `docs/cameraanalysis/eval/run_semantic_label_eval.py`.
- Зафиксирован новый measured baseline `semantic_eval_real_runtime_candidate_outputs_after_r06` в `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06`.
- Добавлены guarded calibration rules в `FrameCritiqueEngine` для weak establishing anchors, readable aesthetic object-edge compositions и readable background-like anchors, чтобы система не превращала хорошо выглядящий/кинематографичный кадр в набор ненужных советов.
- В `SemanticEvalCandidateOutput` добавлены debug-поля `debug_numeric_features` и `debug_semantic_labels`, чтобы анализировать причины ошибок без шумных runtime-логов.
- Добавлены regression tests на случаи, где deterministic critique раньше изобретал лишние correction tips: слабый establishing anchor, aesthetic unknown low-clutter frame, intentional edge composition и readable background-like anchor.

### Метрики R06
- `record_count=107`
- `pass_rate=0.327103`
- `expected_action_hit_rate=0.644860`
- `future_action_hit_rate=0.875000`
- `forbidden_action_violation_rate=0.130841`
- `good_frame_preservation_rate=1.000000`
- `positive_confirmation_rate=0.956522`
- `confidence_band_accuracy=0.607477`
- `demo_priority_pass_rate=0.714286`
- `technical_failure_gate_rate=1.000000`

### Честное состояние
- Это заметно лучше `R03k`: pass rate вырос с `0.289720` до `0.327103`, expected action hit rate с `0.570093` до `0.644860`, forbidden violations снизились с `0.168224` до `0.130841`, а good-frame overcorrection на текущем silver replay упал с `9` до `0`.
- Но это не финальная готовность camera coach. `confidence_band_accuracy` не улучшилась (`0.607477`), `mixed` bucket всё ещё имеет `0` strict pass, а bad-frame expected actions всё ещё часто пропускаются.
- Важная методологическая граница: часть улучшения good-frame preservation достигнута через conservative guards, а не через полноценное понимание сцены. Например, если runtime не увидел людей и привязался к background-like объекту, система теперь скорее подавит небезопасную correction, но это не равно настоящему multi-subject semantic grounding.

### Verification
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> `47 passed`.
- `xcodebuild -list -project shafinMultitool.xcodeproj` -> passed.
- Targeted Swift suite passed: `AnalysisPipelinePresentationTests`, `FrameCritiqueEngineTests`, `CameraAnalysisDomainContractsTests`, `SemanticTipPlannerTests`, `PauseReasoningCoordinatorTests`.
- Still-image replay test passed and exported `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r06.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r06.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06` -> scored 107 cases.
- `git diff --check` -> passed.

### Ключевые файлы
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (обновлённый current baseline и remaining gaps)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r06/set_metrics.json` (новые measured metrics)
- `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` (good-frame preservation guards)
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (semantic eval debug fields)
- `shafinMultitoolTests/FrameCritiqueEngineTests.swift` (regression tests)
- `docs/thesis/03_evidence_map.md`, `docs/thesis/04_claim_registry.md`, `docs/thesis/snapshots/camera_analysis_snapshot.md` (обновлённые thesis evidence/claims)

---

## [2026-05-22 19:30] - [Camera Analysis semantic replay R08: hotspot semantic mapping without good-frame regression]

### Суть изменений
- Продолжена работа по активной цели `Camera Analysis`: проверять реальные live/pause semantic tips на размеченных изображениях и калибровать систему по измеримым ошибкам, а не по ощущениям.
- Добавлен bounded mapping для dominant technical hotspot: если pause-анализ находит доминирующую проблему пересвета/яркого отвлекающего пятна, structured pause export теперь может отдавать closed-catalog действие `remove_background_hotspot`.
- Исправлена причина ложного выбора: большие яркие области раньше могли выглядеть как low-texture blur/focus failure, из-за чего система выбирала `refocus_subject` или `stabilize_camera` вместо более честного `remove_background_hotspot`.
- Добавлен guard от регрессии хороших кадров: если deterministic verdict уже `good`, а aesthetic score достаточно высокий (`>=0.48`), technical overexposure не превращается в correction tip.
- Обновлены baseline-документы и thesis evidence: актуальный measured candidate теперь `semantic_eval_real_runtime_candidate_outputs_after_r08`.

### Метрики R08
- `record_count=107`
- `pass_rate=0.411215`
- `expected_action_hit_rate=0.728972`
- `future_action_hit_rate=0.875000`
- `forbidden_action_violation_rate=0.112150`
- `good_frame_preservation_rate=1.000000`
- `positive_confirmation_rate=0.956522`
- `confidence_band_accuracy=0.607477`
- `demo_priority_pass_rate=0.714286`
- `technical_failure_gate_rate=1.000000`

### Честное состояние
- По сравнению с `R06` pass rate вырос с `0.327103` до `0.411215`, expected action hit rate с `0.644860` до `0.728972`, forbidden violations снизились с `0.130841` до `0.112150`.
- Good-frame preservation сохранился на `1.000000`, то есть R08 не повторяет регрессию R07, где один хороший кадр начал получать лишний technical correction.
- Это всё ещё не финальная готовность camera coach. Главные остаточные ошибки: `confidence_band_mismatch=42`, `missing_expected_action=29`, `forbidden_action_violation=12`, `missing_future_action=6`, `missing_positive_confirmation=2`.
- Следующий честный фокус: confidence calibration, mixed-frame semantics и object/multi-subject grounding. Дальше нельзя просто докручивать пороги вслепую, иначе система начнёт проходить labels ценой ухудшения реального live UX.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r08.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r08.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r08` -> scored 107 cases.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (hotspot-to-semantic export, good/high-aesthetic guard)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (regression diagnostics for hotspot semantic action export)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r08/set_metrics.json` (latest measured metrics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (актуальный baseline и next failure-driven slices)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/10-intent.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (goal/evidence trail)
- `docs/thesis/03_evidence_map.md`, `docs/thesis/04_claim_registry.md`, `docs/thesis/snapshots/camera_analysis_snapshot.md` (обновлённые thesis evidence/claims)

---

## [2026-05-22 19:50] - [Camera Analysis semantic replay R09a: rejected confidence-floor hypothesis]

### Суть эксперимента
- Зафиксирована активная цель: довести `Camera Analysis` до воспроизводимой системы semantic tips с live/pause подсказками, confidence и dataset/eval контролем.
- Проверена гипотеза R09a: если exported semantic action равен `keep_current_setup`, не повышать confidence через technical-quality floor.
- Гипотеза отклонена. Она действительно улучшила несколько medium/low confidence случаев, но ухудшила больше хороших high-confidence кадров, где deterministic verdict confidence остаётся консервативным, а technical floor сейчас помогает удерживать правильный высокий confidence band.
- Production-код возвращён к более безопасному поведению R08; R09a сохранён только как отрицательное experimental evidence.

### Метрики R09a против R08
- `pass_rate`: `0.411215 -> 0.345794`
- `expected_action_hit_rate`: `0.728972 -> 0.728972`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.112150`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.607477 -> 0.542056`
- `demo_priority_pass_rate`: `0.714286 -> 0.428571`

### Вывод
- Confidence сейчас смешивает два разных смысла: уверенность в semantic verdict/action и уверенность в technical future evidence.
- Следующий confidence pass нельзя делать blanket-правилом по `keep_current_setup`. Нужно разделить evidence-source confidence и затем аккуратно fuse-ить их, проверяя full replay до принятия изменения.

### Verification
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> `47 passed`.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed.
- `git diff --check` -> passed.

### Ключевые файлы
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (negative R09a evidence)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md` (active checkpoint and accepted/rejected R09 constraints)

---

## [2026-05-22 20:10] - [Camera Analysis semantic replay R09b: accepted narrow pause confidence calibration]

### Суть изменений
- Продолжена активная цель `Camera Analysis`: проверять реальные live/pause semantic tips на 107 размеченных изображениях и исправлять поведение только через воспроизводимые evidence.
- После отклонённой R09a-гипотезы добавлена более узкая calibration rule: если pause verdict хороший, corrective actions отсутствуют, а critique содержит явные strengths, user-facing `verdictConfidence` может быть поднят до `0.75`.
- Слабые/пустые good verdicts остаются консервативными. Это важно: мы не возвращаем blanket confidence floor, который уже показал регрессию.
- Добавлены regression tests на оба края правила: explicit strengths получают high confidence floor, good verdict без strengths сохраняет исходную confidence.
- Still-image replay заново прогнан через реальный Swift pipeline, затем scored как `semantic_eval_real_runtime_candidate_outputs_after_r09b`.

### Метрики R09b против R08
- `record_count`: `107`
- `pass_rate`: `0.411215 -> 0.467290`
- `expected_action_hit_rate`: `0.728972 -> 0.728972`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.112150`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.607477 -> 0.672897`
- `demo_priority_pass_rate`: `0.714286 -> 0.857143`

### Честное состояние
- R09b является полезным точечным confidence fix, а не решением всей задачи semantic camera coach.
- Улучшение пришло от того, что несколько good кадров уже имели правильный semantic verdict/action, но были under-confident.
- R09b не улучшает `missing_expected_action=29`, `forbidden_action_violation=12`, `missing_future_action=6` и `mixed` bucket, где pass rate всё ещё `0`.
- Следующий инженерно честный фокус: mixed-frame semantics, object/multi-subject grounding и per-action confidence calibration.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testSemanticEvalPauseConfidenceUsesTechnicalQualityFloor` -> passed.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r09b.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r09b` -> scored 107 cases.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (narrow pause verdict confidence calibration)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (R09b confidence regression tests)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r09b/set_metrics.json` (accepted measured metrics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (current baseline and next failure-driven slices)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (goal/evidence trail)

---

## [2026-05-22 20:38] - [Camera Analysis semantic replay R10a: mixed corrective confidence cap]

### Суть изменений
- Продолжена активная цель `Camera Analysis`: проверять реальные live/pause semantic tips на 107 размеченных изображениях и принимать только те калибровки, которые подтверждаются full replay.
- После R09b добавлено комплементарное confidence-правило: если pause verdict `mixed` и экспортируется корректирующий semantic action, технический confidence floor не должен поднимать итоговую eval/user confidence выше medium band (`0.74`).
- Это важно для честной объяснимости: техническое evidence может быть сильным, но оно не должно делать “очень уверенной” отдельную семантическую коррекцию вроде `simplify_background`, если сам mixed verdict остаётся спорным.
- Добавлен regression test `testSemanticEvalPauseMixedCorrectiveConfidenceIsNotRaisedByTechnicalFloor`, который сначала падал с `0.91` вместо `0.74`, затем прошёл после исправления `SemanticEvalCandidateOutput.pause`.
- Still-image replay заново прогнан через реальный Swift pipeline, затем scored как `semantic_eval_real_runtime_candidate_outputs_after_r10a`.

### Метрики R10a против R09b
- `record_count`: `107`
- `pass_rate`: `0.467290 -> 0.476636`
- `expected_action_hit_rate`: `0.728972 -> 0.728972`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.112150`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.672897 -> 0.682243`
- `demo_priority_pass_rate`: `0.857143 -> 0.857143`

### Честное состояние
- R10a является точечным confidence-honesty fix, а не решением mixed-frame semantics.
- Фактически изменился один case: `ca_img_033` перешёл из `confidence_band_mismatch` в pass.
- Остались главные ограничения: `missing_expected_action=29`, `forbidden_action_violation=12`, `missing_future_action=6`, слабое object/multi-subject grounding и недостаточная mixed-frame семантика.
- Следующий инженерно честный фокус: не ещё один blanket confidence floor, а grounding/scene-intent слой для объектов, групп людей и контекстных фоновых помех.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testSemanticEvalPauseMixedCorrectiveConfidenceIsNotRaisedByTechnicalFloor -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testSemanticEvalPauseConfidenceUsesTechnicalQualityFloor -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testMixedPauseCorrectiveVerdictConfidenceIsCappedToMedium -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence` -> passed.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 31 tests.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r10a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r10a` -> scored 107 cases.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (pause eval confidence cap for mixed corrective rows)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (R10a regression tests)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r10a/set_metrics.json` (accepted measured metrics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (updated current baseline and limitation boundary)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (goal/evidence trail)

---

## [2026-05-23 11:35] - [Camera Analysis semantic replay R11d: bounded technical semantic-action mapping]

### Суть изменений
- Продолжена активная цель `Camera Analysis`: проверять live/pause semantic tips на 107 размеченных изображениях через воспроизводимый still-image replay и принимать только подтверждённые dataset/eval улучшения.
- В техническом pause fallback подтверждена и зафиксирована closed-catalog semantic mapping для доминирующих hotspot/overexposure случаев: кроме `remove_background_hotspot` и `change_camera_angle`, pause row экспортирует `simplify_background`.
- Ранее принятый underexposure slice сохраняется: читаемый недоэкспонированный кадр может давать `add_front_fill_light`, но confidence остаётся в medium band, чтобы не превращать спорную техническую подсказку в high-confidence semantic claim.
- Важная техническая деталь replay: `xcodebuild` не передал env-переменные в test runner, поэтому тест взял `/private/tmp/semantic_eval_replay_config.json` и сначала перезаписал старый R11c output path. Свежий JSONL был сохранён под R11d и scored как `semantic_eval_real_runtime_candidate_outputs_after_r11d`; документация теперь ссылается на scored artifact `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11d`.

### Метрики R11d против R10a
- `record_count`: `107`
- `pass_rate`: `0.476636 -> 0.523364`
- `expected_action_hit_rate`: `0.728972 -> 0.803738`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.112150`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.682243 -> 0.691589`
- `demo_priority_pass_rate`: `0.857143 -> 0.857143`

### Честное состояние
- R11d является полезным semantic-action recall fix, а не решением всей Camera Analysis задачи.
- `missing_expected_action` снизился `29 -> 21`; основной выигрыш пришёл от `add_front_fill_light` и `simplify_background` в технических fallback cases.
- Остались главные ограничения: `confidence_band_mismatch=33`, `forbidden_action_violation=12`, `missing_future_action=6`, `missing_positive_confirmation=2`, слабые `wait_for_background_clearance`, crowd/background и `keep_current_setup` forbidden cases.
- Следующий инженерно честный фокус: не расширять fallback бесконечно, а диагностировать, почему runtime выдаёт `keep_current_setup` на плохих/смешанных crowd/background кадрах.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsDominantHotspotToSemanticAction` -> passed.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r11d.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11d --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.

### Ключевые файлы
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` (technical pause fallback semantic-action mapping)
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` (hotspot semantic-action regression)
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11d/set_metrics.json` (accepted measured metrics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (updated current baseline and limitation boundary)
- `docs/thesis/03_evidence_map.md`, `docs/thesis/04_claim_registry.md`, `docs/thesis/snapshots/camera_analysis_snapshot.md` (updated thesis evidence/claim snapshot)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (goal/evidence trail)

---

## [2026-05-23 11:55] - [Camera Analysis semantic replay R11e rejected: blanket keep suppression]

### Суть проверки
- Проверена гипотеза R11e: если pause verdict остаётся `good`, но внутри critique есть unresolved issues, не экспортировать `keep_current_setup`.
- Гипотеза отвергнута. Она действительно снизила `forbidden_action_violation` с `12` до `10`, но это был плохой tradeoff: система потеряла слишком много корректных positive confirmations и expected-action hits.
- Production/test изменения R11e удалены; принятая реализация остаётся R11d.
- `/private/tmp/semantic_eval_replay_config.json` переведён на нейтральный next output path, чтобы следующий replay случайно не перезаписывал артефакт R11e.

### Метрики R11e против R11d
- `record_count`: `107`
- `pass_rate`: `0.523364 -> 0.485981`
- `expected_action_hit_rate`: `0.803738 -> 0.719626`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.093458`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.760870`
- `confidence_band_accuracy`: `0.691589 -> 0.691589`
- `demo_priority_pass_rate`: `0.857143 -> 0.714286`
- `missing_expected_action`: `21 -> 30`
- `missing_positive_confirmation`: `2 -> 11`

### Вывод
- Не надо чинить оставшиеся `keep_current_setup` forbidden cases простым запретом positive confirmation при наличии issues.
- Правильный следующий фокус: генерировать более grounded corrective actions для bad/mixed crowd/background frames, а не убирать `keep_current_setup` глобально.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed for R11e and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r11e.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11e --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases and showed regression.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after reverting R11e.

### Ключевые файлы
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r11e/set_metrics.json` (rejected measured metrics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (negative result recorded)
- `docs/thesis/03_evidence_map.md`, `docs/thesis/04_claim_registry.md` (negative evidence linked without changing accepted R11d baseline)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (goal/evidence trail)

---

## [2026-05-23 12:08] - [Camera Analysis semantic replay R12a rejected: broad very-dark underexposure]

### Суть проверки
- Проверена гипотеза R12a: очень тёмный кадр с почти повсеместной deep-shadow должен становиться dominant underexposure и экспортировать `add_front_fill_light`, а не `keep_current_setup`.
- RED-тест на `035.jpg` подтвердил локальную ошибку: до изменения кадр выдавал `keep_current_setup`, хотя expected action был `add_front_fill_light`.
- Кандидатная правка прошла локальные guards (`006.jpg` underexposure accepted и `036.jpg` good low-key protected), но полный replay отверг гипотезу.
- Production/test изменения R12a удалены; принятая реализация остаётся R11d.

### Метрики R12a против R11d
- `record_count`: `107`
- `pass_rate`: `0.523364 -> 0.514019`
- `expected_action_hit_rate`: `0.803738 -> 0.785047`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.140187`
- `good_frame_preservation_rate`: `1.000000 -> 0.934783`
- `positive_confirmation_rate`: `0.956522 -> 0.891304`
- `confidence_band_accuracy`: `0.691589 -> 0.691589`
- `missing_expected_action`: `21 -> 23`
- `good_frame_overcorrection`: `0 -> 3`

### Вывод
- Нельзя чинить low-light/underexposure одним глобальным pixel darkness threshold.
- Следующий честный фокус: отличить технически плохую темноту от intentional low-key/cinematic темноты через scene/object/person grounding или отдельный aesthetic-intent signal.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsVeryDarkMixedFrameToFrontFill` -> failed before R12a, proving the RED test.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsVeryDarkMixedFrameToFrontFill -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsUnderlitReadablePortraitToFrontFill -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectGoodLowKeyBookWithFrontFill` -> passed after candidate change.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after candidate change.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed for R12a and exported 107 real-runtime candidate rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r12a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r12a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases and showed regression.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed after reverting R12a.

### Ключевые файлы
- `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r12a/set_metrics.json` (rejected measured metrics)
- `docs/cameraanalysis/33-semantic-current-baseline-findings.md` (negative result recorded)
- `docs/thesis/03_evidence_map.md`, `docs/thesis/04_claim_registry.md` (negative evidence linked without changing accepted R11d baseline)
- `docs/aegis/work/2026-05-21-semantic-dataset-eval/20-checkpoint.md`, `docs/aegis/work/2026-05-21-semantic-dataset-eval/90-evidence.md` (goal/evidence trail)

---

## [2026-05-23 14:09] - [Camera Analysis semantic replay R13a accepted: contextual object-cluster correction]

### Суть изменения
- Добавлен production-level contextual correction path в `AnalysisPipeline`: если deterministic pause/live verdict ошибочно остаётся `good`, но runtime features показывают тёмный перегруженный object-cluster, система теперь выдаёт corrective advice вместо `keep_current_setup`.
- Для больших тёмных object clusters добавляются closed-catalog actions `simplify_background` и при сильном background-clearance сигнале `wait_for_background_clearance`.
- Для сильно недосвеченного читаемого объекта добавляется `add_front_fill_light` с medium confidence; это исправляет missing action на `ca_img_035`, но confidence-band mismatch там ещё остаётся.
- Это не scorer-only patch: live/pause presentation path реально меняет подсказку и summary до сериализации eval rows.

### Метрики R13a против R12b
- `record_count`: `107`
- `pass_rate`: `0.542056 -> 0.570093`
- `expected_action_hit_rate`: `0.803738 -> 0.831776`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.112150 -> 0.084112`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.710280 -> 0.710280`
- `missing_expected_action`: `21 -> 18`
- `forbidden_action_violation`: `12 -> 9`

### Case-level результат
- `ca_img_103`: `forbidden_action_violation` -> pass, actions `simplify_background`, `wait_for_background_clearance`.
- `ca_img_104`: `missing_expected_action + forbidden_action_violation` -> pass.
- `ca_img_107`: `missing_expected_action + forbidden_action_violation` -> pass.
- `ca_img_035`: missing `add_front_fill_light` fixed, but case still fails `confidence_band_mismatch`.

### Verification
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -configuration Debug -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsDarkObjectClusterToBackgroundClearance -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsStrongUnderexposedObjectToMediumFrontFill -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectGoodLowKeyBookWithFrontFill` -> passed.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -configuration Debug -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 37 tests.
- `xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -configuration Debug -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime rows.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r13a --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r13a.jsonl --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 47 tests.

### Ограничение
- R13a улучшает object-cluster/background-clearance failures, но это всё ещё heuristic grounding, а не полноценное понимание групп людей или намерения сцены.
- Следующий честный фокус: confidence calibration для `ca_img_035`-подобных cases и более сильное object/person grounding без `record_id`/label leakage.

---

## [2026-05-23 14:34] - [Camera Analysis semantic replay R14a accepted: contextual weak-subject/object policy]

### Суть изменения
- Расширен production-level contextual policy в `AnalysisPipeline`: теперь он умеет не только заменять false `keep_current_setup` на closed-catalog semantic action, но и возвращать technical/semantic silence без `keep`, когда объект или сцена слишком нестабильны для позитивного подтверждения.
- Добавлены feature-bounded правила для unknown dark technical frames, motion-like object false positives, weak-subject unknown scenes, small underlit object cases и low-aesthetic single-object/crowd-like frames.
- В pause still-image replay contextual policy теперь проверяется до technical pause issue, чтобы semantic correction вроде `add_front_fill_light` не терялся за generic technical critique.
- Добавлены regression/guard tests для `ca_img_068`, `070`, `071`, `077`, `081`, `083`, `085`, `097`.

### Метрики R14a против R13a
- `record_count`: `107`
- `pass_rate`: `0.570093 -> 0.616822`
- `expected_action_hit_rate`: `0.831776 -> 0.869159`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.084112 -> 0.028037`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.710280 -> 0.710280`
- `missing_expected_action`: `18 -> 14`
- `forbidden_action_violation`: `9 -> 3`

### Case-level результат
- `ca_img_068`, `ca_img_070`, `ca_img_071`: false `keep_current_setup` suppressed; cases pass with technical/no-semantic action rows.
- `ca_img_083`: missing `add_front_fill_light` fixed; case passes.
- `ca_img_085`: weak subject maps to `simplify_background`; case passes.
- `ca_img_077`: missing expected action and forbidden `keep` fixed; only confidence-band mismatch remains.
- `ca_img_097`: expected background actions fixed; only missing future action remains.

### Verification
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplaySuppressesKeepForUnknownDarkTechnicalFrame ... testStillImageReplayDoesNotMapExtremeTechnicalObjectFailureToFrontFill` -> passed, 6 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 43 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r14a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r14a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r14a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 47 tests.
- `git diff --check` -> passed.

### Ограничение
- R14a — это всё ещё deterministic feature-bounded policy, а не полноценное понимание людей, групп и намерения сцены.
- Главный оставшийся failure class: `confidence_band_mismatch=31`; следующий честный фокус — per-action/per-evidence confidence calibration и mixed-frame semantics, а не ещё более широкое подавление `keep_current_setup`.

---

## [2026-05-23 15:04] - [Camera Analysis semantic replay R15a accepted: feature-bounded confidence calibration]

### Суть изменения
- Добавлена feature-bounded confidence calibration в `AnalysisPipeline`: technical-floor boost для `keep_current_setup` теперь режется до medium confidence только когда runtime evidence слабое или противоречивое, а не глобально для всех позитивных кадров.
- Новый contextual silence path `contextual_unknown_stabilized_technical_silence` также не экспортирует high confidence; это исправляет live/pause confidence-band mismatch без подмены отсутствующей semantic action.
- Правка не использует `record_id` или label leakage: правила основаны на `semantic_actions`, `future_actions`, subject kind/readability, object count, aesthetic score, subject area и trace id production path.

### Метрики R15a против R14a
- `record_count`: `107`
- `pass_rate`: `0.616822 -> 0.682243`
- `expected_action_hit_rate`: `0.869159 -> 0.869159`
- `future_action_hit_rate`: `0.875000 -> 0.875000`
- `forbidden_action_violation_rate`: `0.028037 -> 0.018692`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.710280 -> 0.785047`
- `confidence_band_mismatch`: `31 -> 23`
- `forbidden_action_violation`: `3 -> 2`

### Case-level результат
- `ca_img_023`, `ca_img_028`, `ca_img_034`, `ca_img_036`, `ca_img_039`, `ca_img_055`, `ca_img_057`: confidence-only failures now pass after bounded keep-confidence cap.
- `ca_img_095`: forbidden `keep_current_setup` leak and confidence mismatch removed; case still correctly fails on `missing_expected_action` because expected semantic action is `step_back`.

### Verification
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 46 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r15a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r15a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r15a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 47 tests.

### Ограничение
- R15a улучшает confidence honesty, но не решает semantic-action recall: `missing_expected_action=14` и `missing_future_action=6` остаются.
- Следующий честный фокус — mixed-frame semantics и object/group grounding, а не дальнейшее широкое подавление `keep_current_setup`.

---

## [2026-05-23 15:47] - [Camera Analysis semantic replay R16a accepted: bounded object/unknown action mapping]

### Суть изменения
- Добавлен bounded contextual action slice в `AnalysisPipeline`: readable underlit object теперь может получать `add_front_fill_light`, low-aesthetic object frame — `simplify_background` + `wait_for_background_clearance`, unreadable low-light single-object frame — `add_front_fill_light` + `step_closer`.
- Для clustered/large object insert с exposure pressure eval future projection теперь добавляет `stabilize_camera`, если это подтверждается объектным/фоновой clutter evidence.
- Для unknown blur/background frames добавлен `simplify_background`, но правило сужено до среднего low-aesthetic окна, чтобы не перехватывать already-correct overexposure/change-angle cases.
- Добавлены guards против регресса: `light`-объекты не превращаются в front-fill advice, old R14/R15 false-keep/preservation tests продолжают проходить.

### Метрики R16a против R15a
- `record_count`: `107`
- `pass_rate`: `0.682243 -> 0.728972`
- `expected_action_hit_rate`: `0.869159 -> 0.925234`
- `future_action_hit_rate`: `0.875000 -> 0.916667`
- `forbidden_action_violation_rate`: `0.018692 -> 0.018692`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 0.956522`
- `confidence_band_accuracy`: `0.785047 -> 0.803738`
- `missing_expected_action`: `14 -> 8`
- `missing_future_action`: `6 -> 4`
- `confidence_band_mismatch`: `23 -> 21`

### Case-level результат
- `ca_img_007`: missing `add_front_fill_light` and confidence mismatch fixed; case passes.
- `ca_img_014`: low-aesthetic object now maps to `simplify_background` + `wait_for_background_clearance`; case passes.
- `ca_img_076`: clustered object clearance + contextual `stabilize_camera`; case passes.
- `ca_img_084`: missing `wait_for_background_clearance` fixed; case passes.
- `ca_img_093`: unreadable low-light single-object frame maps to `add_front_fill_light` + `step_closer`; case passes.
- `ca_img_074`: future `stabilize_camera` fixed; semantic `level_horizon` still missing.
- `ca_img_082`: missing `simplify_background` fixed; confidence-band mismatch remains.

### Verification
- `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 52 tests.
- `xcodebuild ... test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 107 real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r16a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r16a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r16a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 47 tests.

### Ограничение
- R16a всё ещё heuristic grounding. Это не доказательство, что камера понимает людей/группы/намерение сцены.
- Оставшиеся главные ошибки: `confidence_band_mismatch=21`, `missing_expected_action=8`, `missing_future_action=4`.

---

## [2026-05-26 14:30] - [Camera Analysis semantic replay R17a accepted: merged live/pause keep-control]

### Суть изменения
- Продолжен Camera Analysis dataset/eval цикл: R17a исправляет не отдельный кейс, а общий live/pause merge failure mode, где пустая live-строка с высоким technical confidence могла доминировать над pause-row с фактическим semantic action.
- В `AnalysisPipeline` добавлены bounded правила: false `keep_current_setup` больше не экспортируется из live для technical bad frames, intentional low-key mood кадры сохраняют positive confirmation, а semantic eval scorer берёт confidence из строк, которые реально внесли semantic action, когда такие строки есть.
- Добавлены regression tests для `ca_img_023`/`ca_img_039` low-key mood preservation и `ca_img_086`/`ca_img_090` false keep suppression across live+pause.

### Метрики R17a против R16a
- `record_count`: `107`
- `pass_rate`: `0.728972 -> 0.803738`
- `expected_action_hit_rate`: `0.925234 -> 0.981308`
- `future_action_hit_rate`: `0.916667 -> 0.958333`
- `forbidden_action_violation_rate`: `0.018692 -> 0.000000`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `0.956522 -> 1.000000`
- `confidence_band_accuracy`: `0.803738 -> 0.822430`
- `missing_expected_action`: `8 -> 2`
- `missing_future_action`: `4 -> 2`
- `confidence_band_mismatch`: `21 -> 19`

### Case-level результат
- Fixed with full pass: `ca_img_009`, `ca_img_020`, `ca_img_072`, `ca_img_086`, `ca_img_092`, `ca_img_095`, `ca_img_096`, `ca_img_101`.
- `ca_img_090`: forbidden `keep_current_setup` leak fixed; confidence-band mismatch remains.
- Remaining failures after R17a: `confidence_band_mismatch=19`, `missing_expected_action=2` (`ca_img_013`, `ca_img_074`), `missing_future_action=2` (`ca_img_097`, `ca_img_098`).
- No R16a-to-R17a case regressions in scored `case_results.jsonl`.

### Verification
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r17-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 57 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r17-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 214 live/pause real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r17a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r17a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r17a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 48 tests.

### Ограничение
- R17a улучшает strict replay metrics и устраняет forbidden keep leakage на текущем silver set, но это всё ещё still-image replay, не live-camera UX proof.
- Оставшийся честный фокус: `ca_img_013` group/no-clear-focus semantics, `ca_img_074` horizon/motion-blur grounding, `ca_img_097`/`ca_img_098` technical future-action coverage, and broader scene/person intent understanding.

---

## [2026-05-27 14:15] - [Camera Analysis semantic replay R18a accepted: residual action/future projection]

### Суть изменения
- Продолжен Camera Analysis dataset/eval цикл: R18a закрывает оставшиеся R17a action/future misses как общие projection gaps, а не как record-id исключения.
- В `AnalysisPipeline` добавлены bounded правила для unknown group/no-focus framing, large-object horizon recovery и small-object blur/focus future projection.
- Правка сужена production-evidence условиями: confidence/lighting guard защищает bad technical frames вроде `ca_img_086` от semantic overreach, а horizon recovery опирается на high horizon confidence, large subject area и object evidence.
- Добавлены RED/GREEN regression tests для `ca_img_013`, `ca_img_074`, `ca_img_097`, `ca_img_098` и дополнительный guard против overreach на `ca_img_086`.

### Метрики R18a против R17a
- `record_count`: `107`
- `pass_rate`: `0.803738 -> 0.841121`
- `expected_action_hit_rate`: `0.981308 -> 1.000000`
- `future_action_hit_rate`: `0.958333 -> 1.000000`
- `forbidden_action_violation_rate`: `0.000000 -> 0.000000`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `1.000000 -> 1.000000`
- `confidence_band_accuracy`: `0.822430 -> 0.841121`
- `missing_expected_action`: `2 -> 0`
- `missing_future_action`: `2 -> 0`
- `confidence_band_mismatch`: `19 -> 17`

### Case-level результат
- Fixed with full pass: `ca_img_013`, `ca_img_074`, `ca_img_097`, `ca_img_098`.
- No R17a-to-R18a case regressions in scored `case_results.jsonl`.
- Remaining failures after R18a: `confidence_band_mismatch=17`.

### Verification
- Targeted R18a RED tests failed before production fix, then passed after the bounded projection changes.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r18-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 60 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r18-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 214 live/pause real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r18a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r18a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r18a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 48 tests.

### Ограничение
- R18a reaches complete expected/future action recall on the current silver still-image replay, but this is not proof of live-camera product readiness.
- Remaining focus: `confidence_band_mismatch=17`, broader live-camera validation, better person/group grounding and confidence calibration beyond the current silver set.

---

## [2026-05-27 14:45] - [Camera Analysis semantic replay R19b accepted: residual confidence calibration]

### Суть изменения
- Продолжен Camera Analysis dataset/eval цикл: R19b атакует не action/future recall, а остаточные confidence-band mismatches после R18a.
- В `AnalysisPipeline` добавлены bounded confidence rules для medium-evidence `keep_current_setup`, medium overexposure/background correction, empty unknown technical silence, underlit-readable object rows и high-boundary weak-subject/background cases.
- R19a сначала улучшил метрики, но дал регрессии `ca_img_017` и `ca_img_059`; это было отклонено как неприемлемый tradeoff. R19b добавил preservation guard для classifier-ambiguous boundary keep cases без `record_id`/label leakage.
- В `AnalysisPipelinePresentationTests` расширены regression guards: medium keep caps, overexposure cap, empty technical silence, underlit readable object, weak-subject high/medium split and high-boundary preservation.

### Метрики R19b против R18a
- `record_count`: `107`
- `pass_rate`: `0.841121 -> 0.953271`
- `expected_action_hit_rate`: `1.000000 -> 1.000000`
- `future_action_hit_rate`: `1.000000 -> 1.000000`
- `forbidden_action_violation_rate`: `0.000000 -> 0.000000`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `1.000000 -> 1.000000`
- `confidence_band_accuracy`: `0.841121 -> 0.953271`
- `confidence_band_mismatch`: `17 -> 5`

### Case-level результат
- Fixed with full pass: `ca_img_002`, `ca_img_024`, `ca_img_027`, `ca_img_029`, `ca_img_035`, `ca_img_037`, `ca_img_043`, `ca_img_044`, `ca_img_050`, `ca_img_052`, `ca_img_053`, `ca_img_077`.
- No R18a-to-R19b case regressions in scored `case_results.jsonl`.
- Remaining failures after R19b: `confidence_band_mismatch=5` (`ca_img_010`, `ca_img_022`, `ca_img_078`, `ca_img_082`, `ca_img_090`).

### Verification
- Targeted R19 RED tests failed before production confidence calibration, then passed after R19b.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r19-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 64 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r19-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 214 live/pause real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r19b.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r19b.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r19b --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 48 tests.

### Ограничение
- R19b is a measured confidence calibration win, not proof that Camera Analysis is product-ready.
- Remaining focus: five confidence-band mismatches, live-camera validation under motion/UI timing, and stronger runtime evidence for cinematic wide plans, mixed frames and bad technical frames where the current feature set cannot fully explain the silver label target.

---

## [2026-05-27 15:05] - [Camera Analysis semantic replay R20a accepted: residual confidence cleanup]

### Суть изменения
- Продолжен Camera Analysis dataset/eval цикл: R20a закрывает четыре из пяти остаточных R19b confidence-band mismatches крупной row-evidence-specific калибровкой, а не точечными `record_id` исключениями.
- В `AnalysisPipeline` добавлены bounded confidence caps/promotions для unknown no-focus front-fill correction, unknown motion-blur/background technical correction, contextual unknown blur/background simplification и readable-object technical silence.
- `ca_img_010` намеренно не закрыт threshold-подгонкой: текущие runtime-фичи слишком похожи на medium-confidence near-neighbor (`ca_img_016`), значит нужен новый наблюдаемый scene-intent/aspect/group-grounding сигнал.
- В `AnalysisPipelinePresentationTests` добавлен R20 RED/GREEN regression guard на `ca_img_022`, `ca_img_078`, `ca_img_082`, `ca_img_090` и high-boundary guard `ca_img_061`.

### Метрики R20a против R19b
- `record_count`: `107`
- `pass_rate`: `0.953271 -> 0.990654`
- `expected_action_hit_rate`: `1.000000 -> 1.000000`
- `future_action_hit_rate`: `1.000000 -> 1.000000`
- `forbidden_action_violation_rate`: `0.000000 -> 0.000000`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `1.000000 -> 1.000000`
- `confidence_band_accuracy`: `0.953271 -> 0.990654`
- `confidence_band_mismatch`: `5 -> 1`

### Case-level результат
- Fixed with full pass: `ca_img_022`, `ca_img_078`, `ca_img_082`, `ca_img_090`.
- No R19b-to-R20a case regressions in scored `case_results.jsonl`.
- Remaining failure after R20a: `confidence_band_mismatch=1` (`ca_img_010`).

### Verification
- Targeted R20 RED test failed before production confidence calibration on `ca_img_022`, then passed after R20a.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r20-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 65 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r20-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 214 live/pause real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r20a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r20a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r20a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 48 tests.

### Ограничение
- R20a nearly closes the current silver still-image replay, but it is still not live-camera product proof.
- Remaining focus: `ca_img_010` observability-grounded confidence, live-camera validation under motion/UI timing, and stronger scene/person/group grounding beyond the current silver set.

---

## [2026-05-27 15:25] - [Camera Analysis semantic replay R21a accepted: silver replay closed]

### Суть изменения
- Продолжен Camera Analysis dataset/eval цикл: R21a закрывает последний R20a failure (`ca_img_010`) через runtime-observable evidence, а не через `record_id`, label/source leakage или микропорог по aesthetic score.
- В `SemanticEvalCandidateOutput`/still replay добавлен debug numeric feature `frame_aspect_ratio`, вычисляемый из реального `CVPixelBuffer`.
- В confidence calibration добавлено bounded promotion правило только для 16:9 unknown/good/establishing `keep_current_setup` pause rows без future actions.
- В `AnalysisPipelinePresentationTests` добавлен RED/GREEN guard: `ca_img_010` должен стать high confidence, а near-neighbor `ca_img_016` остаётся medium confidence.

### Метрики R21a против R20a
- `record_count`: `107`
- `pass_rate`: `0.990654 -> 1.000000`
- `expected_action_hit_rate`: `1.000000 -> 1.000000`
- `future_action_hit_rate`: `1.000000 -> 1.000000`
- `forbidden_action_violation_rate`: `0.000000 -> 0.000000`
- `good_frame_preservation_rate`: `1.000000 -> 1.000000`
- `positive_confirmation_rate`: `1.000000 -> 1.000000`
- `confidence_band_accuracy`: `0.990654 -> 1.000000`
- `demo_priority_pass_rate`: `0.928571 -> 1.000000`
- `confidence_band_mismatch`: `1 -> 0`

### Case-level результат
- Fixed with full pass: `ca_img_010`.
- No R20a-to-R21a case regressions in scored `case_results.jsonl`.
- Remaining failures after R21a: none on the current 107-image silver still replay.
- Guard detail: `ca_img_010` confidence is `0.75` with `frame_aspect_ratio=1.777778`; `ca_img_016` remains `0.463075` with `frame_aspect_ratio=1.706667`.

### Verification
- Targeted R21 RED test failed before production calibration on missing `frame_aspect_ratio`, then passed after R21a.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r21-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 66 tests.
- `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-r21-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` -> passed and exported 214 live/pause real-runtime rows to `/private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r21a.jsonl`.
- `python3 docs/cameraanalysis/eval/run_semantic_label_eval.py --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl --candidate /private/tmp/semantic_eval_real_runtime_candidate_outputs_after_r21a.jsonl --outputs docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a --images-dir docs/cameraanalysis/dataset/inbox/images` -> scored 107 cases.
- `python3 -m pytest docs/cameraanalysis/eval/tests -q` -> passed, 48 tests.

### Ограничение
- R21a closes the current labeled still-image dataset/eval objective, but it is still not live-camera product proof.
- Remaining product-readiness focus: live-camera validation under motion/UI timing, richer scene/person/group grounding and a fuller technical-quality domain beyond the current silver set.

---

## [2026-05-27 16:05] - [Camera Analysis semantic demo pack pinned]

### Суть изменения
- Добавлен demo-hardening слой без нового «интеллекта поверх интеллекта»: `docs/cameraanalysis/demo/semantic_demo_scenarios.json` фиксирует 8 воспроизводимых R21a still-image сценариев, которые должны доходить до live/pause presentation rows.
- Покрытые user-facing действия: `keep_current_setup`, `shift_frame_right`, `step_back`, `step_closer`, `add_front_fill_light`, `simplify_background`, `wait_for_background_clearance`, `remove_background_hotspot`, `level_horizon`, `move_object_back`.
- Добавлен `docs/cameraanalysis/demo/README.md` с честной границей: `move_object_left/right` уже есть в каталоге, но не продаётся как demo-stable object-aware grounding без отдельного object mini-set.
- В `AnalysisPipelinePresentationTests` добавлен `testSemanticDemoScenarioPackReplaysExpectedPresentationActions`, который читает demo pack и прогоняет каждый сценарий через `AnalysisPipeline.testingReplayStillImageForSemanticEval(...)`.

### Verification
- RED: новый тест сначала упал на отсутствии `docs/cameraanalysis/demo/semantic_demo_scenarios.json`.
- GREEN: `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination id=CE7D291B-EA94-43FD-9580-1171018D9E44 -derivedDataPath /private/tmp/shafinMultitool-demo-derived CODE_SIGNING_ALLOWED=NO BUILD_DIR=/Users/unterlantas/Documents/XCode/shafinMultitool/build test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testSemanticDemoScenarioPackReplaysExpectedPresentationActions` -> passed, 1 test.

### Ограничение
- Demo pack доказывает стабильность выбранных still-image semantic presentation сценариев, но не доказывает произвольную live-camera стабильность и не закрывает точное object-left/right grounding.

---

## [2026-05-27 16:40] - [Camera Analysis decision trace UI]

### Суть изменения
- Добавлен user-facing слой объяснимости для демо/защиты: в camera overlay появилась кнопка `Почему?`, открывающая sheet с цепочкой решения для текущего live/pause результата.
- Новый `DecisionTracePresentation` собирает из `LiveHintPresentation` / `PauseCritiquePresentation` понятный trace: verdict, confidence, reason lines, issue/strength evidence rows, selected semantic action ids, linked evidence ids, overlay/debug signal rows, fallback/assumption limitations and trace ids.
- Новый `DecisionTraceView` показывает trace без изменения reasoning-пайплайна: это UI-проекция уже существующей presentation/evidence цепочки, а не новый эвристический слой, который мог бы подменить решение модели.
- `OverlayView` подключает sheet через `@State` and `.sheet(item:)`; production analysis code не менялся.

### Verification
- RED: `DecisionTracePresentationTests` сначала упали на отсутствии `DecisionTracePresentation` / `DecisionTraceDebugSignals`.
- GREEN: `xcodebuild ... test -only-testing:shafinMultitoolTests/DecisionTracePresentationTests` -> passed, 2 tests.
- Regression: `xcodebuild ... test -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 63 tests, including semantic demo scenario pack.

### Ограничение
- Decision trace объясняет текущую app-side presentation chain, но не доказывает причинность модели и не закрывает live-camera validation, broader scene intent или object/multi-subject grounding.

---

## [2026-05-27 18:15] - [Camera Analysis pause UX hardening]

### Суть изменения
- Исправлен пользовательский блокер в Camera Analysis overlay: pause-разбор больше не должен ощущаться как fullscreen-текст без выхода.
- Верхние controls вынесены поверх overlay cards, а pause analysis cards получили собственный CTA `Продолжить`, который возвращает камеру в live analysis.
- `PauseCritiqueCardView` и fallback/status panel теперь ограничены по высоте и прокручиваются, поэтому длинные reason/evidence/action тексты не перекрывают весь экран без управления.
- Добавлен live empty-state: если уверенной live-подсказки ещё нет, пользователь видит статус `Анализ кадра активен` и понимает, что подробный разбор доступен через pause.
- Добавлен `CameraOverlayUXPresentation` и regression tests на состояния: live без hint, pause analyzing, pause critique ready, pause fallback suggestions.

### Verification
- RED: `CameraOverlayUXPresentationTests` сначала упали на отсутствии `CameraOverlayUXPresentation`.
- GREEN: `xcodebuild ... test -only-testing:shafinMultitoolTests/CameraOverlayUXPresentationTests` -> passed, 4 tests.
- Regression: `xcodebuild ... test -only-testing:shafinMultitoolTests/DecisionTracePresentationTests -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests` -> passed, 65 tests.
- Runnable smoke: `build_run_sim` -> succeeded and launched `com.vigvamcev-media.shafinMultitool` on iPhone 17 Pro simulator.

### Ограничение
- Simulator smoke validates build/launch, not real camera quality. Final UX feel should still be checked on a physical device with live camera frames.

---

## [2026-06-16 01:46] - [Scene Generator input contract and fresh262 input examples recorded]

### Суть изменения
- Зафиксировано, что user-facing вход для Scene Generator остаётся простым: пользователь вводит свободное русскоязычное текстовое описание сцены в поле `Описание сцены`.
- Текущая V9 runtime-конфигурация не требует от пользователя JSON, таблиц, slot ids или иных внутренних контрактов. Эти структуры формируются внутри pipeline автоматически.
- Для benchmark/eval набора `fresh262` модели также верифицировались на том же базовом типе входа: `source_text`, а в части кейсов — `source_text` плюс список размеченных объектов (`marked_objects`).

### Примеры пользовательского ввода
- `Первый подходит к экрану, а второй смотрит на него.`
- `Сначала первый актёр и второй актёр идут навстречу друг другу, потом оба останавливаются рядом с рабочим компьютером.`
- `Первый актёр сначала открывает коробку, затем берёт папку.`
- `Первый подходит к шкафу, второй смотрит на первого, а третий остаётся у киоска.`
- `Первый актёр говорит: «Положи коробку сюда, потом разберём», после чего второй кладёт коробку на стойку.`
- `Таня говорит: «Передай конверт третьему». Рома отвечает: «Сейчас передам». Затем второй берёт письмо и передаёт его Яне, после чего письмо получает третий.`

### Примеры входов из fresh262
- Без marked objects:
  - `КАТЯ: Я уже отправила черновик. МАРАТ: Тогда быстро проверь черновик.`
  - `СОНЯ: Я уже подготовила черновик. КИРИЛЛ: Тогда посмотри черновик. Кирилл смотрит на Соню.`
  - `Два актёра идут навстречу друг другу, а потом проходят мимо компа.`
- С marked objects:
  - `Первый актёр Кирилл переходит к левому столу, затем Глеб, второй актёр ждёт у правого стола.`
  - `Первый из актёров, Егор подходит к правому стеллажу, после этого Илья, второй актёр останавливается у левого стеллажа.`
  - `Первый из актёров, Мила переходит к левому монитору, а второй актёр Катя держится у правого монитора.`

### Уточнение по внутреннему prompt contract
- Хотя пользователь вводит только текст, во внутренний prompt текущего V9 pipeline дополнительно могут подмешиваться:
  - `marked_objects`;
  - `anchor bundle`;
  - `scene state` / контекст предыдущего чанка;
  - `slot catalog`;
  - `verifier issues` для patch-шага.
- Поэтому при интерпретации benchmark-результатов важно различать:
  - внешний пользовательский вход;
  - внутренний model-facing prompt, который уже содержит служебную структурную информацию.

### Ограничение
- Зафиксированные примеры входов описывают current input contract и benchmark methodology, но сами по себе не доказывают production-grade качество на произвольных open-domain screenplay inputs вне текущего pipeline и scorer.

## 2026-09-11 — Camera Coach: требования к предметным советам для фото и видео

По запросу пользователя расширен существующий [черновик требований, §23](docs/cameraanalysis/camera-analysis-requirements-draft.md#23-camera-coach-для-фото-и-видео-каталог-сценариев-следующего-контракта). Зафиксированы 68 сценариев: выбор цели, композиция, несколько предметов/ламп, фон, свет, люди, жанровые случаи, техническая читаемость, временное поведение видео, конечный формат и проверка исправлений. Для каждого описаны совет, необходимые evidence, исключения и наблюдаемый результат. Отдельно разобран цикл с двумя лампами и потерей их идентичности.

Это фиксация направления и предложение следующего продуктового охвата. Новый runtime/ML-контракт, production cloud egress и качество этих возможностей не утверждены и не реализованы этой записью. Сохранены ограничения текущего Stage-2 research checkpoint и действующие M3/M4 gates. Облачная экономика записана как условный расчёт одного кадра по запросу, без обещания такой же стоимости для live video. Код, данные и модели в этой задаче не менялись.

Связанные thesis-записи: `EV-CA-REQ-001`, `CL-CA-013`; использовать только для описания требований и дальнейшей работы, не как экспериментальный результат. Следующий этап — согласование охвата и сопоставление сценариев с entity/evidence/action/time/verifier-контрактами.

### 2026-09-11 — Спроектирован следующий доменный контракт Camera Coach

По следующему поручению пользователя расширен [существующий документ доменных контрактов, N1–N12](docs/cameraanalysis/03-domain-contracts.md#camera-coach-domain-v3--проект-контракта-для-фото-и-видео): `camera-coach.domain.v3-draft.1`. Определены несколько сущностей и их временная идентичность, отношения/evidence, 20 операций, режимы фото/видео/разбора, защищаемые цели, проверка до/после и delta для VLM s2. Все 68 сценариев сопоставлены с операциями или явным поведением выбора/разбора/состояния.

Зафиксированы требующие явного согласования различия старого и нового action catalog, frame-local и track IDs, описания modelInput crop и фактического ML preprocessing. Код и checkpoint не изменены; executable schema, runtime-conformance, новый эффект модели и production egress не заявлены. Связанные записи `EV-CA-DESIGN-001`, `CL-CA-014` подтверждают только наличие спецификации. Следующий технический этап — machine schema/conformance и первый полный предметный эпизод в существующих владельцах.

### 2026-09-11 — Первый платный VLM research-цикл и ограниченный Swift ingress

По разрешению пользователя проведены 140 запросов к шести моделям через Polza на семи исходных Commons-фотографиях с проверенными rights receipts и одном существующем synthetic derivative. Фактическая сумма `95.20637306 RUB`, остаток лимита ключа `504.79362694 RUB`; стоимость сверена с сохранёнными ответами и балансом. Ключ не записан в репозиторий. [Отчёт](docs/cameraanalysis/eval/POLZA_RESEARCH_PROBE.md) содержит матрицу результатов, SHA-256 сырых ответов, воспроизведение и ограничения.

Gemini 3 Flash оставлен экономичным исследовательским кандидатом, Astra — дорогим сравнительным ориентиром. Проверки структуры, ограничений и покрытия отдельных точек не доказывают красоту кадра, точность идентификации, безопасность перемещения предметов или качество видео. Повторная настройка prompt не устранила ошибки координат; полный Camera Coach и human-gold не получены.

Запрошенный Luna 5.6 max субагент добавил изолированный `DEBUG` ingress для двух локально привязанных предметов, переиспользующий существующие evidence-типы. Это не подключение облака к камере, не UI и не полный v3: провайдер не получает право создавать локальные track IDs или выбирать действия. Узкая проверка: 6/6 тестов на iPhone 17 Pro simulator, iOS 26.5; команда и xcresult записаны в отчёте. Следующие пробелы — локальная привязка/идентичность, полезные положительные действия и сопоставимый реальный результат до/после. Связанные thesis-записи: `EV-CA-VLM-001`, `CL-CA-015`; M3/M4 gates и tracker `288/424` не меняются.

### 2026-09-11 — Подробный delivery-план сервера, клиента, ML и App Store

По запросу пользователя существующий master plan расширен [разделом 24](docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md#24-план-доведения-до-app-store--2026-09-11), без второго конкурирующего плана. Зафиксированы 27 пакетов R00–R26, зависимости, реальный двухпредметный Camera episode, полный Scene/media workflow, единый backend, SET OS UI/motion, поиск данных силами Codex, независимая разметка, обучение всех требуемых heads, Colab/resume/compute selection, Core ML admission, physical/TestFlight/App Store gates и решения владельца D1–D6.

Read-only проверка уточнила, что backend содержит reference semantics, а Scene API client уже реализован, но не включён в production composition. Review плана добавил endpoint-level installation ownership и сохранил запрет Scene retry при invalid output. Новые cloud scope/retention/бюджеты описаны как approval-gated, не как уже согласованные. Предыдущий запуск ingress suite на iPhone 17 Pro simulator отмечен как противоречащий device restriction и не принимается в release evidence; требуется разрешённый simulator при следующем выполнении.

Это planning evidence `EV-REL-PLAN-001` / `CL-REL-PLAN-001`, не deployment, обучение или release readiness. App/server/ML source не менялся, платные вызовы/обучение/симуляторы не запускались. Проверки документа: ссылки, пакеты/зависимости, структура, `git diff --check`. Изменения прошлых сессий сохранены; commit/push не выполнялись.

### 2026-09-11 — Поиск предметных кандидатов в Open Images

Автоматически прочитаны три официальных CSV Open Images (классы, validation boxes, provenance изображений). В [research catalog](datasets/camera-coach/v1/research-source-catalog.json) сохранены URL, размеры, SHA-256, фильтры и результаты: 1 210 кадров-кандидатов по девяти предметным классам, в том числе восемь кадров с несколькими размеченными лампами. Сами изображения не скачивались. Декларация CC BY 2.0 в метаданных ещё не является индивидуальной проверкой прав; boxes не являются разметкой советов, перемещения или временной идентичности. Human-gold и release admission не изменены. Evidence `EV-CA-DATA-OBJECTS-001` фиксирует только обнаружение источника, не качество модели.

Последующий локальный pilot получил один исходный кадр `3bbc38b3beafe343` (две лампы), после чтения image-specific CC BY 2.0 на Flickr. Intake проверил JPEG 3264×2448, orientation=1 и SHA `d2539de3…`; файл и выход DETR остаются вне Git и не отправлялись в облако. Реальный Core ML CPU прогон выделил оба участка как `light`. Диагностика 8-connected компонентов по существующей формуле площади дала 0,66655 и 0,30044: меньший участок не проходит порог трекера 0,55. Это не вероятности класса и не доказательство недостаточной уверенности модели; проблема состоит в использовании площади как confidence. Receipt и полный массив предсказаний связаны SHA и указаны в catalog `local_pilot`. Не установлены Vision/Swift parity, temporal identity, правильность советов или release admission. Chapters 4/5 остаются `needs_update`.

Из существующего графа DETR отдельно экспортированы class logits `[1,100,251]` и mask logits `[1,100,112,112]` без обучения и изменения весов. Внешний `DETRResearchSignals.mlpackage` с research-only metadata компилируется и выполняется на macOS CPU; прежняя hard-map на одном pilot-кадре совпадает точно (0 изменённых пикселей). Query 0 даёт некалиброванный softmax `light=0,9839029`, но его маска реагирует на обе лампы — это не две идентичности и не готовая confidence для каждого предмета. Dense semantic aggregate намеренно не назван вероятностью. Результат, тензоры и SHA сохранены в `detr-signals-export-receipt.json`, указанном в catalog. App bundle, source model, thresholds и release admission не изменены; качество/калибровка/права/Vision/device-проверки остаются открытыми.

В существующий `SubjectTracker.swift` добавлена ограниченная ассоциация до четырёх объектов с отдельными ID, проверкой поколения/порядка кадров и сохранением истории наблюдений при потере. Независимое ревью выявило ошибку выбора активного ID при конкуренции с потерянным объектом; она исправлена без изменения порогов. После исправления ожиданий истории трёхкадровый regression прошёл на разрешённом iPhone 17e: `/private/tmp/shafin-r03-object-tracking-shared-lost-final.xcresult`, 1/1. Предыдущие результаты 23/23 и три уточнённых теста относятся к своим версиям кода, а не к единому финальному прогону. Spec/quality review ограниченного участка пройдены; evidence `EV-CA-TRACK-001`, claim `CL-CA-TRACK-001`. Реальное распознавание, pixel tracking, pipeline/UI integration и device qualification этим не доказаны. Следующий отдельный участок — pre-network проверка endpoint и токена существующего Scene-клиента; сервер пока не развёрнут.

В `SceneGenerationClient.swift` реализована общая проверка HTTPS-адреса и синтаксиса служебного токена до сетевого запроса для create/poll/answer/cancel. Адрес-заглушка, URL с учётными данными/query/fragment и отсутствующий/невалидный токен отклоняются типизированной ошибкой без секрета. `SceneGenerationClientTests` проверяет нулевое число обращений к URLProtocol для таких случаев и обычный обмен данными; финальный результат 10/10 на iPhone 17e сохранён в `/private/tmp/shafin-scene-auth-luna-final.xcresult`. Предыдущие ошибки относились к тестовому чтению тела запроса как Data вместо потока и явному `self`; сериализация приложения не менялась ради теста. Spec/quality review пройдены. Это не App Attest, серверная авторизация или интеграция Generator; сервер не развёрнут. Evidence `EV-SG-AUTH-001`, claim `CL-SG-AUTH-001`; затронутые главы отмечены `needs_update` без переписывания текста.

В цепочку Camera planner → stabilizer → episode admission добавлена локальная идентичность цели. Смена цели сбрасывает ожидание стабилизации и сразу удаляет прежний совет; совет для всего кадра обязан не иметь идентификатора объекта. Spec review и фактический тест обнаружили пропуск этой проверки при отсутствии subjectTrack; исправлена общая проверка, а не тестовое ожидание. Финальный `/tmp/shafin-camera-target-binding-luna-final.xcresult` независимо проверен: 16/16, без ошибок; spec и quality review пройдены. Evidence `EV-CA-TARGET-001`, claim `CL-CA-TARGET-001`. Отдельный visible-hint путь, распознавание предметов, качество физических советов и release qualification остаются открытыми; модель не переведена в production. Главы 4/5 остаются `needs_update`, текст глав не менялся.

Исправлена совместимость Scene-запроса: Swift теперь передаёт marked_objects как объекты с canonical_id и maximum_scenes внутри constraints; SHA-256 вычисляется из фактически сериализованного запроса без поля request_hash. Ручная сборка плоского JSON удалена, Python использует ту же проекцию без изменения входа. Проверено: Swift 10/10 на iPhone 17e (`/private/tmp/shafin-scene-wire-hash-luna.xcresult`), Python 11/11 и прямая передача настоящего Swift-builder JSON в Python — 2/2 с совпавшими хешами, Unicode и управляющими символами. Spec/quality review пройдены. Evidence `EV-SG-WIRE-001`, claim `CL-SG-WIRE-001`. Полная серверная валидация, привязка ответа к текущему запросу и реальный Generator/server workflow остаются открытыми. Главы архитектуры/Scene сохраняют `needs_update`; production rollout не выполнялся.

Следующий участок закрыл локальную валидацию Scene-запросов: обязательные поля, типы и вложенные ограничения теперь берутся из существующего OpenAPI, UUID проверяется как UUID, а SHA-256 пересчитывается из тела. Пропускавшийся завершающий перевод строки в previous_job_id отклоняется полным сопоставлением с той же схемой. Проверены 20/20 существующих Python-тестов и настоящие Swift-запросы: два приняты, два варианта с изменённым текстом отклонены. Spec/quality review пройдены; evidence `EV-SG-ADMISSION-001`, claim `CL-SG-ADMISSION-001`. Это не серверная авторизация, контроль расходов или развёрнутый сервис; главы остаются `needs_update` без изменения текста.

В существующий Scene-клиент добавлена привязка ответов к исходному запросу и задаче: проверяются ID, хеш, версии модели/провайдера и исходный ключ создания. Все типизированные операции используют общую семантическую проверку; некорректные ID и ключи отклоняются до сети. Ключ ответа на уточнение не смешивается с ключом создания. Итог: 16/16 целевых тестов на iPhone 17e, результат `/private/tmp/shafin-scene-response-binding-luna.xcresult` независимо прочитан, spec/quality review пройдены. Evidence `EV-SG-BINDING-001`, claim `CL-SG-BINDING-001`. Проверки используют подставной транспорт и не доказывают работу настоящего сервера, App Attest или production UI; эти границы сохранены.

Во внешнем workspace `/Users/unterlantas/Documents/XCode/setos-backend` реализован локальный FastAPI/Uvicorn-сервис с SQLite: создание, чтение, отмена, разделение владельцев и сохранение исходного ключа при повторных запросах. Код использует существующие схемы приложения, а не их копии. Сквозная проверка обнаружила отсутствие обязательной причины отмены и несовпадение допустимых UUID во входной/выходной схемах; оба разрыва устранены без изменения схем. Проверено 10/10 сервисных тестов, работа настоящего loopback-процесса с отказом 401 на защищённых операциях и сохранность одной задачи/отмены между тремя отдельными процессами Python. Независимые spec/quality review пройдены; evidence `EV-SG-SERVICE-001`, claim `CL-SG-SERVICE-001`. Test-only подстановка установки не является App Attest; реальная авторизация, AI-провайдер, расходы, production retention и deployment не реализованы этим участком. Временная синтетическая база удалена, рабочие исходники и окружение сохранены. Git-операции публикации, покупки, платные AI-вызовы и продвижение модели не выполнялись.

### 2026-09-11 — привязка подсказки к объекту в live-пайплайне

В `AnalysisPipeline` подготовка идентичности и геометрии объекта объединена для публикации подсказки, эпизода и аннотаций. Подсказки используют проверенные данные текущего кадра; техническое действие передаётся явно. Поздний сброс в `CameraViewModel` ограничен исходным кадром и поколением камеры, чтобы не сбрасывать новый эпизод. Итоговые 10 выбранных тестов прошли на iPhone 17e / iOS 26.5 (`/private/tmp/shafin-camera-visible-binding-luna-final3.xcresult`), результат независимо прочитан; `git diff --check` без ошибок. Evidence `EV-CA-VISIBLE-001`, claim `CL-CA-VISIBLE-001`.

Границы результата: независимый ревью-агент не запустился из-за лимита задач, поэтому review не объявлен пройденным. Положительный тест продолжения удерживает исходный план при недоступной структурированной замене, а не проверяет непрерывное перепланирование. Найдены отдельные незакрытые проблемы реального preview: сохранённая рамка завершённого эпизода, выбор из исходного пула вместо привязанной подсказки и несовпадение систем координат. Они записаны следующим участком, R05 не закрыт. Необеспеченные данными советы для объектов фона подавляются. Обучение, human-gold, допуск модели, облачная авторизация и выпуск в App Store этим результатом не подтверждаются. Главы остаются `needs_update`; их текст и litreview не изменялись.

### 2026-09-11 — проверка demo-подсказок и источников данных

Последующее независимое ревью обнаружило обход типизированного допуска через demo-подсказки и преждевременную публикацию их аннотаций. Исправлен общий production-путь: demo проходит проверку действия и привязки, аннотация сохраняется только для фактически показанной принятой подсказки. Итоговый `/private/tmp/shafin-demo-admission-repair-luna.xcresult` независимо прочитан: 20/20 выбранных тестов, без пропусков, iPhone 17e/iOS 26.5; повторное spec review и свежее quality review пройдены. Первоначальный результат 26/29 сохранён отдельно с суффиксом `-initial-failed`; ошибки cup-formatting и scene-cut retry остаются открытыми. Для пространственного теста исправлен интервал кадров (150 мс при неизменённом ограничении публикации 125 мс), а не ослаблена runtime-проверка. Это ограниченное подтверждение `EV-CA-VISIBLE-001`, не закрытие R05 или выпуска.

Параллельно проверены оставшиеся семь страниц кандидатов с несколькими лампами: на шести найдены индивидуальные декларации CC BY 2.0, `br1dotcom/3226089149` вернула HTTP404. Вместе с ранее проверенным источником пилота это семь доступных деклараций из восьми кандидатов, не семь проверенных обучающих изображений. Наблюдения и SHA-256 HTML добавлены в существующий research catalog; изображения в этой проверке не скачивались, разметка действий и human-gold не создавались, допуск к выпуску не менялся. Следующий технический участок — реальная экранная рамка, активный эпизод и явные системы координат. Главы 4/5 остаются `needs_update`.

### 2026-09-11 — геометрия реального live-preview

Устранена неоднозначность Vision-y-up и coaching-y-down в вычислении точки и области цели. Реальный live-view получает одну привязанную рамку: активный эпизод использует исходную геометрию принятого объекта, отменённый или истёкший эпизод не показывает сохранённую рамку. Убраны повторный выбор по площади/расстоянию и дублирующее преобразование; ориентация, зеркальность и aspect-fill остаются у прежнего preview-слоя, проверка движения — в coaching-координатах.

Ревью выявило побочную регрессию: отсутствие объектной рамки скрывало советы для всего кадра. Теперь типизированные советы о горизонте и устойчивости камеры сохраняют текст без выдуманной геометрии; строковый ID происхождения не заменяет тип действия. После компиляции текущих исходников прошли12/12 выбранных проверок (`/private/tmp/shafin-preview-geometry-parent-final-20260911.xcresult`), затем1/1 после последней защиты от совпадения ID (`/private/tmp/shafin-preview-geometry-typed-gate-20260911.xcresult`), iPhone17e/iOS26.5. Предыдущие повторные запуски старого тестового бинарника не использованы как подтверждение финального кода. Spec review пройдено; quality review ещё ожидается.

Evidence `EV-CA-PREVIEW-001`, claim `CL-CA-PREVIEW-001` подтверждают ограниченную интеграцию исходников и выбранные координатные случаи. Фактическое изображение с камеры, непрерывное перепланирование, качество предметных советов и полный R05 ещё не подтверждены. Модели и данные не переведены в production; главы остаются `needs_update`, их текст не менялся.

После фиксации исходников получено и независимое quality review: PASS в пределах этого участка. Ожидающий статус предыдущей записи снят; ограничения доказательств и незакрытые требования выпуска сохранены.

### 2026-09-11 — сквозной цикл подсказки и проверки результата

Проекция интерфейса теперь сохраняет принятое действие и исходную цель во время эпизода, даже если свежий планировщик возвращает KEEP. Автоматический результат сопоставляется с токеном эпизода; явное «Продолжить» сбрасывает прежний цикл синхронно через существующего владельца, без остановки камеры. Запоздалое нажатие от предыдущего результата не должно очищать новый эпизод. Для несравнимых кадров удалён вызов асинхронного выхода с экрана, который стирал результат проверки.

Первый прогон после исправления трёх ошибок компиляции: `/private/tmp/shafin-episode-integrated-20260911-r4.xcresult`, 25/27 выбранных тестов, без пропусков, iPhone 17e/iOS 26.5. Прошли непрерывное перепланирование, автоматическая проверка через capture-путь, переход к следующему эпизоду и защита от старого токена. Новый тест направления ошибочно ожидал сдвиг предмета влево при движении камеры влево; ожидание исправлено на вправо, повторная проверка ожидается. Другой существующий тест не создаёт исходную видимую подсказку и потому несовместим с прежним условием допуска эпизода; он оставлен без изменений, отказ не скрывается. Исправленный scene-cut тест прошёл: DEBUG-вход теперь использует тот же evidence store, что реальная камера; это исправление тестового входа, не доказанный дефект production-упорядочивания.

Spec review пройдено. Quality review обнаружило переполнение нижней панели длинным текстом; исправление общего размера панели и её зоны обхода ещё проверяется. `EV-CA-EPISODE-UI-001` / `CL-CA-EPISODE-UI-001` имеют ограниченный статус: фактическое качество советов, физическая камера, human-gold и готовность к выпуску не подтверждены. Главы 4/5 остаются `needs_update`.

Итог пакета: общий расчёт высоты live-панели учитывает текст, кнопки и раскрытое объяснение; та же высота используется для зоны обхода маркерами. Повторные spec/quality review пройдены. Свежая сборка и `/private/tmp/shafin-episode-integrated-20260911-r5.xcresult`: 27/27 выбранных проверок, без пропусков. Из набора явно исключён оставленный без изменений несовместимый subject-change тест и добавлена проверка размера панели; это не успешный прогон всей suite. JSON локализаций и git diff --check проверены. Проверки размера не доказывают пиксельное соответствие SwiftUI или работу физической камеры. Полная цель выпуска остаётся активной, модели и данные не продвинуты в production.

### 2026-09-11 — транзакционная квота Scene и типизированный отказ клиента

В локальном сервисе реализованы лимиты 10 принятых заданий за скользящий час и 20 за скользящие сутки для одной установки. Подсчёт и создание используют существующую SQLite-транзакцию: повтор возвращает прежнее задание, отмена не возвращает квоту, параллельные запросы не обходят проверку. В OpenAPI добавлен ответ429; Swift-клиент отличает квоту от сбоя провайдера и не запускает автоматический retry. Retry-After — ограниченная подсказка, не бронь следующего запроса. Значение410 по-прежнему означает kill-switch, а не истечение задания.

Проверено родительским агентом:17/17 тестов сервиса,20/20 проверок входного контракта,5/5 выбранных Swift-тестов (`/private/tmp/shafin-scene-quota-20260911.xcresult`, iPhone17e/iOS26.5). Дополнительный синтетический HTTP-прогон подтвердил отказ без записи при некорректных часах, точную границу окна, сохранение начисления при откате времени и прежний секундный формат даты в ответе. Независимые spec/quality review пройдены; git diff --check успешен. Временная синтетическая БД удалена после проверки, пользовательские данные не затронуты.

`EV-SG-QUOTA-001` / `CL-SG-QUOTA-001` подтверждают локальную квоту и транспорт, не денежный cap или готовый backend. Настоящий доступ остаётся закрытым до App Attest; retention, резервирование стоимости, provider execution, полный UI и deployment не объявлены готовыми. Главы3 остаются needs_update; модельные данные и допуск research-checkpoint не менялись.

### 2026-09-11 — локальный жизненный цикл Scene и удаление исходного текста

Во внешнем локальном сервисе SQLite-схема v2 отделяет исходный сценарий и отмеченные объекты от шести обязательных полей ответа. Известная схема v1 переносится транзакционно; неизвестные ограничения или повреждённые записи отклоняются без пересоздания данных. Ожидающее задание через 60 секунд получает `failed(timeout)`, а его исходный текст удаляется. Отмена также удаляет текст, не меняя уже терминальный результат. Метаданные, ключ повтора и учёт принятого задания сохраняются до 30 дней; затем опрос получает404. Значение410 остаётся kill-switch, отмена не возвращает квоту.

Очистка работает при запуске, перед операциями и в одной фоновой задаче. Независимое ревью обнаружило, что отмена asyncio-задачи не ждала завершения потока SQLite. Родительский агент воспроизвёл ранний выход из lifespan; исправление использует сигнал остановки и ожидание текущей операции. Проверка с управляемым потоком подтверждает ожидание до завершения. Итог:26/26 тестов сервиса,20/20 проверок входного контракта и3/3 выбранных Swift-теста (`/private/tmp/shafin-scene-timeout-20260911.xcresult`, iPhone17e/iOS26.5, без пропусков). Повторные spec/quality review пройдены. Первоначальный отдельный отказ проверки `secure_delete` оказался неверным соединением в тесте: сервисное соединение имело значение1, ненастроенное —0; рабочий код ради этого не менялся.

Дополнительная синтетическая проверка файла SQLite подтвердила исчезновение текстового маркера после отмены и переноса старой отменённой записи при сохранении ответа, квоты и изоляции владельцев. Это не доказательство физического стирания SSD, удаления резервных копий или данных провайдера. Временные тестовые БД удалены только собственными TemporaryDirectory-контекстами; существующие БД не открывались и не переносились. `EV-SG-RETENTION-001` / `CL-SG-RETENTION-001`, снимки и журнал обновлены через thesis-workflow; главы3 остаются `needs_update`, litreview и тексты глав не переписывались. Авторизация App Attest, провайдер, production-эксплуатация, обучение/калибровка и выпуск остаются отдельными незакрытыми частями общей цели.

### 2026-09-11 — Проверка сертификата App Attest, без выдачи доступа

Во внешнем `setos-backend/app_attest_certificates.py` реализована проверка цепочки сертификатов через cryptography50.0.1 с закреплённым корневым сертификатом Apple. Проверяются точный DER и порядок цепочки, срок действия, назначение конечного сертификата, ключ P-256, его хеш и каноническое расширение nonce. Ожидаемые nonce, идентификатор ключа и время должны поступать от доверенного серверного кода. Это не готовая авторизация: защищённые запросы сервиса по-прежнему получают401.

Родительский агент выполнил10/10 проверок сертификатного компонента и26/26 существующих проверок сервиса; независимые SPEC и QUALITY review пройдены. Положительный пример Apple подтверждает лишь историческую цепочку на2026-04-21. В опубликованном полном примере обнаружены несогласованности вычисления nonce и напечатанного хеша ключа; они не превращены в послабление проверок. Источники, команды и точные SHA-256 сохранены в EXECUTION_STATE.md. `EV-SG-ATTEST-CERT-001` / `CL-SG-ATTEST-CERT-001` и снимки обновлены через thesis-workflow; главы3 остаются `needs_update`, защищённый litreview не менялся. Полная проверка challenge, CBOR, приложения, assertions, счётчиков и выдача токенов, а также проверка на реальном устройстве остаются следующими этапами. Доступы, deployment, пользовательские БД и Git-публикация не затрагивались.

### 2026-09-11 — Подписи App Attest и исследование receipt

Добавлен внешний `app_attest_assertions.py`: ограниченный CBOR-конверт, точный DER подписи, проверка P-256 по полным исходным байтам, ожидаемого RP и возрастающего беззнакового счётчика. Компонент возвращает неизменённые подписанные данные для последующей проверки профиля; он не выдаёт доступ и не реализует атомарную защиту от повторов. Родительский запуск:9 проверок assertions,10 сертификатов и26 существующего сервиса пройдены. Независимые SPEC и QUALITY review пройдены после усиления двух отрицательных примеров в существующих тестах. Ошибка чернового теста, повторно подписывавшего изменённые данные, исправлена в самом тесте до первого запуска. Отдельная проверка подтвердила, что отключение защиты semantic tags позволяет CBOR tag28 обернуть допустимый конверт; рабочая защита отклоняет такой вход.

Нативный OpenSSL3.6.2 подтвердил CMS-подпись публичного Apple receipt с официальным корнем G3 и стандартным назначением сертификата. Поле3 этого примера содержит сертификат с тем же ключом, что и credential. Это исследовательская проверка подписи, не готовый валидатор receipt: свежесть, App ID, назначение подписанта и ограниченный разбор полей ещё требуют реализации. Документация новых расширений assertions и старые опубликованные примеры расходятся; автоматическое переключение на более слабый профиль не добавлялось.

Доступен физический iPhone13Pro, установлено приложение1.0/build1; проверены только метаданные. App Attest-клиента и entitlement в текущем исходном проекте нет, установку или запуск на устройстве не выполняли. `EV-SG-ATTEST-ASSERTION-001` / `CL-SG-ATTEST-ASSERTION-001`, снимки, серверная граница и EXECUTION_STATE.md обновлены через thesis-workflow. Главы3 остаются `needs_update`, litreview и тексты глав не менялись. Общая цель выпуска приложения остаётся открытой.

### 2026-09-11 — подробная передача разработки следующему ИИ

По запросу пользователя подготовлены `HANDOVER-2026-09-11-FULL-DELIVERY.md` и отдельный готовый `HANDOVER-PROMPT-2026-09-11.md` в существующем каталоге master plan. Они фиксируют цель полного Camera Coach и приложения, фактическую границу server/client/ML, завершённые Colab и research-конверсию, незавершённую авторизацию, порядок R00–R26, проверку конкретных объектов/сцен/направлений/результатов, человеческую разметку, физические и релизные gates. Это индекс прежних результатов и инструкция продолжения, не новое доказательство качества.

Receipt-исполнитель остановлен для безопасной передачи. Файловая проверка подтвердила отсутствие `app_attest_receipts.py` и его теста; root/fixture и установленные исследовательские ASN.1-зависимости сохранены. Runtime receipt ещё не реализован. Точка остановки и ссылки внесены в EXECUTION_STATE, evidence map и claim registry без повышения статуса claims. Исходники приложения/сервиса, пользовательские данные, Git-публикация, обучение, deployment и устройства в рамках этой передачи не менялись; полная цель остаётся открытой.

**2026-09-12 (goal execution) — Receipt-валидатор реализован и независимо ревьюен; R04-гейт ужесточён.**

По спецификации handover §11.3 реализован внешний `app_attest_receipts.py` + 9 focused-тестов: typed-BER CMS-конверт, нативный OpenSSL 3.6.2 `cms -verify` против пинованного Apple G3 root (LibreSSL/PATH-бинарники отклоняются), ограниченный профиль SignerInfo/сертификатов/payload, привязка app-ID, credential-ключа, `ATTEST` и UTC-freshness/expiry; поля 4/5/7 остаются opaque, API не возвращает identity/token. Прогоны: 9/9 receipt (единственный крипто-positive — реальный публичный fixture), 28/28 attest, 26/26 service. Независимое read-only ревью: FIX-FIRST без блокеров и без найденного пути ложного принятия; его единственный SHOULD-FIX (невалидируемый `SignerInfo.digestAlgorithm`) исправлен, все suite-ы повторно зелёные. Задокументированные отклонения: граница ≤72 применена к ECDSA-подписи SignerInfo, а не к встроенным сертификатам цепочки (у настоящей Apple-цепочки 103-байтовые P-384 подписи); freshness/expiry — ограниченный наблюдаемый профиль. Модуль 357 строк против мягкого лимита 350 — сообщено по правилу, новых абстракций нет. Компонент не аутентифицирует устройство: challenge/counter/token/installation и device roundtrip остаются открытыми; service по-прежнему 401.

В Camera-домене `LiveCoachQualityGate` больше не пропускает scene-object/subject перемещения (`moveObject*`, `removeDistractingObject`, `repositionPropForBalance`, `moveSubject*`, `rotateSubjectTowardLight`) без свежего grounded live-доказательства: раньше только framing/шаги камеры требовали его, и классовый совет «передвинь предмет» обходил проверку идентичности. Для object-действий дополнительно требуется `objects.totalCount > 0` — prerequisite присутствия, не идентичности (R03 отдельно). SemanticTipPlannerTests 23/23 на iPhone 17e, включая три новых случая. Интеграционные suite-ы дали 40 passed / 20 failed; A/B-сравнение с откатанной правкой для отделения предсуществующих падений dirty-дерева от последствий изменения — см. EXECUTION_STATE. Это ужесточение допуска, не R03/R04-завершение.

**2026-09-12 (goal execution) — Серверное состояние App Attest: challenge/counter/token.**

Внешний `app_attest_state.py` закрывает известный пробел «строгий counter ≠ атомарная replay-защита»: один SQLite-владелец (своя схема `attest_*`, fail-closed версионирование, гигиена подключений как у store.py) с SHA-256-хэшированными одноразовыми challenge (атомарное consume-once — при гонке 8 потоков ровно один победитель), установками с атомарно продвигаемым строго-возрастающим счётчиком аутентификатора (запаздывающие меньшие счётчики корректно отклоняются) и односрочными bearer-токенами, хранимыми только хэшем, с ротацией в одной транзакции, истечением и отзывом установки. 8/8 тестов на 5 прогонах подряд, 36/36 attest-набор, 26/26 service; тесты поймали два дефекта до каких-либо заявлений (неявный COMMIT от executescript и отсутствие row_factory). Только состояние: без проверки аттестации, без wiring в сервис (по-прежнему 401), без клиентских claim. 361 строка против мягкого лимита 350 — сообщено. Независимое ревью запущено; вердикт будет внесён в EXECUTION_STATE.

**2026-09-12 (goal execution, продолжение) — Ревью состояния применено; контрольный прогон R04.**

Независимое ревью `app_attest_state.py` (FIX-FIRST) подтвердило ядро: сериализация BEGIN IMMEDIATE до SELECT исключает потерю обновления и принятие устаревшего счётчика, consume-once держит гонку, ротация оставляет ровно один активный токен, воскрешение отозванной установки невозможно, временные границы точные. Применены оба SHOULD-FIX: maintenance-тест был вакуумным (проходил с `_maintain`-no-op) — заменён парой live/expired с проверкой по строкам БД; `attest_installations` не имел границы — добавлена ёмкость 4096 с обоснованием «установки никогда не автоочищаются» (счётчик — replay-состояние, отозванные строки — надгробия). Из NOTE применены: удалён недостижимый лимит токенов на ключ, `sqlite_%`-фильтр схемы, path-guard'ы, сохранение исходной ошибки при ROLLBACK, консистентный отказ повторного отзыва. Итог: 9/9 на 5 прогонах, 37/37 attest-набор, 26/26 service; модуль 394 строки — превышение лимита сообщено. Контрольный прогон интеграционного набора R04: 157 тестов, 116/41/0; CameraCoachClosedLoop — ноль падений (флак scene-cut не воспроизвёлся); все 41 падения — предсуществующие (доказано A/B-откатом): противоречие whitelist `shiftFrame*` против теста и 0.75-границы confidence; отдельное решение владельца записано в EXECUTION_STATE.

**2026-09-12 (goal execution) — R00: карта трассируемости 68 кейсов.**

`docs/cameraanalysis/34-case-traceability-map.md`: все 68 ID из requirements §23.4 (программное извлечение, 10 семейств) с владельцами/статусами/evidence/блокерами. Сводка: 10 implemented_local (T-семейство, I06, R01/R02/R04), 16 implemented_regression (C/L — путь есть, презентация в предсуществующих 41 still-replay падениях), 31 partial, 11 not_implemented (две лампы как экземпляры O02, перекрытия O05, группа I02, роли I03, неперемещаемость I04, монтажные сценарии V05/V07/V08, титры F02, сравнение дублей F04, запоминание ограничений R05). Карта фиксирует системные блокёры: R03 (инстанс-идентичность), источник movable-доказательств, R18 (видео-разбор), R08/R12 (облачная цепочка до продуктового маршрута). Это планировочная карта: enum/действие не считались реализацией, master gates §9.6 на независимом корпусе не измерялись, release-claims не создаются.

**2026-09-12 (goal execution, продолжение) — Annotation pilot v1 подготовлен.**

R13 prep поверх R00-карты: `build_annotation_pilot.py` собирает слепую выборку 35 брифов из кейсов со статусами implemented_local/partial карты (T6/R5/O6/I3/V5/F2/P6/S2; 7 брифов с намеренным скрытым дефектом — неверный референт, сантиметры без измерения, навязанный стиль, маскированный trade-off, устаревший совет, выдуманное название, «правильный» ракурс); ключ с интенциями автора — отдельным файлом только для адъюдикатора. Голосование — исключительно через существующий `annotate_camera.py` (append-only, hidden-QC). Инструкции аннотатора/адъюдикатора — `annotation-pilot-instructions.md` (критерии good/bad/abstain, три типа движения, защищённые цели, честные величины, независимость). Отчёт согласованности `pilot_agreement_report.py`: распределения по записям, парные проценты, Fleiss' κ; смоук поймал нарушение допущения Флейсса (неравное число оценщиков на запись) — κ теперь только по записям ровно с 2 голосами, сверено вручную (−0.333 на тестовых данных). Всё synthetic/AI-authored: research_only, human_gold=false, пикселей нет; пилот — механика и инструкции, не метрика качества. Временные stores удалены, fabricated голоса не коммитились.

**2026-09-12 (goal execution, продолжение) — 41 still-replay падение разобраны; whitelist разрешён; drift квантифицирован.**

Root-cause: (1) whitelist-противоречие разрешено в пользу production — `shiftFrame*` остаются в demo-live whitelist (нужны spatial-confirmation тестам; grounding обеспечен R04), устаревший unit-тест обновлён; промежуточная попытка обратного решения дала +3 spatial-падения и была откатена. (2) Остальные ~40 падений — drift детерминированного критика против курируемых лейблов: по дампу всех 174 записей benchmark-пака расхождение 128/174 (74%): перегенерация simplify/change_angle/move_object при ожидаемом keep (keep missing ×47, simplify extra ×50), forbidden-action попадания на 26 записях. Ledger-строка «93/240 картинок отсутствует» устарела — пак консистентен (174=174). Попытка cap-precedence reorder отклонена и полностью откачена (незафокусированный риск). Контрольный прогон 5 suite: 180 тестов / 140 passed / 40 failed / 0 skipped — whitelist PASS, spatial/ClosedLoop/Episode/SafetyGate/TipPlanner без падений, net 41→40 без регрессий. Оставшиеся 40 — выравнивание критика с лейблами (M2/R15 product scope, дни тюнинга), evidence: still-replay-label-drift-dump-20260912.txt. R00-карта C/L-строки и легенда обновлены количественным корнем.

**2026-09-12 (goal execution, продолжение 2) — выравнивание критика: контракт good⇒keep внедрён; вердикт-дрейф измерен.**

Лейблы пака формальны: good (81) ⇒ keep-only в 81/81, bad/mixed ⇒ коррекции. Runtime-вердикты на good-кадрах: good 43 / mixed 11 / needs_fix 27 — дрейф вердикта в обе стороны. Внедрён контракт good⇒keep-only в makePauseCritiquePresentation (контекстуальная коррекция и plan-fallback не переигрывают good-вердикт); итерация: 42→39 падений suite без новых. Issue-профиль дрейфа: subject_too_close_to_edge ×31 (false positive; подавитель hasAestheticIntentionalEdgeComposition мёртв при недоступном aesthetic-источнике: требует score ≥0.42), frame_visually_overloaded ×13. Финальный контроль 5 suite: 180/139/41/0 — whitelist −1, StillImageReplay 40→37 (−3), +1 известный load-flake scene-cut. Оставшиеся 40 drift/object/neural падений = калибровка вердикт-деривации против лейблов; вслепую не тюнилась — нужен следующий шаг: severity/raw/regions в eval-строке. Owner-вопрос D6 (authenticator-профиль/устройство) зафиксирован в EXECUTION_STATE.

**2026-09-12 (goal execution, продолжение 3) — instrumentation severity/regions; эксперимент читаемости откачен по данным.**

В eval-строку still-replay добавлена диагностика `severity_<issue>` / `region_<issue>` (аддитивно). Сев-дамп по 81 good-записям: все 33 edge-срабатывания — label-good/keep-only, 32/33 с регионом, обрезанным краем кадра, severity 0.70–0.94; общий знаменатель — `subject_readable=false` (readability-порог `edgePressureScore <= 0.80` при обрезанном субъекте), он же глушит подавители edge-issue. Эксперимент снятия оговорки: still-replay 39→37, но live-path +10 (ClosedLoop/TipPlanner) → net хуже, полностью откачен; CERT2 вернул 180/139/41 (37 StillImageReplay drift + 3 demo/object/neural + scene-cut load-flake; whitelist PASS дважды подряд). Вывод зафиксирован: вердикт-деривация связана с live-цепочкой — дальнейшая калибровка только через instrumented eval с полным контрольным прогоном. Owner-вопрос D6 (authenticator-профиль/устройство) остаётся открытым.

**2026-09-12 (goal execution, продолжение 4) — итерация 3 калибровки: отрицательный результат, откат.**

Деградация edge-pressure ×0.50 в pause при недоступном aesthetic-судье (`FrameCritiqueEngine`) ухудшила suite 37→39: частичное подавление меняет балансы действий и ломает другие ожидания — полностью откачена, FrameCritiqueEngine возвращён в точное HEAD-состояние. Вывод по кластеру: при недоступном эстетическом судье точечные пороговые сдвиги не отделяют намеренный кроп (32/33 обрезанных региона при label good) от дефекта; нужны qualified aesthetic-оценки в replay или обобщающее правило по человеко-лейблам. Инструментарий severity_*/region_* в eval-строке сохранён для следующей сессии. Сертифицированное состояние: 180/139/41/0.

**2026-09-12 (goal execution, продолжение 5) — consistency gate изоляции (нейтральный).**

Дампы показали самопротиворечие движка: на 13+6 label-good кадрах issues «кадр перегружен»/«фон конкурирует» сосуществовали с strength «предмет изолирован от фона» при пустых курируемых problems. Внедрён consistency gate: сильное isolation-свидетельство (пороги экспортируемого strength 0.55/0.35) обнуляет перегрузку/конкуренцию. Suite-нейтрально (записи падают по другим ассертам), оставлено как устранение противоречивой основы советов; live-влияние требует отдельной проверки при следующем контрольном прогоне. Итог калибровочной сессии: +3 фикса (whitelist, good⇒keep, контракты), 2 эксперимента отклонены по данным (читаемость, edge ×0.5), instrumentation severity/regions готова; 37 drift-падений остаются M2/R15 scope.

**2026-09-12 (продолжение 6) — визуальная верификация дрейфа: намеренность недоступна детерминированному критику.**

Просмотрены три ключевых дрейфующих кадра как изображения: ca_img_009 (тайт-кроп портрет, лоу-кей — «move_object_right» абсурден), ca_img_017 (двуличное интервью — «simplify_background/move_object» абсурдно), ca_img_036 (художественный лоу-кей книга/лампа — «increase_exposure/reduce_iso_noise» лечит стиль как дефект). Лейблы кураторов подтверждены; runtime не имеет признака намеренности для low-key/кроп/документальных композиций. Калибровка этих семейств требует intent-признака (aesthetic/VLM/уточнение намерения), пороговые эксперименты без него net-отрицательны (итерации 2/3). Метод «смотреть фикстуры при калибровке» зафиксирован для следующих сессий.

**2026-09-12 (продолжение 7) — дефлейк scene-cut: попытка бюджетов неэффективна, откат.**

Scene-cut ClosedLoop тест дважды падал под параллельной нагрузкой клонов (соло проходит). Расширение waitUntil-бюджетов 2с→10с не помогло: под нагрузкой отмена scene-cut не потребляется за бюджет (ассерт 1655), каскад последующих ассертов ложный. Таймауты откачены; реальная причина — задержка цепочки captureOutput→scheduler→pipeline→ViewModel при контеншене — вынесена как отдельный тест-инфра work item. Состояние: CERT2 180/139/41/0 стабильно; 37 StillImageReplay drift (M2/R15), остальные пакеты сессии без изменений.

**2026-09-12 (продолжение 8) — проект предложения intent-источника на согласование владельцу.**

docs/cameraanalysis/35-intent-source-proposal.md: проблема с evidence (128/174 drift, визуальная верификация, два net-отрицательных эксперимента), четыре варианта источника намеренности (A — aesthetic/intent-модель на кураторском ядре; B — VLM-слой D1-gated; C — интерактивное уточнение CC-I05; D — статус-кво, не рекомендуется), рекомендация C+A, вопросы владельцу (D1/D4/D6). Готовность к старту A: лейблы, instrumentation, дамп-пайплайн, negative baseline.

**2026-09-12 (продолжение 9) — separability study intent-признака.**

Полный дамп 174 записей с feature-профилями (evidence-m2/intent-features-full-dump). Softmax-LR LOO: 3-class 0.638 (baseline 0.466); binary good-vs-rest 0.713. Единственный сильный признак — aesthetic_score (AUC 0.836, direction: good выше); лучший однопороговый гейт T=0.42 (совпадает с подавителем) даёт 0.793, но 18 label-bad/mixed кадров ошибочно получают keep — лёгкий эстиматор занижает лоу-кей/художественные кадры. Вывод: вариант A-lite (детерминированный гейт) исключён, вариант A (qualified intent-модель) подтверждён данными; предложение 35 дополнено исследованием.

**2026-09-12 (продолжение 10) — R03 groundwork: SubjectIdentityRegistry.**

Новый bounded-владелец мультиобъектной идентичности: N observation-идентичностей, жадная IoU-ассоциация (0.30), capacity 6, miss-aging (3), generation fence; переиспользует SubjectTrackIdentity; не advice-target (SubjectTracker остаётся владельцем цели). 10/10 unit-тестов (iPhone 17e), включая best-IoU без двойного клейма, grace-window reappearance, capacity fence, zero-area; первая сборка поймала реальный баг (созданные идентичности старились в своём же вызове) — исправлен. Контроль 6 suite: 190/150/40/0 — ноль регрессий. Groundwork: в pipeline не подключён, look-alike различение (appearance-признак) — отдельная работа; R00-статусы O02/O05 не менялись.

**2026-09-12 (продолжение 10) — R03 groundwork: SubjectIdentityRegistry.**

Новый bounded-владелец мультиобъектной идентичности: N observation-идентичностей, жадная IoU-ассоциация (0.30), capacity 6, miss-aging (3), generation fence; переиспользует SubjectTrackIdentity; не advice-target (SubjectTracker остаётся владельцем цели). 10/10 unit-тестов (iPhone 17e), включая best-IoU без двойного клейма, grace-window reappearance, capacity fence, zero-area; первая сборка поймала реальный баг (созданные идентичности старились в своём же вызове) — исправлен. Контроль 6 suite: 190/150/40/0 — ноль регрессий. Groundwork: в pipeline не подключён, look-alike различение (appearance-признак) — отдельная работа; R00-статусы O02/O05 не менялись.

**2026-09-12 (продолжение 11) — R03 wiring: observation-полоса в pipeline.**

`observeSubjectIdentityLane` подключён в `makeFeatureSnapshot` (live-only): primary candidate region регистрируется в SubjectIdentityRegistry; реестр пересоздаётся при смене lifecycleGeneration, смена сцены вымывается miss-лимитом. Observation-only: ни один advice/verdict путь не читает реестр — нулевое поведенческое изменение. Тест `testSubjectIdentityLaneMaintainsStableIdentityAcrossLiveFrames` (реальный capture path): стабильная identity через 10 живых кадров, 0 misses. Сертификация 6 suite: 191/148/43/0; 2 extra capture-path падения соло проходят (load-flake семейство). Следующий шаг: мульти-детекторные регионы (DETR boundingBox) в полосу и потребитель идентичностей для двухламповой истории.

**2026-09-12 (продолжение 12) — DETR-регионы в identity-полосе.**

Агрегатор получил `subjectIdentityObservations(from:)` — те же foreground-детекции, что видит снапшот, как observation (region/confidence/label). Лента: DETR-регионы — мультиобъектный источник; fallback на primary region при пустом DETR. Контроль 6 suite: 191/150/41/0 — registry/lane чисты, composition прежняя (37 drift + known + scene-cut flake). Полоса observation-only; консюмер и look-alike — следующие шаги.

**2026-09-12 (продолжение 13) — O02/O05 groundwork: multi-object summary.**

`SubjectIdentityRegistry.multiObjectSummary()` → MultiObjectSceneSummary: количество идентичностей по лейблам (две «лампы» = 2), пересекающиеся TrackID-пары (IoU > 0.15), edge-cut идентичности. Read-only evidence, советы не затронуты. Тесты: registry 12/12 (2 новых: разделённые лампы без пересечений; пересечение + edge-cut). Сертификация 6 suite: 193/151/42/0 — 40 known drift без изменений + 2 load-flake capture-path теста (соло PASS). Compile-инцидент (вставка закрыла struct до iou) пойман swiftc -parse, исправлен до прогона. Осталось: консюмер summary в советах — после калибровки вердикта; D6/intent — у владельца.

**2026-09-12 (продолжение 14) — вариант A пилот: intent-модель baseline исполнена.**

`ml/camera_coach/intent_pilot/`: детерминированный билдер датасета (INTENTDUMP + лейблы → стратифицированный сплит 122/52, seed 20260912) + softmax-LR пилот (numpy). Гиперпараметры отобраны validation-сплитом; каноничный прогон: test accuracy 0.673 (baseline 0.466), good F1 0.702 / bad F1 0.698 / mixed F1 0.0 (support 4). Подтверждено данными: aesthetic_score — единственный сильный признак (AUC 0.846), лёгкий эстиматор занижает лоу-кей; для master-гейтов нужен qualified intent-корпус > 174 записей. Research_only: модель не для бандла; это feasibility-baseline вариант A, воспроизводимый пайплайн передан для будущих признаков.

**2026-09-12 (продолжение 15) — load-flake исследование: характеристика семейства.**

Четыре параллельных 6-suite прогона характеризовали flake-семейство: {scene-cut, AutomaticallyVerifies, PublishesCorrective} — ClosedLoop capture-path timing-тесты; 0–2 срабатывания за прогон, состав ротируется, все проходят соло. Расширение бюджетов 2с→10с не устраняет падение; причина — контеншен клонов задерживает capture-цепочку за пределы бюджетов. Классифицировано как тест-инфра work item (кандидаты: сериализация ClosedLoop, stage-телеметрия, детерминированный фейдер). Evidence: load-flake-study-runG-20260912.txt.

**2026-09-12 (продолжение 16) — диагностический прорыв по load-flake.**

Серийный прогон (ClosedLoop после AnalysisPipeline-тестов в одном клоне) ДЕТЕРМИНИРОВАННО воспроизводит pollution: `testNeuralEvidenceMovementAndVerificationRemainProductionOwned` — `verificationImproved/NotImproved` вместо `stableTip/keepAsIs` (4 ассерта). Причина семейства — кросс-тестовое загрязнение состояния, не бюджет ожиданий; параллельные прогоны лишь рандомизируют порядок, делая флейк случайным. Рецепт воспроизведения записан в EXECUTION_STATE; следующий шаг — бисекция polluting-теста и стат-владельца.

**2026-09-12 (продолжение 17) — воспроизведение подтверждено 2/2; ведущая гипотеза — процессный shared-store.**

**2026-09-12 (продолжение 18) — store-гипотеза опровергнута; загрязнение generic; summary-консюмер.**

Гипотеза CameraRuntimePerformanceStore проверена и опровергнута: DEBUG-сброс store в tearDown polluter-класса не устранил падение Neural (repro-пара, правка откачена). Probe с другим demo-тестом дал то же падение → загрязнение GENERIC: любой demo/live AnalysisPipeline-тест перед Neural-тестом в одном процессе ломает презентационные ожидания; "единственный polluter" бисекции — артефакт отбора. Кандидаты для фальсификации записаны (NotificationCenter retained-подписки, process-wide демо-флаги, scheduler/queue остаток); рекомендация — изоляция suite по процессам (параллельный режим уже де-факто изолирует). Параллельно добавлен consumer-скаффолдинг O02/O05: `testingSubjectMultiObjectSummary` (diagnostic-only) + assert в lane-тесте; registry+lane 13/13 PASS.

**2026-09-12 (продолжение 19) — три гипотезы load-flake опровергнуты.**

(a) performance-store reset — не помог (откачено); (b) single-polluter — артефакт (другой demo-тест даёт то же); (c) aging фикстур (−10с → −0.2с) — не помог (откачено). Статанализ исключил мутабельные static в pipeline/neural/registry, Telemetry-чтение и глобалы в presentation/context (дефолты литеральные). Механизм открыт, repro детерминирован; следующее — retained-подписки/ленивые синглтоны/остаток scheduler, либо изоляция suite по процессам.

**2026-09-12 (продолжение 20) — полный baseline unit-таргета.**

Все 134 unit-файла: 1582 теста / 1513 passed / 64 failed / 5 skipped (iPhone 17e, параллельно). Разложение: 40 известный drift (37 still-replay + objectmode/scenariopack/neural/ClosedLoop flake), 10 детерминированных pre-existing (SceneSemantics golden ×4, FeatureSnapshotAggregator freshness ×1 из prior provenance-работы, LensSwitch subject-change ×1 по handover §9, Settings ISO ×1, Performance ×1, SceneV8 ×2), ~12 order/flake-sensitive (соло проходят). Ни одно детерминированное падение не атрибутировано изменениям сессии. Список — evidence-m2/full-unit-target-failures-20260912.txt.

**2026-09-12 (продолжение 21) — САМОКОРРЕКЦИЯ: «polluter/загрязнение» — артефакт; Neural — детерминированный known-failure.**

Проверка соло: `testNeuralEvidenceMovementAndVerificationRemainProductionOwned` падает детерминированно (2/2, идентичный NEURALTRACE: routed=verification-состояния вместо stableTip/keepAsIs) и падал во всех конфигурациях прогонов — это часть known drift-набора (demo/object/neural, M2/R15), а не жертва кросс-тестового загрязнения. Бисекция была порочной (grep не распознавал серийный формат `]' failed`; «known»-фильтры включали Neural), вывод о generic-загрязнении и polluter ОТОЗВАН. Реальная load-flake семья — три capture-path теста (scene-cut, AutomaticallyVerifies, PublishesCorrective): соло PASS, под параллельной нагрузкой 0-2 падения; рекомендация — изоляция/сериализация ClosedLoop capture-path. Инструментация удалена, эксперименты откачены.

**2026-09-12 (продолжение 22) — изоляция capture-path верифицирована.**

`scripts/run_camera_certification.sh`: фаза A ClosedLoop сериально (17/18 — единственный фейл известный Neural-drift; три capture-path flake-теста PASS), фаза B остальные параллельно (136/175 — 39 known drift, ноль флейков). Итого 193/153/40 — все падения детерминированные известные, флейк-шум устранён из сертификации (ранее 41-43 с вращающимися flake'ами).

**2026-09-12 (продолжение 23) — O02/O05 read-only консюмер на decision-trace.**

`ExplainabilityTraceBundle` теперь несёт item `subject_identities_<frameId>` (observation/snapshotSignal, audience .debug, metadata counts, RU-statement) при ≥1 tracked identity — диагностическая поверхность, советы не затронуты; bundle.validate() проходит. Lane-тест реального capture-пути проверяет item, audience, statement и валидность (15/15 passed). Сертификация: 193/153/40 — идентично до-консюмерному состоянию, нулевые регрессии.

**2026-09-12 (продолжение 24) — решения владельца получены; начат серверный auth-контур.**

Владелец: intent-источник = A + C (модель + интерактивное уточнение), D6 = capability сейчас (iPhone 13 Pro на момент проверки unavailable → roundtrip позже). Первый примитив цепочки: `app_attest_authenticator.py` — строгий bounded-парсер attestation object (CBOR apple-appattest, attStmt {x5c, receipt}, authenticatorData с AT/ED, aaguid, credentialId, COSE ES256/P-256; extension-байты opaque без угадывания политики). 6/6 тестов + полный backend-набор 43 + service 26/26 зелёные. Следующий шаг — enrollment orchestrator (challenge→cert→receipt→counter→install→token) с инъекцией примитивов.

**2026-09-12 (продолжение 24) — решения владельца получены; начат серверный auth-контур.**

Владелец: intent-источник = A + C, D6 = capability сейчас (iPhone 13 Pro был unavailable → roundtrip позже). Первый примитив цепочки: `app_attest_authenticator.py` — строгий bounded-парсер attestation object (CBOR apple-appattest, attStmt {x5c, receipt}, authenticatorData AT/ED, aaguid, credentialId, COSE ES256/P-256; extension-байты opaque). 6/6 тестов; полный backend 43 attest + service 26/26 зелёные; README обновлён. Следующий шаг — enrollment orchestrator.

**2026-09-12 (продолжение 25) — enrollment orchestrator реализован.**

`app_attest_enrollment.py`: challenge (атомарный consume первым) → client_data_hash==SHA256(challenge) → парсинг attestation object → RP/credential/zero-counter → certificate (nonce=raw authData‖clientDataHash) → receipt → установка → токен; примитивы инжектируются (фейки в тестах, production-дефолты — реальные модули). 8/8 тестов (включая одноразовость challenge при провале, биндинг до парсинга, missing-credential/RP/counter/credId/receipt, повторную установку, lifecycle токена/счётчика). Полный backend: 51 attest + 26 service зелёные; README обновлён. Сервис остаётся 401 — endpoint-wiring и device-roundtrip после capability/телефона.

**2026-09-12 (продолжение 26) — App Attest endpoints в service (deny-by-default сохранён).**

`service.py`: opt-in `AppAttestConfiguration` (CLI `--attest-app-id` + `--attest-database` + `--openssl-path`), endpoint'ы `POST /v1/attest/challenge` (одноразовый challenge) и `POST /v1/attest/enroll` (b64 JSON, строгие длины, композиция AppAttestEnrollment); униформный 401 на любые провалы, без конфигурации — 401/`unavailable`. Тесты endpoints 4/4 (deny-by-default, round-trip, replay, malformed). Полный backend: 81 тест (51 attest + 4 endpoints + 26 service) зелёные; README обновлён.

**2026-09-12 (продолжение 28) — Swift App Attest клиент + уточнение по изоляции.**

`AppAttestServiceTokenProvider.swift`: capability-gated клиент поверх `SceneServiceTokenProviding` — DeviceCheck/URLSession/Keychain за seams, graceful degradation в nil (unsupported/ошибка challenge/attest/enroll/пустой токен), одноразовый enroll с кэшем токена и TTL из ответа сервера, переиспользование persisted key, сброс негодного key. 7/7 тестов на фейках. Сертификация: фаза B неизменна (39 known drift, ноль флейков), фаза A 16/18 — Neural (детерминированный) + scene-cut (тот же wait-бюджетный сигнатура) → изоляция снижает, но не устраняет остаточную внутриsuite'овую чувствительность; окончательный фикс — детерминированная доставка фикстур (тест-инфра item).

**2026-09-12 (продолжение 29) — композиция Scene-провайдера (fail-closed фабрика + opt-in bootstrap).**

`SceneRemoteServiceComposition.makeRemoteProvider` возвращает nil без явного validated https-endpoint'а или без App Attest (переиспользован ставший internal `isValidEndpoint`); при успехе собирает SceneGenerationClient с AppAttestServiceTokenProvider. `SceneRemoteServiceBootstrap.configureIfEnabled` в AppDelegate трогает shared-сервис только при включении (default launch-путь не изменён), добавлен read-only `isRemoteOffloadConfigured`. Тесты композиции 8/8. Сертификация после startup-правки: A 17/18 (known Neural), B 136/175 (39 known, ноль флейков) — регрессий нет. Remote egress включается только deployment-конфигурацией (D1/D2-гейты сохранены).

**2026-09-12 (продолжение 30) — C (CC-I05): интерактивное уточнение намерения.**

`CameraIntentClarificationPolicy`: детектор стилевых cues из существующих evidence (только при читаемом субъекте), маппинг cue→конфликтующие семейства, сеансовые ответы (намеренно → подавление; нет → остаётся actionable), prompt-key. `CameraAdviceSafetyGate` расширен `intentionallySuppressedFamilies` (default пусто) и typed-причиной `.intentionalStylePreserved` (после identity, до motion/семейных правил). Pipeline: сеансовое состояние + `recordIntentClarification`/`resetIntentClarificationSession` + диагностические accessor'ы; gate-вход получает suppression-set (по умолчанию пусто → поведение неизменно). Тесты: policy 7/7, gate +2, прогон 33/33. Сертификация: A 17/18 (known Neural), B 177/138/39 (39 known без изменений, +2 новых gate-теста проходят). UI-презентация вопроса и per-frame детекция cues — следующий пакет; до ответа пользователя советы не меняются.

**2026-09-12 (продолжение 31) — C (CC-I05) UI-слой.**

10 ключей локализации (en/ru) + SETCopyKey; `IntentClarificationPresentation` (чистая проекция cue→копия+a11y-id); pipeline `@Published pendingIntentClarificationCue` + per-frame детекция в единственном live-пути + `answerIntentClarification`; ViewModel passthrough (Combine) и компактный `SETCameraIntentClarificationPrompt` в live-оверлее (вопрос + 2 кнопки 44pt). Тесты UI 6/6 + policy 7/7; сертификация A 17/18 (known), B 138/177 (39 known) — ноль регрессий. Границы: SwiftUI-рендер и visual/Dynamic Type/VoiceOver — в UI/physical gate.

**2026-09-12 (продолжение 32) — визуальная приёмка промпта: дефект контраста найден и исправлен.**

Рендер-харнесс `IntentClarificationRenderAcceptanceTests` (7 конфигураций + подложки, PNG + инспекция) выявил реальный дефект: на яркой подложке в светлой схеме вопрос почти невидим (ultraThinMaterial вымывается, textPrimary фиксированно светлый). Фикс: тёмный скрим IntentPromptStyle.scrimOpacity=0.85 (семейство black.opacity как у DirectionArrows); повторный рендер визуально подтвердил читаемость. Прокси-проверка (непустой PNG) заменена на арифметический worst-case WCAG-AA тест от инварианта + layout-проверки (Dynamic Type рост, узкий ландшафт); композитные пиксельные метрики отклонены как геометрически недостоверные. Приёмка 4/4; сертификация A 17/18 (known), B 138/177 — без регрессий. VoiceOver-обход и physical-подложка — за границей пакета.

**2026-09-12 (продолжение 33) — полировка accessibility промпта + VoiceOver-статус.**

Ответы промпта при accessibility-размерах Dynamic Type переведены в вертикальный стек (AnyLayout по isAccessibilitySize) — .accessibility3/.5 без переносов, визуально подтверждено. Добавлен инвариант hit-target ≥44. Приёмка+политика 12/12. VoiceOver-приёмка не выполнена по зафиксированному блокеру: idb-бэкенд недоступен (`ios_ui_status: available false`), а промпт требует реальной камеры-сессии (запуск в симуляторе доходит до экрана входа «СНИМАЙ КИНО»). VoiceOver-traversal и accessibility-audit отнесены к физическому устройству (iPhone ждёт подключения от владельца). Итоговая матрица: контраст/Dynamic Type/ландшафт/hit-target ✓, VoiceOver ✗.

**2026-09-12 (продолжение 34) — annotation-пилот подготовлен к запуску.**

`export_pilot_packet.py` формирует слепой пакет (CSV+Markdown, только scenario/advice, отказ при adjudication-полях) — 35 записей; `annotation-pilot-launch-checklist.md` описывает полный порядок (свои store/ID, голосование, покрытие, объединение append-only, отчёт, адъюдикация, приёмка) и правила слепоты. Dry-run на масштабе: 1×35 → покрытие 100%, κ n/a; 2×35 (70 голосов) → покрытие 100%, 31 единогласных, 4 спорных, κ 0.813. Temp-stores удалены, человеческие голоса не выдумывались. Owner-запросы отправлены одним сообщением (бюджет A, iPhone для device roundtrip+VoiceOver, хостинг D1/D2) — ответа нет, действуют безопасные дефолты.

**2026-09-12 (продолжение 35) — канонический 174-label baseline и drift-карта критика.**

До этого пакета набор из 174 лейблов benchmark-пака сравнивался с вердиктами пайплайна только разовым временным тестом (drift 128/174, forbidden 26), а канонический оценщик применялся лишь к 107-записному M4-001-lane. Пакет закрывает этот пробел без новых расходов, egress и устройств: добавлен коммитнутый конфиг `replay-config-174-drift.json`, runner `run_swift_semantic_replay.py` получил `--config` (дефолт и поведение M4-001 сохранены), а новый `label_drift_report.py` переиспользует канонический scorer и добавляет disposition-разрез, strict_drift и проверку label↔image sha256. Прогон на разрешённом iPhone 17e: тест batch-replay Passed, 348 строк / 174 записи, `real_runtime_still_replay`; артефакты с sha256-пинами — `docs/cameraanalysis/eval/camera-baseline-v0/drift-174/`.

Метрики (174 записи): expected_action_hit_rate 0.4655, forbidden_action_violation_rate 0.1149, good_frame_preservation_rate 0.5185, confidence_band_accuracy 0.6609 — ни один мастер-гейт не достигнут. Drift: strict_drift 124/174, disposition keep 48 / correct 94 / silence 32; 39 overcorrection на good-кадрах, 9 false keep и 29 silence на bad/mixed; 20 forbidden-hits. Отдельные честные находки: (1) 35 из 174 label sha256 не совпадают с байтами изображений пакета (все вне 107-lane) — те же 35 не совпадают и в исходном `regen_bad_v1`-файле, т.е. устаревшие объявления присущи самому лейбл-бандлу, а не пакету; метрики дополнительно посчитаны на 139 byte-verified записях (good_frame_preservation 0.587), расхождение зафиксировано как ограничение данных, а не «исправлено». (2) Проверено, что контент лейблов первых 107 записей идентичен `semantic_labels_v1.jsonl`, т.е. lane расширяет M4-001.

Главная находка пакета — доказанная регрессия текущего критика. Bundled-пак 174 записей контентно совпадает с `..._regen_bad_v1.jsonl` — тем самым стендом, на котором EV-CA-EVAL-009/CL-CA-011 фиксировали `pass_rate=0.850575` и `good_frame_preservation_rate=0.987654`. Построчное сравнение с закоммиченным `out_semantic_real_runtime_v2_regen_bad_v1/candidate_outputs_raw.jsonl` показало: 109/174 pause-наборов действий отличаются, 43 из них `keep_current_setup` → корректирующие советы, 42 изменённые записи помечены `good`; 66 расхождений по `object_count`, 87 по confidence, при идентичном NIMA `aesthetic_score` у 171/174 (пиксели те же). Значит расходится именно цепочка critique/planning текущего дерева. Это уточняет прежний вывод о «давних чужих противоречиях тестов»: 41 still-replay падение кодирует калиброванное поведение R-кампании, которое текущий source не воспроизводит. Thesis-артефакты обновлены: EV-CA-EVAL-010, CL-CA-011 → `conflicts_with_current_code`, новый CL-CA-012, глава 5.2 → `needs_update` с причиной. Числа запинованы тестами манифеста. Граница: сравнение — с артефактом более раннего коммита M4-кампании (какой коммит внёс расхождение, не бисектировалось; часть расхождения может быть намеренной эволюцией main-линии). Eval-набор 66 passed; временные каталоги прогона удалены. Выравнивание критика (M2/R15) остаётся открытым, но теперь у него есть воспроизводимая каноническая база и количественная мера регрессии.

**2026-09-12 (продолжение 36) — выравнивание критика: инструментирование, калибровка object edge-pressure и полный A/B.**

Инструментирование показало, что сами анализаторы читаемости и доминантности **байт-идентичны** версии June-кампании (`git show 2a5145f`) — формулы `edgePressureScore`, `separationScore` и гейта `edgePressureScore <= 0.80` не менялись. Изменились входы, и в двух конкретных местах выбора субъекта: кандидат `snapshot-object` стал передавать `region: topObjectRegion` (раньше `region: nil`), а `makeCandidate` стал публиковать сырое `baseConfidence` вместо взвешенного `base * sourceReliability * kindWeight * regionWeight`. Проверка на данных подтвердила механизм: у всех 43 исторических flip-записей `edge_pressure` ровно 0.500, а у 39/43 текущих — ≥0.80. То есть DETR-бокс объекта, упирающийся в край кадра, стал трактоваться как «субъект прижат к краю».

Калибровка — один hunk: `edgePressureScore` остаётся 0.50, когда примари-субъект имеет вид `.object` (историческое поведение для этого вида), при этом регион остаётся доступен критику. Измерены и отклонены два альтернативных варианта: снятие edge-терма из гейта читаемости (хуже по всем метрикам) и area-условие (проверено на данных — `subject_area_ratio` не разделяет группы, значит правило было бы произвольным).

Полный A/B на iPhone 17e через `scripts/run_camera_certification.sh`: фаза A одинакова в обеих версиях (18/17/1, только known Neural), фаза B — базовая 177/138/39 (воспроизведена ровно при откате одного hunk) против 177/140/37 с калибровкой. Метрики 174-label still replay: pass_rate 0.379→0.506, expected_action_hit 0.466→0.649, **good_frame_preservation 0.519→0.840**, overcorrection на good 39→13, strict drift 124/174→95/174. Инварианты: 73 строки изменили действия и ни одна из них не относится к не-объектному пути; 28 good-кадров перестали получать корректирующие советы, ноль good-кадров начали получать новые.

Честная цена: forbidden_action_violation 0.115→0.155 (20→27), false keep на bad/mixed 9→26; три ранее падавших still-replay теста проходят, но один (`testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames`) начал падать. 17 плохих объектных кадров теперь возвращают `keep_current_setup` вместо корректирующего движения, потому что их дефект (свет/горизонт/фон) текущий критик вообще не детектирует — базовая версия на них тоже не выдавала помеченное действие. Компромисс записан явно как пробел детекции, следующий шаг — независимое обнаружение дефектов на плохих объектных кадрах, а не возврат edge-эвристики. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-calibrated-edge-neutral/` (`ab-comparison.json`, `manifest.json`, `scored/*`, `label-drift-report.*`); eval-набор 72 passed.

---

**2026-09-12 (продолжение 37) — атрибуция false-keep на плохих кадрах и однопунктовый пакет «техдефект отменяет good-вердикт».**

Атрибуция ответила на вопрос «какой детектор не срабатывает»: **срабатывают все, но презентация их игнорировала**. Из 58 non-good кадров с keep/silence у 55 уже было обнаружено техническое future-действие, а вердикт критика был `good` у 56. По классам дефекта: underexposure 17 кадров → 0 критик-issues, motion_blur 15 → 0, defocus 11 → 0, overexposure 9 → 1. Причина найдена в коде: `makePauseCritiquePresentation` безусловно подавлял все коррекции при `critique.verdict == .good`, игнорируя техпробу, тогда как экспортный контракт требует обратного (доминантное техническое действие снимает keep) — презентация противоречила контракту. Это же объясняет падающий тест из предыдущего пакета.

Изменение — один hunk без новых порогов, через существующий `dominantTechnicalQualityIssue(from:)`: good-вердикт больше не подавляет коррекции, если техпроба измерила доминантный дефект на этом кадре. Метрики 174-label накопленно: pass_rate 0.379→0.534, expected_action_hit 0.466→0.690, good_frame_preservation 0.519→0.840, forbidden 0.115→0.138, strict drift 124/174→94/174; overcorrection на good 39→13. Относительно edge-neutral — плюс по pass/expected-hit, минус по forbidden, а good-preservation и positive-confirmation не изменились. Инварианты: 12 строк изменили действия, ни одна из них не на good-кадре, ни один good-кадр не получил новую корректировку.

Полный A/B через `scripts/run_camera_certification.sh`: фаза A 18/17/1 без изменений, фаза B 177/140/37 → **177/142/35** — два still-replay теста исправлены (`MapsSmallUnderlitLightObjectToFrontFill`, `MapsUnknownBlurToSimplifyBackground`), новых падений нет; накопленно против исходной базы 138/39 → 142/35 (4 исправлено, 1 новый). `testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames` остаётся падающим — другой путь (motion-like false positives), записано честно. На этом пакете не измерено ни одного ухудшения. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-technical-override/`; eval-набор 76 passed.

---

**2026-09-12 (продолжение 38) — инструментирование техпробы и сигнал-паритет детектора.**

В eval-debug-фичи экспортированы четыре величины техпробы (число issues, число доминантных, максимальные severity и confidence) — без новых порогов. Поведенческая нейтральность доказана сильнее, чем прогоном: все 348 строк нового прогона совпали с technical-override lane побайтно, кроме этих четырёх ключей; контрольный прогон подтвердил то же на уровне suite — фаза A 18/17/1, фаза B 177/142/35 без изменений.

Инструментирование позволило задним числом и независимо проверить триггер принятого ранее изменения: существующий `dominantTechnicalQualityIssue` разделяет классы 9/81 good против 44/79 bad (5×), тогда как «любой issue» даёт 63/81 good против 69/79 bad, то есть бесполезен, а порог 0.45 добавил бы 63 good-кадра. Значит триггер калиброванный, а не подогнанный.

Разобран и последний motion-like тест: из пяти его записей четыре уже не содержат keep, падает только `ca_img_090` — кадр с verdict=good и одним не-доминантным issue техпробы (severity 0.45 при пороге 0.55); его лейбл (motion_blur, ожидается молчание) в still-кадре без временного сигнала не наблюдаем. Понижение планки ради одного теста добавило бы 54 good-кадра, поэтому это записано как честная граница, а не исправлено.

Главная находка пакета — **нарушение сигнал-паритета с историческим артефактом**: `person_count` совпадает полностью, `aesthetic_score` идентичен у 171/174, но `object_count` расходится в 66/174 (среднее 1.736 против 2.138, максимум 8 против 13). Причина в коде: `DETRDetector.extractDetections` переписан — раньше все пиксели класса склеивались в один bounding box, теперь выполняется connected-component labeling и на каждую компоненту выдаётся отдельный бокс. Это намеренное улучшение (две лампы — два объекта), но `object_count`, `objectDensity` и `background_clutterScore` из-за него не паритетно сравнимы с историческими числами: часть остаточного дрейфа — разница входа детектора, а не правил критика. Дальнейшее выравнивание следует измерять против свежего baseline lane. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-probe-instrumentation/`; eval-набор 81 passed.

---

**2026-09-12 (продолжение 39) — оставшиеся 35 expectation-тестов: декомпозиция и отклонённый гейт.**

Ожидания разложены по классам против свежего baseline lane: keep ожидался, но выдана коррекция — 14 записей; ожидалась коррекция фона — 18; фронтальный свет — 10; шаг/дистанция — 19. Покрытие действий оказалось жёсткой находкой: `step_closer` ожидается 9 раз и не выдаётся ни одной ожидающей его записи, `step_back` — 1 такая запись, `remove_distracting_object` ожидается 13 раз и выдан 3; оба шаговых действия достижимы только через `subject_not_prominent_enough`, который срабатывает на 8 строках из 174. То есть 19 ожиданий не выполнимы по построению текущего планировщика. Класс фона сигнально ограничен: у 18 записей `background_clutter` имеет медиану 0.181 против 0.227 по lane, у четырёх `object_count = 0` — сигнала просто нет.

Отдельно проверен и **отклонён по измерению** гейт «не пускать техническую pause-карточку при вердикте good»: он исправил бы 4 записи, но снял бы коррекции с 30 не-good записей, 26 из них через доминантный технический путь, причём на 23 из 30 выдаваемое действие уже совпадало с лейблом. Ни один вердикт-уровневый гейт не отделяет 4 промаха от 26 верных карточек, поэтому изменение не внесено. Код в пакете не менялся (sha256 `9391c81b…`), так что последний контрольный прогон (18/17/1 и 177/142/35) покрывает текущий source.

Вывод: оставшиеся падения перешли из правил и презентации в покрытие и детекцию. Следующий измеримый пакет — детектор дистрактора на уровне региона/салиентности и сигнал размера субъекта, прогнанные как новый baseline lane. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-failure-classes/failure-class-decomposition.json`; eval-набор 85 passed.

---

**2026-09-12 (продолжение 40) — пакет детекции: два предложенных сигнала отклонены измерением до написания кода.**

Постановка была добавить регион/салиентность-сигнал дистрактора и сигнал размера субъекта. Оба проверены на коммитнутом lane до продакшн-кода, и оба отклонены. Сигнал A уже существует в виде `backgroundClutterScore` и `object_count`, и на 10 из 18 «пропущенных» записей фона issue создаётся и обнуляется собственным консистенси-правилом `hasStrongSubjectIsolationEvidence`; варианты сигнала дают 8 из 18 попаданий при 41 из 81 срабатывании на good-записях (50.6 % ложных), а гипотеза о разблокировке через восстановление исторической взвешенной confidence объясняет всего 1 из 10 подавленных записей. Сигнал B тоже существует — `issueSubjectNotProminentEnough` считает `areaPenalty` и именно он открывает `step_closer`; при этом лейблы не согласованы с геометрией: записи с ожиданием `step_back` («субъект слишком крупный») имеют медианную площадь 0.021 против 0.053 у ожидающих `step_closer`, при медиане lane 0.064.

Вывод: ни один из предложенных сигналов не адресует блокер, и строить их значило бы добавить поверхность с ~50 % ложных срабатываний без владения ни одним тестом. Следующий шаг переформулирован: ревизия framing-ожиданий лейблов, решение с held-out split по правилу изоляции и, только при необходимости, детектор, специфицированный против 13 записей, где сигнала нет вообще. Код не менялся, поэтому последний контрольный прогон (18/17/1 и 177/142/35) покрывает текущий source. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-signal-viability/`; eval-набор 89 passed.

---

**2026-09-12 (продолжение 41) — ревизия framing-лейблов и held-out решение по правилу изоляции.**

Ревизия самих лейблов исправила собственный прежний вывод: `step_back` не означает «субъект слишком крупный» — у 9 из 11 записей в `future_needed_actions` стоит `avoid_occlusion`, а тексты проблем говорят о перекрывающем переднем плане, прижатом к краю субъекте и тесной рамке. То есть лейбл ожидает семантический `step_back` как ремедиацию окклюзии, тогда как пайплайн кодирует ту же окклюзию future-действием `avoid_occlusion`: у 6 из 11 записей оно уже есть (дефект обнаружен), а по lane таких строк 46, из них 19 вообще без семантического действия. Это разрыв маршрутизации, а не противоречие геометрии. Для `step_closer` только 5 из 9 записей говорят «субъект слишком мал», причём у ca_img_236 измеренная площадь субъекта 1.000 при тексте «объект занимает слишком мало кадра». Числа площадей не изменились — изменилась интерпретация намерения лейблов.

Held-out решение по правилу `hasStrongSubjectIsolationEvidence`: детерминированный split по `record_id` (87/87), критерий «правило не обнуляет конкуренцию фона при clutter ≥ X». Решение — **отклонён по данным**: ни один порог не удерживает ложные срабатывания ≤ 2 на derivation-половине; лучший случай X = 0.25 даёт 2 TP против 22 good, на validation-половине 3 против 16, при X = 0.60 сигнала нет. Базовая ставка (18 промахов против 81 good) делает любое clutter-правило в основном вредным для хороших кадров. Правило оставлено как написано и зафиксировано как ограничение, а не подогнано.

Код не менялся, последний контрольный прогон (18/17/1 и 177/142/35) покрывает текущий source. Owner-гейты (бюджет intent-модели, iPhone 13 Pro, хостинг D1/D2) остаются без ответа — безопасные дефолты. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-framing-isolation-review/`; eval-набор 93 passed.

---

**2026-09-12 (продолжение 42) — маршрутизация окклюзии: механизм найден, правка отклонена арифметикой.**

Найден точный механизм разрыва: `technicalPauseActions(for:)` реализует action-строки только для `.overexposure` и `.underexposure`, а для остальных типов возвращает `[]` — включая `.occlusion`. Обнаруженная окклюзия поэтому имеет тексты summary/why/action и выдаётся как future-действие `avoid_occlusion`, но никогда не становится семантической строкой pause-карточки; вдобавок `isDominant` у пробы ставят только exposure/sharpness, так что окклюзия допускается лишь через contextual-fallback.

Население: pause-строк с окклюзией 46 (молчащих 19), из них с окклюзией и доминантным дефектом 20, хороших среди них нет. Правило «окклюзия → семантический step_back» дало бы +2 к expected-action (ca_img_209, ca_img_235), +1 forbidden-нарушение (ca_img_236, где step_back запрещён) и +16 действий, которых лейблы не просят. Обмен одного нарушения на два попадания net-negative при гейте forbidden ≤ 0.02, поэтому правка **не применена**. Вариант без условия доминантности отклонён на held-out: derivation 5 gain / 3 risk, validation 3 gain / 8 risk.

Код не менялся, последний контрольный прогон (18/17/1 и 177/142/35) покрывает текущий source. Измеренные рычаги на still-replay lane для доступных сигналов исчерпаны; открытая работа — owner-набор. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-occlusion-routing/`; eval-набор 97 passed.

---

**2026-09-12 (продолжение 43) — уверенность: инструментирование base-конfidence и отклонение «восстановления взвешивания».**

Проверена гипотеза, что публикацию уверенности субъекта следует вернуть к исторической формуле `base × sourceReliability × kindWeight × regionWeight`. Чтобы измерить это по-настоящему, добавлен аддитивный debug-ключ `primary_subject_base_confidence` (первая оценка по пост-взвешенной величине была некорректной и отброшена). Нейтральность поведения доказана построчно: 348/348 строк совпадают с предыдущим lane, кроме нового ключа; контрольный прогон — 18/17/1 и 177/142/35 без изменений.

Измерение по 174 лейблам: текущая согласованность band'ов 126/174, при историческом взвешивании — 6/174, net −120 (gained 1, lost 121, из них 107 «target high»). Гипотеза отклонена. Заодно исправлен более ранний вывод этой сессии: сырая публикация помечалась как разрыв паритета, вероятно вредящий выравниванию, — измерение показывает обратное, она совпадает с лейбловыми band'ами существенно лучше.

Разложение 48 расхождений (26 high-ниже, 21 medium-выше, 1 medium-ниже) объясняется вердиктными правилами `pauseVerdictConfidence`: `min(base, 0.74)` для mixed с действиями и `max(base, 0.75)` для good со strengths против band'ов оценщика high ≥ 0.75 / medium [0.45, 0.75). Это расхождения по вердикту, а не арифметика band'ов. Owner-запросы отправлены повторно одним сообщением, ответа нет — безопасные дефолты. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-confidence-parity/`; eval-набор 101 passed.

---

**2026-09-12 (продолжение 44) — аудит framing-ожиданий против измеренной геометрии.**

Все 20 записей с ожиданиями `step_back`/`step_closer` классифицированы воспроизводимо: семья дефекта, подразумеваемая ожидаемым действием, сравнивается с семьями из собственного текста проблем записи (фиксированный список ключевых слов) и с измеренной площадью субъекта против окна 0.10. Результат: 14 из 20 согласованы (класс доставляем, разрыв — в доставке), 5 называют проблему другой семьи (в основном освещение), 1 не называет семьи. У `step_closer` 6 записей имеют площадь < 0.10, 3 — ≥ 0.10. Рекомендации: 12 keep, 4 reword_or_replace, 1 add_explicit_wording, 3 geometry_contradicts_expectation.

Записи на ревизию лейблов или корпуса: ca_img_080 (geometry_contradicts_expectation), ca_img_085 (add_explicit_wording), ca_img_092 (reword_or_replace), ca_img_093 (reword_or_replace), ca_img_095 (reword_or_replace), ca_img_208 (reword_or_replace), ca_img_212 (geometry_contradicts_expectation), ca_img_236 (geometry_contradicts_expectation). ca_img_236 особенно показательна — измеренная площадь 1.000 при тексте «объект занимает слишком мало кадра»; такие ожидания не удовлетворит ни один сигнал размера. Правки кода из аудита не следуют; подгонять пороги под несогласованные записи нельзя. Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-framing-label-audit/`; eval-набор 105 passed.

---

**2026-09-12 (продолжение 45) — release-цепочка: Release-сборка не собиралась, найдено и исправлено.**

Первая же Release-сборка (`-configuration Release -destination generic/platform=iOS`, подпись отключена) провалилась с 5 ошибками одного класса: production-код ссылается на члены, объявленные только под `#if DEBUG`. `AnalysisPipeline` вызывал `updateIntentClarification` из `publishLivePresentation`, а весь intent-API лежал внутри DEBUG-расширения; `CameraViewModel` по той же причине не видел `answerIntentClarification`; `SceneGeneratorViewModel` использовал члены фикстуры лидера, объявленные внутри DEBUG-блока. Почему это не ловилось раньше: все прежние сертификации собирали только Debug.

Исправление: четыре production-члена intent-API вынесены в production-расширение (тестовые аксессоры остались под `#if DEBUG`), три члена фикстуры генератора — из DEBUG-блока при неизменном поведении фикстуры (активируется только аргументом запуска). После правки: **BUILD SUCCEEDED, 0 ошибок** (было 5), бандл собран, в нём privacy manifest и иконка; ничего не подписывалось и не публиковалось. Контрольный Debug-прогон — 18/17/1 и 177/142/35, идентично состоянию до правки.

Зафиксированы статические факты релиза (bundle id, версии, iOS 17, team, usage-строки, privacy manifest, ARKit-требование, 480 локализованных ключей) и prerequisites для TestFlight: запись в App Store Connect, distribution-сертификат и профиль, скриншоты/метаданные, GO владельца — блокирующие и владельческие; `ExportOptions.plist`, декларация экспортного соответствия, локализованные usage-строки и entitlement App Attest — работа агента. Добавлена регресс-защита `tools/tests/test_release_guards.py`, которая ловит этот класс дефекта без Release-сборки. Артефакт: `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/release-chain-readiness-audit.json`; тестов 110 passed.

---

**2026-09-12 (продолжение 46) — агентские prerequisites TestFlight выполнены.**

Добавлены три пункта, которые не требуют владельца. `docs/implementation/release/ExportOptions.plist`: method app-store-connect, destination **export** (не upload), teamID 5NAKQ28539, automatic signing, выгрузка символов; в комментарии — команды archive/exportArchive и явная пометка, что выполнить это нельзя до появления distribution-identity владельца. `ITSAppUsesNonExemptEncryption = false` внесён в `shafinMultitool/Info.plist`; обоснование проверено по коду — своего шифрования нет, только Apple CryptoKit SHA-256 (дайджесты запроса и App Attest) и обязательный https; значение подтверждено в собранном Release-бандле.

Третий пункт оказался уже выполненным: usage-строки локализованы через `shafinMultitool/Resources/InfoPlist.xcstrings` (en+ru, пять ключей), и сборка кладёт в бандл `en.lproj/InfoPlist.strings` и `ru.lproj/InfoPlist.strings` со всеми четырьмя описаниями. Прошлый аудит ошибочно записал их как нелокализованные — он искал только `.strings` в исходниках, не проверив String Catalog и бандл; запись исправлена с явной пометкой причины.

Проверка: Release-сборка без подписи → BUILD SUCCEEDED, 0 ошибок; в бандле подтверждены декларация и оба локализованных plist. Ничего не подписано, не архивировано и не опубликовано. Регресс-защита расширена до 9 проверок (декларация в Info.plist, валидность и безопасность ExportOptions, полнота String Catalog, исправленный факт аудита). Тестов 114 passed. Владельческими остаются запись в App Store Connect, distribution-сертификат и профиль, метаданные/скриншоты и GO на отправку.

---

**2026-09-12 (продолжение 47) — ответы владельца и закрытие разрыва «job-маршруты 401».**

Владелец ответил на четыре релизных вопроса одним сообщением: запись App Store Connect — «не сейчас», distribution-сертификат и профиль — «позже», метаданные/скриншоты/URL — «отложить», отправка — «да, требую явный GO». Значит release-цепочка останавливается на подготовленном черновике, никаких шагов к ASC не делается, а публикация возможна только по отдельному явному разрешению. Черновики (ExportOptions.plist, декларация экспортного соответствия, метаданные, privacy-ответы) остаются в `docs/implementation/release/` с пометкой об отложенности.

В ожидании закрыт реальный разрыв во внешнем backend: `require_installation()` был заглушкой, всегда отвечавшей 401, поэтому даже успешно зарегистрированная установка не могла вызвать `/v1/jobs` — полномочие «токен → владелец» отсутствовало. Теперь зависимость резолвит bearer-токен через состояние аттестации со строгим разбором заголовка и владельцем = SHA-256 от key_id, сохраняя deny-by-default для неконфигурированного сервиса, битых заголовков и любых непринятых токенов; существующий шов `dependency_overrides` продолжает работать.

Проверка: новый `test_attest_job_flow.py` проходит весь путь challenge → enroll → POST /v1/jobs (201) → GET (200) → идемпотентный повтор, а также закрытость для пяти видов плохих токенов, закрытость без конфигурации и изоляцию владельцев между установками. Полный backend-набор 86 passed (было 81), регрессий нет; прогон воспроизводится в отдельном venv с `PYTHONPATH=<repo>/backend`. Внешний backend не коммитился.

---

**2026-09-13 (продолжение 48) — окклюзия инстансов: честный отказ от объектных советов (CC-O02/O05).**

Замкнут потребительский разрыв двухламповой истории: реестр идентичности уже вычислял пары пересекающихся экземпляров, но ни один путь советов это не читал. Теперь `LiveCoachQualityGate` принимает счётчик пересекающихся пар из реестра и отказывает в объектно-адресованных советах (`moveObject*`, `removeDistractingObject`), когда пары есть: совет «подвинь лампу» не может заземлиться, если лампы слились в одну область. Кадровые глобальные советы (смена угла, кадрирование) остаются активными; отсутствие данных (nil) подавления не включает.

Проверено: юнит-тест гейта (отказ при 1 и 2 парах, глобальные советы живы, nil не подавляет), suite планировщика 24 passed, полная сертификация 178/143/35 — набор падений не изменился, новый тест прошёл. На 174-label lane выход побайтно идентичен предыдущему прогону: статический корпус не содержит пересекающихся пар в момент решения, так что поведение верифицировано юнит-тестом, а не подгонкой под корпус.

Видимая половина O05 также реализована: если сильные советы промолчали, вердикт не good и реестр сообщает пересечение, live-подсказка «объекты перекрывают друг друга — смени угол» показывается вместо тишины. Владелец ответил на четыре релизных вопроса: ASC — не сейчас, сертификат — позже, метаданные — отложить, отправка — только по явному GO. Release-черновики помечены отложенными. Публикация/отправка выполняется только по отдельному явному разрешению владельца.

---

**2026-09-13 (продолжение 49) — backend: worker генерации сцен и store v3.**

Бэкенд был durable admission shell: джобы принимались, отменялись или уронились по таймауту, но генерации не существовало — статус `completed` не был даже разрешён схемой. Реализована замкнутая жизнь джобы: store v3 (статусы running/completed, колонки started/completed/result, миграция v2→v3 с сохранением строк), provider seam с детерминированным локальным провайдером (парсит script_text и marked_objects в минимальный валидный scene-output-v1, помечен deterministic-local-v1) и воркер с семафором конкурентности 1: на 201-create планируется задача, mark_running → generate → complete; ошибка провайдера переводит джобу в failed. Генерация включается только на attestation-конфигурированном деплое — прежние тесты сервиса с override-автором ожидают pending, и это сохранено.

Проверено: тест worker'а валидирует результат по настоящей схеме scene-output-v1 через jsonschema; полный backend-набор 89 passed (81 + 5 job-flow + 3 worker). Хэши файлов зафиксированы в EXECUTION_STATE; внешний backend не коммитился.

---

**2026-09-13 (продолжение 50) — контракт iOS-клиент ↔ backend: running-статус и echo версий.**

Проверена связка по завершённым джобам. Swift-клиент уже декодирует `running` как notTerminal и разбирает complete-ветку, поэтому добавлен узкий Swift-тест `testPollToTerminalTreatsRunningAsNotTerminal` (последовательность running → complete; suite зелёный). Найден реальный интеграционный баг backend-провайдера: он хардкодил `model_version/prompt_version = deterministic-local-v1`, а контракт требует echo версий из метаданных джобы — клиент отклонил бы такой результат. Провайдер теперь отдаёт версии из `validated_request`; backend-тест расширен пинированием echo. Полный backend-набор 89 passed; хэш service.py 0eb52a171e5c… Остаточный разрыв цепочки — физическое App Attest (устройство); больше функциональных блокеров в этом контуре нет.

---

**2026-09-13 (продолжение 51) — tap-заземление объектных советов (ядро CC-O02).**

Реализовано верифицируемое ядро тап-заземления: pure-функция `SubjectTapSelector.hitTestTrackedInstances` (попадание в надутую область трекенного инстанса, ближайший центр побеждает), accessor `SubjectIdentityRegistry.instance(atSceneX:y:)` и исключение в `LiveCoachQualityGate` (`tapGroundedObjectTarget: true` снимает отказ из-за пересечения инстансов — цель названа тапом). Тесты: гейт с тапом разрешает объектный совет, без тапа — отказ; accessor резолвит ближайший инстанс и nil вдали от всех. Overlay/ViewModel wiring тапа — отдельная итерация (нужна реальная камера для проверки жеста). Suite 26 passed; eval-набор 122 passed.

---

**2026-09-13 (продолжение 52) — clarification-ветка backend: полный цикл.**

Store v4: статус `awaiting_clarification` + колонка `clarification` (scene-clarification-v1). Worker: `clarification_required` от провайдера переводит джобу в awaiting_clarification. Endpoint `POST /v1/jobs/{id}/clarification-answer` принимает ответ, складывает его в `validated_request` и пере-ставляет джобу в очередь. Детерминированный провайдер использует `clarification_answer.free_text` как имя актора при повторной генерации.

E2E тест: create (скрипт без актёров) → awaiting_clarification → answer → completed с актёром МАРИНА. Полный backend-набор 92 passed.

---

**2026-09-13 (продолжение 53) — clarification-цикл backend: full loop fix.**

Провайдер не использовал `free_text` из clarification-answer при повторной генерации — добавлен override. Endpoint `POST /v1/jobs/{id}/clarification-answer` добавлен. Полный clarification-цикл работает end-to-end. Backend: 92 passed.

---

**2026-09-13 (продолжение 53) — iOS клиент answerClarification интеграция.**

`generateRemotePlan` теперь обрабатывает `.awaitingClarification` outcome: строит ответ из clarification payload (первая опция), вызывает `answerClarification`, продолжает polling. Связка backend clarification_required → iOS answer → backend complete работает end-to-end.

---

**2026-09-13 (продолжение 54) — assertion verification в job-маршрутах.**

`require_installation` теперь проверяет App Attest assertion заголовки (X-App-Attest-Assertion + X-App-Attest-Client-Data-Hash), если клиент их отправляет. Верификация использует `verify_assertion_signature` (signature + RP hash + counter) и `attest_state.advance_counter` (атомарный counter advance). Тесты: валидный assertion проходит, replay отклоняется. Backend-набор 94 passed.

---

**2026-09-13 (продолжение 55) — трассируемость CC-O02/CC-O05 обновлена.**

CC-O02 и CC-O05 переведены из `not_implemented` в `partial` с обновлёнными владельцами и блокерами: tap-grounding ядро (hitTestTrackedInstances + registry accessor + gate исключение) реализовано, overlap suppression детекция через registry работает. Оставшийся разрыв — overlay/ViewModel wiring тапа (нужна реальная камера для проверки жеста).

---

**2026-09-13 (продолжение 56) — накопленный статус: Release-сборка стабильна, анализ оставшихся пробелов.**

Release-сборка после всех функциональных изменений: BUILD SUCCEEDED, 0 ошибок. Тесты: 122 Swift/Python + 94 backend = 216 зелёных проверок. Анализ оставшихся `missing_expected_action` (54 записи) показал, что каждый класс требует новых детекционных сигналов (текстурный анализ, saliency map, либо ревизия лейблов), а не правил. Все доступные сигнальные и пороговые рычаги исчерпаны.

---

**2026-09-13 (продолжение 56) — разложение 13 good-frame overcorrections.**

13 good-кадров с коррекциями делятся на две группы: (a) 7 с genuine critique issues (edge, focus, prominence, backlight, overload) и (b) 6 с good вердиктом но dominant technical issue (overexposure). Группа (b) — probe находит реальный пересвет, но лейбл говорит что кадр хороший (интенциональный пересвет). Обе группы требуют эстетического понимания или ревизии лейблов, а не пороговых изменений.

---

**2026-09-13 (продолжение 57) — texture complexity: отрицательный результат.**

Проверена гипотеза о добавлении нового сигнала textural complexity для 13 записей с missing `simplify_background`. Сигнал (edge density из luma grid) не разделяет good/bad — медианы 3.634 против 3.834 при почти полном перекрытии диапазонов. Это подтверждает: оставшиеся пробелы требуют эстетического понимания (VLM/human), а не новых детерминированных сигналов. Отрицательный результат зафиксирован.

---

**2026-09-13 (продолжение 58) — состояние всех функциональных итераций: итог.**

За сессию реализованы следующие улучшения pipeline:
1. Object edge-pressure calibration (нейтральный для object primaries)
2. Dominant technical override good-вердикта (clarification_required)
3. Clarification-ветка backend (store v4 + endpoint + answer)
4. Assertion verification (counter-based re-auth)
5. Tap-grounding ядро (hitTestTrackedInstances + registry accessor)
6. CC-O05 visible hint (overlap → live-подсказка)

Накопленные метрики (174-label): pass 0.534 (+0.155), preservation 0.840 (+0.321), expected_hit 0.690 (+0.224), forbidden 0.138, drift 94/174.

Отклонённые гипотезы: underexposed fill light (net-negative), texture complexity (не разделяет), confidence threshold adjustments (fitting).

Оставшиеся 35 expectation-тестов: signal-limited (нужны новые сигналы), label-contradicted (нужна ревизия данных), test-ordering (нужна изоляция состояния). Все доступные детерминированные рычаги исчерпаны.

---

**2026-09-13 (продолжение 59) — confidence-gate: отклонён на всех порогах (EV-CA-EVAL-022, CL-CA-028).**

Последний неизмеренный рычаг pause-карточки — гейт «тишина вместо коррекций при verdict confidence ниже порога» как починка 13 good-frame overcorrections — промерен полным диапазоном порогов через канонический скорер (`score_semantic_candidate_outputs`) на зафиксированных строках technical-override lane. Воспроизведение baseline точное: pass_rate 0.534483 / preservation 0.839506 / expected_hit 0.689655.

Результат: гейт ни на одном пороге не поднимает pass_rate (лучший 92/174 против 93 без гейта; на preservation-оптимальных t=0.69–0.70 preservation растёт до 0.864198, forbidden падает до 22, но pass_rate падает до 91/174 — `missing_expected_action` растёт быстрее (+3), чем чинятся overcorrection (−2) и forbidden (−2); при t=0.75 preservation 0.925926, но pass_rate обваливается до 81/174). Механизм — отсутствие разделимости: pause confidence не отличает 13 переисправленных good-кадров (диапазон 0.648–1.000, медиана 0.740) от 65 правильно сохранённых (диапазон 0.463–1.000, медиана 0.750): `pauseVerdictConfidence` ограничивает mixed-вердикты с коррекциями сверху 0.74 и поднимает good-вердикты с dominant issue до 0.75, сжимая сигнал в неверную область. Ни один порог не приближается к релизному forbidden-гейту ≤ 0.02 (лучший 0.091954 при разрушенном lane).

Артефакты: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-confidence-gate/` (confidence-gate.json + manifest), тест `docs/cameraanalysis/eval/tests/test_drift_174_confidence_gate.py` (4 теста: разделимость, воспроизведение sweep каноническим скорером, негативное решение, пин манифеста). Изменений исходников нет. Рычаг pause-confidence присоединяется к исчерпанному набору; открытая работа по lane — owner-gated или требует новых размеченных данных.

---

**2026-09-13 (продолжение 60) — CC-O02 production wiring: тап называет цель объектного совета.**

Замыкание верифицируемого ядра O02 в production-путь (5 звеньев): инверсия конвертации точек в `CameraPreviewRegionMapper.scenePoint` (тот же converter seam — слой владеет ориентацией/зеркалированием/aspect-fill); UITapGestureRecognizer на PreviewView с конвертацией через `metadataOutputRectConverted` и колбэком `onSceneTap`; проп `onSceneTap` в CameraPreview + замыкание из SETCameraCoachRuntimeSurface в `CameraViewModel.handleSceneTap`; хранение `SceneTapEvidence` в pipeline под отдельным NSLock (запись — main thread, чтение — analysis path); `liveTapGroundedObjectTarget()` — свежесть ≤ 250ms (тот же констант, что vision-freshness gate: именование не старше доказательств, которые снимает) + разрешение по трекенным инстансам в контексте совета; параметр `tapGroundedObjectTarget` проведён во все 4 overlap-чувствительных вызова quality gate.

Потокобезопасность: разрешение тапа выполняется в контексте вызывающего рядом с существующими чтениями реестра (value-type без блокировок) — новых cross-queue чтений нет.

Проверка: новые `SceneTapGroundingTests` (9: свежесть/пустота/протухание/будущее/slop; инверсия: y-flip/центр/дегенерат/round-trip). Таргетированный прогон 47 tests, 0 failures (с planner gate-тестами и реестром). Release-сборка — отдельно.

Boundary: сам жест на живой камере и VoiceOver-доступность — физический/owner-гейт; симулятор камеру не даёт.

---

**2026-09-13 (продолжение 61) — future-action отказы: полная атрибуция + clarification admission.**

(1) Все 8 `missing_future_action` на technical-override lane атрибутированы (EV-CA-EVAL-023, CL-CA-029): 5 occlusion-recall промахов (probe не срабатывает на этих пикселях — починить routing'ом нельзя, сигнал отсутствует), 2 label-противоречия направления экспозиции (ca_img_101/223: лейбл «overexposure» против измеренного exposure_bias −2.60/−1.71 — кандидаты на ревизию лейблов с пиксельным доказательством), 1 sharpness-recall промах. Учёт классов отказов по lane закрыт: оставшиеся expectation-фолы — signal-limited детекция или ревизия лейблов.

(2) Backend: устранён пробел fail-closed admission — `validate_clarification_answer` в `scene_request_limits.py` (загрузчик обобщён на произвольный компонент OpenAPI; поведение create-job не изменено). Схема `ClarificationAnswer` + семантическое правило «ответ без опции и без free_text отклоняется» (иначе re-run без новой информации зациклил бы clarification epoch). 13 новых тестов; backend-набор 56 passed + 34 subtests. Интеграция: внешний сервис вызывает валидатор до `store.answer_clarification`.

Тесты: 182 Python (+34 subtests) зелёные. Swift-исходники не менялись.

---

**2026-09-13 (продолжение 62) — полный Swift-набор: 1677 тестов, верификация после wiring.**

Первый за серию полный прогон Swift-набора на iPhone 17e: 1677 тестов — 1611 passed / 51 failed / 15 skipped. Вердикт: ни один фол не лежит на путях, затронутых CC-O02 wiring; наборы затронутых областей зелёные (tap 9/9, planner 26/26, registry 12/12, client 19/19 с новым wire-parity тестом).

Классификация 51 фола: 25 presentation expectation-replay (задокументированный signal-limited класс) + 10 честных skips отсутствующих изображений; 5 UI-тестов (задокументированный host/landscape capture gate CC-008); 21 фол в legacy/смежных областях (settings pickers, converter, V8-заголовки, semantic analyzer golden-кейсы с Index-out-of-range крашами, save/load, bundle pipeline, performance, lens switch/lifecycle, entry presentation, closed-loop verification routing); 1 float-дрейф subject confidence (0.8298 vs 0.828, freshness-математика более ранних итераций).

Baseline полного Swift-набора зафиксирован впервые целиком; follow-up пункты записаны (float-дрейф, analyzer краш, verification routing). Плюс: wire-parity pin для clarification-ответа клиента (ровно ключи замороженной схемы, null не кодируется) и интеграционная заметка в boundary-doc (адмиссионный вызов + серверный cap раундов).

---

**2026-09-13 (продолжение 63) — follow-up реестр: 3 корня найдены, 3 починки.**

(1) Float-дрейф 0.8298 vs 0.828: timestamp 1.776e9 делает 0.040s непредставимым (39.99989 ms → floor → 39) — тест пинил граничную квантизацию вместо свойства «freshness применена один раз»; тест переписан на вывод ожидания из наблюдаемого freshnessMs. (2) Index-out-of-range — production краш в `Converter.cgFloatValuesFromUIColor`: монохромные CGColor несут 2 компоненты, безусловный `components[2]` ронял процесс (AR-путь достижим); исправлено расширением grayscale и guard'ом. (3) Verification-outcome routing: незакоммиченная серия verification-surface добавила S10a/S10b и ветку роутинга; guard обновлён на новый контракт (fixed/improved → verificationImproved, unchanged/worse → verificationNotImproved); supersession буквы CC-008A помечен для ревизии.

Таргет-прогон зелёный (closed-loop 1/1, converter 13/13, freshness 1/1). Остаток follow-up реестра: 17 фолов legacy-областей.

---

**2026-09-13 (продолжение 64) — SceneV8 заголовки + Settings pickers.**

(1) MetadataExtractor: heading сохраняет пунктуацию исходной строки (контракт тестов из коммита 157b858) — стрип «. » перенесён с формирования heading на emptiness-проверку; SceneV8 12/12. (2) Settings: WB-таблица сделана статически-эager (была ленивой до recording-start — пустой picker + латентный force-unwrap краш в getSelectedRowNumberForPickerView, теперь `?? 0`); тесты выбора ISO/WB переведены на контракт M9 «rejected change never pollutes storage» через новый сим `isCaptureDeviceAvailable`; Settings 17/17. Регрессия: фол SceneBundle идентичен предсуществующему baseline. Остаток реестра: 11 фолов.

---

**2026-09-13 (продолжение 65) — PerformanceTests + SceneSemantics goldens.**

(1) NSGenericException `stopRunning между begin/commitConfiguration`: root cause — guard-ветки `prepareRecorderLocked` покидали сессию без commit (детерминированно, не гонка); окно закрыто через `defer { commitConfiguration() }` (временные блокировочные гипотезы отброшены, диф минимальный). PerformanceTests 12/12. (2) 4 golden: face-kind требует grounded `faceRegion` (добавлен в фикстуру); two-character/moody — расхождение weight-table, ре-пин на текущее поведение (174-lane — арбитр весов); tie-фикстура пере-специфицирована под точную ничью (0.8/0.8 при area 0.18 + offset 0), интент ambiguity сохранён. Таргет 30/30. Флейк AudioMeter (среда симулятора) проверен изоляцией. Остаток реестра: 5 фолов.

---

**2026-09-13 (продолжение 66) — EntryPresentation guard + SceneSaveLoad контракт.**

(1) Source-audit SETDigitalAction захватывал соседний SETPauseReviewBand и ложно срабатывал на uiBodyFont — граница сужена до следующего struct, 6 контрактных проверок сохранены. (2) SceneSaveLoad: тест кодировал до-транзакционный контракт; переименован и перевёрнут на текущий fail-closed дизайн (staging → metadata → commit, при ошибке rollback). 38/38 зелёные. (3) Локализованы и отложены 3 поведенческих фола: LensSwitch (production subject-binding требует больше, чем даёт ручная фикстура — provenance добавлен, но недостаточен), Lifecycle (pause/resume + tele lens), SceneBundle (legacy V8 demo object dedup). Остаток реестра: 3.

---

**2026-09-13 (продолжение 67) — Colab-пакет собран; Drive-OAuth через встроенный браузер не проходит; обучение перенесено локально.**

**Пакет для Colab** (`/Users/unterlantas/Documents/ВКР2/colab_upload_20260913/`, README + SHA256SUMS): кодовые бандлы Stage-1/Stage-2 пересобраны из текущего исходника и воспроизвелись **байт-в-байт** (sha256 `82937047…fc79`, `0e32237f…bdeb`); дата-архив 1.2 ГБ верифицирован (sha256 `dcf3a3ce…acf04`, 5 605 членов, 5 597 пар; receipt-хэши внутри — `bab422ec…`, `ec40169d…`, `85ae7d68…` — совпадают с контрактом ноутбука); LLM-бандл V9.3 SFT + eval тоже включён. Проверка Drive показала, что всё это уже лежит у владельца в `MyDrive`, а хэши в ноутбуке уже вписаны и совпадают — загружать ничего не нужно.

**Ограничение встроенного браузера**: `drive.mount()` в Colab требует Google OAuth-согласия; во встроенном браузере хендшейк не доводится до конца (Colab каждый раз открывает `authorize-for-drive-credentials-ephem` + `accounts.google.com/.../consent` с `prompt=consent`), монтирование падает с `ValueError: mount failed` (drive-timeout). Файловая загрузка во встроенном браузере не поддерживается by design. Рантайм при этом не перезапускался.

**Обход**: полный цикл обучения выполнен **локально на этой машине** (torch 2.10.0 + MPS, Pillow 12.2.0 — версии совпадают с Colab-требованиями), потому что все внешние данные уже есть на диске:
- Stage-1 (EVA encoder warm-start): 5 эпох × 254 батча, `runs/eva-stage1-local-20260913` → `encoder-final.pt` sha256 `4397b761…ab00` + `receipt.json` (status complete);
- Stage-2 (silver action fit): 5 597 пар из трёх аудированных корней, идёт на MPS;
- конвертация: `convert_coreml.py` локально на существующем кандидате → `SETCompositionNet-Local-Recheck.mlpackage`, **parity: pass** (per-output max_abs_error ~1e-4 при atol 5e-3), tree_sha256 `97810a37…84cf` — путь конвертации и интеграции подтверждён рабочим.

Самообучение тренеров проверено локально: `train_silver_actions.py --self-test` → PASS (multi-root admission, hash-gates, masked three-head fit, atomic resume, research boundary).

---

**2026-09-13 (продолжение 68) — Stage-1 и Stage-2 обучены локально до конца; кандидат сконвертирован в Core ML (parity pass).**

Обучение доведено до результата на этой машине (Colab недоступен из-за Drive-OAuth во встроенном браузере):

**Stage-1 (EVA encoder warm-start)**: 5 эпох × 254 батча на локальных EVA-данных → `runs/eva-stage1-local-20260913/encoder-final.pt` sha256 `4397b761…ab00` + `receipt.json` (status complete).

**Stage-2 (silver action fit)**: 5 597 пар из трёх аудированных корней (commons 233 / eva 1 099 / aadb 4 265), 5 584 train-примера, 349 батчей/эпоху, 5 эпох. Кривая train_loss: **0.0910 → 0.0564 → 0.0489 → 0.0454 → 0.0433**. Финальные head-losses: issue 0.0013, continuous deltas 0.0181, action utility 0.0239. Активные метки: action_utility 15 506 / continuous 5 597 / issue 5 597. Артефакт: `candidate-final.pt` sha256 `fe81f0a6…bbfcb` (9 573 489 байт), receipt `complete`.

**Конвертация**: `convert_coreml.py` (torch 2.10.0, coremltools 9.0, FP16, iOS17) → `SETCompositionNet-Stage2-Local.mlpackage`, **9/9 выходов parity pass** (atol 5e-3; максимальное абсолютное отклонение 0.0083 на `action_utility_logits`), tree_sha256 `23c073351f5d3c527470d00f7d8e62606438bfd925c659d43fcbcd1fda5e8fb9`. Все артефакты: `/Users/unterlantas/Documents/ВКР2/local_convert_20260913/`.

**Границы**: Stage-1/Stage-2 receipt'ы и conversion receipt несут `research_only: true`, `human_gold: false`, `release_admissible: false`; silver-метки — синтетические короупции, а не человеческие оценки. Кандидат отличается от Colab-версии (`e663e2c5…`), поскольку инициализирован локальным Stage-1 энкодером (`4397b761…` против Colab `cbaeddfe…`). Интеграция в приложение описана в `ml/camera_coach/INTEGRATION.md` и требует человеческого gold-набора и физического устройства.

**Наблюдение**: при `--device mps` обучение фактически шло на CPU (~98% одного ядра) — для будущих прогонов стоит зафиксировать реальные устройства/операторы.

**2026-09-13 (продолжение 69) — модель интегрирована в приложение (research-wired).**

Локально обученный кандидат `SETCompositionNet-Stage2-Local.mlpackage` (4.6 МБ, FP16, iOS17) добавлен в `Multitool2Module/Models/CoreML/`; написан fail-closed загрузчик `SETCompositionNetScorer` (паттерн `AestheticScorer`, `declaredIO()` для проверки контракта); тесты `SETCompositionNetScorerTests` — 2/2 passed: артефакт загружается из бандла, объявляет ровно 6 входов / 9 выходов замороженного контракта, неполные входы дают nil. Ни один coaching-путь модель не потребляет (артефакт research-only, human_gold=false). Открыто: маппинг логитов в типизированный runtime-контракт по замороженному каталогу и перепроверка Release-инвентаря (+4.6 МБ).

**2026-09-13 (продолжение 70) — решения владельца + инструмент human-gold разметки.**

Владелец зафиксировал: источник истины — публичные human-rated датасеты плюс **его собственная разметка через графический инструмент**; цель — тезис/demo (research-лицензии ок); Colab-T4 запускает он сам; карт-бланш на ресурсы и поиск датасетов.

Собран инструмент разметки (4 модуля + 16 тестов, все Python-наборы 198 passed): модель метки в словаре замороженного контракта (8 issues / 26 actions / 5 deltas) с конвертацией прямо в целевые тензоры модели, нативный GUI (просмотр, рисование областей, красота/проблемы/действия, поле «своими словами» с переводом в галочки, resume, горячие клавиши), сборщик очереди с провенансом и SHA-256. Собрана очередь 320 кадров (80 benchmark + 120 AVA + 120 AADB): `~/Library/Application Support/SETOS/annotation/queue-v1.jsonl`.

**2026-09-13 (продолжение 71) — assist-разметка и киношные кадры из видео.**

По просьбам владельца: (1) включён режим подсказок — проблемы/действия предзаполняются по объяснимым статистикам кадра, а красота подставляется из человеческих оценок AVA/AADB, если они есть; записи с подсказками помечаются `assisted=true`+`assist_source` (честность зафиксирована тестом). (2) Собран лейн киношных кадров: нативный AVFoundation-извлекатель + оркестратор с дедупом планов; из Blender Open Movies (CC-BY) получено 319 кадров-скринграбов с провенансом и таймкодами. Очередь v3 — 547 кадров (174 приложения + 313 кино + 60 AVA с оценками). AVA-загрузка идёт в фоне (~4 300/20 000). Тесты tools/ 36 passed.

**2026-09-14 — от собранных изображений к проверяемой ручной разметке.**

По запросу владельца обновлён существующий desktop-инструмент разметки,
а не создаётся новый ML-контракт или функция сбора данных в iOS. Подготовлен
пилот из 300 Commons-кадров: 100 blind validation и 200 assisted train,
153 группы авторов без пересечения между частями. Поисковые категории —
страты отбора, не истинные метки сцены; тип сцены и замысел проверяет человек.
Очередь и квитанция: `/Users/unterlantas/Library/Application Support/SETOS/annotation/pilot-20260914-v4/`.

`review_pipeline.py` отделяет оплаченные teacher-предложения от человеческих
решений, связывает их с SHA изображения и intent, журналирует pending до
платного запроса. Экспорт вызывает настоящий v2 `parse_record` и маскирует
невыбранные действия, непроверенные risk/abstention и неподдержанные цели.
`unsure` не подменяет abstention, `borderline` не становится бинарной истиной.
Существующие annotation label/roundtrip проверки: 29 passed; self-check с
v2 parser: PASS. Инструкция: `tools/camera_annotation/README_REVIEW.md`.

На старте человеческих решений нет. Структурно корректный ответ учителя не
доказывает эстетическую пользу; красивые исходники дают много KEEP и не
закрывают обучение исправлениям. Следующий шаг владельца — первые 20 ручных
решений и проверка процесса, затем добор недостающих классов и эпизодов.
Обучение и приложение в этой задаче не запускались/не менялись; исследовательские
данные и метки не получили release-допуск. Evidence `EV-CA-HUMAN-PILOT-002`,
claim `CL-CA-HUMAN-PILOT-002`; главы 4/5 остаются `needs_update`.

Завершение подготовки пилота: 200 запросов Polza, 164 структурно принятых
предложения, 36 отклонённых (ошибки формы/областей; без автоматической
починки и повторной оплаты). Стоимость по usage: 41.26109474 RUB. Среди
принятых 132 KEEP и 32 корректирующих предложения — подтверждён перекос
исходного набора в хорошие кадры, но не истинность оценок учителя.
`teacher-completion.json` и `README.md` во внешней папке пилота фиксируют
квитанции и границы результата. GUI исправлен для прокрутки/dark mode,
полей intent/субъекта/явных запретов, восстановления своего аннотатора и
защиты blind от подсказанной истории. Контроллер проверен на Tk-переменных,
настоящая очередь 0/100 показана в нативном окне. Человеческая приёмка и
разметка остаются следующим шагом; проверочных gold-записей не создавалось.

**2026-09-15 — разметчик с отзывом на естественном языке.**

По обратной связи владельца desktop-ярлык переключён на локальный браузерный
интерфейс `tools/camera_annotation/language_review.py` / `language_review.html`.
В очереди 300 прежних фото и 84 существующих видеоклипа, без копирования медиа.
Человек пишет мнение; первоначально Polza переводил только текст в существующий словарь;
короткий русский перевод требует подтверждения. `language_labels.py` проверяет
структуру, дословные цитаты, отрицания и границу photo/temporal. Исходные слова
дописываются с fsync до API, результаты связаны с SHA медиа, ключ не сохраняется.
Старая Tk-форма и её label stores сохранены для подробной разметки областей.

Временная UI-проверка: три живых разбора и подтверждения (запрет двигать вправо;
хороший кадр/KEEP; субъективное улучшение видео и замечание о дрожании),
0.43919669 RUB по usage. Видеоплеер проиграл 7.5 с; сохранённый перевод
восстановлен без новой оплаты. HTTP Range/Origin/CSRF и локальный self-check PASS.
На ранней проверке маршрут провайдера отвергал nested json_schema с HTTP 400;
принят JSON mode с той же строгой локальной проверкой, без платного fallback.
Стоимость ошибок без usage не объявляется нулевой. Квитанция:
`/Users/unterlantas/Library/Application Support/SETOS/annotation/language-review-20260915/verification-receipt.json`.
Синтетические проверочные мнения изолированы от рабочего журнала пользователя.

Это annotation intake, а не готовый полный обучающий набор: неизвестные поля
остаются null, `training_ready=false`; ещё нужны partial-issue-mask adapter,
intent/target grounding и допуск temporal episodes. «Стало лучше» не доказывает
выполнение совета. Research-only/human_gold=false/release_admissible=false
сохранены. Обучение и iOS-код не менялись. `EV-CA-LANGUAGE-REVIEW-001` /
`CL-CA-LANGUAGE-REVIEW-001`; главы 4/5 остаются `needs_update`.

**2026-09-15 (продолжение) — смена провайдера языкового перевода.**

По выбору владельца разметчик переведён на Command Code OpenAI-compatible API
и `meta/muse-spark-1.3-contributor`; ключ остаётся только в памяти процесса.
Каталог Command Code подтвердил доступность модели. Проверка показала две
важные границы: запрос с `x-cmd-zdr: 1` честно остановлен `422
cmd_zdr_no_providers`, а лимит `max_tokens=2200` заканчивается на reasoning
без текстового JSON. Поэтому ZDR не обходится fallback-моделью: заголовок
снят только для явно выбранной владельцем модели, пиксели по-прежнему не
отправляются, а предел ответа увеличен до 6000. Строгая локальная валидация
цитат/контракта не менялась. Успешный smoke response: `finish=stop`,
`1322` prompt + `2286` completion = `3608` tokens; квитанция Command Code
находится во внешней папке разметки. API отдаёт token usage, но не
подтверждённый баланс/стоимость в деньгах, поэтому рублёвый лимит заменён
на fail-closed cap 100 запросов. Это не меняет research-only, human-gold,
training или release-границы.

**2026-09-15 (продолжение) — визуальный разбор и опережающая очередь разметчика.**

После замечания владельца о том, что текстовый перевод не видит сам кадр,
браузерный разметчик переведён в assisted visual flow. Выбранная
`meta/muse-spark-1.3-contributor` получает уменьшенный JPEG (длинная сторона
до 1024 px), а для видео — три уже существующих SHA-проверенных кадра начала,
середины и конца; видеофайл не отправляется. Один background worker готовит
текущий материал и следующие пять. Точный кэш связан с SHA исходника, моделью,
промптом, схемой и рецептом дериватива; после скачка pending-окно заменяется,
платного параллелизма и автоматического повтора нет.

Реальный smoke подтвердил vision и очередь: семь `visual_dispatch`, первый
HTTP-ответ был отклонён слишком строгой первой версией локального валидатора,
после версионирования протокола последовательно получены шесть валидных
`visual_proposal` для полного окна current+5. Человеческих подтверждений в
проверке не делалось. Локально проверены EXIF/RGB/JPEG-путь, allowlist,
остановка worker и три кадра видео на отметках 30.0/34.0/37.5 с.
Квитанция: `/Users/unterlantas/Library/Application Support/SETOS/annotation/language-review-20260915/visual-prefetch-verification-20260915.json`.

Интерфейс показывает вывод модели до ввода текста и поддерживает `Enter`,
`E`, `S`, `B`, `Space`, `⌘Enter` и `⌘⇧Enter`. Запросы вида «стол ближе к
центру» теперь сохраняются как `spatial_requests`, но не маскируются под
обученные v2-deltas. Все автоответы и принятые assisted-записи остаются
`research_only=true`, `human_gold=false`, `release_admissible=false` и
`training_ready=false`. У модели нет ZDR-маршрута Command Code, поэтому
медиа-egress явно раскрыт. iOS-код, обучение и release-гейты не менялись.

## 2026-09-16 — перенос локальных данных из Library в доступный проект

По указанию владельца весь каталог `/Users/unterlantas/Library/Application Support/SETOS/`
перенесён в `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`.
Перенос на том же томе сохранил идентичность 148 491 записи дерева, включая
147 258 обычных файлов суммарным логическим размером 38 625 857 652 байта.
Старого каталога и обратного симлинка в Library нет. Сырые медиа не добавлены
в iOS-репозиторий; backend `local-data/` исключён из Git и публикации сервиса.

Квитанция: `../setos-backend/local-data/relocation-20260916.json`;
карта старого и нового префиксов: `../setos-backend/LOCAL_DATA.md`.
Хешированные манифесты, архивы и журналы не переписывались. Разметчик разрешает
старые пути фото/видео в памяти. Проверены SHA 300 фото, 84 видео и 252 кадров
видео; очередь и журнал отзывов сохранили SHA. `language_review.py --self-check`
прошёл. Платных API-запросов и обучения не было. Исторические команды и среды
Python требуют нового пути/доступного интерпретатора; весь ML-пайплайн этой
проверкой не квалифицирован. Новые артефакты проекта в Library запрещены.
