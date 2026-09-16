# Стартовый промпт для следующей модели

Скопируй текст ниже в новую задачу ИИ. Лучше открыть задачу непосредственно в локальном проекте `/Users/unterlantas/Documents/XCode/shafinMultitool`. Если другая модель работает на другом компьютере, ей понадобятся сами рабочие файлы приложения, внешний backend и допустимые данные/артефакты: один текст промпта не передаёт файловую систему.

---

Ты продолжаешь разработку SET OS / Shafin Multitool. Не начинай проект заново и не ограничивай задачу написанием очередного плана. Реализуй существующий полный пакет до квалифицированного приложения для App Store: iOS-клиент, один сервер, Camera Coach для фото и видео, Scene/media workflows, UI и анимации, поиск данных, обучение/калибровка модели, проверки качества и выпуск.

Я хочу максимально автономную работу большими содержательными блоками. Используй доступные браузер, Safari, Google, Colab, API, CLI и computer use для работы в рамках проекта. Не перекладывай на меня обычные загрузки/скачивания/настройки, которые можешь безопасно сделать сам. Простые хорошо описанные технические пакеты делегируй сабагенту gpt-5.6-luna с reasoning max, если он доступен. Не притворяйся, что есть инструменты, которых в твоей среде нет. Не создавай отдельные пользовательские задачи вместо сабагентов без просьбы.

## Обязательная исходная ориентация

Прочитай полностью:
1. `/Users/unterlantas/Documents/XCode/shafinMultitool/AGENTS.md`.
2. `/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/HANDOVER-2026-09-11-FULL-DELIVERY.md`.

Затем по маршруту handover прочитай master plan, актуальный EXECUTION_STATE, доменные Camera contracts, ML evidence и серверную границу. Не останавливайся после двух файлов и не выбирай старое pending-состояние вместо более нового final disposition.

Канонический master:
`/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md`.

§24 — полный delivery plan R00–R26, который дополняет, а не отменяет исходные §1–23 и M-gates. Не создавай новый конкурирующий master.

Текущий tracker:
`/Users/unterlantas/Documents/XCode/shafinMultitool/docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/EXECUTION_STATE.md`.

Внешний backend:
`/Users/unterlantas/Documents/XCode/setos-backend`.
Он не является Git-репозиторием и не отображается в git diff приложения. Не забудь прочитать и сохранить его.

После чтения выполни read-only проверку HEAD/status, нужных файлов и активных исполнителей. Последний HEAD на handover:
`0733df2cb83c8e3687c31251e11e5d0747052602`, ветка store.
В приложении много намеренных dirty/untracked файлов. Не стирать, не откатывать и не перезаписывать их старой версией.

## Продуктовая цель — не просто классификатор

Пользователь снимает красивое фото/видео. Приложение должно распознать конкретные объекты и сцену, учитывать намерение, выбрать полезное безопасное действие и показать его понятно.

Пример: две похожие лампы. Нужно выбрать правильную лампу, показать правильную область и согласованное направление. Название lamp не заменяет identity. Нельзя по одному виду лампы утверждать, что её безопасно двигать. Нельзя спутать движение телефона и предмета. Движение другой лампы или движение выбранной в обратную сторону не должно приводить к «стало лучше». При смене сцены, потере identity и несопоставимости нужен честный incomparable/reselect/abstain. Уже хороший кадр должен сохраняться.

Для полного результата нужны:
- корректное восприятие scene/object/region;
- устойчивые локальные идентичности;
- типизированная evidence и action prerequisites;
- один существующий локальный planner/safety gate;
- стабильный UI принятого эпизода;
- честный verifier;
- реальное capture/save/playback/export;
- доказанная полезность на независимых случаях, а не только валидный JSON.

Все 68 case IDs перечислены в requirements §23 и разобраны в handover. Не заменяй их одним demo с интерьером.

## Что уже сделано — не повторять с нуля

1. Собраны 15 301 исходное изображение с Vision geometry и 5 597 paired-corruption примеров. Всё research_only=true, human_gold=false, release_admissible=false.
2. Stage 1 и Stage 2 в Colab завершены. Stage 2 обучает только issue_logits, action_utility_logits, continuous_target_deltas. Остальные головы не квалифицированы.
3. Research FP16 Core ML экспорт уже сделан; все канонические входы/выходы есть; один CPU parity case пройден. Это не production admission.
4. Проведено 140 платных VLM ответов по ограниченным публичным картинкам; стоимость 95.20637306 RUB. Это не независимый human-gold benchmark и не выбранный production provider.
5. В Camera pipeline реализованы bounded selected-identity/source-geometry/stale/generation guards и работа принятого эпизода/UI; последняя выборка 27/27 на iPhone 17e. Это не доказательство работы всех реальных сцен.
6. В локальном сервере есть transactional quota, timeout/retention/ownership/lifecycle. Но require_installation по-прежнему возвращает 401.
7. Готовы отдельные App Attest certificate и assertion-signature primitives, 19/19 targeted checks, service 26/26. Полной авторизации ещё нет.
8. Receipt runtime НЕ реализован: при handover app_attest_receipts.py/test_app_attest_receipts.py отсутствовали. Есть root/fixture, native research и подробная спецификация в handover §11.3. Старый исполнитель остановлен.

Наличие исходника, tensor, enum, документа или теста не означает готовность продукта. Проверяй только фактически доказанные свойства.

## Как продолжать

Сначала сравни текущие файлы с handover. Если receipt worker всё-таки записал что-то позже, прочитай это и выясни статус; не перезаписывай автоматически.

Рекомендуемый ближайший серверный путь:
1. Закончить bounded receipt validation по сохранённой спецификации.
2. Квалифицировать полный authenticator profile; не вводить слабый legacy fallback из-за противоречивых публичных примеров.
3. Реализовать trusted challenge, app/environment binding, atomic replay/counter state, installation identity и tokens.
4. Добавить настоящий iOS App Attest client/capability по фактическому signing/provisioning.
5. Проверить positive/negative device roundtrip.
6. Встроить один provider с денежным reserve/reconcile, retention, ownership и строгой output validation.
7. Довести результат до реального SceneBundlePipeline.

Критическая ловушка: product path parseAsyncForGeneration → parseBundleAsync → SceneBundlePipeline и default v9Full не равны legacy SceneParseCoordinator. configureRemoteOffload в legacy ещё не означает, что production UI использует сервер. Не переключать на legacy, чтобы создать видимость интеграции.

Параллельно, если независимая работа не конфликтует по файлам, продолжай Camera R03/R04/R06/R05, data acquisition/annotation preparation и UI/media. Не застревай в одном crypto-компоненте, если есть полезный разрешённый следующий пакет. Но безопасность не сокращай ради скорости.

## Обучение и данные

Не пытайся обучить огромную VLM с нуля. Используй qualified external VLM для семантических предложений, существующее локальное восприятие и доменный контроль; полный on-device model trainer доводи по текущему контракту.

Поиск данных и подготовка workflow — твоя работа. Проверяй права на pixels, labels и pretrained weights отдельно. Boxes не дают safety/action labels. Research lineage нельзя автоматически сделать коммерческим.

Нужны family-aware train/dev/calibration/sealed-test splits, независимые human labels, annotation pilot, полный masked trainer, воспроизводимый smoke/resume, несколько фиксированных seeds, validation selection, отдельная calibration, locked evaluation, Core ML parity и physical admission. Не подменяй неизвестные risk/good/abstain targets нулями.

Колабом можно управлять через доступный браузер. Уже завершённые Stage 1/2 не перезапускать. Большой ZIP читать с Drive, не files.upload. Новый эксперимент — новый run ID, hashes/receipt/metrics/checkpoints и бюджет. При CalledProcessError искать внутренний FAIL/traceback; не гадать. Не обходить Colab quotas.

## Главная проверка: правильно ли распознаёт и помогает

До tuning зафиксируй корпус, splits, метрики, denominator, minimum support и thresholds. Проверяй отдельно:
- scene classification и OOD;
- localization/IoU;
- конкретный target и identity continuity;
- problem/action correctness;
- безопасность и protected targets;
- текст/overlay/direction/frame consistency;
- verifier wrong-object/wrong-direction/scenecut false success;
- полезные положительные случаи и abstention coverage;
- human before/after preference;
- latency, thermal, memory и стоимость.

Нужны реальные последовательности: нужный предмет движется правильно; другой предмет; обратное направление; оба стоят; движется камера; перекрытие; похожие предметы пересекаются; зеркало; смена сцены/линзы/ориентации; stale cloud result; хороший и стилевой кадр. Always-abstain не считается качеством.

Сохраняй master gates: expected-action ≥0.90, forbidden ≤0.02, good-frame preservation ≥0.95, critical forbidden=0, false improved ≤0.02, wrong-direction false success=0. Дополнительные proposed IoU/assignment thresholds из handover ещё требуют утверждения, не объявляй их достигнутыми.

ИИ-разметка — не human-gold. Нужных людей не выдумывай. Сам подготовь инструменты/инструкции/выборку/отчёты и запроси только действительно необходимое человеческое участие.

## Ограничения полномочий

Автономия не разрешает:
- commit/push/PR/reset/stash/broad clean без отдельной просьбы;
- удаление dirty/untracked, datasets, checkpoints и evidence;
- хранение секретов в Git/логах/промпте;
- поднятие лимита API, новые расходы/подписки/платный GPU без согласованного бюджета;
- обход 2FA/CAPTCHA/квот/TLS/auth/schema;
- production Camera egress без согласованного consent/privacy scope;
- автоматическую публикацию/юридические действия/Store submission без нужного owner GO;
- объявление research модели production-ready.

Старый Polza ключ в переписке не переносить. Запрашивать новый безопасный secret только когда он действительно нужен. Исторический остаток денег не текущий баланс.

Разрешённый simulator — iPhone 17e, UDID 1F680A42-CEB3-43E8-9CED-52F874962A62. Не использовать iPhone 17 Pro. Физический iPhone 13 Pro ранее был доступен; доступность перечитать. Не подменять physical gates simulator screenshots.

Если недостаёт signing/hosting/human labels/budget/owner decision — найди ответ в документах, затем задай один точный вопрос и продолжай независимую работу. Не требуй моего «давай дальше» после каждой маленькой функции.

## Рабочая дисциплина и итог

Для каждой задачи сначала найди существующего владельца и похожий паттерн. Не плодить второй planner/server/contract/runtime. Делегируй конкретные файлы, укажи ограничения и предупреди о чужих изменениях. Parent проверяет integrated result.

Проверки минимальны и относятся к изменённому пути. Для docs не нужен simulator; для crypto/деньги/identity нужен соответствующий runnable check и независимое review. Не запускать всё ради красивого отчёта и не скрывать failed/skipped cases.

Обновляй существующий EXECUTION_STATE, evidence и diploma; thesis artifacts по AGENTS/thesis-workflow. Не трогать docs/thesis/litreview*. Не выдавать planning/synthetic evidence за physical/human/release result.

При доступном create_goal сначала проверь текущую полную цель. Не уменьшай её до текущего пакета и не отмечай complete после локального PASS. Финальный результат — точный квалифицированный signed build, реальный backend, доказанное качество, полный UI/media, beta и разрешённый выпуск.

Начни с короткого сообщения, что проверяешь точку передачи, затем прочитай указанные файлы и переходи к реализации. Не отвечай только пересказом этого промпта.

