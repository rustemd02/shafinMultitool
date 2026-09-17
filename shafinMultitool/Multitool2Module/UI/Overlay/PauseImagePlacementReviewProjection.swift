/// Display-only placement guidance for the exact accepted pause.
/// This does not change the critique or establish a tracked subject in a later frame.
struct PauseImagePlacementReviewProjection: Equatable {
    let goal: CaptureImagePlacementGoal

    var observedRegion: NormalizedRect { goal.observedRegion }
    var instructionKey: SETCopyKey { .cameraPlacementReframe }
    var labelKey: SETCopyKey { .cameraPlacementGoal }

    static func make(
        proposal: PauseImagePlacementProposal?,
        snapshotID: String,
        frameID: String,
        critique: PauseCritiquePresentation?
    ) -> Self? {
        guard let proposal, proposal.isActiveReviewSuggestion,
              proposal.goal.isValid,
              proposal.goal.snapshotID == snapshotID,
              proposal.goal.frameID == frameID,
              let critique, critique.frameId == frameID else { return nil }

        // Recheck against the current presentation: a previously active proposal
        // cannot displace advice that acquired priority after it was produced.
        let intent = CaptureIntent(
            selection: .user,
            subjectRefs: [proposal.goal.entityRef],
            imagePlacementGoal: proposal.goal,
            intentRevision: proposal.intentRevision
        )
        guard RecommendationPlanner().makeImagePlacementProposal(
            intent: intent,
            snapshotID: snapshotID,
            frameID: frameID,
            presentation: critique
        )?.isActiveReviewSuggestion == true else { return nil }

        return Self(goal: proposal.goal)
    }
}
