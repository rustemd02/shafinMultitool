import Foundation
import Photos

/// M7-028: outcome of one transactional Photos export of a project-owned
/// recording. Success is emitted only after Photos completes its change
/// request; every failure kind is explicit and recoverable at the caller.
enum ScenePhotosExportOutcome: Equatable, Sendable {
    case exported
    case denied
    case restricted
    /// An export for this owner is already in flight; the request was not
    /// started, so retrying later is safe and cannot duplicate an asset.
    case alreadyInFlight
    case failed
}

/// Photos add-only library seam. Tests inject a deterministic fake; the
/// production adapter is the only type that touches `PHPhotoLibrary`.
protocol PhotosLibraryExporting: Sendable {
    /// Requests add-only authorization contextually. Called only from an
    /// explicit export action, never at launch.
    func requestAddOnlyAuthorization() async -> PHAuthorizationStatus
    /// Performs one creation change for the movie at `url`. Throws on any
    /// Photos-side failure.
    func performVideoExport(at url: URL) async throws
}

struct PHPhotosExportAdapter: PhotosLibraryExporting {
    func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func performVideoExport(at url: URL) async throws {
        // The change block itself is non-throwing; a nil creation request is
        // folded into the awaited call's thrown error afterwards.
        var creationSucceeded = false
        try await PHPhotoLibrary.shared().performChanges {
            creationSucceeded = PHAssetCreationRequest
                .creationRequestForAssetFromVideo(atFileURL: url) != nil
        }
        guard creationSucceeded else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// M7-028: the transactional Photos export owner for project-owned
/// recordings. Authorization is contextual (requested inside the export),
/// denials map to typed recoverable outcomes, an in-flight guard prevents
/// concurrent duplicate exports, and success is reported only after the
/// Photos change commits.
actor ScenePhotosExportService {
    private let library: any PhotosLibraryExporting
    private var exportInFlight = false

    init(library: any PhotosLibraryExporting = PHPhotosExportAdapter()) {
        self.library = library
    }

    /// Exports one local movie into the user's Photos library. The caller
    /// owns the source file; this service never deletes or moves media.
    func exportMovie(at url: URL) async -> ScenePhotosExportOutcome {
        guard !exportInFlight else { return .alreadyInFlight }
        exportInFlight = true
        defer { exportInFlight = false }

        let status = await library.requestAddOnlyAuthorization()
        switch status {
        case .authorized, .limited:
            break
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            // requestAuthorization resolves before returning; an unresolved
            // status here means the request did not complete.
            return .failed
        @unknown default:
            return .failed
        }

        do {
            try await library.performVideoExport(at: url)
            return .exported
        } catch {
            return .failed
        }
    }
}
