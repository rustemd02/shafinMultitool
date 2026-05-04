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
    var sceneID: String?
    var sceneHeading: String?
    var locationName: String?
    var knownActors: [String: String]
    var knownObjects: [String: String]
    var actorAliases: [String: String]
    var objectAliases: [String: String]
    var speakerAliasMap: [String: String]
    var actorPoses: [String: ActorPose]
    var heldObjects: [String: String]
    var lastResolvedSpeaker: String?
    var previousChunkSummary: String?
    var openBeatContext: String?
    var lastActorPositions: [String: String]

    init(
        sceneID: String? = nil,
        sceneHeading: String? = nil,
        locationName: String? = nil,
        knownActors: [String: String] = [:],
        knownObjects: [String: String] = [:],
        actorAliases: [String: String] = [:],
        objectAliases: [String: String] = [:],
        speakerAliasMap: [String: String] = [:],
        actorPoses: [String: ActorPose] = [:],
        heldObjects: [String: String] = [:],
        lastResolvedSpeaker: String? = nil,
        previousChunkSummary: String? = nil,
        openBeatContext: String? = nil,
        lastActorPositions: [String: String] = [:]
    ) {
        self.sceneID = sceneID
        self.sceneHeading = sceneHeading
        self.locationName = locationName
        self.knownActors = knownActors
        self.knownObjects = knownObjects
        self.actorAliases = actorAliases
        self.objectAliases = objectAliases
        self.speakerAliasMap = speakerAliasMap
        self.actorPoses = actorPoses
        self.heldObjects = heldObjects
        self.lastResolvedSpeaker = lastResolvedSpeaker
        self.previousChunkSummary = previousChunkSummary
        self.openBeatContext = openBeatContext
        self.lastActorPositions = lastActorPositions
    }
}
