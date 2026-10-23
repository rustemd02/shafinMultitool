// Numeric CameraCoach ranker inputs. Foundation only: no model or app execution.
// This is a separate contract, NOT SETCompositionNet v2's nine style features.
// Images must be supplied separately as upright sRGB N,T,C,H,W 224x224 history.
import Foundation

enum InputError: Error { case invalid(String) }

struct ActionCandidate: Codable {
    let id: String
    let translation: [Double]
    let pan_deg: Double
    let tilt_deg: Double
    let focal_factor: Double
    let exposure_ev: Double
    let fill_watts: Double
    let key_shift_m: [Double]
    let duration_s: Double
    let cost: Double

    func vector() throws -> [Double] {
        guard translation.count == 3, key_shift_m.count == 3 else {
            throw InputError.invalid("Translation/light shift must have three coordinates")
        }
        let v = translation + [pan_deg, tilt_deg, focal_factor, exposure_ev, fill_watts]
                + key_shift_m + [duration_s, cost]
        guard v.count == 13, v.allSatisfy({ $0.isFinite }), focal_factor > 0,
              duration_s >= 0, cost >= 0, fill_watts >= 0 else {
            throw InputError.invalid("Nonfinite or invalid candidate parameters")
        }
        return v
    }
}

struct NumericRequest: Codable {
    // Tap is already in the upright image's top-left normalized coordinates.
    let selected_tap_xy: [Double]?
    let goal: [String: Double]?
    // Explicit pixel-tone constraint, never inferred from an artistic style flag.
    let preserve_dark_tone: Bool
    let equipment_constraints: [Bool]
    // fx/source width is equivalent to f_mm/sensor_width_mm for the render camera.
    let focal_px: Double
    let focal_bounds_px: [Double]
    let upright_width: Int
    let upright_height: Int
    let history_time_s: [Double]
    let action_candidates: [ActionCandidate]
    let candidate_available: [Bool]
    // A bijection over the 31 nonredundant candidates. Also used to interpret scores.
    let candidate_order: [Int]
}

struct NumericFeatures: Codable {
    let selected_tap_xy: [Double]
    let selected_tap_available: Bool
    let goal_bounds: [Double]
    let goal_field_mask: [Bool]
    let preserve_dark_tone: Bool
    let equipment_constraints: [Bool]
    let focal_over_sensor_width: [Double]
    let source_image_aspect_ratio: Double
    let history_time_s: [Double]
    let candidate_params: [[Double]]
    let candidate_available: [Bool]
}

struct EncodedRequest {
    let features: NumericFeatures
    // Metadata only. Do not pass IDs or provenance to the learned network.
    let candidateIDs: [String]
}

struct CameraActionInputsV1 {
    static let goalKeys = ["height_min", "height_max", "visible_min", "visible_max", "luminance_min", "luminance_max"]
    static let decisions = ["keep", "recommend", "ask", "abstain"]

    static func encode(_ r: NumericRequest) throws -> EncodedRequest {
        guard r.upright_width > 0, r.upright_height > 0,
              r.focal_px.isFinite, r.focal_px > 0,
              r.focal_bounds_px.count == 2,
              r.focal_bounds_px.allSatisfy({ $0.isFinite && $0 > 0 }),
              r.focal_bounds_px[0] <= r.focal_bounds_px[1],
              r.focal_px >= r.focal_bounds_px[0], r.focal_px <= r.focal_bounds_px[1] else {
            throw InputError.invalid("Invalid upright dimensions or calibrated optics")
        }
        guard r.history_time_s.count == 3,
              r.history_time_s.allSatisfy({ $0.isFinite && $0 <= 0 }),
              r.history_time_s[0] < r.history_time_s[1],
              r.history_time_s[1] < r.history_time_s[2],
              abs(r.history_time_s[2]) < 1e-8 else {
            throw InputError.invalid("History must be past-only, ordered, and end at t=0")
        }
        guard r.equipment_constraints.count == 5,
              r.action_candidates.count == r.candidate_available.count,
              Set(r.action_candidates.map { $0.id }).count == r.action_candidates.count else {
            throw InputError.invalid("Invalid equipment/availability or duplicate action IDs")
        }
        if let tap = r.selected_tap_xy {
            guard tap.count == 2, tap.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
                throw InputError.invalid("Tap must be normalized in the upright image")
            }
        }
        if let goal = r.goal {
            guard Set(goal.keys).isSubset(of: Set(goalKeys)), !goal.isEmpty,
                  goal.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
                throw InputError.invalid("Invalid objective bounds; style flags are not goals")
            }
            for stem in ["height", "visible", "luminance"] {
                if let lo = goal[stem + "_min"], let hi = goal[stem + "_max"], lo > hi {
                    throw InputError.invalid("Inverted goal interval")
                }
            }
        }
        guard let keep = r.action_candidates.first(where: { $0.id == "keep" }) else {
            throw InputError.invalid("Missing keep candidate")
        }
        let keepPhysical = Array(try keep.vector().prefix(12))
        var selected: [Int] = []
        for (i, a) in r.action_candidates.enumerated() {
            let vector = try a.vector()
            if a.id == "wait_1s" {
                guard Array(vector.prefix(12)) == keepPhysical else {
                    throw InputError.invalid("A different wait transition cannot be dropped")
                }
            } else { selected.append(i) }
        }
        guard selected.count == 31,
              r.candidate_order.count == selected.count,
              Set(r.candidate_order) == Set(0..<selected.count) else {
            throw InputError.invalid("Expected a permutation of exactly 31 distinct candidates")
        }
        let indices = r.candidate_order.map { selected[$0] }
        let vectors = try indices.map { try r.action_candidates[$0].vector() }
        let width = Double(r.upright_width)
        let features = NumericFeatures(
            selected_tap_xy: r.selected_tap_xy ?? [0, 0],
            selected_tap_available: r.selected_tap_xy != nil,
            goal_bounds: goalKeys.map { r.goal?[$0] ?? 0 },
            goal_field_mask: goalKeys.map { r.goal?[$0] != nil } + [r.goal != nil],
            preserve_dark_tone: r.preserve_dark_tone,
            equipment_constraints: r.equipment_constraints,
            focal_over_sensor_width: [r.focal_px / width] + r.focal_bounds_px.map { $0 / width },
            source_image_aspect_ratio: width / Double(r.upright_height),
            history_time_s: r.history_time_s,
            candidate_params: vectors,
            candidate_available: indices.map { r.candidate_available[$0] }
        )
        return EncodedRequest(features: features, candidateIDs: indices.map { r.action_candidates[$0].id })
    }
}
