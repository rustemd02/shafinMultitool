# Packet A1 — факты о лицензии кинокадров из первоисточников (2026-09-13)

Это **фактическая справка**, а не юридическое заключение и не решение: решение принимает владелец. Все цитаты приведены
дословно со страниц самих правообладателей, прочитанных в браузере 2026-09-13.

## Главное: два подмножества требуют разных решений

| Подмножество | Кадров в очереди | Что говорит издатель | Следствие |
|---|---|---|---|
| **Big Buck Bunny** (Peach) | 146 | «you can freely reuse and distribute this content, **also commercially**, as long you provide a proper attribution» | коммерческое переиспользование **разрешено издателем** при корректной атрибуции; остаётся подтвердить решение владельца по включению в продукт |
| **Tears of Steel + teaser** (Mango) | 167 + 6 | «the actors keep their **Personal Image (Portrait) and Privacy Rights**. That means the footage is OK to use for **technical demos, showcases, tutorials** etc. **But not to use the actor for making a commercial**» | издатель сам разграничивает дозволенное (демо, показы, туториалы) и недозволенное (коммерческое использование актёра) — это и есть предмет решения владельца |

То есть формулировка «подтвердить CC-BY» неточна: для BBB вопрос про атрибуцию, а для ToS — про права актёров.

## Условия лицензии CC BY 3.0 (дословно, creativecommons.org)

- **Share**: «copy and redistribute the material in any medium or format **for any purpose, even commercially**».
- **Adapt**: «remix, transform, and build upon the material for any purpose, **even commercially**».
- Правообладатель не может отозвать эти свободы, пока соблюдаются условия.
- **Attribution** (для версий до 4.0): «you must provide the name of the creator and attribution parties, a copyright
  notice, a license notice, a disclaimer notice, and a link to the material… **CC licenses prior to Version 4.0 also
  require you to provide the title of the material if supplied**».
- **No additional restrictions**.
- Собственная оговорка лицензии: «The license may not give you all of the permissions necessary for your intended use.
  For example, **other rights such as publicity, privacy, or moral rights may still limit how you use the material**».

Последняя оговорка — это ровно то, о чём говорит сайт Mango применительно к актёрам.

## Точная строка атрибуции, предписанная издателем (Big Buck Bunny)

Издатель задаёт варианты атрибуции; для **нашего** случая (переиспользование частей фильма) действует вариант 3:

> **(c) copyright 2008, Blender Foundation / www.bigbuckbunny.org**

Варианты 1 и 2 относятся соответственно к файлам с сайта/DVD-ROM («Blender Foundation | www.blender.org») и к показу
фильма целиком (нужен полный список титров). **Исключено из лицензии:** все логотипы (включая Blender и Creative
Commons) и связанные товарные знаки; обложка/полиграфия DVD. Значит логотипы нельзя класть в бандл.

Для Tears of Steel точная строка кредита на прочитанной странице **не опубликована** — я её **не выдумываю**: владельцу
нужно взять её из собственного кредита издателя (футер сайта или финальные титры) и внести в карту атрибуции.

## Что это меняет для решения владельца

1. Решение можно принять **раздельно** по подмножествам: BBB — включение в продукт с атрибуцией; ToS/teaser — как
   минимум исследовательское/демонстрационное использование, либо карантин.
2. Атрибуция обязана нести создателя, copyright notice, license notice, disclaimer, ссылку и название; логотипы и
   товарные знаки в бандл не попадают.
3. Решение фиксируется в `rights-attestation` (22 поля) и карте атрибуции; после этого активация — механическая:
   `validate_rights_attestation.py` → `emit_attribution_notices.py` → запись в `rights-manifest.jsonl` →
   `build_split_groups.py`.

## Границы

Прочитаны три официальные страницы (creativecommons.org/licenses/by/3.0/, peach.blender.org/about/,
mango.blender.org). Это **не** юридическое заключение и не проверка прав третьих лиц по каждому кадру; приватность и
права изображённых людей — отдельный вопрос, который поднимает сам издатель.
