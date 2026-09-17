import Foundation
import CoreGraphics
import ImageIO

/// A pause outline identifies observed evidence in one accepted image. It is
/// neither a displacement destination nor a claim of persistent object identity.
enum CameraPauseMarkerPresentation {
    static func observedRegion(
        in critique: PauseCritiquePresentation?,
        acceptedSnapshotID: String,
        locale: Locale
    ) -> NormalizedRect? {
        guard let critique,
              critique.frameId == acceptedSnapshotID,
              let projection = critique.linkedEvidence,
              projection.frameID == acceptedSnapshotID,
              let action = critique.actions.first,
              action.actionId == projection.actionID,
              critique.actions.filter({ $0.actionId == action.actionId }).count == 1,
              action.actionType == projection.actionType,
              action.semanticActionType == projection.semanticActionType,
              action.linkedIssueIds == [projection.issueID],
              DeterministicCritiqueSummaryBuilder().makeExplanation(
                for: projection, locale: locale
              ) != nil else { return nil }

        let linkedIssues = critique.issues.filter { $0.issueId == projection.issueID }
        guard linkedIssues.count == 1,
              let issue = linkedIssues.first,
              issue.type == projection.issueType,
              let region = issue.affectedRegion,
              isValid(region) else { return nil }

        // The planner can place a requested future destination in targetRegion.
        // It cannot supply missing observation geometry or identify a sibling.
        return region
    }

    static func mappedFrame(
        for region: NormalizedRect,
        sourcePixelSize: CGSize,
        orientation: CGImagePropertyOrientation,
        canvasSize: CGSize,
        isMirrored: Bool,
        unobscuredArea: CGRect
    ) -> CGRect? {
        guard isValid(region),
              [sourcePixelSize.width, sourcePixelSize.height,
               canvasSize.width, canvasSize.height].allSatisfy({ $0.isFinite && $0 > 0 }),
              let mapped = SETAcceptedFrameRegionMapper.map(
                region,
                sourcePixelSize: sourcePixelSize,
                orientation: orientation,
                canvasSize: canvasSize,
                isMirrored: isMirrored
              ),
              unobscuredArea.contains(mapped) else { return nil }
        // Preserve the displayed observation bounds. A fixed box or a moved
        // centre could outline a neighbouring object. Occlusion hides the box.
        return mapped
    }

    private static func isValid(_ region: NormalizedRect) -> Bool {
        [region.x, region.y, region.width, region.height].allSatisfy(\.isFinite)
            && region.x >= 0 && region.y >= 0
            && region.width > 0 && region.height > 0
            && region.x + region.width <= 1
            && region.y + region.height <= 1
    }
}
