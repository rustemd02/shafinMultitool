# Воспроизводимая техническая сборка SET OS

Этот рецепт создаёт неподписанный archive для устройства и сохраняет доказательства
его происхождения. Он не выполняет Apple publishing workflow. Текущий статус
функций и допуска остаётся в `APP_STORE_RELEASE_TRACKER.md` и `AppStoreSubmissionGates.json`.

## Исходники и окружение

Baseline нового snapshot — `c5eb957975cb4f2ee1beb98df49572ec806dd520`, ветка `store`.
Значения ниже сверены с завершёнными archive и post-check receipts.
Это unsigned engineering artifact; release admission остаётся закрытым.
Последующая реализация включает modified и untracked файлы. Для воспроизведения
конкретного archive нужны его
`source-before.json`, `source.patch` и `untracked-inputs.tar.gz`, а не только HEAD.
В отдельной копии этого baseline применяют соответствующий binary patch и новые
входные файлы; SHA, размеры, исполнимость и локальные symlink должны совпасть с
manifest. Рабочее дерево владельца для этого не сбрасывают.

Окружение нового archive: `Xcode 26.6 (17F113), iOS SDK 26.5`; фактическая запись —
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/archives/20260917T050524112755Z-release-archive/toolchain.txt`, SHA `d509f7e4757a27f561dd8a82781f14a86652989ac35b3a9a61fb16fce70dc1a9`. Исторический
archive 19:51 использовал macOS arm64, Xcode 26.6 (17F113), iOS SDK 26.5 и
Python 3.11.9. Используется `shafinMultitool.xcworkspace`, схема
`shafinMultitool`, конфигурация Release. `Podfile.lock`, установленный SnapKit,
`Frameworks` и модели входят в идентифицируемые входы. Замена зависимости или
toolchain создаёт новый проверяемый candidate.

Историческая проверка 2026-09-16 установила соответствие того toolchain опубликованному минимальному
SDK-требованию: с 28 апреля 2026 Apple требует Xcode 26+ и iOS/iPadOS 26 SDK.
Источник: [Apple Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).

До сборки проверяют свободное место. Wrapper требует не менее 8 GiB; это нижний
порог отказа, а не обещание достаточности для любого нового toolchain. Archive и
DerivedData размещаются вне Git. Один DerivedData не используют одновременно
несколько процессов Xcode.

## Команда из корня репозитория

```sh
python3 -B tools/release/archive_build.py \
  --repo-root /Users/unterlantas/Documents/XCode/shafinMultitool \
  --output-parent /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/archives \
  --derived-data /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-next-preflight-20260916-1hb3qbu4/archives/20260916T195158920366Z-release-archive/DerivedData
```

Каждый запуск создаёт новый каталог archive/result/source evidence с UTC-временем.
Команда выше повторно использует только отдельный Release DerivedData cache;
прежние archive, xcresult и source receipts остаются неизменными. Если
`--derived-data` опущен, wrapper создаёт новый DerivedData внутри нового run.
Существующий каталог завершённого запуска не используют как новый output. Wrapper исполняет настоящий
`xcodebuild archive` для `generic/platform=iOS` с `CODE_SIGNING_ALLOWED=NO`.
Он проверяет ненулевой исполнимый файл, bundle ID, платформу iPhoneOS и arm64;
затем вызывает существующий `scripts/validate_release_bundle.sh` и повторно
сверяет исходники. Ошибка сборки, отсутствующий archive, изменение входов или
провал bundle gate не превращаются в успешную проверку.

Результат читают в `receipt.json`. Важны одновременно `build_exit`,
`source_unchanged`, `validation_exit`, `status` и исходный лог. Exit 2 wrapper
может означать, что archive успешно создан, но допуск ресурсов не пройден;
смысл устанавливают по receipt, не по наличию `.app`. Даже успешный unsigned
gate оставляет `release_ready=false` и `distribution_signed=false`.

## Состав evidence

- `source-before.json`, `source-after.json`, `source-after-verification.json`:
  baseline, область входов, SHA каждого файла и общий fingerprint.
- `source.patch`, `untracked-inputs.tar.gz`: изменения, необходимые для
  восстановления конкретного candidate поверх baseline.
- `toolchain.txt`, `invocation.json`, `xcodebuild.log`, `archive.xcresult`:
  точная команда, окружение и фактическое исполнение.
- `SETOS.xcarchive`, `archive-files.json`, `binary-architecture.txt`:
  приложение, SHA всех его файлов, metadata, endpoint configuration и архитектура.
- `bundle-validation.log`, `receipt.json`: результат проверок и SHA evidence.

## Новый engineering archive

Статус этой записи: **VERIFIED UNSIGNED ENGINEERING ARTIFACT — RELEASE ADMISSION BLOCKED**. Запись заполнена по
завершённым native, post-archive и negative-control receipts. Исторический archive
19:51 ниже не является текущим доказательством более поздних исходников.

| Поле | Фактическое значение нового artifact |
| --- | --- |
| Archive | `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/archives/20260917T050524112755Z-release-archive/SETOS.xcarchive` |
| Baseline / branch | `c5eb957975cb4f2ee1beb98df49572ec806dd520` / `store` |
| Source fingerprint / число входов | `d974816b880e3df4f762e72dd9ffe1f7c7bbd5697f58bb388a344f7e1c6adaba` / 667 |
| Native build / wrapper / validation exit | 0 / 2 / 1 |
| Receipt status / source unchanged | `engineering_archive_built_release_validation_failed` / true |
| Archive manifest SHA256 | `10e3208d16990d02bd58a9a1d32d40955cf5cd6166c7e03a3097440195cd95bf` |
| Фактически скомпилировано app Swift / untracked inputs | 213 / 39 |
| Developer backend URL / distribution signature | `"" (empty)` / false |

Воспроизводят именно `source-before.json`, `source.patch` и
`untracked-inputs.tar.gz` этого run. Post-archive proof сравнивает три source
snapshots, текущие build inputs, каждый untracked payload и фактический arm64
SwiftFileList. В него должны войти также `CaptureImagePlacementGoal.swift` и
`PauseImagePlacementSheet.swift`, `PauseImagePlacementReviewProjection.swift` и
исправленный `DETRDetector.swift`, как и остальные текущие Swift-файлы app target.
`docs/implementation/provenance` входит в archive fingerprint; release-документы
этого каталога и test targets имеют отдельные evidence и в эту область не входят.

Новый локальный путь Position in Frame позволяет выбрать или вручную задать
область на принятом paused image, отменить черновик, сохранить цель следующего
кадра и сбросить её. Цель задаётся в координатах изображения и не доказывает
физическое перемещение объекта, его identity или улучшение кадра. Последний
проверенный UI run: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-execution-20260916/20260917T045712379671Z-camera-image-placement-content-start-iphone`, receipt SHA `82b99e16128769fab5dba38a3864c26ff9f8c6122e432336aa384e6d1c7d8fd4`,
результат 2/2 PASS; RU/EN simulator fixture journeys with runtime binary identity bound. На принятой паузе видны reference image, наблюдаемая область и инструкция
следующего дубля; Resume сбрасывает привязанную к кадру цель. Это не доказывает
перенос identity на новый live-frame или физическое выполнение рекомендации.
Runtime binding: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/placement-content-start-qualified-s1lf5kg4/runtime-binding-proof/receipt.json`, SHA `21a0efc20a08457753e314f85899acc646262a78dfada1412eb294176c2b77ad`.
Agent visual review: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/placement-content-start-qualified-s1lf5kg4/root-visual-review.json`, SHA `86340af41b6d7cea83a574974e694bfb5bfc235855c76977976695fb2d0cfa3c`;
просмотрены 6 PNG и 3 текстовых attachment. `human_gold=false`; это simulator
fixture evidence, не физическая съёмка и не субъективная оценка владельца.

Фактические compiled EN/RU products: 682 Localizable keys
и 5 InfoPlist keys в каждом языке; два source catalogs,
четыре compiled products, два privacy manifest (app и SnapKit).
Новый content-only resource proof: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/placement-content-start-qualified-s1lf5kg4/resource-proof/qualification-receipt.json`,
SHA `aa3ad741399d24bea5f0565116a00b5670f7772227fe630e911a74a0dae656b1`. Source/compiled equality и
source-bound Debug proof не заменяют независимую проверку нового Release bundle.

| Модель в новом bundle | SHA256 source и compiled `weights/weight.bin`, требуется фактическое совпадение |
| --- | --- |
| `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | `8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7` |
| `aesthetic_nima_mobilenet_fp16.mlmodelc` | `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717` |

Ожидаемые неизменённые source weights — DETR
`8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7`
и NIMA `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717`.
Официальное соответствие трёх DETR source files отражено в
`docs/implementation/provenance/detr-provenance.json`; отдельный
`validate_detr_legal.py` проверяет два полных source/bundle legal files и
зафиксированный provenance hash. Совпадение этих bytes не закрывает общий model gate.

Обработка недоступности DETR исправлена в wrapper и исполняемых владельцах:
ошибка или отсутствие результата не публикуется как успешное пустое наблюдение.
Узкий actual bundled-image `019` inference checkpoint: `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-execution-20260916/20260917T050227603858Z-detr-typed-bundled-019-inference`,
1/1 PASS, receipt SHA `ec62ce9bfbf98d8875063b4a6356678af92caef28de969d926d24f88ca9d525d`.
Это проверка данного пути, не общая оценка точности или coaching utility.

Исследованный исправленный NIMA FP32 остаётся внешним candidate. Его воспроизводимость
сохранена в `../setos-backend/local-data/SETOS/verification/provenance-gaps-20260916-3unzo_1a/nima-corrected-export-20260916/reproducibility-receipt.json`
относительно корня проекта. Это не замена production NIMA и не допуск качества,
прав или физического устройства. Исходная production-конверсия сохраняет
зафиксированный padding defect. Ни этот candidate, ни research composition
checkpoint, GGUF или DeviceBenchmark не должны наследовать bundle admission.

Существуют шесть ограниченных component decisions: собственная procedural
геометрия Circle/Person и четыре конкретных configuration/localization resources;
их границы заданы `first-party-resource-admission.md` и content-bound validators.
Четыре текущих PENDING: `detr-segmentation-model`, `llama-framework`,
`nima-aesthetic-model`, `resource-assets-catalog`. Финальный bundle gate должен
показать фактический точный набор; ни replacement dependencies, ни quality,
physical и production-operator gates не снимаются этой записью.

| Свежий receipt | SHA256 / результат |
| --- | --- |
| `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/archives/20260917T050524112755Z-release-archive/receipt.json` | `ee1d1256630a39f3c1ce72ebd2c5ed5b4b394f48b6adcf36fa8205fe4c10dad8` |
| `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/post-archive-proof-uiaw_dbt/receipt.json` | `40ce460a2e54885d961f3a65441159d69cb8a3bbdb5385b90195f9ef21460d94`; engineering_artifact_identity_verified_release_provenance_pending |
| `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/release-050524-targeted-controls-9nif362j/receipt.json` | `1226cf93a4556c71c16a18f0efab831e56f63c7cb6e77c0c64aa306d7ba88e6b`; 12/12 corrupted-copy controls rejected with expected reasons |
| `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/post-archive-proof-uiaw_dbt/receipt.json` | `40ce460a2e54885d961f3a65441159d69cb8a3bbdb5385b90195f9ef21460d94`; PASS: source/compiled DETR and NIMA weight bytes match (same post-archive receipt) |

Точные команды трёх targeted validators и 12 controls находятся в `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/release-050524-targeted-controls-9nif362j/receipt.json`.
Post-archive helper: `../setos-backend/local-data/SETOS/verification/release-next-preflight-20260916-1hb3qbu4/post_archive_proof.py`;
requirements: `../setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/post-archive-requirements.json`.
Параметры: `--repo-root`, `--archive-run`, фактический `--source-fingerprint`,
`--requirements` и существующий внешний `--output-parent`.
После controls отдельно read-only сверены текущие build inputs и весь archive:
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/release-docs-050524-final/preparation-receipt.json`.
Ожидаемый отказ из-за четырёх PENDING не является release PASS. Изменение endpoint,
исходников, моделей или legal resources требует нового artifact и связанных gates.

## Исторический archive 2026-09-16 19:51

Следующие числа, результаты и десять тогдашних PENDING относятся только к
неизменному историческому snapshot; они не описывают текущий source или новый run.

Артефакт:
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-next-preflight-20260916-1hb3qbu4/archives/20260916T195158920366Z-release-archive/SETOS.xcarchive`.

Build exit 0; wrapper exit 2; `validation_exit=1` и статус
`engineering_archive_built_release_validation_failed`. Исходники совпали до
сборки, после сборки и после проверок. Fingerprint 634 входных файлов:
`3931df3de95e7fcd2542a1fea4ead2edf7254099f58ab2d02cde7b41f9c79200`.
`archive-files.json` SHA256:
`28dd55e5f8c6af3e92a9118d7254c5f1a9665a5e0df6dd02a4244829a7a5abdf`.

По фактическому compiler file list включены все 193 Swift-файла app target,
в том числе три новых файла удаления installation data и соответствующего UI.
Все шесть untracked build inputs сохранены в tar и сверены с manifest.
Тестовые файлы не входят в область archive inputs; их исполнение имеет отдельные
XCTest receipts. Release-документы в этом каталоге также вне этой области.

В приложении `com.vigvamcev-media.shafinMultitool` версии 1.0 (1), iOS 17.0+,
есть оба device families (iPhone/iPad). `SETOSSceneBaseURL` пустой; облачный Scene
endpoint не настроен. Это unsigned engineering artifact. `release_ready=false`,
`distribution_signed=false`; наличие встроенного fallback не закрывает приёмку
обязательного серверного пути.

В Release скомпилированы ровно две Core ML модели:

| Модель в bundle | SHA256 исходных и скомпилированных `weights/weight.bin` | Размер весов | Контракт в compiled metadata |
| --- | --- | ---: | --- |
| `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | `8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7` | 42 748 128 bytes | RGB 448×448 `image` → Int32 [448,448] `semanticPredictions` |
| `aesthetic_nima_mobilenet_fp16.mlmodelc` | `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717` | 6 416 212 bytes | RGB 224×224 `image` → Float16 [1,10] `Identity` |

Это доказательство состава, компиляции и совпадения весов. Оно не доказывает
качество советов, калибровку, происхождение обучения или право распространения
модели. Research composition checkpoint, GGUF и DeviceBenchmark отсутствуют
в Release. `llama.framework` остаётся в bundle; отсутствие GGUF не удаляет его
отдельный provenance gate.

Source-to-bundle gate с фактическим `xcstringstool` подтвердил оба каталога
и четыре compiled EN/RU products: по 638 Localizable keys (включая по 21 ключу
удаления данных) и по 5 InfoPlist keys. Parsed privacy manifest совпал с source;
в bundle ровно два manifest: приложения и SnapKit. Это техническое подтверждение
текущего `remote_disabled` профиля и ресурсов; оно не утверждает окончательную
политику production service или юридический допуск текста и изображений.

Source и bundle validators завершаются кодом 1 только из-за десяти `PENDING`
строк: `circle-usdz`, `detr-segmentation-model`, `info-plist-localization`,
`llama-framework`, `localized-resources`, `module-assets-catalog`,
`nima-aesthetic-model`, `person-usdz`, `privacy-manifest`,
`resource-assets-catalog`. Их статус не изменён на основании технических проверок.

Все 12 контролей намеренно повреждённых копий отвергнуты: отсутствующий font,
отсутствующая RU InfoPlist localization, изменённое RU value, отсутствующая
version, неверный scene class, отсутствующий AppIcon, запрещённые DeviceBenchmark
и GGUF, неизвестная третья модель, неожиданный framework, отсутствующий root
privacy manifest и лишний manifest. Source и исходный archive остались неизменны.

Evidence root:
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-next-preflight-20260916-1hb3qbu4/`.

| Receipt относительно evidence root | SHA256 |
| --- | --- |
| `final-release-archive-verification.json` | `13198b3aa57582c95c0a4026f4788c3118341d663c34e9b855da475563d4c75b` |
| `post-archive-proof-cugd5wig/receipt.json` | `251fc6f3c13c35fbcb6d85e22a32ef5102d05d6828097b14943c0729106a326d` |
| `post-archive-proof-cugd5wig/model-byte-proof.json` | `125f5729dc3a1987f651404e8890924cae2c7a8615460d7f7e44638573db742c` |
| `bundle-controls-k0u8drap/receipt.json` | `c6c63d8120ad50d643fe08396f78aa7ba615ebb5846ba6d78def0e673f38971d` |

## Историческая сборка 2026-09-16 15:20

Первый фактически созданный archive: `20260916T152044616359Z-release-archive`,
baseline `611ca193e8ca852889918d5c8a7a6c54193d121e`.
Build exit 0, входы не изменились, fingerprint
`1bf1d9290edf71ae543b58236a48205936f8fb296190a47b9f9393e1980b0e8e`.
`archive-files.json` SHA256:
`8588ddf572e12ebab85a39be23873faa8c9347ab9c3ba4820734e8cf2b57b84c`.
В нём `SETOSSceneBaseURL` пустой. Это snapshot до полного пакета записи Camera
и текущего Vision tracking; он не квалифицирует последующие изменения.

Исходный validator завершился ошибкой отсутствующего helper. После исправления
`20260916T152455588085Z-archive-validator-repair/receipt.json` подтверждает
проверку того же неизменённого archive: ожидаемый exit 1 из-за десяти незакрытых
provenance rows и успешные 11 проверок намеренно повреждённых копий. Первый
receipt сохранён без переписывания. Полные пути и последующие кандидаты
индексируются в `../setos-backend/local-data/SETOS/verification/`
`release-execution-20260916/RUNNING_CHECKPOINT.md` относительно корня проекта.

## Перед передачей владельцу

Требуются закрытые ресурсные и модельные gates, рабочая квалифицированная
конфигурация сервера, физические и пользовательские проверки. Любые следующие
изменения build inputs требуют нового archive и повторных связанных gates.

Фактическая попытка device Debug build
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/physical-command-package-20260916-m1z9o3ub/20260916T195715143150Z-debug-ieqgn7wo/`
завершилась native exit 65: выбранная Personal
Development Team `5NAKQ28539` не поддерживает требуемую App Attest capability.
`build-receipt.json` SHA256:
`e24dbdf485728927a7f5f5ca9ebbfc29c9371b28526480008b7def0bfdf6e055`.
`installed=false`, `launched=false`; приёмка на устройстве не выполнена.
Выбор подходящей команды владельцем ещё ожидается. Отдельный диагностический
Debug app не квалифицирует подписание приложения с предусмотренным App Attest.

Подписание и export используют подходящие certificate/profile и отдельно
проверенный `ExportOptions.plist`; unsigned archive их не заменяет. Текущий
репозиторный ExportOptions фиксирует Personal Team `5NAKQ28539` и остаётся
неподтверждённым шаблоном. Его нельзя запускать как готовую signing-конфигурацию: сначала
нужны выбранная владельцем App Attest-capable команда и соответствующие profiles.
Точный более поздний physical/diagnostic статус сверяют в
`APP_STORE_RELEASE_TRACKER.md` и hash-bound receipts;
диагностическая конфигурация без capability не закрывает предусмотренное подписание.
Загрузка, metadata, TestFlight, App Review и публикация остаются действиями
владельца. Побайтовая идентичность двух Xcode archives этим рецептом не заявляется:
воспроизводятся проверяемые входы, команды, состав приложения и результаты gates.
