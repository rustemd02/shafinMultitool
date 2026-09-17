# Privacy and support — release draft, not hosted or submitted

This draft accompanies `AppPrivacyAnswers.json` and the in-app **Privacy & licenses** page. The page is reachable from Library and from the entry screen before camera permission. Its Scene branch uses the configured parser; the separate Camera Cloud action is shown only for a configured client and accepted paused frame. Source and policy copy must be checked again in the final archived configuration and working UI.

The owner must provide the public policy/support URL, contact, effective date and actual service/operator identity. No URL or contact is invented here. Publication to App Store Connect remains the owner's action.

Scene and Camera now have explicit, request-bound transfer approval flows with endpoint/provider policy disclosures. Reading the information page or granting camera permission does not authorize either upload. Current checked build settings have an empty service URL and no Camera policy; the examined 19:51 archive is remote-disabled and predates the new Camera client. The following optional-flow copy requires the final service's actual operator, provider, region, retention and policy version before enablement. Implemented consent does not qualify those external facts.

## Policy body, EN

SET OS helps plan and record scenes. An account is not required. The app has no advertising and does not use an advertising identifier or track users across other apps and websites.

**Camera and AR.** Live Camera Coach analysis runs on the device. If online analysis is connected, you can separately choose one paused frame, review the exact image and service policy, and approve sending that image with its local analysis context. Faces, visible text and objects remain visible; location/EXIF metadata are removed and large images are reduced. This does not anonymize the image. Video and audio are not sent automatically. AR uses the camera and motion sensors to place and restore scenes. Scene generation requests do not contain camera frames, recordings or AR maps.

**Projects and media.** Projects, AR maps and recorded video are stored in the app container. You can delete a saved project from Library. Copies saved to Photos or shared with another application remain under your control in those applications; deleting the original project does not delete exported copies. Photos permission is requested when you choose to save a recording there.

**Microphone.** Recording with sound, the sound-level meter and spoken input use microphone permission. Video recording without sound does not use the microphone. The sound meter processes audio locally without saving an audio recording. A recorded take is saved locally and is transferred only through an export or share action you choose.

**Spoken input.** The app uses Apple Speech to turn speech into editable scene text. Apple may process microphone audio on its servers. The app does not send this audio to its Scene generation service. The recognized text follows the Scene text policy below if you submit it for generation.

**Scene text — select the paragraph matching the published configuration.**

- With remote Scene generation disabled, scene descriptions are processed locally and saved projects remain in the app's storage.
- With remote Scene generation enabled, the scene description, object references and clarification answers can be sent to the configured SET OS service and its AI provider to generate a scene. The app requires explicit approval of that request and its policy before obtaining a service token. Before publishing this profile, insert the actual operator, provider, region, policy URL/version and retention agreement. Local database tests are not a promise about the provider.

**Service identifiers, remote profile.** Apple App Attest identifies an installation to authenticate requests and enforce quotas. Requests, generated content and job records can be associated with the same installation. The lack of an account does not make these records anonymous. They are used for service functionality and security, not advertising.

**Storage and deletion, remote profile.** The prepared SET OS working database clears raw request content at terminal state and completed result content after 14 minutes. Unfinished content, including unanswered clarification, has an absolute limit of 23 hours 59 minutes from creation. Startup/access checks and a sweep interval no longer than 30 seconds provide margins for the intended 15-minute/24-hour limits while the service operates. An authenticated delete of an owned completed job removes its content immediately. Content expiry or deletion does not launch a new generation or erase the original idempotency/quota record.

Scene job ownership, hashes, IDs, fixed version metadata and timestamps are retained for up to 30 days from creation. The separate shared Scene/Camera expense ledger, Camera quota records and cancellation tombstones have no automatic expiry in the current implementation. App Attest security/replay and revocation records also remain after retirement. Final durations and the operator's policy for these retained categories must be stated separately; the Scene job lifetime is not a deadline for every server record.

**Selected-frame analysis, optional remote profile.** The prepared backend keeps the JPEG and analysis context in active request/provider-task memory rather than a durable image store. Its in-memory response cache has a maximum of 64 entries and 60-second expiry, cleared by access/maintenance or installation deletion. These implementation limits do not establish the external AI provider's storage, secondary use, logs or backup policy. Insert the actual provider terms and the image/request-record retention shown in the app's approval sheet before publishing this profile.

**Delete service content.** The Privacy page lets you confirm deletion for this installation. The service stops active Scene and Camera requests, clears stored Scene content and cached Camera responses, and retires service access. The app removes its local service credentials after validated completion. Server generation and online Camera analysis then remain disabled for this installation. Uncertain or expired receipts do not create a new success result. Security/replay, quota/idempotency and expense records remain under their disclosed policy; provider copies follow the provider's separate terms. Local projects/media and exported copies are not removed. Merely opening Privacy or deleting a local project does not send a server-deletion request. Deployed backups, recovery, logging and cleanup during host downtime still require separate qualification.

**Permissions.** Camera, microphone, speech recognition and Photos permissions can be changed in iOS Settings. Camera permission is separate from approval to send a Scene description or selected frame to an AI service. Cancelling an in-flight request stops local waiting and attempts bounded server cancellation; it is not a promise to erase content already received by a provider.

**Contact and changes.** [Owner: public support contact, operator identity, effective date and change notice procedure.] Do not publish this placeholder.

## Политика, RU

SET OS помогает планировать и записывать сцены. Учётная запись не требуется. В приложении нет рекламы и рекламного идентификатора; оно не отслеживает пользователя между другими приложениями и сайтами.

**Камера и AR.** Текущий разбор Camera Coach выполняется на устройстве. Если онлайн-анализ подключён, можно отдельно выбрать кадр на паузе, проверить именно отправляемое изображение и политику сервиса и разрешить передачу этого изображения с контекстом локального анализа. Лица, видимый текст и предметы сохраняются; геоданные и EXIF удаляются, большие изображения уменьшаются. Это не анонимизация изображения. Видео и звук автоматически не отправляются. AR использует камеру и датчики движения для размещения и восстановления сцены. Кадры, записи и карты AR не входят в запрос генерации сцены.

**Проекты и записи.** Проекты, карты AR и видео хранятся в контейнере приложения. Сохранённый проект можно удалить из библиотеки. Экспортированные в «Фото» и другие приложения копии управляются отдельно. Микрофон используется при записи со звуком, включении измерителя уровня звука и голосового ввода. Измеритель обрабатывает звук локально, не сохраняя аудиофайл. Запись без звука не использует микрофон.

**Голосовой ввод.** Apple Speech преобразует речь в редактируемый текст и может обрабатывать звук на серверах Apple. Звук не отправляется сервису генерации SET OS. Распознанный текст следует правилам обработки описания сцены, если его отправить на генерацию.

**Описание сцены.** При выключенной серверной генерации текст обрабатывается локально. При включённой описание, ссылки на объекты и ответы на уточнения могут передаваться сервису SET OS и его поставщику ИИ. Приложение запрашивает отдельное согласие на конкретный запрос и его политику до получения доступа к сервису. До публикации этой конфигурации необходимо указать реального оператора, поставщика ИИ, регион, политику и сроки хранения. Просмотр страницы приватности и разрешение на камеру таким согласием не являются.

**Идентификаторы и хранение.** В серверной конфигурации Apple App Attest связывает запросы с одной установкой приложения для авторизации, квот и безопасности. Отсутствие аккаунта не делает эти записи анонимными. Рабочая база подготовленного сервера удаляет исходный запрос при завершении, результат — через 14 минут, а незавершённое содержимое — не позднее 23 часов 59 минут с создания, с проверкой при запуске/обращении и интервалом очистки до 30 секунд. Это локально проверенный механизм для рабочего сервиса, а не доказательство условий внешнего поставщика ИИ, резервных копий или журнала хостинга.

Служебные сведения о заданиях Scene хранятся до 30 дней с создания. Отдельный общий журнал расходов Scene/Camera, записи квот Camera и запреты повторного запуска отменённых запросов сейчас не имеют автоматического срока удаления. Записи безопасности App Attest, защиты от повторов и отзыва доступа также сохраняются после отключения установки. Сроки и политика этих категорий должны быть указаны отдельно: срок задания Scene не распространяется на все серверные записи.

**Онлайн-анализ выбранного кадра.** Подготовленный сервер держит JPEG и контекст в памяти активного запроса, не записывая изображение в постоянное хранилище. Временный кэш ответов содержит не более 64 записей со сроком 60 секунд и очищается при обращении, обслуживании или удалении установки. Эти ограничения не определяют хранение, повторное использование, журналы или резервные копии внешнего поставщика ИИ. До публикации необходимо указать его реальные условия и сроки хранения изображения и записей запросов, показанные в окне согласия.

**Удаление данных из сервиса.** На странице приватности можно подтвердить удаление для этой установки. Сервис останавливает запросы Scene и Camera, удаляет сохранённое содержимое сцен и временные ответы Camera и отзывает доступ. После корректного подтверждения приложение удаляет локальные данные входа. Серверная генерация сцен и онлайн-анализ кадров после этого отключены для этой установки. Неопределённый исход или просроченное подтверждение не создают нового сообщения об успешном удалении. Записи безопасности, квот, защиты от повторов и расходов сохраняются по указанной политике; копии у провайдера — по его отдельным условиям. Локальные проекты, медиа и экспортированные копии не удаляются. Открытие страницы или удаление локального проекта не отправляет запрос удаления в сервис. Резервные копии, восстановление, журналы и очистку при остановленном сервере ещё требуется проверить в рабочем развёртывании.

**Разрешения.** Разрешения можно изменить в настройках iOS. Доступ к камере не означает согласия на передачу описания сцены или кадра ИИ-сервису. Отмена запроса прекращает ожидание и инициирует ограниченную по времени попытку отмены на сервере; она не гарантирует удаления уже полученных провайдером материалов.

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

The earlier Scene-content backend gate executed 353 tests with zero skips/failures/errors and 10 loopback HTTP checks, with unchanged source for that run: `backend-content-retention-20260916/20260916T160603869364Z-receipt.json`, SHA-256 `9c1db4824e2626ba6fb02b13653a6db49df90bc622811df0fad0859b29a5f9be`. Its reproducible extracted package has archive SHA-256 `c07e7495b5cf105bdc8f5b015a2bd8c25263ecc46c5eef3e495b2ddfa7040f39`. Snapshot v2 copies Scene metadata tombstones into a fresh database without inserting private content, including interrupted export. Extracted service smoke and independent snapshot verification passed for that package. This historical evidence does not qualify the later Camera endpoint or final combined source. Prior backups, provider storage, security-identity/spend lifecycles and a real production host remain separate.

The collection/linkage draft follows [Apple's App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/) and the [App Store Connect privacy guide](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), checked 2026-09-16. Apple distinguishes local processing, retained collection and linkage through a device. Applying those definitions to SET OS is documented as an engineering inference in `AppPrivacyAnswers.json`; it is not an already submitted declaration.

Final gates: deployed provider/host policy, security-identity lifecycle, explicit transfer consent, the manifest for the chosen remote profile, hosted policy/support, archive-bound source/configuration evidence and iPhone/iPad page acceptance. The current in-app server-storage wording deliberately does not promise an unverified external retention period.
