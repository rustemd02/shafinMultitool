# Reviewer/Red-Team Agent

## proposal
- Подтверждён фикс совместимости `rowId/rowID` в Swift Codable + LLM decode/grammar path. Оставить `rowId` каноническим wire-ключом и поддерживать `rowID` только как legacy decode alias.
- Подтверждён фикс guardrail contamination: в `v8_hotfix` mode guardrails больше не применяются.
- Подтверждён фикс patch-retry semantics в `applyV9Full`:
  - retry идёт через `generateEventPatchOps(...)`,
  - provider `patchOps` не применяются повторно.
- Дальше усилить контроль semantic fidelity:
  - сохранить явную классификацию repair-путей в runtime+eval:
  - `structural repair` (schema/slot hygiene),
  - `semantic degradation` (targetless downgrade, row drop, target nulling).
- Закрепить правило отчётности:
  - verifier-derived метрики только как `*_structural_pass_rate`;
  - `*_accuracy` только against gold.
- Для V9-Full оставить hard requirement на parity-проверки поведения, не только JSON:
  - actor intent,
  - target binding,
  - beat ordering в playback.
- Закрыть оставшийся runtime semantic drift:
  - `compileToPlan` сейчас всё ещё переносит `spatialRelations` из `originalPlan` без полной reconciliation с repaired event rows.

## risks
- **High: silent semantic repair**
  - `target_required_missing -> stand` повышает валидность, но тихо убивает intent/trajectory.
- **Resolved: cross-contract mismatch (`rowId` vs `rowID`)**
  - После фикса это больше не top-risk; оставить regression tests, чтобы не вернулось.
- **High: misleading eval perception (residual)**
  - Несмотря на появление semantic block, benchmark-пайплайн всё ещё может интерпретироваться как structural-first без product behavior guarantees.
- **Medium: runtime behavior drift (residual)**
  - Repaired actions + legacy `spatialRelations` из original plan потенциально конфликтуют.
- **Resolved: retry semantics ambiguity**
  - retry теперь patch-only; риск double-apply provider patchOps снят.
- **Medium: overfitting to synthetic corruption**
  - Corruption diversity улучшена, но всё ещё ограничена узким набором стратегий и one-shot corruption per sample.

## required_tests
- **Contract conformance tests (critical)**
  - Единый golden test для `sg_v9_event_table_v1` и `sg_v9_patch_ops_v1` с каноническим `rowId` и legacy decode `rowID`.
  - Roundtrip: Python->JSON->Swift->JSON->Python без потери row identity.
- **Guardrail isolation test**
  - В mode=`v8_hotfix` ни один `v9.*guardrail*` reason не должен появляться.
- **No-silent-repair audit**
  - Для каждого semantic degradation reason (`targetless`, dropped row, target/holding null) обязательна трасса в:
    - runtime diagnostics,
    - compiled artifacts (`slice_reason_codes`),
    - aggregate counters.
- **Semantic-vs-structural separation**
  - Кейс, где structural pass = true, semantic accuracy < 1.0 (перепутанные actor/target).
  - Кейс с repaired targetless action: structural growth при зафиксированном semantic degradation increment.
- **Runtime edge-cases**
  - Budget exceeded => deterministic `v9.runtime_budget_exceeded_fallback_v8`.
  - Provider unavailable/main-thread guard => явный fallback trace без silent mode confusion.
  - Retry path: максимум 1 retry, patch-only, no infinite loop, deterministic reason codes.
- **Behavioral parity suite (demo gate blocker)**
  - `dialogue + motion + marked object`
  - `навстречу -> оба к объекту`
  - `collective stop near object`
  - `described_action` отдельно от dialogue в UI, без потери action text.

## open_conflicts
- Граница “V9-Full ready” всё ещё не может быть закрыта только кодом без parity/eval evidence.
- Policy на допустимый уровень semantic degradation не зафиксирован численно (blocking threshold).
- Compile semantics conflict (`originalPlan.spatialRelations` vs repaired event actions) не снят.

## gate_votes
- `contract_gate`: **YES (for V9-Full, conditional)**  
  Rationale: `rowId/rowID` compatibility gap закрыт; требуется только regression guard against reintroduction.
- `data_gate`: **IN_REVIEW / NO-PASS**  
  Rationale: текущие фиксы не закрывают leakage/overfitting и threshold policy; нужны данные/eval evidence.
- `runtime_gate`: **YES (for V9-Bridge), IN_REVIEW (for V9-Full)**  
  Rationale: guardrail contamination и patch-retry bug исправлены; остаётся semantic drift в compile relations и нет parity evidence.
- `eval_gate`: **NO-PASS**  
  Rationale: без полного evidence-пакета semantic fidelity vs structural recovery gate закрывать рано.
- `demo_gate`: **NO-PASS**  
  Rationale: нет принятого real-app parity evidence с adversarial coverage.
