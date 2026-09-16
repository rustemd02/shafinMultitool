# Форма решения владельца — права на кинокадры (Packet A1)

Это **форма для вас**, а не заключение и не рекомендация. Инструмент ничего не выбирает за вас: любое
пустое/плейсхолдерное значение (`<...>`, `PENDING`, `null`, `""`) означает «не решено», и конвертер
**откажет**, ничего не записав. Никакое значение по умолчанию не подставляется.

Факты о лицензии уже установлены и при необходимости берутся конвертером из
`datasets/camera-coach/v1/cinematic-license-facts.draft.json` **с указанием провенанса**; это факты, а не
решения. Спорные строки (например, кредит Tears of Steel) там намеренно пусты — их вписываете вы.

Ответить можно за пару минут: заполните 4 блока ниже текстом **или** сразу JSON-скелет из раздела 6 и
передайте его конвертеру.

---

## 1. Кто заявляет (attester)

| поле | что это | ваш ответ |
|---|---|---|
| `attester.attester_id` | короткий идентификатор того, кто принимает решение | |
| `attester.attester_name` | имя / юридическое имя | |
| `attester.attester_role` | роль (например, `dataset-owner`) | |
| `attester.attester_contact` | контакт (необязательно) | |
| `attested_at` | дата решения, `YYYY-MM-DD` | |

## 2. Решение по каждому подмножеству

Подмножества решаются **раздельно** — у них разные условия у издателя. Отметьте одно решение и, если
выбрали `admit`, один вариант области.

### 2.1 Big Buck Bunny (`big_buck_bunny`, 146 кадров)

Издатель (peach.blender.org/about/) разрешает переиспользование и распространение, в том числе
коммерческое, при корректной атрибуции. Точная строка атрибуции для нашего случая (переиспользование
частей) уже установлена как факт: `(c) copyright 2008, Blender Foundation / www.bigbuckbunny.org`.

| выбор | что означает |
|---|---|
| `decision` = `admit`, `scope` = `train+eval` | кадры можно использовать для обучения/калибровки/оценки; в релизный бандл они **не** попадают |
| `decision` = `admit`, `scope` = `train+eval+release` | кадры можно вложить в релизный бандл (потребуется полная атрибуция и основание со ссылкой/`sha256`) |
| `decision` = `quarantine` | подмножество не допускается; обучение/релиз с ним заблокированы |
| `decision` = `reject` | подмножество исключается из рассмотрения |

Ваш выбор: `decision` = ____________ , `scope` = ____________ (scope нужен только для `admit`).

### 2.2 Tears of Steel (`tears_of_steel`, 167 кадров)

Издатель (mango.blender.org) прямо оговаривает: актёры сохраняют **Personal Image (Portrait) и Privacy
Rights**; съёмку можно использовать для технических демо, показов и туториалов, но **не** для
коммерческого использования актёра. Точная строка кредита на прочитанной странице не опубликована — её
**нельзя выдумывать**: если вы допускаете `release`, впишите её сами (кредит издателя / финальные титры).

| выбор | что означает |
|---|---|
| `decision` = `admit`, `scope` = `train+eval` | только исследование/обучение/калибровка/демо; в релизный бандл не попадает |
| `decision` = `admit`, `scope` = `train+eval+release` | в релизный бандл — только если вы подтверждаете права актёров и даёте строку кредита |
| `decision` = `quarantine` | не допускается |
| `decision` = `reject` | исключается из рассмотрения |

Ваш выбор: `decision` = ____________ , `scope` = ____________ (scope нужен только для `admit`).

### 2.3 Tears of Steel — teaser (`tos_teaser`, 6 кадров)

Те же условия издателя, что и для полнометражного фильма (те же актёры и права). Отсутствие этих 6 кадров
в очереди разметки — отдельное наблюдение (очередь создана раньше их добавления), не решение.

Ваш выбор: `decision` = ____________ , `scope` = ____________ (scope нужен только для `admit`).

## 3. Основание решения (basis) — по каждому подмножеству

Заполняется для любого решения (и для `quarantine`/`reject` — кратко, зачем).

| поле | что это |
|---|---|
| `basis.basis_type` | одно из: `license`, `written_permission`, `public_domain`, `owner_authorship`, `synthetic_lineage`, `other` |
| `basis.basis_reference` | ссылка/описание основания своими словами |
| `basis.basis_url` **или** `basis.basis_sha256` | обязательно, если допускаете с `production_allowed=true` или `scope` содержит `release` |

## 4. Разрешения и люди — по каждому подмножеству, которое вы допускаете

| поле | что это |
|---|---|
| `permissions.production_allowed` | `true`/`false`: могут ли эти кадры питать production-веса |
| `permissions.redistribution_allowed` | `true`/`false`: можно ли распространять сами медиа |
| `permissions.derived_media_allowed` | `true`/`false` (необязательно): можно ли производные медиа |
| `people.people_present` | `true`/`false`: есть ли в кадре узнаваемые люди |
| `people.consent_obtained` | `true`/`false`: получено ли согласие (или неприменимо) |
| `people.consent_reference` | ссылка на согласие или строка `not_applicable` |

## 5. Карта атрибуции — по каждому фильму, который вы допускаете

| поле | что это |
|---|---|
| `author` | **обязательно и только от вас**: в манифесте нет поля `author`, и инструмент не выводит его из названия или лицензии |
| `attribution_string` | строка кредита. Для Big Buck Bunny берётся из фактов, если вы её не указали; для Tears of Steel/teaser её нужно взять из кредита издателя (в фактах её нет). Обязательна, если в scope есть `release` |
| `license_url` / `source_url` | можно не дублировать: конвертер возьмёт установленные факты с провенансом |
| `author_url`, `title` | необязательно |

## 6. JSON-скелет (эквивалент блокам 1–5)

Скопируйте и заполните. Ключи подмножеств — это ключи фильмов из карты атрибуции
(`big_buck_bunny`, `tears_of_steel`, `tos_teaser`).

```json
{
  "schema_id": "camera-owner-decisions-v1",
  "attester": {
    "attester_id": "<кто заявляет>",
    "attester_name": "<имя>",
    "attester_role": "<роль>",
    "attester_contact": "<контакт, необязательно>"
  },
  "attested_at": "<YYYY-MM-DD>",
  "corpus": {
    "corpus_id": "cinematic",
    "source_id": "cinematic",
    "manifest_sha256": "<нужно, если не передаёте --manifest>"
  },
  "subsets": {
    "big_buck_bunny": {
      "decision": "<admit|quarantine|reject>",
      "scope": "<train+eval|train+eval+release>",
      "permissions": {
        "production_allowed": null,
        "redistribution_allowed": null,
        "derived_media_allowed": null
      },
      "people": {
        "people_present": null,
        "consent_obtained": null,
        "consent_reference": "<ссылка или not_applicable>"
      },
      "basis": {
        "basis_type": "<license|written_permission|public_domain|owner_authorship|synthetic_lineage|other>",
        "basis_reference": "<основание>",
        "basis_url": "<ссылка>",
        "basis_sha256": "<или sha256>"
      }
    },
    "tears_of_steel": { "decision": "", "scope": "", "permissions": {}, "people": {}, "basis": {} },
    "tos_teaser":     { "decision": "", "scope": "", "permissions": {}, "people": {}, "basis": {} }
  },
  "attribution_map": {
    "provided_by": "<кто предоставил>",
    "entries": [
      { "film_key": "big_buck_bunny", "author": "<автор от вас>", "attribution_string": "", "source_url": "" },
      { "film_key": "tears_of_steel", "author": "<автор от вас>", "attribution_string": "<кредит издателя>", "source_url": "" },
      { "film_key": "tos_teaser",     "author": "<автор от вас>", "attribution_string": "<кредит издателя>", "source_url": "" }
    ]
  }
}
```

`scope`, `permissions`, `people` нужны только для `admit`; для `quarantine`/`reject` достаточно
`decision` и `basis`. `license` можно не указывать — он берётся из фактов.

## 7. Что произойдёт дальше

```bash
# 1) превратить ответы в подтверждение и карту атрибуции
python3 tools/datasets/attestation_from_decisions.py \
  --decisions <ваш-файл.json> \
  --manifest <путь-к-manifest.jsonl> \
  --attestation-out <attestation.json> \
  --attribution-map-out <attribution-map.json>

# 2) проверить подтверждение
python3 tools/datasets/validate_rights_attestation.py --attestation <attestation.json> --print-missing

# 3) дописать допущенную запись в datasets/camera-coach/v1/rights-manifest.jsonl (только если всё сошлось)
python3 tools/datasets/attestation_from_decisions.py ... --append-manifest
```

Конвертер откажет (exit 1) и **ничего не запишет**, если:

- хотя бы одно решение пусто/плейсхолдер;
- `production_allowed=true` или `release` в scope без основания (`basis_reference` и `basis_url`/`basis_sha256`);
- AVA/AADB/EVA помечены допущенными/production-разрешёнными (противоречит аудиту D01/D05);
- для допускаемого фильма нет записи в карте атрибуции;
- `attribution_string` пуст, а в scope есть `release`.

Без флага `--append-manifest` конвертер печатает точную следующую команду и **ничего** не дописывает в
`datasets/camera-coach/v1/rights-manifest.jsonl`. Exit 2 — если файл решений отсутствует или не парсится.

Правовые границы: `PacketA-license-facts.md` и `cinematic-license-facts.draft.json` — это факты из
первоисточников, не юридическое заключение. Логотипы и товарные знаки исключены из лицензии и в бандл не
попадают. Приватность и права изображённых людей поднимает сам издатель; решение по ним — ваше.
