import XCTest
@testable import shafinMultitool

final class RecordingContractV1Tests: XCTestCase {

    func testCameraAndARContractsAreValid() {
        let contracts = [
            makeContract(
                source: .cameraCoach,
                audioPolicy: RecordingAudioPolicy(
                    mode: .required,
                    unavailableBehavior: .failRecording
                )
            ),
            makeContract(
                source: .arWorkspace,
                audioPolicy: RecordingAudioPolicy(
                    mode: .disabled,
                    unavailableBehavior: .notRequested
                )
            ),
        ]

        XCTAssertEqual(contracts.map { $0.validate() }, [[], []])
        XCTAssertEqual(
            Set(RecordingContractV1.lifecycleStates),
            Set(RecordingLifecycleState.allCases)
        )
        XCTAssertTrue(
            RecordingContractV1.allowsTransition(from: .ready, to: .recording)
        )
        XCTAssertFalse(
            RecordingContractV1.allowsTransition(from: .released, to: .recording)
        )
    }

    func testIdentityAndFormatViolationsAreExactTypedRejections() {
        XCTAssertEqual(
            makeContract(ownerID: zeroUUID).validate(),
            [.zeroOwnerID]
        )
        XCTAssertEqual(
            makeContract(recordingID: zeroUUID).validate(),
            [.zeroRecordingID]
        )
        XCTAssertEqual(
            makeContract(generation: 0).validate(),
            [.zeroGeneration]
        )
        XCTAssertEqual(
            makeContract(projectTarget: .sceneProject(zeroUUID)).validate(),
            [.zeroPromotionProjectID]
        )
        XCTAssertEqual(
            makeContract(width: 0).validate(),
            [.invalidDimensions]
        )
        XCTAssertEqual(
            makeContract(height: -1).validate(),
            [.invalidDimensions]
        )
        XCTAssertEqual(
            makeContract(framesPerSecond: 0).validate(),
            [.invalidFramesPerSecond]
        )
        XCTAssertEqual(
            makeContract(pixelFormatFourCC: 0).validate(),
            [.zeroPixelFormatFourCC]
        )
    }

    func testRequiredAudioCannotSilentlyDowngradeToVideoOnly() {
        let requiredContract = makeContract(
            audioPolicy: RecordingAudioPolicy(
                mode: .required,
                unavailableBehavior: .explicitVideoOnlySelection
            )
        )
        XCTAssertEqual(
            requiredContract.validate(),
            [.requiredAudioCannotDowngrade]
        )

        XCTAssertEqual(
            makeContract(
                audioPolicy: RecordingAudioPolicy(
                    mode: .required,
                    unavailableBehavior: .failRecording
                )
            ).validate(),
            []
        )
        XCTAssertEqual(
            makeContract(
                audioPolicy: RecordingAudioPolicy(
                    mode: .disabled,
                    unavailableBehavior: .explicitVideoOnlySelection
                )
            ).validate(),
            []
        )
        XCTAssertEqual(
            makeContract(
                audioPolicy: RecordingAudioPolicy(
                    mode: .required,
                    unavailableBehavior: .notRequested
                )
            ).validate(),
            [.invalidAudioPolicy]
        )
        XCTAssertEqual(
            makeContract(
                audioPolicy: RecordingAudioPolicy(
                    mode: .disabled,
                    unavailableBehavior: .failRecording
                )
            ).validate(),
            [.invalidAudioPolicy]
        )
    }

    func testCodecOrientationMirroringAndPromotionVariantsRemainTyped() {
        XCTAssertEqual(RecordingQuickTimeCodec.allCases.count, 2)
        XCTAssertEqual(RecordingCaptureOrientation.allCases.count, 4)
        XCTAssertEqual(RecordingMediaContainer.allCases, [.quickTimeMovie])

        for codec in RecordingQuickTimeCodec.allCases {
            for orientation in RecordingCaptureOrientation.allCases {
                let contract = makeContract(
                    codec: codec,
                    orientation: orientation,
                    mirrored: true,
                    projectTarget: .sceneProject(UUID())
                )
                XCTAssertEqual(contract.validate(), [])
            }
        }
    }

    func testTerminalDispositionMatrixIsExhaustiveAndOneToOne() {
        let projectID = UUID()
        let matrix = RecordingTerminalDispositionMatrix.canonical(
            for: .sceneProject(projectID)
        )
        XCTAssertEqual(matrix.entries.count, RecordingTerminalOutcome.allCases.count)
        XCTAssertEqual(
            Set(matrix.entries.map(\.outcome)),
            Set(RecordingTerminalOutcome.allCases)
        )
        for outcome in RecordingTerminalOutcome.allCases {
            XCTAssertNotNil(matrix.obligation(for: outcome))
            XCTAssertNotNil(matrix.disposition(for: outcome))
        }
        XCTAssertEqual(
            makeContract(projectTarget: .sceneProject(projectID)).validate(),
            []
        )

        var missing = matrix.entries
        missing.removeLast()
        XCTAssertTrue(
            makeContract(
                projectTarget: .sceneProject(projectID),
                terminalDisposition: RecordingTerminalDispositionMatrix(entries: missing)
            ).validate().contains(.terminalOutcomeMissing(.promotedProjectOwned))
        )

        var duplicated = matrix.entries
        duplicated.append(matrix.entries[0])
        XCTAssertTrue(
            makeContract(
                projectTarget: .sceneProject(projectID),
                terminalDisposition: RecordingTerminalDispositionMatrix(entries: duplicated)
            ).validate().contains(.terminalOutcomeDuplicated(.finalized))
        )

        var mismatched = matrix.entries
        let finalized = matrix.disposition(for: .finalized)!
        mismatched[0] = RecordingTerminalDisposition(
            outcome: .finalized,
            obligation: .preserveAppLocalMedia,
            artifactRequirement: finalized.artifactRequirement,
            failureRelation: finalized.failureRelation
        )
        XCTAssertTrue(
            makeContract(
                projectTarget: .sceneProject(projectID),
                terminalDisposition: RecordingTerminalDispositionMatrix(entries: mismatched)
            ).validate().contains(.terminalDispositionTargetMismatch(.finalized))
        )
    }

    func testTargetAwareMatrixRejectsIncompatibleAppLocalPromotion() {
        let target = RecordingPromotionTarget.appLocal
        let canonical = RecordingTerminalDispositionMatrix.canonical(for: target)
        var entries = canonical.entries
        let finalized = canonical.disposition(for: .finalized)!
        entries[0] = RecordingTerminalDisposition(
            outcome: .finalized,
            obligation: .pendingJournalThenIdempotentPromotion,
            artifactRequirement: finalized.artifactRequirement,
            failureRelation: finalized.failureRelation
        )

        XCTAssertTrue(
            makeContract(
                projectTarget: target,
                terminalDisposition: RecordingTerminalDispositionMatrix(entries: entries)
            ).validate().contains(.terminalDispositionTargetMismatch(.finalized))
        )

        let promoted = canonical.disposition(for: .promotedProjectOwned)!
        XCTAssertFalse(promoted.accepts(
            artifact: RecordingArtifact(
                id: RecordingID(rawValue: UUID()),
                localURL: URL(fileURLWithPath: "/tmp/setos-m7-001-app-local.mov"),
                duration: 1,
                hasAudio: false
            ),
            recorderFailure: nil,
            stopReason: nil
        ))

        var promotedMismatch = canonical.entries
        let promotedIndex = promotedMismatch.firstIndex {
            $0.outcome == .promotedProjectOwned
        }!
        promotedMismatch[promotedIndex] = RecordingTerminalDisposition(
            outcome: .promotedProjectOwned,
            obligation: .preserveProjectOwnedMedia,
            artifactRequirement: promoted.artifactRequirement,
            failureRelation: promoted.failureRelation
        )
        XCTAssertTrue(
            makeContract(
                projectTarget: target,
                terminalDisposition: RecordingTerminalDispositionMatrix(
                    entries: promotedMismatch
                )
            ).validate().contains(.terminalDispositionTargetMismatch(.promotedProjectOwned))
        )
    }

    func testTerminalRowsEnforceArtifactAndTypedFailureInvariants() {
        let projectID = UUID()
        let matrix = RecordingTerminalDispositionMatrix.canonical(
            for: .sceneProject(projectID)
        )
        let artifact = RecordingArtifact(
            id: RecordingID(rawValue: UUID()),
            localURL: URL(fileURLWithPath: "/tmp/setos-m7-001-artifact.mov"),
            duration: 1.0,
            hasAudio: true
        )

        let finalized = matrix.disposition(for: .finalized)!
        XCTAssertTrue(finalized.accepts(artifact: artifact, recorderFailure: nil, stopReason: nil))
        XCTAssertFalse(finalized.accepts(artifact: nil, recorderFailure: nil, stopReason: nil))
        XCTAssertFalse(finalized.accepts(artifact: artifact, recorderFailure: .finishFailed, stopReason: nil))

        let recoverable = matrix.disposition(for: .recoverableFailure)!
        XCTAssertTrue(recoverable.accepts(
            artifact: artifact,
            recorderFailure: .finishFailed,
            stopReason: nil
        ))
        XCTAssertFalse(recoverable.accepts(
            artifact: nil,
            recorderFailure: .finishFailed,
            stopReason: nil
        ))
        XCTAssertFalse(recoverable.accepts(
            artifact: artifact,
            recorderFailure: nil,
            stopReason: nil
        ))

        let unrecoverable = matrix.disposition(for: .unrecoverableFailure)!
        XCTAssertTrue(unrecoverable.accepts(
            artifact: nil,
            recorderFailure: .writerCreationFailed,
            stopReason: nil
        ))
        XCTAssertFalse(unrecoverable.accepts(
            artifact: artifact,
            recorderFailure: .writerCreationFailed,
            stopReason: nil
        ))

        let cancelled = matrix.disposition(for: .cancelledPrecommit)!
        XCTAssertTrue(cancelled.accepts(
            artifact: nil,
            recorderFailure: nil,
            stopReason: .user
        ))
        XCTAssertFalse(cancelled.accepts(
            artifact: artifact,
            recorderFailure: nil,
            stopReason: .user
        ))
        XCTAssertFalse(cancelled.accepts(
            artifact: nil,
            recorderFailure: .finishFailed,
            stopReason: .user
        ))

        let promoted = matrix.disposition(for: .promotedProjectOwned)!
        XCTAssertTrue(promoted.accepts(artifact: artifact, recorderFailure: nil, stopReason: nil))
        XCTAssertFalse(promoted.accepts(artifact: nil, recorderFailure: nil, stopReason: nil))
    }

    func testTerminalPolicyShapeRejectsArtifactAndFailureRelationDrift() {
        let projectID = UUID()
        let canonical = RecordingTerminalDispositionMatrix.canonical(
            for: .sceneProject(projectID)
        )
        var entries = canonical.entries
        let recoverable = canonical.disposition(for: .recoverableFailure)!
        entries[1] = RecordingTerminalDisposition(
            outcome: .recoverableFailure,
            obligation: recoverable.obligation,
            artifactRequirement: .forbidden,
            failureRelation: .none
        )

        let violations = makeContract(
            projectTarget: .sceneProject(projectID),
            terminalDisposition: RecordingTerminalDispositionMatrix(entries: entries)
        ).validate()
        XCTAssertTrue(violations.contains(.terminalArtifactRequirementMismatch(.recoverableFailure)))
        XCTAssertTrue(violations.contains(.terminalFailureRelationMismatch(.recoverableFailure)))
    }

    func testValidatedReturnsTheSameImmutableContractOrTypedError() throws {
        let valid = makeContract()
        XCTAssertEqual(try valid.validated(), valid)

        XCTAssertThrowsError(try makeContract(generation: 0).validated()) { error in
            XCTAssertEqual(
                error as? RecordingContractValidationError,
                RecordingContractValidationError(violations: [.zeroGeneration])
            )
        }
    }

    // MARK: - Fixtures

    private func makeContract(
        source: RecordingWorkspaceSource = .cameraCoach,
        ownerID: UUID = UUID(),
        recordingID: UUID = UUID(),
        generation: UInt64 = 1,
        audioPolicy: RecordingAudioPolicy = RecordingAudioPolicy(
            mode: .required,
            unavailableBehavior: .failRecording
        ),
        width: Int = 1_920,
        height: Int = 1_080,
        framesPerSecond: Int = 24,
        pixelFormatFourCC: UInt32 = 0x3432_5241,
        codec: RecordingQuickTimeCodec = .h264,
        orientation: RecordingCaptureOrientation = .portrait,
        mirrored: Bool = false,
        projectTarget: RecordingPromotionTarget = .appLocal,
        terminalDisposition: RecordingTerminalDispositionMatrix? = nil
    ) -> RecordingContractV1 {
        RecordingContractV1(
            owner: RecordingOwnerToken(
                source: source,
                ownerID: ownerID,
                recordingID: RecordingID(rawValue: recordingID),
                generation: generation
            ),
            audioPolicy: audioPolicy,
            mediaFormat: RecordingQuickTimeMediaFormat(
                container: .quickTimeMovie,
                codec: codec,
                pixelFormatFourCC: pixelFormatFourCC,
                width: width,
                height: height,
                framesPerSecond: framesPerSecond
            ),
            trackTransform: RecordingTrackTransformMetadata(
                captureOrientation: orientation,
                isMirrored: mirrored,
                strategy: .preferredTransformMetadata
            ),
            timebase: .canonical,
            promotionTarget: projectTarget,
            terminalDisposition: terminalDisposition
                ?? RecordingTerminalDispositionMatrix.canonical(for: projectTarget)
        )
    }

    private var zeroUUID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
}
