# 26. Source Generation Implement Verify Final

## Цель

Повторно проверить реализацию Track 4 после исправления findings из [25-source-generation-implement-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/25-source-generation-implement-verify.md).

Проверка выполнена против:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- [24-source-generation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/24-source-generation-design-verify.md)
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)

## Что перепроверено

- conditional ordinal requirement policy
- same-type marker disambiguation checks
- morphology-around-marked-object smoke coverage
- named-dialogue behavior without forced ordinal wording
- full local suite for `source_generation`

## Findings

Блокирующих findings не обнаружено.

Проверка подтвердила:
- ordinals теперь обязательны только в recoverability-sensitive cases, а не для любого `ordinal_map`
- named-dialogue path может генерироваться без искусственного `первый/второй`
- morphology-specific graph input теперь покрыт smoke test-ом
- Track 4 по-прежнему сохраняет ownership boundary с Track 6 через `needs_semantic_critic=true`

## Verification Notes

### Ordinal Policy

`required_ordinal_tokens` теперь вычисляются conditionally:
- explicit ordinal preservation
- actor-specific recoverability hints
- explicit ordinal-focused patterns
- unnamed 3-actor cases

Ключевые ссылки:
- [prompt_builder.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/prompt_builder.py#L268)
- [prompt_builder.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/prompt_builder.py#L421)

### Morphology Coverage

Smoke suite теперь включает graph record c `morphology_stress` variant и проверяет сохранение morphology surface anchor.

Ключевые ссылки:
- [test_source_generator_cli.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/tests/test_source_generator_cli.py#L108)

### Dialogue Recoverability

Named dialogue fixture проходит generation без forced ordinal wording и остаётся русскоязычным в heuristic smoke path.

Ключевые ссылки:
- [prompt_builder.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/prompt_builder.py#L41)
- [prompt_builder.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/prompt_builder.py#L367)
- [test_source_generator_cli.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/tests/test_source_generator_cli.py#L84)

## Verification Command

```bash
python3 -m unittest discover docs/SGv7pipeline/source_generation/tests -v
```

Result:
- `OK`
- `8` tests passed

## Verdict

Итог `implement verify`:
- implementation exists: `yes`
- prompt templates / batching / metadata / reject filters present: `yes`
- aligned with current Track 4 design and DoD: `yes`

Текущее состояние:
- source generation implementation ready
- remaining risks are non-blocking and belong mainly to future Track 5 / Track 6 integration depth
