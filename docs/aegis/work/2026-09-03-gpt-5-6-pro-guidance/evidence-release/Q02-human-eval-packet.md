# Q02 — human evaluation packet (подготовка)

Дата: 2026-09-13. Ветка `store`, HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`.
Задача: runbook `docs/aegis/plans/2026-09-13-setos-release-execution.md`, карточка **Q02** (§9).
Метод: read-only анализ runbook, существующих capture/label/episode контрактов и annotation tooling;
созданы только docs-артефакты. App-код, `ml/**`, `tools/**`, `datasets/**`, `docs/cameraanalysis/**`,
`backend/**`, `project.pbxproj` и `docs/implementation/device-tests/**` (Q03) не тронуты.

## 1. Статус

| Срез | Статус |
|---|---|
| Подготовка (shot list + форма попытки + правила слепой оценки/adjudication) | **`needs_review`** |
| Сама human evaluation (реальные попытки, голоса, квоты, §5 human gates) | **`blocked_external`** |
| Причина | реальных участников/оценщиков нет; admitted корпусов 0; Q01 (интегрированный candidate) ещё `blocked`; D03 заблокирован правами (Packet A) |

Карточка Q02 прямо разрешает этот срез: «если нет людей — подготовка verified, сама оценка blocked_external».
Подготовка выполнена без имитации человеческих результатов.

## 2. Файлы

| Файл | sha256 | Зачем |
|---|---|---|
| `docs/implementation/human-eval/shot-list-v1.md` | `39f42954cbd92851396070d29661aac0b021c310325db69aed81072ac120360a` | Готовый перечень 10 условий съёмки (portrait, two objects, labels/glare, documentary no-staging, low light, wide-angle near face, hands/props, moving background, scene cut, lens switch): что снимать, что в кадре, валидная попытка, что аннулирует. |
| `docs/implementation/human-eval/attempt-record-schema.md` | `26921cb0fc13749549f7452e4604de4a77502a27ab471489897bd319d59874a1` | Форма фиксации реальной попытки (proposed/understood/executable/performed_change/before-after/intent/target-protected/latency/refusal), fail-closed правило неполноты, 5 измерений слепой оценки + причинная атрибуция, adjudication без большинства. |

Дополняют (не переписывают): `datasets/camera-coach/v1/capture-protocol.md`,
`annotation-guide.md`, `episode-schema.json` v1.0.0, `label-schema.json` v1.0.0.

## 3. Что владелец может выполнить по этому пакету без домысливания

1. **Спланировать реальные сцены** строго по `shot-list-v1.md` (SL-01…SL-10), включая consent/права изображённых
   людей; подготовить реальные до/после и объявить intent/target/protected до съёмки.
2. **После стабилизации Q01** снимать реальные попытки и заполнять `attempt-record-schema.md`; каждое поле —
   факт, неполные записи помечаются `incomplete` и никуда не засчитываются.
3. **Найти людей:** ≥3 независимых blind-ревьюеров + отдельного адъюдикатора; второй независимый аннотатор
   для human-gold. Владелец может быть одним аннотатором, но **не** двумя; ИИ-подсказки ревьюерами не считаются.
4. **Отдельно решить Packet A** (права на CC-BY кинокадры, attestation device pack, PD Commons, граница AVA),
   что открывает D03 → pilot → admitted corpus.
5. Запускать существующий annotation GUI (Packet B, `OWNER-PACKET.md`) — это development-инструмент
   и pre-pilot D03, **не** blind human-eval Q02.

Пока Q01 не стабилен, реальную съёмку Q02 начинать нельзя (зависимость карточки), но подготовка и вербовка
людей/права не блокируются.

## 4. Точная арифметика квот и gates

### 4.1. Квоты (§5.2 runbook / master §9.1, M4-024, M13-010)

| Артефакт | Нужно | Есть сейчас | Дефицит |
|---|---|---|---|
| Locked blind review cases | 350 | **0** | 350 |
| Blind review votes (350 × 3 независимых ревьюера) | **1 050** | **0** | 1 050 |
| Before/after episodes | 700 (100 × 7 классов) | **0** | 700 |
| Protected hard negatives | 350 (50 × 7 классов) | **0** | 350 |
| Locked physical guided sequences | 210 (30 × 7 классов, ≥2 tiers) | **0** | 210 |
| Gold-аннотация: независимых аннотаторов | 2 + адъюдикатор | **0** (0 голосов, 0 второго человека) | 2 + 1 |
| Hidden QC / adjudicated re-review | 5% / 10% | 0 | — |
| Cohen κ KEEP/CORRECT/ABSTAIN | ≥0.80 | **не вычислимо (0 голосов)** | — |
| Action family κ / forbidden agreement / ROI IoU / hidden QC | ≥0.75 / ≥0.90 / ≥0.80 / ≥95% | **не вычислимо** | — |

Владелец + подсказки ИИ **не** дают второго независимого аннотатора: assisted-голоса технически исключаются
(`tools/camera_annotation/pilot_agreement_report.py`), поэтому 1050 голосов нельзя получить «ускорением» одним
человеком. Числа 350/700/350/210 — плановые минимумы; ни одно не закрыто и не заявляется закрытым.

### 4.2. Gates, которые остаются непройденными

- §5.1 human blind gates: safe+executable ≥0.90, helpful ≥0.80, preference among non-ties ≥0.60,
  materially harmful ≤0.01, critical harm = 0 — знаменатель 0, статус **NOT PASSED / `blocked_external`**.
- §5.2 gold gate (два независимых аннотатора + adjudicator, κ≥0.80 и т.д.) — **открыт**.
- M3-022 / **M3-GATE** (human-gold Camera/Scene infrastructure) — открыт.
- **M4-024** (350 locked cases × 3 reviewers) / **M4-GATE** — `blocked_external`.
- **M13-010** (210 locked physical guided sequences, DEVICE+HUMAN) / **M13-GATE** — `blocked_external`.
- **Q02 gate** («настоящие голоса и real action evidence») — открыт.
- **M15-GATE** — не пройден; зависит от M13/Q02/Q04.

Проверено: ни в `docs/implementation/release/AppStoreSubmissionGates.json`, ни в `evidence-release/**`
ни один human/device blind gate не помечен `satisfied`/`passed`/`verified`; физический device gate имеет
статус `blocked`. Единственное совпадение по слову «human» — контрактный токен `human_preference`
в P01 (не gate).

## 5. Как в пакете исключена имитация

Явно запрещено и не выполнено:

- заполнять опросы/оценки/карточки от лица реальных людей; выдумывать участников, оценки, κ, квоты;
- считать AI-подсказки независимым оценщиком; выдавать владельца за двух независимых аннотаторов
  (owner + AI hints ≠ two independent annotators);
- помечать любой human gate пройденным; всё человеческое помечено `blocked_external` с причиной;
- считать `visually_improved` без `attribution=action_caused` успехом совета
  (правило: «красивый after по другой причине не является доказательством успешного совета»);
- усреднять разногласия голосованием большинства — только adjudication по протоколу;
- истребовать причину отказа: `refusal_reason=not_provided` — полноценное значение;
- импутировать пропущенные поля; неполная запись → `incomplete`, вне квот и gates.

## 6. Честно НЕ сделано

- Нет ни одной реальной записи попытки (`0`), ни одного голоса (`0`), ни одной blind-сессии.
- Квоты 1050/700/350/210 и §5 human gates не закрыты и не могут быть закрыты подготовкой.
- Нет машинного валидатора/JSON Schema в `tools/**` (запрещено заданием): проверяемость обеспечена
  точным перечнем полей и детерминированным fail-closed правилом `record_status=complete` (§3
  `attempt-record-schema.md`); при появлении кода он должен быть согласован с существующими
  episode/label контрактами.
- Нет второго независимого аннотатора/ревьюеров и нет admitted media для реальных попыток (D01 Packet A).
- Q02 как gate **не** пройден; статус передачи — `needs_review` (подготовка) + `blocked_external` (оценка).

## 7. Воспроизводимость проверки

```sh
# состав пакета
ls -la docs/implementation/human-eval/
shasum -a 256 docs/implementation/human-eval/shot-list-v1.md docs/implementation/human-eval/attempt-record-schema.md
# квоты: human-votes сейчас 0 (в сторе только очереди, без labels)
ls -la "$HOME/Library/Application Support/SETOS/annotation/"
# admitted/human_gold = 0
grep -rl '"human_gold": true' "$HOME/Library/Application Support/SETOS/Datasets" | wc -l   # 0
# ни один human gate не помечен пройденным
python3 -c "import json;d=json.load(open('docs/implementation/release/AppStoreSubmissionGates.json'));print([(g['n'],g['status']) for g in d['gates'] if 'физическ' in g['gate'].lower()])"
```
