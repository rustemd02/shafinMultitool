# Воспроизводимая техническая сборка SET OS

Этот рецепт создаёт неподписанный archive для устройства и сохраняет доказательства
его происхождения. Он не выполняет Apple publishing workflow. Текущий статус
функций и допуска остаётся в `EXECUTION_STATE.md` и `AppStoreSubmissionGates.json`.

## Исходники и окружение

Рабочий baseline — `611ca193e8ca852889918d5c8a7a6c54193d121e`, ветка `store`.
Коммит сохраняет первоначальный рабочий набор; последующая реализация остаётся
незакоммиченной. Для воспроизведения конкретного archive нужны его
`source-before.json`, `source.patch` и `untracked-inputs.tar.gz`, а не только HEAD.
В отдельной копии этого baseline применяют соответствующий binary patch и новые
входные файлы; SHA, размеры, исполнимость и локальные symlink должны совпасть с
manifest. Рабочее дерево владельца для этого не сбрасывают.

Проверенное окружение первого archive: macOS arm64, Xcode 26.6 (17F113), iOS SDK
26.5, Python 3.11.9. Используется `shafinMultitool.xcworkspace`, схема
`shafinMultitool`, конфигурация Release. `Podfile.lock`, установленный SnapKit,
`Frameworks` и модели входят в идентифицируемые входы. Замена зависимости или
toolchain создаёт новый проверяемый candidate.

На проверке 2026-09-16 этот toolchain удовлетворяет опубликованному минимальному
SDK-требованию: с 28 апреля 2026 Apple требует Xcode 26+ и iOS/iPadOS 26 SDK.
Источник: [Apple Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).

До сборки проверяют свободное место. Wrapper требует не менее 8 GiB; это нижний
порог отказа, а не обещание достаточности для любого нового toolchain. Archive и
DerivedData размещаются вне Git. Один DerivedData не используют одновременно
несколько процессов Xcode.

## Команда из корня репозитория

```sh
python3 -B tools/release/archive_build.py \
  --output-parent /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-execution-20260916 \
  --derived-data /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-execution-20260916/DerivedData
```

Каждый запуск создаёт новый каталог с UTC-временем. Wrapper исполняет настоящий
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

Первый фактически созданный archive: `20260916T152044616359Z-release-archive`.
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

Требуются новый archive финального source snapshot, закрытые ресурсные и модельные
gates, рабочая квалифицированная конфигурация сервера, физические и пользовательские
проверки. Подписание и export используют подходящие certificate/profile и
проверенный `ExportOptions.plist`; текущий unsigned archive их не заменяет.
Загрузка, metadata, TestFlight, App Review и публикация остаются действиями
владельца. Побайтовая идентичность двух Xcode archives этим рецептом не заявляется:
воспроизводятся проверяемые входы, команды, состав приложения и результаты gates.
