//
//  SceneData.swift
//  shafinMultitool
//
//  Created by Рустем on 14.11.2023.
//

import Foundation
import RealityKit

struct SceneData: Codable {
    var name: String
    var actors: [ActorData]?
    var script: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case actors
        case script
    }
    
    init(name: String, actors: [ActorData]?, script: String) {
        self.name = name
        self.actors = actors
        self.script = script
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        actors = try container.decodeIfPresent([ActorData].self, forKey: .actors)
        script = try container.decodeIfPresent(String.self, forKey: .script)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(actors, forKey: .actors)
        try container.encodeIfPresent(script, forKey: .script)
    }
}

