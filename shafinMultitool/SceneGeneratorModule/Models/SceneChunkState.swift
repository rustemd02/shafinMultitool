//
//  SceneChunkState.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

/// Компактное состояние сцены между последовательными чанками текста.
/// Используется как hint для planner-а, но не влияет напрямую на финальный SceneScript.
struct SceneChunkState: Codable, Equatable {
    var locationName: String?
    var knownActors: [String: String]
    var actorPoses: [String: ActorPose]
    var heldObjects: [String: String]

    init(
        locationName: String? = nil,
        knownActors: [String: String] = [:],
        actorPoses: [String: ActorPose] = [:],
        heldObjects: [String: String] = [:]
    ) {
        self.locationName = locationName
        self.knownActors = knownActors
        self.actorPoses = actorPoses
        self.heldObjects = heldObjects
    }
}
