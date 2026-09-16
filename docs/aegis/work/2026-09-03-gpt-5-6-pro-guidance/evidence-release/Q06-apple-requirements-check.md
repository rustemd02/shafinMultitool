# Q06-preparation — сверка требований Apple с фактами проекта

Источник: официальная страница Apple **«Upcoming Requirements»**, прочитана в браузере 2026-09-13
(`https://developer.apple.com/news/upcoming-requirements/`). Цитаты приведены как есть со страницы;
ничего не добавлялось «по памяти».

## 1. Что требует Apple (подтверждено первоисточником)

| Требование | Действует с | Формулировка со страницы | Применимо к нам |
|---|---|---|---|
| **SDK minimum requirements** | **28 апреля 2026** | «Apps uploaded to App Store Connect must be built with **Xcode 26** or later using an SDK for **iOS 26, iPadOS 26, tvOS 26, visionOS 26, or watchOS 26**.» | **Да** |
| **Approved reasons for APIs** | 1 мая 2024 | «You’ll need to include approved reasons for the listed APIs used by your app’s code (including from third-party SDKs) to upload a new or updated app to App Store Connect.» | **Да** |
| **Age Rating Updates** | **31 января 2026** | «Ratings for all apps and games on the App Store have been automatically updated to align with our new age rating system… Provide responses to the updated age rating questions for each of your apps by January 31, 2026, to avoid an interruption when submitting your app updates in App Store Connect.» | **Да** (действие владельца в ASC) |
| **DSA trader status required for apps in the EU** | 17 февраля 2025 | «Apps without trader status will be removed from the App Store in the European Union (EU) until trader status is provided and verified…» | **Да** (действие владельца в ASC) |
| App Store Receipt Signing Intermediate Certificate | 24 января 2025 | SHA‑1 intermediate истёк; on-device receipt validation должна поддерживать SHA‑256, либо использовать `AppTransaction`/`Transaction` | Нет: IAP/подписок и on-device receipt validation в приложении нет |
| APNs certificate update | 20–24 февраля 2025 | обновление Trust Store для нового сертификата APNs | Нет: push не используются |
| Quarantine attribute (macOS) | 18 февраля 2025 | удалить `com.apple.quarantine` в macOS-приложениях | Нет: это iOS/iPadOS-приложение |
| Game Center entitlement | 16 августа 2023 | entitlement + конфигурация в ASC для Game Center | Нет: Game Center не используется |
| tvOS 16.1 SDK / Xcode 14.1 / Xcode 15 (исторические) | 2023–2024 | предыдущие ступени требований SDK | Заменены требованием от 28.04.2026 |

## 2. Сверка с фактическими настройками проекта

Факты из `shafinMultitool.xcodeproj/project.pbxproj` и среды (прочитаны на этой же машине):

| Факт | Значение | Соответствие |
|---|---|---|
| Xcode | **26.6** (Build 17F113) | соответствует «Xcode 26 or later» |
| SDK сборки | SDK из состава Xcode 26.6 (iOS 26 SDK) | соответствует требованию; **подтвердить на самой archive-сборке** |
| `IPHONEOS_DEPLOYMENT_TARGET` | 17.0 | допустимо: Apple требует минимальный **SDK сборки**, а не минимальную версию развёртывания |
| `TARGETED_DEVICE_FAMILY` | `1,2` (iPhone + iPad) | соответствует обязательному iPad в требованиях проекта |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | 1.0 / 1 | заполнено; версия кандидата будет названа в Q01/M05 |
| `PrivacyInfo.xcprivacy` | 4 категории: `UserDefaults`, `SystemBootTime`, `FileTimestamp`, `DiskSpace`; `NSPrivacyTracking=false`; собираемые типы — пустой массив | соответствует требованию «approved reasons» |
| Приватный манифест третьей стороны | `Pods/SnapKit/Sources/PrivacyInfo.xcprivacy` | требование распространяется и на сторонние SDK — манифест присутствует |
| Entitlements-файл | отсутствует | отдельного требования нет; если появится capability (например App Attest/Game Center), он понадобится |
| Интеграция зависимостей | CocoaPods (`Podfile`, `Podfile.lock`) | учтено: манифесты сторонних SDK проверены на уровне Pods |

## 3. Что это значит практически

1. **Технически к требованию SDK мы готовы** — Xcode 26.6 стоит, но требование проверяется на **архивной** сборке
   кандидата: сборка обязана использовать iOS 26 SDK. Это будет зафиксировано в Q01/Q06, а не заявлено заранее.
2. **Approved reasons уже закрыт**: манифест приложения содержит четыре категории с причинами, манифест стороннего
   SDK на месте. Ранее найденный и исправленный пробел (FileTimestamp/DiskSpace) закрыт, и пиннинг
   `tools/tests/test_release_metadata.py` теперь проверяет, что манифест объявляет **всё, что использует код**.
3. **Два требования — только действия владельца в App Store Connect, и они не отменяются подготовкой:**
   - **новый опросник age rating** (система от 31.01.2026) — ответить в App Information;
   - **DSA trader status** для распространения в ЕС — без него приложение удаляется из App Store в ЕС.
   Это учтено в `OWNER-PACKET.md` как часть Packet E (Apple-аккаунт), а не как «технический шаг».
4. **Неприменимые пункты** (receipt signing, APNs, macOS quarantine, Game Center, notarization) не превращаются в
   «блокеры»: они относятся к возможностям, которых в приложении нет. Это же основание позволяет не вводить
   StoreKit/subscriptions — подтверждено отсутствием платных функций, а не удобством.

## 4. Границы этой проверки (честно)

- Проверена **страница Upcoming Requirements** и настройки проекта. **Не проверялись**: полнота ответов App Privacy
  в консоли (это действие владельца), требования App Review Guidelines по существу, возрастные категории для
  конкретного контента (опросник заполняет владелец).
- Требование «Xcode 26 / iOS 26 SDK» проверено как **факт среды** (Xcode 26.6 установлен), но не как факт архивной
  сборки кандидата — она появится в Q01/Q06. До этого момента нельзя утверждать, что архив соответствует.
- Дата проверки: **2026-09-13**. Требования Apple меняются; перед самой загрузкой страницу надо перечитать.
