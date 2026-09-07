//
//  SceneSurfaceRaycasting.swift
//  shafinMultitool
//
//  M6-020: protocol-based surface raycast seam. The RealityKit
//  `ARView.Raycast.Result` has no public initializer, so tests cannot
//  drive the raw adapter — the seam projects results into a plain
//  struct the VM consumes. Production adapter wraps the existing
//  ARView calls one-to-one (same two-pass query, same ray math); the
//  default wiring stays the real ARView. Unit tests inject a fake
//  provider to drive hit/miss/failure events without pretending to
//  run an AR session.
//

import Foundation
import RealityKit
import simd

/// Plain surface-hit value the VM consumes.
struct SceneSurfaceRaycastResult: Equatable, Sendable {
    let worldTransform: simd_float4x4

    var position: SIMD3<Float> {
        SIMD3<Float>(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
    }
}

/// Surface-query seam over the AR workspace view.
protocol SceneSurfaceRaycasting: AnyObject {
    /// Two-pass surface query mirroring the production order:
    /// existing plane geometry first, then estimated planes.
    func raycastSurfaces(from point: CGPoint) -> [SceneSurfaceRaycastResult]
    /// Camera ray through a screen point for the floor-plane fallback.
    func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)?
}

/// Production adapter: one-to-one wrapper over the workspace ARView.
final class ARViewSurfaceRaycaster: SceneSurfaceRaycasting {
    private weak var view: ARView?

    init(view: ARView) {
        self.view = view
    }

    func raycastSurfaces(from point: CGPoint) -> [SceneSurfaceRaycastResult] {
        guard let view else { return [] }
        var results = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any)
        if results.isEmpty {
            results = view.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
        }
        return results.map { SceneSurfaceRaycastResult(worldTransform: $0.worldTransform) }
    }

    func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard let view, let ray = view.ray(through: point) else { return nil }
        return (ray.origin, ray.direction)
    }
}
