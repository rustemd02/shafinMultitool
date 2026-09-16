# S07 — права, privacy и эксплуатационный пакет (2026-09-13)

Package: S07 of `docs/aegis/plans/2026-09-13-setos-release-execution.md` §6.
Repo: `/Users/unterlantas/Documents/XCode/shafinMultitool`, branch `store`,
HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`, dirty worktree.

## 1. Статус

**needs_review** — пакет выполнен, но у финального состава есть **явно названные**
provenance/privacy blockers, которые блокируют READY. Часть провайдера/хостинга —
**blocked_external** (зависит от C09 и решения владельца). Ни одна проверка не
ослаблена ради PASS; ничего не подписывалось, не собиралось в Release, не
публиковалось.

## 2. Файлы (sha256 — зачем)

Изменены (S07):

- `shafinMultitool/PrivacyInfo.xcprivacy`
  `21dd725578c5f3200687542a891ac0480308ac7f484be4ccd57be3057ba11d31`
  — добавлены отсутствовавшие required-reason declarации FileTimestamp C617.1 и
  DiskSpace E174.1 (файл — мой по распределению).
- `scripts/validate_privacy_manifest.sh`
  `b22a8f2b0fc1d97b8358b43af544f426b95f8124bd9e6d17909aa5f4fcee3334`
  — гейт теперь требует ровно 4 пары category/reason (было жёстко 2) и получил
  негативные фикстуры wrong-timestamp-reason / wrong-disk-reason; это усиление,
  не ослабление.
- `docs/implementation/provenance/release-component-status.json`
  `e38980bcac291e691637fd256b55e364d4aea35c1ea04ee5b17a13b45c307aa3`
  — `scene-gguf-model.source_state` исправлен `absent` → `present` (гитигноренный
  локальный файл реально существует); Release/Debug остаются `excluded`.
- `docs/implementation/release/AppPrivacyAnswers.json`
  `13743a0432d7349fdf8595293f21044a563d5728d643c2ab97cfa4048c9c08f2`
  — исправлено ложное утверждение «скан не нашёл file-timestamp/disk-space API»;
  добавлен off-device факт по Apple Speech; зафиксировано расхождение с
  замороженным tools-тестом.
- `docs/implementation/release/AppStoreSubmissionGates.json`
  `015d69ee093a3412b74f4a5f48118f02759b7aa937951d5f9fb7771749468c03`
  — гейты 3 и 5 приведены к фактам (4 required-reason API; draft-страница есть,
  URL и in-app вход отсутствуют).
- `docs/implementation/release/AppStoreMetadata.draft.json`
  `edb871bcdc1bd202e6dab3fa229f0e0431eec4f86416568e32cc26504e851403`
  — EN/RU store-описание честно упоминает обработку голосового ввода сервисом Apple.
- `docs/implementation/release/ReviewNotes.draft.md`
  `5f6b517c3cfa97521d0adc51d80c41b70dcb42c3cd2053e18a1e9221b6b96704`
  — убрано неверное «no server dependency»; Speech назван исключением.

Новые (S07):

- `docs/implementation/provenance/s07-component-inventory.json`
  `03092cea1a16102bb271d6ecd2c626fe71f05467957077a40c1136436d36e405`
  — фактический component inventory: версия/hash/license/disposition/lineage по
  19 зарегистрированным семействам + 1 незарегистрированный артефакт.
- `docs/implementation/provenance/data-flows.md`
  `3cc7f8ac0705f7b5be516fcdf68d0b874580aea45869d22e26e3750c0536be25`
  — реальные потоки local/conditional cloud, хранение/удаление/отзыв, граница логов.
- `third-party-notices/NOTICES.md`
  `6e696921caeb263351707219161b5600d79adc7b483c2a44a9d8b419b0d59fbc`
  — credits/notices (авторство, не валюта и не монетизация) + честные UNKNOWN-статусы.
- `docs/implementation/release/PrivacySupportPage.draft.md`
  `03a27a6bc6fa37ba855754a6596b136bd79d79ec5349cd21e53affdec4cff0c0`
  — draft privacy/support-страницы (EN/RU) + спецификация in-app входа.

## 3. Команды, exit code, результат

| Команда | exit | Результат |
|---|---|---|
| `python3 scripts/validate_release_component_status.py --repo-root .` | **1** | shape валиден, `KNOWN_BLOCKER_COUNT=16` (все — `legal-state-pending`); до правки падал malformed из-за gguf |
| `python3 scripts/validate_llama_framework_provenance.py --repo-root .` | 0 | PASS, 25 files, commit 8f974d2, MIT |
| `python3 scripts/validate_circle_asset_provenance.py --repo-root .` | 0 | PASS (repository correlation; causality не доказана) |
| `bash scripts/validate_privacy_manifest.sh --self-test --source-manifest shafinMultitool/PrivacyInfo.xcprivacy` | 0 | PASS: 4 entries, 6 негативных фикстур |
| `python3 -m pytest scripts/tests/test_validate_release_component_status.py scripts/tests/test_validate_llama_framework_provenance.py scripts/tests/test_validate_circle_asset_provenance.py -q` | 0 | 43 passed, 2 subtests |
| `bash scripts/tests/test_release_provenance_gate.sh` | 0 | PASS |
| `python3 -m pytest tools/tests/test_release_guards.py tools/tests/test_release_metadata.py -q` | 0 | 17 passed (замороженные guard-тесты не сломаны) |
| `plutil -lint shafinMultitool/PrivacyInfo.xcprivacy` | 0 | OK |
| `bash scripts/validate_release_bundle.sh ... --app <Release.app>` | **не воспроизводимо** | нет финального Release-бандла; тяжёлая сборка запрещена (идут чужие xcodebuild). Требует M05/Q01-кандидата. |

## 4. Component inventory

- Компонентов: **19** зарегистрированных + **1 незарегистрированный** в релизном
  пути (`SETCompositionNet-Stage2-Local.mlpackage`).
- License определена у **7** (llama MIT, SnapKit MIT, 5 шрифтов OFL-1.1 из name-table);
  **9** — UNKNOWN (NIMA, gguf, SETCompositionNet, Circle.rcproject/.usdz, Person.usdz,
  Resource/Module asset catalogs, SETGrain); **3** — n/a (privacy manifest, 2 xcstrings).
  У DETR license-строка Apache-2.0 **встроена в модель**, но независимо не проверена.
- sha256 записан у **16**; Release=bundled у **16**, excluded у **3** (gguf, rcproject,
  SETGrain — `Resources/Models`, `Resources/Textures`, `Resources/Circle.rcproject`
  исключены из target через `membershipExceptions`).
- `legal_state=APPROVED`: **0**. Owner/notice-решение требуется у **16**.
- Training lineage решена отдельно и нигде не выведена из факта наличия файла.

## 5. Реальные потоки данных (что проверено)

Полностью — в `docs/implementation/provenance/data-flows.md`. Ключевое:

- **L4 Speech — реальный off-device поток.** `SpeechRecognitionService.swift`
  создаёт `SFSpeechAudioBufferRecognitionRequest` и **не** ставит
  `requiresOnDeviceRecognition`, значит распознавание серверное; собственный
  purpose string прямо говорит «отправку звука на сервера Apple». Приложение аудио
  не хранит, но и удалить его у Apple не может. Это не «on-device ML».
- **C1 remote Scene** — fail-closed: без https-эндпоинта и App Attest
  (`SceneRemoteServiceComposition.makeRemoteProvider` → nil) ничего не уходит;
  при включении уходят текст сцены + App Attest payloads. Deployment blocked_external (S02a).
- **C2 remote VLM** — `#if DEBUG`-only, env-gated; при включении шлёт структурный
  контекст + redacted/EXIF-stripped visual ref (`VLMVisualInput`, longEdge≤1024,
  exifStripped/redactionApplied обязательны). В Release не конструируется (пин
  `tools/tests/test_release_metadata.py`).
- **Логи:** API keys/tokens/App Attest payloads не печатаются; кадры/пиксели не
  логируются; Speech логирует только `localizedDescription`. Остаточный риск:
  unguarded `print` в `SceneGeneratorViewModel` (строки 3429/5723/5791/6528/6530 —
  вне всех `#if DEBUG`) и `SceneParserService` могут писать пользовательский
  текст сцены в системный лог Release. Это не утечка секрета, но владельцу Scene-логов
  надо убрать/приглушить.

## 6. Blockers, которые блокируют READY

1. **Незарегистрированный research-артефакт в Release.** `Models/CoreML` не входит в
   `membershipExceptions`, поэтому `SETCompositionNet-Stage2-Local.mlpackage` (4.6 МБ,
   research-only, untracked, sha256 `fd6438f4…`) автоматически бандлится в Debug и
   Release. В inventory/record его нет, права не решены. Нужно: исключить из target
   либо зарегистрировать (M05) с явным rights-решением. **Блокирует READY.**
2. **16 registered components с `legal_state=PENDING`** (validator exit 1): NIMA без
   автора/лицензии; Person.usdz/Circle.usdz без creator/redistribution evidence;
   asset catalogs без authorship; DETR/llama без принятого redistribution-решения;
   шрифтам и SnapKit нужны notices. **Блокирует READY** до owner/legal решения.
3. **Required-reason privacy gap — исправлен в манифесте, но замороженный guard
   требует обновления.** Манифест и `scripts/validate_privacy_manifest.sh` теперь
   корректны (4 API), однако `tools/tests/test_release_metadata.py` (мой запрет на
   правку `tools/**`) всё ещё пиннит legacy-набор из 2 API, поэтому
   `AppPrivacyAnswers.required_reason_apis.answer` оставлен legacy-формой с полем
   `answer_superseded_by_s07`. Владельцу `tools/**` нужно обновить guard и убрать
   legacy-поле. **Блокирует READY** (формально).
4. **Privacy policy URL / Support URL / in-app страница отсутствуют** (gate 5).
   Draft-контент готов (`PrivacySupportPage.draft.md`), но хостинга нет и About/
   Settings-экрана в приложении нет. **Блокирует READY.**
5. **Хостинг/провайдер: retention/region/deletion не подтверждены** — S02a держит
   сервис на 127.0.0.1; политика хранения job-запросов (текст сцены + ответы)
   задокументирована, но end-to-end не проверена. C09-часть провайдера не сделана.
   **blocked_external / owner.**
6. **Финальный состав bundle не зафиксирован** — M05 ещё не выдал candidate; S07 не
   строил Release (запрет на тяжёлые параллельные сборки), поэтому bundle-validator
   не воспроизводим, а membership выведен из `project.pbxproj` и требует повтора на
   точном кандидате.

## 7. Решения/документы для владельца

- **Export compliance:** `ITSAppUsesNonExemptEncryption=false` уже в `Info.plist`
  (S07 не трогал чужие правки; добавлю: при C1 появится только HTTPS + CryptoKit
  SHA-256/App Attest — own crypto нет). Требуется подтверждение владельца на Q06.
- **Hosting:** аккаунт/регион, DNS+TLS, egress authorization (S02a §5, owner).
- **Provider:** выбор провайдера/модели/revision, quota, outage (C09).
- **Retention/region/deletion:** задать окно хранения job-стора, регион, процедуру
  удаления и отзыва согласия до включения C1 (сейчас отзывать нечего — путь выключен).
- **Права на контент:** кинокадры Blender CC-BY — вердикт владельца (Packet A, A1);
  S07 его не принимал. NIMA/Person.usdz/asset catalogs — owner decision.
- **App Privacy:** подтвердить `off_device_processing` (Speech→Apple) и ввести ответы
  в ASC; hosted policy должна это disclose.

## 8. Что честно НЕ сделано

- Не запускался Release-build / bundle-validator (нет финального кандидата; запрет
  на тяжёлые сборки). Проверка bundle membership — по `project.pbxproj`, не по байтам.
- In-app privacy/support-экран не подключён: в приложении нет About/Settings-поверхности,
  а его создание затрагивает общий UI (S04/S06). Дан только готовый контент + спека.
- Verbatim текст OFL-1.1 не скопирован в репозиторий (указатели есть; notices-бандл
  до отправки должен стать самодостаточным).
- `tools/**` не редактировался: замороженный guard по required-reason остаётся
  legacy-формы; точное исправление описано, но требует владельца `tools/**`.
- Юридический clearance не выполнялся и не заявлялся; спорные права не помечены cleared.
- Провайдерский retention/region/deletion end-to-end не проверялся (C09).
