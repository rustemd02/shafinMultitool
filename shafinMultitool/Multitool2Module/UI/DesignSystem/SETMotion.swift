import SwiftUI
import UIKit
import Foundation

enum SETMotion {
    static let springResponse = 0.4
    static let springDampingFraction = 0.85
    // O-6 montage reflow: geometry settles before the marker is revealed.
    static let reflowGeometryDuration = 0.28
    static let markerRevealDuration = 0.15
    static let markerDrawDuration = 0.32
    static let reducedMotionCrossfadeDuration = 0.12
    static let pauseCutLineDuration = 0.22
    static let pauseCutLabelDuration = 0.16
    static let chipOvershoot: CGFloat = 8
    static let hintSlide: CGFloat = 12
    static let hintDuration = 0.22
    static let maskRevealDuration = 0.32
    static let staggerDuration = 0.04
    static let sectionWipeDuration = 0.32
    static let reticleFocusDuration = 0.26
    static let tallyPulseDuration = 1.2
    static let leaderStepDuration = 0.32
    static let leaderActionDuration = 0.45

    static var standardSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDampingFraction)
    }

    static var reflowSpring: Animation {
        .spring(response: reflowGeometryDuration, dampingFraction: springDampingFraction)
    }

    static var markerReveal: Animation {
        .easeOut(duration: markerRevealDuration)
    }
}

/// Session/operation-owned one-shot event ledger.
///
/// Presentation views receive stable event identifiers from their owner, but
/// never decide whether an event has already been consumed.  The lock keeps
/// the small ledger safe when an async completion and a UIKit/SwiftUI
/// lifecycle callback arrive on different executors.
final class SETMotionEventLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var consumedEventIDs = Set<String>()

    @discardableResult
    func consume(_ eventID: String) -> Bool {
        consume(eventID: eventID)
    }

    @discardableResult
    func consume(eventID: String) -> Bool {
        guard !eventID.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return consumedEventIDs.insert(eventID).inserted
    }

    func hasConsumed(_ eventID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return consumedEventIDs.contains(eventID)
    }

    func reset() {
        lock.lock()
        consumedEventIDs.removeAll()
        lock.unlock()
    }

    var consumedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return consumedEventIDs.count
    }
}

enum SETHapticEvent: Equatable, Sendable {
    case rigid
    case selection
    case soft
    case error
}

/// UI-005: feedback for the four product moments — target acquired, advice
/// changed, verified improvement, error. One-shot per event ID through the
/// shared motion ledger, so recomposition never replays a haptic, and no
/// animation is owned here (transitions stay in `SETComponents` where the
/// Reduce Motion guards live).
@MainActor
final class SETCameraFeedbackController {
    let eventLedger: SETMotionEventLedger
    private let haptic: SETHapticPerforming

    init(eventLedger: SETMotionEventLedger, haptic: SETHapticPerforming) {
        self.eventLedger = eventLedger
        self.haptic = haptic
    }

    convenience init(eventLedger: SETMotionEventLedger) {
        self.init(eventLedger: eventLedger, haptic: SETHapticFeedback())
    }

    func targetAcquired(eventID: String) { fire(.selection, namespace: "target", eventID: eventID) }
    func adviceChanged(eventID: String) { fire(.soft, namespace: "advice", eventID: eventID) }
    func verifiedImproved(eventID: String) { fire(.rigid, namespace: "verified", eventID: eventID) }
    func failed(eventID: String) { fire(.error, namespace: "failed", eventID: eventID) }

    private func fire(_ event: SETHapticEvent, namespace: String, eventID: String) {
        // The RAW event id must be non-empty: the namespaced ledger key would
        // otherwise turn an anonymous trigger into a valid one ("failed.").
        guard !eventID.isEmpty,
              eventLedger.consume(eventID: "feedback.\(namespace).\(eventID)") else { return }
        haptic.perform(event)
    }
}

@MainActor
protocol SETHapticPerforming {
    func perform(_ event: SETHapticEvent)
}

/// Pause cut-mark owner. The review view may be recreated by rotation or
/// recomposition, but this controller and its session ledger remain stable.
@MainActor
final class SETPauseCutMarkController {
    let eventLedger: SETMotionEventLedger
    private let haptic: SETHapticPerforming

    init(eventLedger: SETMotionEventLedger,
         haptic: SETHapticPerforming) {
        self.eventLedger = eventLedger
        self.haptic = haptic
    }

    convenience init(eventLedger: SETMotionEventLedger) {
        self.init(eventLedger: eventLedger, haptic: SETHapticFeedback())
    }

    @discardableResult
    func begin(eventID: String) -> Bool {
        guard eventLedger.consume(eventID) else { return false }
        haptic.perform(.rigid)
        return true
    }
}

@MainActor
final class SETHapticFeedback: SETHapticPerforming {
    func perform(_ event: SETHapticEvent) {
        switch event {
        case .rigid:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
