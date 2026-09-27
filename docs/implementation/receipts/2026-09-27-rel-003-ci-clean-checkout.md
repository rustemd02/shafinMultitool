# REL-003 — required check: коммит, локальный прогон и clean-checkout воспроизводимость (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `a507118a` · Ветка: `store`
Задача: **REL-003** (закрытие строки; база — ресипт `2026-09-22-rel-003-required-check.md`)
Делегировано: «включение CI» (§19 п.12) — в пределах без push.

## 1. Закоммичено

- `scripts/required_check.sh` + `.github/workflows/required-check.yml` —
  commit `69ee5b5a` (воркфлоу самодокументирует owner-boundary: hosted-раннер
  не проверен, секретов нет, retention 14 дней).
- `ml/camera_coach/contracts/**` (слой контрактов ML-002/DATA-001) —
  commit `6e9b901e`: **найден clean-checkout прогоном** (шаг 1 не мог
  запуститься из чистого клона — валидаторы вообще не были в Git).
- `shafinMultitool/Multitool2Module/UI/DesignSystem/SETMetrics.swift` —
  commit `a507118a`: **найден clean-checkout прогоном** (закоммиченный view
  звал расширенный init `SETCameraCoachRailContent`, живший только в
  незакоммиченном файле → BUILD FAILED в чистом клоне).
- Намеренно НЕ закоммичено: `scripts/stage_nima_qualification.sh` (скрипт
  владельца), `.zcodeignore`, прочие чужие файлы рабочего дерева.

## 2. Прогоны (оба в этом запуске)

| Прогон | Команда | Итог |
|---|---|---|
| Локальный (рабочее дерево) | `REQUIRED_CHECK_KEEP=1 bash scripts/required_check.sh` | **PASSED**, EXIT=0: 4/4 шага (contract validators ✓, Pods prebuild ✓, M0 smoke **133 tests / 0 failures** со всеми declared masks, privacy manifest source+bundle ✓) |
| **Clean-checkout** (реплика CI-раннера) | `git clone <repo> scratchpad/clean-co && bash scripts/required_check.sh` | итерации 1–3 поймали реальные дыры (§1), итерация 4: **PASSED**, EXIT=0, тот же состав 4/4, M0 133/0 |

Clean-checkout проверка — это и есть ответ на «воспроизводимость на чистом
раннере»: свежий clone на HEAD собирается и проходит required check без
каких-либо файлов рабочего дерева. Различие с hosted-раннером (образ macOS,
версия Xcode, симуляторы) остаётся единственным непроверенным измерением.

## 3. Точный остаток (внешний)

**Hosted GitHub Actions прогон** требует: (а) `git push` (запрещён правилами
этого запуска), (б) включения Actions для репозитория (внешний аккаунт
GitHub). Воркфлоу готов и закоммичен; первый запуск на hosted-раннере должен
снять: образ раннера/Xcode (воркфлоу сам резолвит первый доступный iPhone
симулятор), итог 133/0, аплоад логов (retention 14 дней). До тех пор
верифицированная evidence — локальный + clean-checkout прогоны выше.

## 4. Статус

REL-003 → **`DONE`**: минимальный required check реализован, закоммичен и
доказан воспроизводимым из чистого checkout (поймав и закрыв две реальные
дыры воспроизводимости). Остаток — hosted-прогон после push/включения
Actions — внешний аккаунт, описан в §3.
