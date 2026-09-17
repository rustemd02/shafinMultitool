import Foundation

/// Local, immutable context for one accepted pause review. The scene epoch is
/// the selected snapshot ID, not a claim of physical scene reconstruction.
struct CameraCloudPauseContext: Equatable, Sendable {
    let snapshotID: String
    let pipelineGeneration: UInt64
    let pauseRevision: Int
    let intentRevision: UInt64
    let intentAnswers: [String: Bool]
    let localRequest: VLMVisualEvidenceRequest
    /// Local admission revision. It is not image geometry or provider evidence.
    let sceneControlRevision: UInt64
    let imagePlacementRevision: UInt64

    init(snapshotID: String, pipelineGeneration: UInt64, pauseRevision: Int,
         intentRevision: UInt64, intentAnswers: [String: Bool], localRequest: VLMVisualEvidenceRequest,
         sceneControlRevision: UInt64 = 0, imagePlacementRevision: UInt64 = 0) {
        self.snapshotID = snapshotID
        self.pipelineGeneration = pipelineGeneration
        self.pauseRevision = pauseRevision
        self.intentRevision = intentRevision
        self.intentAnswers = intentAnswers
        self.localRequest = localRequest
        self.sceneControlRevision = sceneControlRevision
        self.imagePlacementRevision = imagePlacementRevision
    }
}
