import Foundation

enum CameraCloudReviewFailure: Equatable, Sendable {
    case preparation
    case authentication
    case network
    case serviceUnavailable
    case responseInvalid
}

enum CameraCloudReviewState: Equatable, Sendable {
    case idle
    case preparing
    case awaitingConsent
    case analyzing
    case complete
    case noAdditionalEvidence
    case failed(CameraCloudReviewFailure)

    var isBusy: Bool {
        switch self {
        case .preparing, .awaitingConsent, .analyzing: return true
        default: return false
        }
    }
}
