//
//  SceneRepairBoundary.swift
//  shafinMultitool
//
//  M5-027: the explicit semantic-repair boundary. Every deterministic
//  transformation the pipeline/compiler may apply is classified once,
//  here: syntax-safe normalizations that preserve meaning are allowed;
//  anything that invents, merges, reorders, or re-targets meaning is
//  forbidden and must go through clarification/regeneration instead.
//  Notes emitted by production code are audited against this registry
//  (unknown note codes fail the audit).
//

import Foundation

/// Classification of one deterministic transformation.
enum SceneRepairClass: String, Equatable, Sendable {
    /// Syntax-safe: ID/order/format normalization, meaning invariant.
    case safeNormalization
    /// Meaning-changing: requires clarification/regeneration.
    case forbiddenSemanticRepair
}

/// One registered transformation with its production note code.
struct SceneRepairEntry: Equatable, Sendable {
    let noteCode: String
    let repairClass: SceneRepairClass
    let description: String
}

/// The frozen M5-027 registry. Exhaustive over every note code the
/// production pipeline/compiler can emit (grep-audited); the audit
/// test fails on any unregistered code.
enum SceneRepairBoundary {
    static let entries: [SceneRepairEntry] = [
        // MARK: - Compiler (ScenePlanCompiler, safe: type-preserving downgrades with notes)
        SceneRepairEntry(
            noteCode: "v8.targetless_action_downgraded",
            repairClass: .safeNormalization,
            description: "Target-required action without a resolvable target compiles as stand with a note; actor, beat order, and remaining actions are untouched."
        ),
        SceneRepairEntry(
            noteCode: "v8.invalid_spatial_relation_skipped",
            repairClass: .safeNormalization,
            description: "Spatial relation with an unresolvable endpoint is dropped with a note; valid relations and all entities are untouched."
        ),

        // MARK: - V9 event-table repairs (safe: slot membership + type-preserving fixes)
        SceneRepairEntry(
            noteCode: "v9.action_type_repaired",
            repairClass: .safeNormalization,
            description: "Out-of-slot action type repaired to describedAction with preserved text; no new action invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.holding_slot_repaired",
            repairClass: .safeNormalization,
            description: "Holding reference rebound to the in-slot object; recipient and action type unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.target_slot_repaired",
            repairClass: .safeNormalization,
            description: "Target rebound to the in-slot entity; actor and action type unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.give_recipient_repaired",
            repairClass: .safeNormalization,
            description: "Give recipient inferred from the single unambiguous transfer partner in the same beat; ambiguous cases are left unresolved for clarification."
        ),
        SceneRepairEntry(
            noteCode: "v9.give_holding_repaired",
            repairClass: .safeNormalization,
            description: "Give holding rebound to the transferred object of the same beat; no object invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.pickup_holding_repaired",
            repairClass: .safeNormalization,
            description: "Pick-up holding rebound to the targeted object; no object invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.targetless_event_repaired",
            repairClass: .safeNormalization,
            description: "Targetless event given the beat-default target only when the beat declares exactly one candidate; otherwise left targetless with a note."
        ),
        SceneRepairEntry(
            noteCode: "v9.missing_target_for_object_action",
            repairClass: .safeNormalization,
            description: "Object action without a target keeps its type with a missing-target note for the validator; no target invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.described_text_repaired",
            repairClass: .safeNormalization,
            description: "Empty described-action text recovered from the source span; wording preserved verbatim."
        ),
        SceneRepairEntry(
            noteCode: "v9.unsupported_action_missing_text",
            repairClass: .safeNormalization,
            description: "Unsupported action without text keeps its describedAction type with a missing-text note; nothing invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.collective_action_expanded",
            repairClass: .safeNormalization,
            description: "Collective beat expanded into per-actor actions with identical type/target; actor set unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.collective_motion_materialized",
            repairClass: .safeNormalization,
            description: "Collective motion materialized per actor from the beat roster; no new actor introduced."
        ),
        SceneRepairEntry(
            noteCode: "v9.collective_pass_by_expanded",
            repairClass: .safeNormalization,
            description: "Collective pass-by expanded per actor pair; direction preserved."
        ),
        SceneRepairEntry(
            noteCode: "v9.collective_stop_near_object_expanded",
            repairClass: .safeNormalization,
            description: "Collective stop-near expanded per actor against the same object; object unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.reciprocal_motion_expanded",
            repairClass: .safeNormalization,
            description: "Reciprocal motion expanded into mirrored per-actor actions; no new entities."
        ),
        SceneRepairEntry(
            noteCode: "v9.dialogue_action_collapsed",
            repairClass: .safeNormalization,
            description: "Duplicate dialogue rows for one speaker collapsed into one action; wording preserved."
        ),
        SceneRepairEntry(
            noteCode: "v9.redundant_described_action_dropped",
            repairClass: .safeNormalization,
            description: "Described action duplicating a typed action dropped; typed action kept verbatim."
        ),
        SceneRepairEntry(
            noteCode: "v9.empty_described_beat_dropped",
            repairClass: .safeNormalization,
            description: "Beat with only empty described actions dropped; non-empty beats untouched."
        ),
        SceneRepairEntry(
            noteCode: "v9.dialogue_event_materialized",
            repairClass: .safeNormalization,
            description: "Dialogue event materialized from speaker cue with verbatim text; no paraphrase."
        ),
        SceneRepairEntry(
            noteCode: "v9.look_at_action_materialized",
            repairClass: .safeNormalization,
            description: "Look-at action materialized from gaze cue against the declared object; no target invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.transfer_action_materialized",
            repairClass: .safeNormalization,
            description: "Transfer action materialized from give/pick-up cues within one beat; parties unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.mentioned_marked_object_materialized",
            repairClass: .safeNormalization,
            description: "Mentioned marked object restored to the object roster from the binding snapshot; no new identity."
        ),
        SceneRepairEntry(
            noteCode: "v9.mentioned_object_restored",
            repairClass: .safeNormalization,
            description: "Mentioned object restored from anchors; type and name preserved."
        ),
        SceneRepairEntry(
            noteCode: "v9.object_alias_normalized",
            repairClass: .safeNormalization,
            description: "Object alias normalized to the canonical ID; referent unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.ambiguous_object_alias",
            repairClass: .safeNormalization,
            description: "Ambiguous alias left unresolved with a note for clarification; no guess committed."
        ),
        SceneRepairEntry(
            noteCode: "v9.beats_source_ordered",
            repairClass: .safeNormalization,
            description: "Beats ordered by source position; beat contents untouched."
        ),
        SceneRepairEntry(
            noteCode: "v9.described_action_speaker_prefix_stripped",
            repairClass: .safeNormalization,
            description: "Speaker prefix stripped from described text; remaining wording verbatim."
        ),
        SceneRepairEntry(
            noteCode: "v9.described_action_text_recovered",
            repairClass: .safeNormalization,
            description: "Described text recovered from the source span verbatim; no paraphrase."
        ),

        // MARK: - Diagnostic-only codes (no transformation; safe by construction)
        SceneRepairEntry(
            noteCode: "v9.beat_slot_mismatch",
            repairClass: .safeNormalization,
            description: "Diagnostic: event references a beat outside the slot catalog; row blocked, nothing rewritten."
        ),
        SceneRepairEntry(
            noteCode: "v9.collective_action_not_expanded",
            repairClass: .safeNormalization,
            description: "Diagnostic: collective beat left unexpanded for clarification; no expansion guessed."
        ),
        SceneRepairEntry(
            noteCode: "v9.collective_stop_near_not_expanded",
            repairClass: .safeNormalization,
            description: "Diagnostic: collective stop-near left unexpanded for clarification."
        ),
        SceneRepairEntry(
            noteCode: "v9.dialogue_action_collapsed",
            repairClass: .safeNormalization,
            description: "Diagnostic marker for collapsed dialogue rows (see safe expansion above)."
        ),
        SceneRepairEntry(
            noteCode: "v9.missing_event_for_beat",
            repairClass: .safeNormalization,
            description: "Diagnostic: beat without events flagged for clarification; no event invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.wrong_target_slot",
            repairClass: .safeNormalization,
            description: "Diagnostic: event targets a slot outside the catalog; row blocked."
        ),
        SceneRepairEntry(
            noteCode: "v9.max_rows_guardrail_applied",
            repairClass: .safeNormalization,
            description: "Diagnostic: row cap applied; excess rows dropped in source order with a note."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_provider_path_used",
            repairClass: .safeNormalization,
            description: "Diagnostic: V9 provider path taken; no transformation by itself."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_provider_unavailable_fallback_bridge",
            repairClass: .safeNormalization,
            description: "Diagnostic: provider unavailable, bridge fallback taken."
        ),
        SceneRepairEntry(
            noteCode: "v9.local_event_table_pipeline",
            repairClass: .safeNormalization,
            description: "Diagnostic: local event-table pipeline taken."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_ops_embedded_in_provider_payload",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch ops arrived inside the provider payload."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_applied",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry applied and gained coverage."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_attempted",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry attempted."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_disabled_live_demo",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry disabled for the live demo path."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_no_gain",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry attempted without coverage gain."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_unavailable",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry unavailable."
        ),
        SceneRepairEntry(
            noteCode: "v9.runtime_budget_exceeded_fallback_v8",
            repairClass: .safeNormalization,
            description: "Diagnostic: runtime budget exceeded, V8 fallback taken."
        ),
        SceneRepairEntry(
            noteCode: "v9.runtime_mode_v8_hotfix",
            repairClass: .safeNormalization,
            description: "Diagnostic: V8 hotfix runtime mode active."
        ),
        SceneRepairEntry(
            noteCode: "v9.duplicate_row_dropped",
            repairClass: .safeNormalization,
            description: "Diagnostic: duplicate event-table row dropped; first occurrence kept verbatim."
        ),
        SceneRepairEntry(
            noteCode: "v9.unknown_slot_blocked",
            repairClass: .safeNormalization,
            description: "Diagnostic: event referencing an unknown slot blocked; nothing rewritten."
        ),
        SceneRepairEntry(
            noteCode: "v9.max_actors_guardrail_applied",
            repairClass: .safeNormalization,
            description: "Diagnostic: actor roster truncated to the runtime cap in source order; kept actors untouched."
        ),
        SceneRepairEntry(
            noteCode: "v9.max_objects_guardrail_applied",
            repairClass: .safeNormalization,
            description: "Diagnostic: object roster truncated to the runtime cap in source order."
        ),
        SceneRepairEntry(
            noteCode: "v9.max_beats_guardrail_applied",
            repairClass: .safeNormalization,
            description: "Diagnostic: beat list truncated to the runtime cap in source order."
        ),
        SceneRepairEntry(
            noteCode: "v9.invalid_spatial_relation_skipped",
            repairClass: .safeNormalization,
            description: "Diagnostic: V9 spatial relation with an unresolvable endpoint skipped; valid relations untouched."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_op_unknown_row",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch op targeting an unknown row ignored; table unchanged."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_op_unknown_field",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch op with an unknown field ignored."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_op_invalid_value",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch op with an invalid value ignored."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_op_duplicate_row_id",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch op with a duplicate row ID ignored."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_failed",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry failed; prior table state kept."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_recovered",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry recovered coverage."
        ),
        SceneRepairEntry(
            noteCode: "v9.patch_retry_not_recovered",
            repairClass: .safeNormalization,
            description: "Diagnostic: patch retry did not recover coverage; prior state kept."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_table_max_tokens_reached",
            repairClass: .safeNormalization,
            description: "Diagnostic: event-table generation hit the token limit; partial table flagged, nothing invented."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_table_prompt_used",
            repairClass: .safeNormalization,
            description: "Diagnostic: event-table prompt path taken."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_table_retry_after_parse_failure",
            repairClass: .safeNormalization,
            description: "Diagnostic: event-table retry after a parse failure."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_table_retry_recovered",
            repairClass: .safeNormalization,
            description: "Diagnostic: event-table retry recovered."
        ),
        SceneRepairEntry(
            noteCode: "v9.event_table_verifier_issues_detected",
            repairClass: .safeNormalization,
            description: "Diagnostic: verifier issues detected on the event table; rows blocked, not rewritten."
        ),
        SceneRepairEntry(
            noteCode: "v9.input_canonicalized",
            repairClass: .safeNormalization,
            description: "Input text canonicalized (whitespace/case folding) before parsing; wording preserved."
        ),
    ]

    /// All registered codes.
    static var registeredCodes: Set<String> {
        Set(entries.map(\.noteCode))
    }

    /// Forbidden transformations. Empty today by construction: every
    /// production repair is syntax-safe, and the M5-024 closures
    /// (no default actor, no phantom actor_1, no fallback beats) are
    /// enforced by compiler errors, not notes. This set exists so a
    /// future meaning-changing repair has a typed home that the audit
    /// test routes to clarification.
    static var forbiddenCodes: Set<String> {
        Set(entries.filter { $0.repairClass == .forbiddenSemanticRepair }.map(\.noteCode))
    }
}
