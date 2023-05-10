//
//  ActorEntity.swift
//  shafinMultitool
//
//  Created by Рустем on 09.05.2023.
//

import Foundation
import UIKit
import RealityKit

struct ActorEntity {
    var id: UInt64
    var nameEntity: ModelEntity
    var color: UIColor?
    var coordinates: [simd_float4x4] = []
    
}

var actors: [ActorEntity] = []
