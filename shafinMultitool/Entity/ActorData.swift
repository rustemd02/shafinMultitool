//
//  ActorEntity.swift
//  shafinMultitool
//
//  Created by Рустем on 09.05.2023.
//

import Foundation
import UIKit
import RealityKit

struct ActorData: Codable {
    var id: UInt64
    var name: String
    var red : CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
    var color : UIColor {
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    var coordinates: [[Float]] = [[]]
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case red
        case green
        case blue
        case alpha
        case coordinates
    }
    
    init(id: UInt64, name: String, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.id = id
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        red = try container.decode(CGFloat.self, forKey: .red)
        green = try container.decode(CGFloat.self, forKey: .green)
        blue = try container.decode(CGFloat.self, forKey: .blue)
        alpha = try container.decode(CGFloat.self, forKey: .alpha)
        coordinates = try container.decode([[Float]].self, forKey: .coordinates)

    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
        try container.encode(coordinates, forKey: .coordinates)
    }
}


var actors: [ActorData] = []
