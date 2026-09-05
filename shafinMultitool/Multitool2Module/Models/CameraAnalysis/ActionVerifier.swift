//
//  ActionVerifier.swift
//  shafinMultitool
//
//  M2-025 VerificationOwner: pure before/after action verification.
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
    /// before/after contract, objective fixed predicates and fail-closed
    /// provenance checks.
    static func verify(_ input: ActionVerificationInput) -> ActionVerificationResult {
        let actionID = input.actionID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !actionID.isEmpty else {
            return result(input, decision: .incomparable(reason: .emptyAction))
        }
        guard let family = UserMovementObserver.actionFamily(for: actionID) else {
            return result(input, decision: .incomparable(reason: .unsupportedAction))
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
        let comparison = UserMovementObserver.compareAtOwnEvaluationTimes(
            previous: input.before,
            current: input.after,
            actionID: actionID
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

        return result(
            input,
            decision: .comparable(outcome: outcome),
            deltas: [metricDelta],
            safetyRegressions: safetyRegressions
        )
    }

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

    /// Convenience spelling for call sites that model the owner as a pure
    /// function.
    static func compare(_ input: ActionVerificationInput) -> ActionVerificationResult {
        verify(input)
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
        family: UserMovementActionFamily
    ) -> ActionVerificationIncomparableReason {
        switch observerReason {
        case "evidence_missing":
            return .evidenceMissing
        case "frame_identity":
            return .duplicateFrame
        case "lens_generation":
            return .tokenMismatch
        case "subject_identity", "subject_missing":
            return family.requiresSubjectBinding ? .subjectIdentityMismatch : .subjectBindingMissing
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
        deltas: [ActionVerificationMetricDelta] = [],
        safetyRegressions: [ActionVerificationSafetyRegression]? = nil
    ) -> ActionVerificationResult {
        ActionVerificationResult(
            token: input.token,
            actionID: input.actionID,
            beforeFrameID: input.before.frameID,
            afterFrameID: input.after.frameID,
            decision: decision,
            deltas: deltas,
            safetyRegressions: unique(safetyRegressions ?? input.safetyRegressions)
        )
    }
}
