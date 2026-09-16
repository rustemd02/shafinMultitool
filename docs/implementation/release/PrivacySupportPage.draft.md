# Privacy policy and support page (draft, not hosted, not submitted)

- Status: `draft` / `owner_required`. Nothing here is published, and gate 5 of the
  product plan (`Privacy Policy URL and in-app policy`) remains **blocked** until a
  hosted URL exists.
- Facts in this draft come from `docs/implementation/provenance/data-flows.md` and
  `docs/implementation/release/AppPrivacyAnswers.json`, not from marketing copy.
- The app has **no About/Settings screen** today. An in-app entry for this page still
  has to be created by the UI owner; the strings below are ready to paste.

## Privacy policy (hosted-page body, EN)

Shafin Multitool is a camera coach. This policy describes what the app does with
your data in the version distributed on the App Store.

**No account, no tracking.** The app has no sign-in and no account. It contains no
advertising, attribution or analytics SDK, does not use the advertising identifier,
and does not track you across apps or websites.

**Camera and on-device analysis.** When you use Camera mode, frames are analysed on
your device (Apple Vision and bundled Core ML models). The app does not upload your
camera frames to us.

**Recording and photos.** Recording with sound writes the video and audio to the
app's private storage on your device. When you export a finished video, it is saved
to your photo library (add-only access). We do not receive it.

**Spoken input (Speech).** If you use spoken scene input, the microphone audio is
processed by Apple's Speech service, which may receive the audio on Apple's servers.
We do not receive or store that audio. You can turn the feature off at any time by
revoking Speech or Microphone permission in iOS Settings.

**Scene text.** Written scene descriptions and the scenes built from them are stored
on your device. In this configuration nothing is sent to a server: the remote Scene
provider is disabled unless a deployment explicitly configures it, and the remote
visual-evidence feature does not exist in release builds.

**Data we collect.** In this configuration we collect no personal data from the app.
If a future version enables a server-backed Scene feature, this policy and the App
Store privacy answers will be updated before that version ships.

**Children.** The app is not directed at children.

**Contact.** [OWNER: support email or support URL required here.]

**Changes.** [OWNER: effective date and change procedure required here.]

## Support page (EN)

- **Camera shows no advice.** Silence is intentional: when the app is not confident it
  shows nothing rather than a guess. Make sure Camera permission is allowed in
  iOS Settings and that the lens is not covered.
- **Recording has no sound.** Check Microphone permission; audio is only captured
  while a recording is running.
- **Spoken input does not work.** Check Microphone and Speech permissions. Speech is
  processed by Apple and needs a network connection.
- **Export to Photos fails.** Check Photos add-only permission.
- **Contact.** [OWNER: support email / URL.]

## Privacy policy (RU) — краткая версия для страницы

Приложение «Shafin Multitool» — коуч по кадру. Учётной записи нет, рекламных и
аналитических SDK нет, отслеживания между приложениями нет. Кадры камеры
обрабатываются на устройстве и не отправляются нам. Запись видео и звука хранится
в приватном хранилище приложения; при экспорте вы сохраняете её в свою медиатеку
(доступ только на добавление). При голосовом вводе звук обрабатывает сервис Apple
Speech и может передаваться на серверы Apple — мы этот звук не получаем и не храним;
отозвать доступ можно в настройках iOS. Текст сцены и построенные сцены хранятся на
устройстве; в этой конфигурации удалённый сервис сцен выключен. Персональные данные
приложение не собирает. Контакт: [ВЛАДЕЛЕЦ: укажите почту/URL поддержки].

## In-app screen spec (for the UI owner)

- One reachable row/sheet titled "Privacy & Support" (RU: «Приватность и поддержка»).
- Content: the policy body above plus the support list and a "Contact" link.
- If a hosted policy URL exists, also expose it via `Link`; until then the in-app text
  must be the source of truth.
- Add localized strings through the existing String Catalog
  (`shafinMultitool/Resources/Localizable.xcstrings`); do not hard-code.
- Accessibility: VoiceOver labels for the row and the sheet close control; Dynamic
  Type must not clip the policy text.

## Honest status

- No hosted URL, no support URL, no in-app screen: all `owner_required`.
- The policy text is factually derived, but it is a draft and has not been reviewed
  legally or entered into App Store Connect.
