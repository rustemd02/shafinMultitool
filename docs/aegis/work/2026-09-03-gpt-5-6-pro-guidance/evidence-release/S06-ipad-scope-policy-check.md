# S06 (пункт 2) — одна iPad scope policy: проверено, конфликта в дереве нет

Проверено 2026-09-13 в рабочем дереве HEAD `0733df2` (оркестратор). Карточка S06, пункт 2 требовала
«принять одну iPad scope policy: текущий platform contract full-screen/no Split View против AR test resize step —
конфликт требований… Сохранить обязательный iPad, зафиксировать корректный сценарий проверки».

## Что фактически в дереве

| Факт | Где | Значение |
|---|---|---|
| Полноэкранный режим включён | `shafinMultitool.xcodeproj/project.pbxproj:572` и `:628` | `INFOPLIST_KEY_UIRequiresFullScreen = YES` |
| Универсальный бинарник (iPhone + iPad) | `project.pbxproj` | `TARGETED_DEVICE_FAMILY = "1,2"` |
| Политика полноэкранного окна заявлена | `shafinMultitoolTests/iPadPlatformContractTests.swift:30-33` | `testFullscreenOnlyWindowing`: `UIRequiresFullScreen == true`, сообщение «multitasking windowing is out of scope and must not be claimed» |
| Политика описана в документе | `docs/implementation/ipad-platform-contract-v1.md:18` | «windowing support it has not earned; Split View / Slide Over are out of…» |
| Минимум ОС | `iPadPlatformContractTests.testMinimumOSVersion` | `MinimumOSVersion == "17.0"` (совпадает с `IPHONEOS_DEPLOYMENT_TARGET`) |
| Все четыре ориентации | `iPadPlatformContractTests.testAllFourOrientationsDeclared` | объявлены portrait/upside-down/landscape-left/right |

**Прогон (мой):** `xcodebuild test-without-building … -only-testing:shafinMultitoolTests/iPadPlatformContractTests`
→ **Executed 4 tests, with 0 failures**, `** TEST EXECUTE SUCCEEDED **`, exit 0. То есть контракт **держится** на
собранном продукте.

## Чего в дереве НЕТ: «AR test resize step»

Я искал целенаправленно и не нашёл ни одного теста, который меняет размер окна приложения (Split View/Slide Over):

- в `shafinMultitoolTests/` поиск по `resize|splitview|multitasking` даёт только сообщение самого контрактного теста
  про multitasking; `resize` в `CameraCoordinateSpaceTests` относится к ресайзу **тензоров**, а не окна;
- в `shafinMultitoolUITests/` есть `testDeniedStateLandscapeUsesSplitLayoutAfterActiveRotation` — но это **раскладка
  «две колонки» в ландшафте** (poster rail + phase column), а не Split View многозадачности. Смешивать эти понятия
  нельзя: первое — компоновка внутри полноэкранного приложения, второе — оконный режим системы.

**Вывод:** описанный в карточке конфликт «full-screen против AR resize step» в текущем дереве **отсутствует**.
Политика одна — полноэкранная, она заявлена, описана и проверяется. Приложение не заставляют проходить
невозможную комбинацию, и «чинить» здесь нечего; правильный результат — зафиксировать это как проверенный факт,
а не изобретать правку.

## Ошибка, которую я почти записал (и почему это важно)

Первым шагом я прочитал **файл** `shafinMultitool/Info.plist` через `plistlib` и не нашёл там `UIRequiresFullScreen`,
из чего выходило «тест требует ключ, которого нет» — то есть ложный дефект с красным тестом. Прогон показал
обратное: тест **проходит**, потому что он читает `Bundle.main.infoDictionary`, то есть **собранный** продукт, а ключ
приходит из настройки сборки `INFOPLIST_KEY_UIRequiresFullScreen = YES`, а не из файла plist.

Практическое следствие: **файл `Info.plist` в репозитории не равен поставляемому plist.** Проверять контракт
подачи нужно на **построенном** продукте (как и делает `iPadPlatformContractTests`), а выводы о поставляемых ключах,
сделанные по файлу в репозитории, недействительны. Это записано как урок проверки, а не как дефект приложения.

## Корректный сценарий проверки (зафиксирован)

1. Универсальность: `UIDeviceFamily` содержит 1 и 2 (нет режима совместимости на iPad).
2. Полноэкранность: `UIRequiresFullScreen == true` — многозадачное окно не заявляется.
3. Ориентации: объявлены все четыре; ландшафт проверяется как **раскладка** внутри полноэкранного приложения.
4. Минимум ОС: `MinimumOSVersion == "17.0"`.
5. Физическая проверка на обязательном iPad (поворот, safe areas, Dynamic Type, VoiceOver) — это **Q04**, а не unit-уровень;
   unit-проверки выше доказывают только заявленный контракт подачи.

## Границы

Проверено на симуляторе; физическое поведение iPad (usable area, поворот, жесты) — Q04. Конфликт с `S05` не
затрагивался: пункт 2 не зависит от recording lifecycle.
