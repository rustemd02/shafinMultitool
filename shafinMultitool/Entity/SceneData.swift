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
    
    enum CodingKeys: String, CodingKey {
        case name
        case actors
    }
    
    init(name: String, actors: [ActorData]?) {
        self.name = name
        self.actors = actors
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        actors = try container.decodeIfPresent([ActorData].self, forKey: .actors)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(actors, forKey: .actors)
    }
}

