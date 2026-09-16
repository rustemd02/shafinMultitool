# Privacy and support — release draft, not hosted or submitted

This draft accompanies `AppPrivacyAnswers.json` and the in-app **Privacy & licenses** page. The page is reachable from Library and from the entry screen before camera permission. Its runtime branch uses the configured Scene parser; it does not infer privacy behavior from a missing API key. UI acceptance remains pending until the proposal is applied and exercised.

The owner must provide the public policy/support URL, contact, effective date and actual service/operator identity. No URL or contact is invented here. Publication to App Store Connect remains the owner's action.

The remote-enabled profile additionally requires an explicit, request-bound transfer consent with the actual AI provider, processing region, retention and policy version. Reading the information page or granting camera permission does not authorize a scene upload. The current proposal does not close this consent gate.

## Policy body, EN

SET OS helps plan and record scenes. An account is not required. The app has no advertising and does not use an advertising identifier or track users across other apps and websites.

**Camera and AR.** Camera Coach analyses frames on the device. AR uses the camera and motion sensors to place and restore scenes. Scene generation requests do not contain camera frames, recordings or AR maps.

**Projects and media.** Projects, AR maps and recorded video are stored in the app container. You can delete a saved project from Library. Copies saved to Photos or shared with another application remain under your control in those applications; deleting the original project does not delete exported copies. Photos permission is requested when you choose to save a recording there.

**Microphone.** Recording with sound, the sound-level meter and spoken input use microphone permission. Video recording without sound does not use the microphone. The sound meter processes audio locally without saving an audio recording. A recorded take is saved locally and is transferred only through an export or share action you choose.

**Spoken input.** The app uses Apple Speech to turn speech into editable scene text. Apple may process microphone audio on its servers. The app does not send this audio to its Scene generation service. The recognized text follows the Scene text policy below if you submit it for generation.

**Scene text — select the paragraph matching the published configuration.**

- With remote Scene generation disabled, scene descriptions are processed locally and saved projects remain in the app's storage.
- With remote Scene generation enabled, the scene description, object references and clarification answers can be sent to the configured SET OS service and its AI provider to generate a scene. Before this profile is published, insert the actual operator, provider, processing region, policy URL/version and provider retention agreement, and require explicit transfer consent in the app. The app must not represent the local database retention tests as a promise about the provider.

**Service identifiers, remote profile.** Apple App Attest identifies an installation to authenticate requests and enforce quotas. Requests, generated content and job records can be associated with the same installation. The lack of an account does not make these records anonymous. They are used for service functionality and security, not advertising.

**Storage and deletion, remote profile.** The prepared SET OS working database clears raw request content at terminal state and completed result content after 14 minutes. Unfinished content, including unanswered clarification, has an absolute limit of 23 hours 59 minutes from creation. Startup/access checks and a sweep interval no longer than 30 seconds provide margins for the intended 15-minute/24-hour limits while the service operates. An authenticated delete of an owned completed job removes its content immediately. Content expiry or deletion does not launch a new generation or erase the original idempotency/quota record.

Job ownership, hashes, IDs, fixed version metadata and timestamps are retained for up to 30 days from creation. App Attest installation keys, replay counters and revocation state have a separate, currently non-expiring lifecycle. **The final public policy must state an approved security-identity retirement/deletion policy before release.** Local database retention does not establish provider, backup or host-log retention, or cleanup during host downtime. Those policies need the actual deployment evidence. Deleting a local project currently does not automatically invoke server deletion.

**Permissions.** Camera, microphone, speech recognition and Photos permissions can be changed in iOS Settings. Camera permission is separate from permission to send scene content to an AI service.

**Contact and changes.** [Owner: public support contact, operator identity, effective date and change notice procedure.] Do not publish this placeholder.

## Политика, RU

SET OS помогает планировать и записывать сцены. Учётная запись не требуется. В приложении нет рекламы и рекламного идентификатора; оно не отслеживает пользователя между другими приложениями и сайтами.

**Камера и AR.** Camera Coach анализирует кадры на устройстве. AR использует камеру и датчики движения для размещения и восстановления сцены. Кадры камеры, записи и карты AR не входят в запрос генерации сцены.

**Проекты и записи.** Проекты, карты AR и видео хранятся в контейнере приложения. Сохранённый проект можно удалить из библиотеки. Экспортированные в «Фото» и другие приложения копии управляются отдельно. Микрофон используется при записи со звуком, включении измерителя уровня звука и голосового ввода. Измеритель обрабатывает звук локально, не сохраняя аудиофайл. Запись без звука не использует микрофон.

**Голосовой ввод.** Apple Speech преобразует речь в редактируемый текст и может обрабатывать звук на серверах Apple. Звук не отправляется сервису генерации SET OS. Распознанный текст следует правилам обработки описания сцены, если его отправить на генерацию.

**Описание сцены.** При выключенной серверной генерации текст обрабатывается локально. При включённой описание, ссылки на объекты и ответы на уточнения могут передаваться сервису SET OS и его поставщику ИИ. До публикации этой конфигурации необходимо указать реального оператора, поставщика ИИ, регион, политику и сроки хранения и получить отдельное согласие пользователя перед передачей. Просмотр страницы приватности и разрешение на камеру таким согласием не являются.

**Идентификаторы и хранение.** В серверной конфигурации Apple App Attest связывает запросы с одной установкой приложения для авторизации, квот и безопасности. Отсутствие аккаунта не делает эти записи анонимными. Рабочая база подготовленного сервера удаляет исходный запрос при завершении, результат — через 14 минут, а незавершённое содержимое — не позднее 23 часов 59 минут с создания, с проверкой при запуске/обращении и интервалом очистки до 30 секунд. Это локально проверенный механизм для рабочего сервиса, а не доказательство условий внешнего поставщика ИИ, резервных копий или журнала хостинга.

Служебные сведения о заданиях хранятся до 30 дней с создания. Установка App Attest, счётчик защиты от повторов и состояние отзыва ключа имеют отдельный срок без автоматического удаления; его политика ещё требует завершения до публикации. Удаление локального проекта не удаляет серверный запрос автоматически. Разрешения можно изменить в настройках iOS.

**Контакт.** [Владелец: публичный контакт поддержки, оператор, дата вступления политики в силу и порядок уведомлений.] Не публиковать заглушку.

## Support copy

- No camera advice: some frames need no change, and uncertain observations can produce no advice. Check camera access and whether the lens is covered.
- No recorded sound: select recording with sound and allow microphone access. The sound meter and speech input also use the microphone when explicitly enabled.
- Spoken input unavailable: check microphone and Speech permissions; network availability may affect Apple Speech.
- Photos export failed: check add-only Photos permission and available storage. The saved take remains local when the export fails.
- An expired server result: the editable description remains. Starting generation again is an explicit new request; the app does not silently repeat it.
- Project deletion and exported copies: remove exported copies separately in Photos or the destination app.

## Evidence and release limits

The internal page includes preserved, complete notices for SnapKit, llama.cpp and five bundled fonts. Copying a notice is not evidence that a model, binary, asset or derivative dataset is cleared for distribution. Existing asset/model/llama binary admission gates remain unchanged.

The final local backend gate executed 353 tests with zero skips/failures/errors and 10 loopback HTTP checks, with unchanged source: `backend-content-retention-20260916/20260916T160603869364Z-receipt.json`, SHA-256 `9c1db4824e2626ba6fb02b13653a6db49df90bc622811df0fad0859b29a5f9be`. The reproducible extracted package has archive SHA-256 `c07e7495b5cf105bdc8f5b015a2bd8c25263ecc46c5eef3e495b2ddfa7040f39`. Its new snapshot v2 copies Scene metadata tombstones into a fresh database without inserting private content, including interrupted export. Extracted service smoke and independent snapshot verification passed. This qualifies new stopped-state snapshots; prior backups, provider storage, security-identity/spend lifecycles and a real production host remain separate.

The collection/linkage draft follows [Apple's App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/) and the [App Store Connect privacy guide](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), checked 2026-09-16. Apple distinguishes local processing, retained collection and linkage through a device. Applying those definitions to SET OS is documented as an engineering inference in `AppPrivacyAnswers.json`; it is not an already submitted declaration.

Final gates: deployed provider/host policy, security-identity lifecycle, explicit transfer consent, the manifest for the chosen remote profile, hosted policy/support, archive-bound source/configuration evidence and iPhone/iPad page acceptance. The current in-app server-storage wording deliberately does not promise an unverified external retention period.
