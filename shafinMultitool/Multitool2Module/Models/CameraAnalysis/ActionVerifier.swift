//
//  ActionVerifier.swift
//  shafinMultitool
//
//  M2-025 VerificationOwner: pure before/after action verification.
//
//  C04.2 (runbook 2026-09-13): the verifier follows the N7 order — scope and
//  identity of the commanded object first, then protected refs, then the
//  effect delta/deadband. A measured motor delta alone never yields
//  `improved`; only a change of the same entity the advice addressed does.
//  Expected absence (removal) needs explicit, owner-supplied evidence, and an
//  unknown operation/metric stays `unsupported`/`incomparable`.
//

import CoreMedia
import Foundation

/// Verifies one immutable episode pair after `CoachingEpisodeCoordinator` has
/// reached `readyForVerification`. This type owns no lifecycle, clock, task,
/// or presentation state; all temporal admission remains with the coordinator.
enum ActionVerifier {

    /// Compares the exact baseline and final stable frame in `input`.
    ///
    /// The existing `UserMovementObserver` remains the single action mapping,
    /// deadband, direction and freshness owner. This verifier adds only the
    /// before/after contract, objective fixed predicates, target-scoped
    /// observation and fail-closed provenance checks.
    static func verify(_ input: ActionVerificationInput) -> ActionVerificationResult {
        let actionID = input.actionID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !actionID.isEmpty else {
            return result(input, decision: .incomparable(reason: .emptyAction))
        }

        let family = UserMovementObserver.actionFamily(for: actionID)
        let isRemovalAction = actionID == SemanticActionType.removeDistractingObject.rawValue
        let declaresAbsence = !input.scope.expectedAbsenceRefs.isEmpty

        // N7: `expectedAbsenceRefs` belongs to `exclude_entity` only. Any
        // other operation declaring it is an invalid payload, not a removal.
        if declaresAbsence && !isRemovalAction {
            return result(
                input,
                decision: .incomparable(reason: .expectedAbsenceUnverified),
                reasonCode: .contextChanged
            )
        }
        // `exclude_entity` without declared expected absences cannot be
        // verified; the legacy removal string has no honest movement feature.
        if family == nil && !(isRemovalAction && declaresAbsence) {
            return result(
                input,
                decision: .incomparable(reason: .unsupportedAction),
                reasonCode: .unsupportedVerifier
            )
        }
        if isRemovalAction && !declaresAbsence {
            return result(
                input,
                decision: .incomparable(reason: .expectedAbsenceUnverified),
                reasonCode: .missingEvidence
            )
        }

        let beforeID = input.before.frameID.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterID = input.after.frameID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beforeID.isEmpty, !afterID.isEmpty else {
            return result(input, decision: .incomparable(reason: .frameIdentityMissing))
        }
        guard beforeID != afterID else {
            return result(input, decision: .incomparable(reason: .duplicateFrame))
        }

        guard let beforeEvidence = input.before.evidence,
              let afterEvidence = input.after.evidence else {
            return result(input, decision: .incomparable(reason: .evidenceMissing))
        }
        guard beforeEvidence.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              afterEvidence.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              beforeEvidence.evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              afterEvidence.evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              beforeEvidence.capturedAt <= beforeEvidence.evaluatedAt,
              afterEvidence.capturedAt <= afterEvidence.evaluatedAt else {
            return result(input, decision: .incomparable(reason: .evidenceTimeInvalid))
        }
        guard beforeEvidence.hasValidSampleProvenanceShape,
              afterEvidence.hasValidSampleProvenanceShape else {
            return result(input, decision: .incomparable(reason: .evidenceMissing))
        }
        if beforeEvidence.hasKnownSampleProvenance || afterEvidence.hasKnownSampleProvenance {
            guard beforeEvidence.hasKnownSampleProvenance,
                  afterEvidence.hasKnownSampleProvenance,
                  beforeEvidence.sessionGeneration == afterEvidence.sessionGeneration,
                  CMTimeCompare(
                      afterEvidence.samplePresentationTimestamp,
                      beforeEvidence.samplePresentationTimestamp
                  ) > 0 else {
                return result(input, decision: .incomparable(reason: .outOfOrder))
            }
        } else {
            // Legacy synthetic evidence has no sample PTS/session epoch. It
            // keeps the historical Date ordering explicitly, but can never
            // overtake a known production tuple above.
            guard afterEvidence.capturedAt > beforeEvidence.capturedAt else {
                return result(input, decision: .incomparable(reason: .outOfOrder))
            }
        }

        // Extract the observer-owned finite measurement before applying the
        // higher-level confounder guards. A blocked decision must still retain
        // diagnostics when the immutable pair itself contains a measurable
        // before/after change; diagnostics never override the blocker.
        let targetRefs = input.scope.targetRefs
        let comparison = UserMovementObserver.compareAtOwnEvaluationTimes(
            previous: input.before,
            current: input.after,
            actionID: actionID,
            targetRefs: targetRefs
        )
        let diagnosticDelta = metricDelta(for: comparison)
        let diagnosticDeltas = diagnosticDelta.map { [$0] } ?? []

        // A production input must carry both lifecycle snapshots. Without the
        // pair, lens/route ownership cannot be compared honestly.
        guard let beforeLifecycle = input.beforeLifecycle,
              let afterLifecycle = input.afterLifecycle else {
            return result(
                input,
                decision: .incomparable(reason: .lifecycleUnavailable),
                deltas: diagnosticDeltas
            )
        }
        guard input.token.generation != 0,
              beforeLifecycle.generation == input.token.generation,
              afterLifecycle.generation == input.token.generation,
              beforeEvidence.lensGeneration == input.token.generation,
              afterEvidence.lensGeneration == input.token.generation else {
            return result(
                input,
                decision: .incomparable(reason: .tokenMismatch),
                deltas: diagnosticDeltas
            )
        }
        guard beforeLifecycle.generation == afterLifecycle.generation else {
            return result(
                input,
                decision: .incomparable(reason: .generationMismatch),
                deltas: diagnosticDeltas
            )
        }
        guard beforeLifecycle.orientation == afterLifecycle.orientation,
              beforeEvidence.orientation == beforeLifecycle.orientation,
              afterEvidence.orientation == afterLifecycle.orientation else {
            return result(
                input,
                decision: .incomparable(reason: .orientationMismatch),
                deltas: diagnosticDeltas
            )
        }
        guard let beforeLens = beforeLifecycle.lensID,
              let afterLens = afterLifecycle.lensID,
              beforeLens == afterLens else {
            return result(
                input,
                decision: .incomparable(reason: .lensMismatch),
                deltas: diagnosticDeltas
            )
        }
        guard beforeLifecycle.routeActive,
              afterLifecycle.routeActive,
              !beforeLifecycle.isAppBackgrounded,
              !afterLifecycle.isAppBackgrounded else {
            return result(
                input,
                decision: .incomparable(reason: .safetyRegression),
                deltas: diagnosticDeltas,
                safetyRegressions: input.safetyRegressions + [.lifecycleChanged]
            )
        }
        // A positive result needs comparable scene provenance. A changed pair
        // is a scene cut; a missing side is not silently treated as the same
        // scene and therefore cannot produce a favorable classification.
        guard let beforeScene = beforeLifecycle.sceneSignature,
              let afterScene = afterLifecycle.sceneSignature,
              !beforeScene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !afterScene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return result(
                input,
                decision: .incomparable(reason: .sceneProvenanceMissing),
                deltas: diagnosticDeltas
            )
        }
        guard beforeScene == afterScene else {
            return result(
                input,
                decision: .incomparable(reason: .sceneMismatch),
                deltas: diagnosticDeltas
            )
        }

        // C04.2/N7 step 2: intent/output and the declared comparability axis.
        if let beforeIntent = input.beforeIntentRevision,
           let afterIntent = input.afterIntentRevision,
           beforeIntent != afterIntent {
            return result(
                input,
                decision: .incomparable(reason: .intentChanged),
                deltas: diagnosticDeltas
            )
        }
        if input.scope.comparability == .matchedMedia, input.matchedMediaMappingRef == nil {
            return result(
                input,
                decision: .incomparable(reason: .matchedMediaMappingMissing),
                deltas: diagnosticDeltas
            )
        }

        if let family {
            if family.requiresSubjectBinding {
                guard let beforeGeometry = input.beforeGeometry,
                      let afterGeometry = input.afterGeometry else {
                    return result(
                        input,
                        decision: .incomparable(reason: .geometryProvenanceMissing),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeGeometry.isValid,
                      afterGeometry.isValid else {
                    return result(
                        input,
                        decision: .incomparable(reason: .geometryInvalid),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeGeometry.frameID == beforeID,
                      afterGeometry.frameID == afterID,
                      beforeGeometry.displayTransform.orientation == beforeLifecycle.orientation,
                      afterGeometry.displayTransform.orientation == afterLifecycle.orientation else {
                    return result(
                        input,
                        decision: .incomparable(reason: .geometryMismatch),
                        deltas: diagnosticDeltas
                    )
                }
                // The frame IDs are expected to differ. The immutable camera
                // transform and aspect-fill crop must not differ between the pair.
                guard beforeGeometry.displayTransform == afterGeometry.displayTransform,
                      beforeGeometry.aspectFillTransform == afterGeometry.aspectFillTransform else {
                    return result(
                        input,
                        decision: .incomparable(reason: .geometryMismatch),
                        deltas: diagnosticDeltas
                    )
                }
            }

            if family == .lightExposure {
                guard let beforeExposureState = input.beforeExposureState,
                      let afterExposureState = input.afterExposureState else {
                    return result(
                        input,
                        decision: .incomparable(reason: .exposureEvidenceMissing),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeExposureState == .stable,
                      afterExposureState == .stable else {
                    return result(
                        input,
                        decision: .incomparable(reason: .exposureAdjusting),
                        deltas: diagnosticDeltas
                    )
                }
            }

            guard beforeEvidence.isCalibrated,
                  afterEvidence.isCalibrated,
                  beforeEvidence.calibrationVersion == afterEvidence.calibrationVersion,
                  beforeEvidence.calibrationVersion != nil else {
                return result(
                    input,
                    decision: .incomparable(reason: .calibrationMismatch),
                    deltas: diagnosticDeltas
                )
            }

            if family.requiresSubjectBinding {
                guard let beforeBinding = beforeEvidence.subjectBinding,
                      let afterBinding = afterEvidence.subjectBinding,
                      let expectedSubjectIdentity = input.subjectIdentity else {
                    return result(
                        input,
                        decision: .incomparable(reason: .subjectBindingMissing),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeBinding.identity == afterBinding.identity else {
                    return result(
                        input,
                        decision: .incomparable(reason: .subjectIdentityMismatch),
                        deltas: diagnosticDeltas
                    )
                }
                if expectedSubjectIdentity != beforeBinding.identity ||
                    expectedSubjectIdentity != afterBinding.identity {
                    return result(
                        input,
                        decision: .incomparable(reason: .subjectIdentityMismatch),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeBinding.source == afterBinding.source else {
                    return result(
                        input,
                        decision: .incomparable(reason: .subjectSourceMismatch),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeBinding.coordinateSpace == afterBinding.coordinateSpace else {
                    return result(
                        input,
                        decision: .incomparable(reason: .subjectSpaceMismatch),
                        deltas: diagnosticDeltas
                    )
                }
                guard beforeBinding.identity.generation == input.token.generation,
                      afterBinding.identity.generation == input.token.generation else {
                    return result(
                        input,
                        decision: .incomparable(reason: .generationMismatch),
                        deltas: diagnosticDeltas
                    )
                }
            }
        }

        // C04.2/N7 step 2: a verifier may only classify a change class it is
        // qualified for. A non-empty `allowedChanges` is a whitelist; a missing
        // required class fails closed instead of relying on a hidden bypass.
        if !input.scope.allowedChanges.isEmpty,
           let requiredChange = requiredAllowedChange(actionID: actionID, family: family) {
            guard input.scope.allowedChanges.contains(requiredChange) else {
                return result(
                    input,
                    decision: .incomparable(reason: .contextChanged),
                    deltas: diagnosticDeltas
                )
            }
        }

        // C04.2/N7 step 1: identity of the commanded object and of the
        // protected refs must hold before any effect number is read.
        let entityScope = evaluateEntityScope(input, diagnosticDeltas: diagnosticDeltas)
        if let blocked = entityScope.blocked {
            return blocked
        }

        if declaresAbsence {
            return verifyExpectedAbsence(
                input,
                protectedRegressions: entityScope.protectedRegressions,
                diagnosticDeltas: diagnosticDeltas
            )
        }

        // The absence path returned above, so a non-nil family is guaranteed
        // for every remaining operation.
        guard let family else {
            return result(
                input,
                decision: .incomparable(reason: .unsupportedAction),
                reasonCode: .unsupportedVerifier
            )
        }

        var safetyRegressions = input.safetyRegressions
        if family != .stability, !input.after.motionIsStill {
            safetyRegressions.append(.cameraMoving)
        }
        safetyRegressions = unique(safetyRegressions)

        if case .uncertain(let reason) = comparison.verdict {
            if reason == "camera_motion" {
                safetyRegressions.append(.cameraMoving)
                return result(
                    input,
                    decision: .incomparable(reason: .safetyRegression),
                    deltas: diagnosticDeltas,
                    safetyRegressions: unique(safetyRegressions)
                )
            }
            return result(
                input,
                decision: .incomparable(reason: incomparableReason(
                    for: reason,
                    family: family
                )),
                deltas: diagnosticDeltas,
                safetyRegressions: unique(safetyRegressions)
            )
        }

        guard let metricDelta = diagnosticDelta else {
            return result(
                input,
                decision: .incomparable(reason: .nonFiniteMetric),
                deltas: diagnosticDeltas
            )
        }

        if !safetyRegressions.isEmpty {
            return result(
                input,
                decision: .incomparable(reason: .safetyRegression),
                deltas: [metricDelta],
                safetyRegressions: safetyRegressions
            )
        }

        // C04.2/N7 step 3: a protected ref regression after a comparable pair
        // is `worse`, not a failed comparison. `improved` is never reachable
        // while a protected ref was lost.
        if !entityScope.protectedRegressions.isEmpty {
            return result(
                input,
                decision: .comparable(outcome: .worse),
                reasonCode: .regression,
                goalSatisfied: false,
                deltas: [metricDelta],
                protectedRegressions: entityScope.protectedRegressions,
                safetyRegressions: safetyRegressions
            )
        }

        // N7 step 4: effect delta vs the qualified deadband.
        let outcome: ActionVerificationOutcome
        switch comparison.verdict {
        case .relevant:
            outcome = fixedOutcome(
                actionID: actionID,
                family: family,
                before: input.before,
                after: input.after
            ) ?? .improved
        case .noOp:
            outcome = .unchanged
        case .opposite:
            outcome = .worse
        case .uncertain:
            // The exhaustive guard above handles this case. Keep a fail-closed
            // fallback in case the enum grows without a matching contract.
            return result(
                input,
                decision: .incomparable(reason: .metricUnavailable),
                deltas: diagnosticDeltas
            )
        }

        // `goalSatisfied` is reported independently from a partial
        // improvement: only an established objective predicate (`fixed`)
        // asserts that the criterion was reached. A directional `improved`
        // beyond the deadband is `goalSatisfied = false` until a qualified
        // target threshold exists, rather than claiming success.
        let goalSatisfied = (outcome == .fixed)
        let reasonCode: ActionVerificationReasonCode
        switch outcome {
        case .fixed, .improved:
            reasonCode = .verified
        case .unchanged:
            reasonCode = .noEffect
        case .worse:
            reasonCode = .regression
        }

        return result(
            input,
            decision: .comparable(outcome: outcome),
            reasonCode: reasonCode,
            goalSatisfied: goalSatisfied,
            deltas: [metricDelta],
            safetyRegressions: safetyRegressions
        )
    }

    /// Convenience spelling for call sites that model the owner as a pure
    /// function.
    static func compare(_ input: ActionVerificationInput) -> ActionVerificationResult {
        verify(input)
    }

    // MARK: - C04.2 entity scope

    private struct EntityScopeEvaluation {
        let blocked: ActionVerificationResult?
        let protectedRegressions: [ActionVerificationProtectedRegression]
    }

    /// Validates the identity and presence of the commanded target and the
    /// protected refs. A target that is not observed on both sides is not a
    /// zero-delta success; a protected ref that cannot be observed at all is
    /// missing guardrail evidence, not a pass.
    private static func evaluateEntityScope(
        _ input: ActionVerificationInput,
        diagnosticDeltas: [ActionVerificationMetricDelta]
    ) -> EntityScopeEvaluation {
        let targetRefs = input.scope.targetRefs
        let protectedRefs = input.scope.protectedRefs
        let absenceRefs = Set(input.scope.expectedAbsenceRefs)

        guard Set(targetRefs).isDisjoint(with: Set(protectedRefs)) else {
            // The changed object and a protected object may not be the same.
            return EntityScopeEvaluation(
                blocked: result(
                    input,
                    decision: .incomparable(reason: .contextChanged),
                    reasonCode: .contextChanged,
                    deltas: diagnosticDeltas
                ),
                protectedRegressions: []
            )
        }

        for ref in targetRefs {
            guard let beforeObservation = input.before.entityObservation(for: ref),
                  beforeObservation.isObserved,
                  let beforeTrack = beforeObservation.trackID else {
                return EntityScopeEvaluation(
                    blocked: result(
                        input,
                        decision: .incomparable(reason: .targetMissing),
                        reasonCode: .missingEvidence,
                        deltas: diagnosticDeltas
                    ),
                    protectedRegressions: []
                )
            }
            if absenceRefs.contains(ref) {
                // `exclude_entity`: the after frame must explicitly state the
                // entity left; a missing after observation is handled by the
                // dedicated absence verifier so its reason stays specific.
                if let afterObservation = input.after.entityObservation(for: ref),
                   let afterTrack = afterObservation.trackID,
                   afterTrack != beforeTrack {
                    return EntityScopeEvaluation(
                        blocked: result(
                            input,
                            decision: .incomparable(reason: .subjectIdentityMismatch),
                            reasonCode: .identityChanged,
                            deltas: diagnosticDeltas
                        ),
                        protectedRegressions: []
                    )
                }
                continue
            }
            guard let afterObservation = input.after.entityObservation(for: ref),
                  afterObservation.isObserved,
                  let afterTrack = afterObservation.trackID else {
                return EntityScopeEvaluation(
                    blocked: result(
                        input,
                        decision: .incomparable(reason: .targetMissing),
                        reasonCode: .missingEvidence,
                        deltas: diagnosticDeltas
                    ),
                    protectedRegressions: []
                )
            }
            guard beforeTrack == afterTrack else {
                return EntityScopeEvaluation(
                    blocked: result(
                        input,
                        decision: .incomparable(reason: .subjectIdentityMismatch),
                        reasonCode: .identityChanged,
                        deltas: diagnosticDeltas
                    ),
                    protectedRegressions: []
                )
            }
        }

        var protectedRegressions: [ActionVerificationProtectedRegression] = []
        for ref in protectedRefs {
            guard let beforeObservation = input.before.entityObservation(for: ref),
                  let beforeTrack = beforeObservation.trackID,
                  beforeObservation.isObserved,
                  let afterObservation = input.after.entityObservation(for: ref),
                  let afterTrack = afterObservation.trackID else {
                return EntityScopeEvaluation(
                    blocked: result(
                        input,
                        decision: .incomparable(reason: .protectedEvidenceMissing),
                        reasonCode: .missingEvidence,
                        deltas: diagnosticDeltas
                    ),
                    protectedRegressions: []
                )
            }
            guard beforeTrack == afterTrack else {
                return EntityScopeEvaluation(
                    blocked: result(
                        input,
                        decision: .incomparable(reason: .subjectIdentityMismatch),
                        reasonCode: .identityChanged,
                        deltas: diagnosticDeltas
                    ),
                    protectedRegressions: []
                )
            }
            if !afterObservation.isObserved {
                protectedRegressions.append(
                    ActionVerificationProtectedRegression(
                        entityRef: ref,
                        reason: .protectedEntityLost
                    )
                )
            }
        }

        return EntityScopeEvaluation(blocked: nil, protectedRegressions: protectedRegressions)
    }

    // MARK: - C04.2 expected absence (exclude_entity)

    /// N7: expected absence is proven only by owner-supplied evidence. A
    /// vanished bbox, an unexplained association loss, or a missing free-region
    /// confirmation is `incomparable`; only a confirmed exit with preserved
    /// protected refs is an improvement.
    private static func verifyExpectedAbsence(
        _ input: ActionVerificationInput,
        protectedRegressions: [ActionVerificationProtectedRegression],
        diagnosticDeltas: [ActionVerificationMetricDelta]
    ) -> ActionVerificationResult {
        let scope = input.scope
        guard Set(scope.expectedAbsenceRefs) == Set(scope.targetRefs),
              !scope.expectedAbsenceRefs.isEmpty else {
            return result(
                input,
                decision: .incomparable(reason: .contextChanged),
                reasonCode: .contextChanged,
                deltas: diagnosticDeltas,
                protectedRegressions: protectedRegressions
            )
        }

        var stillPresent = false
        for ref in scope.expectedAbsenceRefs {
            guard let evidence = input.absenceEvidence.first(where: { $0.entityRef == ref }),
                  evidence.observedPresentBefore,
                  evidence.observedExitFromRegion,
                  evidence.regionConfirmedFreeAfter,
                  evidence.associationLossExplained else {
                return result(
                    input,
                    decision: .incomparable(reason: .expectedAbsenceUnverified),
                    reasonCode: .missingEvidence,
                    deltas: diagnosticDeltas,
                    protectedRegressions: protectedRegressions
                )
            }
            guard let beforeObservation = input.before.entityObservation(for: ref),
                  beforeObservation.isObserved,
                  let afterObservation = input.after.entityObservation(for: ref) else {
                // The baseline track must be observed before, and the after
                // frame must explicitly state the entity left. Omission is
                // not an observation.
                return result(
                    input,
                    decision: .incomparable(reason: .expectedAbsenceUnverified),
                    reasonCode: .missingEvidence,
                    deltas: diagnosticDeltas,
                    protectedRegressions: protectedRegressions
                )
            }
            if let beforeTrack = beforeObservation.trackID,
               let afterTrack = afterObservation.trackID,
               beforeTrack != afterTrack,
               !evidence.associationLossExplained {
                return result(
                    input,
                    decision: .incomparable(reason: .subjectIdentityMismatch),
                    reasonCode: .identityChanged,
                    deltas: diagnosticDeltas,
                    protectedRegressions: protectedRegressions
                )
            }
            if afterObservation.visibility != .absent {
                stillPresent = true
            }
        }

        if !protectedRegressions.isEmpty {
            return result(
                input,
                decision: .comparable(outcome: .worse),
                reasonCode: .regression,
                goalSatisfied: false,
                deltas: diagnosticDeltas,
                protectedRegressions: protectedRegressions
            )
        }
        if stillPresent {
            return result(
                input,
                decision: .comparable(outcome: .unchanged),
                reasonCode: .noEffect,
                goalSatisfied: false,
                deltas: diagnosticDeltas
            )
        }
        return result(
            input,
            decision: .comparable(outcome: .improved),
            reasonCode: .verified,
            goalSatisfied: true,
            deltas: diagnosticDeltas
        )
    }

    /// The change class a concrete verifier is qualified to measure (N6.1
    /// operation semantics). `nil` means the verifier makes no declaration and
    /// the legacy guards remain the only gate.
    private static func requiredAllowedChange(
        actionID: String,
        family: UserMovementActionFamily?
    ) -> ActionVerificationAllowedChange? {
        switch actionID {
        case SemanticActionType.shiftFrameLeft.rawValue,
             SemanticActionType.shiftFrameRight.rawValue,
             SemanticActionType.shiftFrameUp.rawValue,
             SemanticActionType.shiftFrameDown.rawValue,
             SemanticActionType.raiseCamera.rawValue,
             SemanticActionType.lowerCamera.rawValue,
             SemanticActionType.levelHorizon.rawValue:
            return .cameraPose
        case SemanticActionType.moveSubjectLeft.rawValue,
             SemanticActionType.moveSubjectRight.rawValue,
             SemanticActionType.moveSubjectAwayFromBackground.rawValue,
             SemanticActionType.moveObjectLeft.rawValue,
             SemanticActionType.moveObjectRight.rawValue,
             SemanticActionType.moveObjectForward.rawValue,
             SemanticActionType.moveObjectBack.rawValue:
            return .targetPosition
        case SemanticActionType.stepCloser.rawValue,
             SemanticActionType.stepBack.rawValue:
            return .zoom
        case SemanticActionType.rotateSubjectTowardLight.rawValue:
            return .targetRotation
        case SemanticActionType.addFrontFillLight.rawValue,
             SemanticActionType.addBackgroundLight.rawValue,
             SemanticActionType.removeBackgroundHotspot.rawValue:
            return .lightState
        case TechnicalQualityActionType.reduceExposure.rawValue,
             TechnicalQualityActionType.increaseExposure.rawValue:
            return .exposureBias
        case TechnicalQualityActionType.refocusSubject.rawValue:
            return .focus
        case TechnicalQualityActionType.stabilizeCamera.rawValue:
            return .cameraPose
        default:
            return nil
        }
    }

    // MARK: - Diagnostics and outcome helpers

    /// Retains only complete finite observer diagnostics. A delta is useful
    /// for explaining a blocked result, but it never changes the decision.
    private static func metricDelta(
        for comparison: UserMovementComparison
    ) -> ActionVerificationMetricDelta? {
        guard let metric = comparison.metric,
              let beforeValue = comparison.beforeValue,
              let afterValue = comparison.afterValue,
              let delta = comparison.delta,
              let directedDelta = comparison.directedDelta,
              let deadband = comparison.deadband,
              [beforeValue, afterValue, delta, directedDelta, deadband]
                .allSatisfy({ $0.isFinite }),
              deadband >= 0 else {
            return nil
        }
        return ActionVerificationMetricDelta(
            metric: metric,
            before: beforeValue,
            after: afterValue,
            delta: delta,
            directedDelta: directedDelta,
            deadband: deadband
        )
    }

    private static func fixedOutcome(
        actionID: String,
        family: UserMovementActionFamily,
        before: UserMovementFrame,
        after: UserMovementFrame
    ) -> ActionVerificationOutcome? {
        switch family {
        case .horizonRotation:
            guard actionID == SemanticActionType.levelHorizon.rawValue,
                  let beforeAngle = before.metrics.horizonAngleDegrees,
                  let afterAngle = after.metrics.horizonAngleDegrees,
                  beforeAngle.isFinite,
                  afterAngle.isFinite,
                  abs(afterAngle) <= UserMovementObserver.rotationDeadbandDegrees,
                  abs(beforeAngle) > UserMovementObserver.rotationDeadbandDegrees else {
                return nil
            }
            return .fixed
        case .lightExposure:
            guard let beforeFault = before.metrics.exposureFault,
                  let afterFault = after.metrics.exposureFault,
                  beforeFault != .clear,
                  afterFault == .clear else {
                return nil
            }
            switch actionID {
            case TechnicalQualityActionType.reduceExposure.rawValue,
                 TechnicalQualityActionType.increaseExposure.rawValue:
                return .fixed
            default:
                return nil
            }
        case .focus:
            guard actionID == TechnicalQualityActionType.refocusSubject.rawValue,
                  before.metrics.focusIsDefocused == true,
                  after.metrics.focusIsDefocused == false else {
                return nil
            }
            return .fixed
        case .stability:
            // `motionIsStill` is the established frame-level predicate used
            // by M2-015/M2-024; no new numeric aesthetic target is invented.
            return after.motionIsStill ? .fixed : nil
        case .subjectDisplacement, .scaleDistance:
            return nil
        }
    }

    private static func incomparableReason(
        for observerReason: String,
        family: UserMovementActionFamily?
    ) -> ActionVerificationIncomparableReason {
        switch observerReason {
        case "evidence_missing":
            return .evidenceMissing
        case "frame_identity":
            return .duplicateFrame
        case "lens_generation":
            return .tokenMismatch
        case "subject_identity", "subject_missing":
            return family?.requiresSubjectBinding == true ? .subjectIdentityMismatch : .subjectBindingMissing
        case "target_missing":
            return .targetMissing
        case "uncalibrated":
            return .calibrationMismatch
        case "orientation_changed":
            return .orientationMismatch
        case "evidence_time":
            return .evidenceTimeInvalid
        case "feature_missing", "focus_missing":
            return family == .focus ? .focusProvenanceMissing : .featureUnavailable
        case "feature_confidence":
            return .featureConfidenceLow
        case "stale_evidence":
            return .evidenceStale
        case "feature_invalid":
            return .nonFiniteMetric
        case "camera_motion":
            return .safetyRegression
        default:
            return .metricUnavailable
        }
    }

    private static func unique(
        _ values: [ActionVerificationSafetyRegression]
    ) -> [ActionVerificationSafetyRegression] {
        var seen = Set<ActionVerificationSafetyRegression>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func result(
        _ input: ActionVerificationInput,
        decision: ActionVerificationDecision,
        reasonCode: ActionVerificationReasonCode? = nil,
        goalSatisfied: Bool? = nil,
        deltas: [ActionVerificationMetricDelta] = [],
        protectedRegressions: [ActionVerificationProtectedRegression] = [],
        safetyRegressions: [ActionVerificationSafetyRegression]? = nil
    ) -> ActionVerificationResult {
        ActionVerificationResult(
            token: input.token,
            actionID: input.actionID,
            beforeFrameID: input.before.frameID,
            afterFrameID: input.after.frameID,
            decision: decision,
            reasonCode: reasonCode ?? derivedReasonCode(for: decision),
            goalSatisfied: goalSatisfied,
            deltas: deltas,
            protectedRegressions: protectedRegressions,
            safetyRegressions: unique(safetyRegressions ?? input.safetyRegressions)
        )
    }

    private static func derivedReasonCode(
        for decision: ActionVerificationDecision
    ) -> ActionVerificationReasonCode {
        switch decision {
        case .comparable(let outcome):
            switch outcome {
            case .fixed, .improved:
                return .verified
            case .unchanged:
                return .noEffect
            case .worse:
                return .regression
            }
        case .incomparable(let reason):
            switch reason {
            case .unsupportedAction, .emptyAction:
                return .unsupportedVerifier
            case .metricUnavailable, .nonFiniteMetric, .calibrationMismatch,
                 .featureUnavailable, .featureConfidenceLow, .focusProvenanceMissing:
                return .metricUnqualified
            case .sceneMismatch, .sceneProvenanceMissing:
                return .sceneChanged
            case .tokenMismatch, .generationMismatch, .subjectBindingMissing,
                 .subjectIdentityMismatch, .subjectSourceMismatch, .subjectSpaceMismatch:
                return .identityChanged
            case .orientationMismatch, .lensMismatch, .intentChanged,
                 .matchedMediaMappingMissing, .contextChanged:
                return .contextChanged
            default:
                return .missingEvidence
            }
        }
    }
}
