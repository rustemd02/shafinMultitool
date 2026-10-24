import Foundation

// Numeric bridge only: no Core ML, neural models, camera access, or app changes.
// RGB preprocessing must be separately verified on the target device.
struct CC21History: Codable { let path: String; let time_s: Double; let sha256: String }
struct CC21Goal: Codable { let metric: String; let minimum: Double?; let maximum: Double?; let scope: String }
struct CC21Action: Codable { let parameters: [Double]; let available: Bool; let native_index: Int }
struct CC21Observation: Codable {
    let history: [CC21History]
    let tap_xy: [Double]?
    let goal: [CC21Goal]
    let goal_known: Bool
    let preserve_dark_tone: Bool
    let optics: [Double]
    let optics_known: [Bool]
    let actions: [CC21Action]
    let observation_cutoff_s: Double
}
struct CC21Request: Codable { let observations: CC21Observation; let candidate_order: [Int] }
struct CC21NumericFeatures: Codable {
    let history_time_s: [Float]
    let selected_tap_xy: [Float]
    let selected_tap_known: Bool
    let goal_bounds: [[Float]]
    let goal_bounds_known: [[Bool]]
    let goal_scope: [Int]
    let goal_known: Bool
    let preserve_dark_tone: Bool
    let optics: [Float]
    let optics_known: [Bool]
    let candidate_params: [[Float]]
    let candidate_present: [Bool]
    let candidate_available: [Bool]
}
struct CC21Encoded: Codable { let features: CC21NumericFeatures; let output_native_indices: [Int?] }
enum CC21InputError: Error { case invalid(String) }

enum CameraActionInputsV21 {
    static let metrics = ["amodal_raster_height_fraction", "amodal_mesh_height_fraction", "visible_pixel_fraction", "visible_surface_sample_fraction", "median_display_luminance", "center_shift_l2", "projected_frame_margin", "front_depth_m", "amodal_pixel_count"]
    static let maxCandidates = 31
    static let parameterCount = 15
    static func encode(_ request: CC21Request) throws -> CC21Encoded {
        let o = request.observations
        guard o.observation_cutoff_s == 0, o.history.map(\.time_s) == [-0.4, -0.2, 0.0] else { throw CC21InputError.invalid("Noncausal history") }
        guard o.optics.count == 3, o.optics_known.count == 3, o.optics.allSatisfy({ $0.isFinite }) else { throw CC21InputError.invalid("Optics") }
        for (i, known) in o.optics_known.enumerated() where known { guard o.optics[i] > 0 else { throw CC21InputError.invalid("Nonpositive known optics") } }
        let n = o.actions.count
        guard n > 0, n <= maxCandidates, request.candidate_order.count == n, Set(request.candidate_order) == Set(0..<n) else { throw CC21InputError.invalid("Candidate permutation") }
        guard Set(o.actions.map(\.native_index)).count == n else { throw CC21InputError.invalid("Duplicate native action") }
        var tap: [Float] = [0, 0]
        if let values = o.tap_xy {
            guard values.count == 2, values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { throw CC21InputError.invalid("Tap") }
            tap = values.map(Float.init)
        }
        var bounds = Array(repeating: [Float](repeating: 0, count: 2), count: metrics.count)
        var boundsKnown = Array(repeating: [Bool](repeating: false, count: 2), count: metrics.count)
        var scopes = [Int](repeating: 0, count: metrics.count)
        var seen = Set<String>()
        guard o.goal_known || o.goal.isEmpty else { throw CC21InputError.invalid("Unknown goal has constraints") }
        for g in o.goal {
            guard let index = metrics.firstIndex(of: g.metric), seen.insert(g.metric).inserted else { throw CC21InputError.invalid("Unknown or repeated metric") }
            let scope: Int
            switch g.scope { case "endpoint": scope = 1; case "all_five_samples": scope = 2; default: throw CC21InputError.invalid("Goal scope") }
            scopes[index] = scope
            for (j, value) in [g.minimum, g.maximum].enumerated() {
                if let value = value {
                    guard value.isFinite else { throw CC21InputError.invalid("Nonfinite goal") }
                    bounds[index][j] = Float(value); boundsKnown[index][j] = true
                }
            }
            if let lo = g.minimum, let hi = g.maximum { guard lo <= hi else { throw CC21InputError.invalid("Inverted bounds") } }
        }
        var parameters = Array(repeating: [Float](repeating: 0, count: parameterCount), count: maxCandidates)
        var present = [Bool](repeating: false, count: maxCandidates)
        var available = [Bool](repeating: false, count: maxCandidates)
        var indices = [Int?](repeating: nil, count: maxCandidates)
        for (destination, source) in request.candidate_order.enumerated() {
            let a = o.actions[source]
            guard a.parameters.count == parameterCount, a.parameters.allSatisfy({ $0.isFinite }) else { throw CC21InputError.invalid("Action vector") }
            guard a.parameters[6] > 0, a.parameters[12] >= 0, a.parameters[13] >= 0, [0.0, 1.0].contains(a.parameters[14]) else { throw CC21InputError.invalid("Action units/profile") }
            parameters[destination] = a.parameters.map(Float.init)
            present[destination] = true; available[destination] = a.available; indices[destination] = a.native_index
        }
        let features = CC21NumericFeatures(history_time_s: o.history.map { Float($0.time_s) }, selected_tap_xy: tap, selected_tap_known: o.tap_xy != nil,
            goal_bounds: bounds, goal_bounds_known: boundsKnown, goal_scope: scopes, goal_known: o.goal_known, preserve_dark_tone: o.preserve_dark_tone,
            optics: o.optics.map(Float.init), optics_known: o.optics_known, candidate_params: parameters, candidate_present: present, candidate_available: available)
        return CC21Encoded(features: features, output_native_indices: indices)
    }
}
