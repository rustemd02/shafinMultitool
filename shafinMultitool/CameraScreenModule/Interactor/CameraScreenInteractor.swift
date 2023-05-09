//
//  MainScreenInteractor.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import Foundation
import AVKit
import ARKit
import RealityKit


protocol CameraScreenInteractorProtocol: AnyObject {
    func startRecording()
    func stopRecording()
    func prepareARView(arView: ARView)
    func prepareRecorder()
    func addActor(arView: ARView)
    func changeName(arView: ARView)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) -> ARView
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView)
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView)
}


class CameraScreenInteractor {
    weak var presenter: CameraScreenPresenterProtocol?
    var firstStep = true
    var entities: [ModelEntity] = []
    var selectedEntity: Entity?
    var cameraService = CameraService()
    
    
    func placeObject(named entityName: String, for anchor: ARAnchor, arView: ARView) {
        let modelEntity = try? ModelEntity.loadModel(named: entityName)
        
        if let modelEntity = modelEntity {
            modelEntity.generateCollisionShapes(recursive: true)
            let anchorEntity = AnchorEntity(anchor: anchor)
            anchorEntity.addChild(modelEntity)
            
            arView.installGestures([.translation, .rotation], for: modelEntity)
            arView.scene.addAnchor(anchorEntity)
            if actors.count == 0 {
                presenter?.changeNameButtonVisibility()
            }
            
            selectedEntity = modelEntity
            let textEntity = setTextEntity(parentEntity: modelEntity, name: "Актёр " + (actors.count + 1).description)
            textEntity.name = "Актёр " + (actors.count + 1).description
            
            textEntity.position.y += 1.05
            textEntity.position.x -= 0.2
            
            modelEntity.addChild(textEntity)
            //let color = giveRandomColorToModel(entity: modelEntity)
            let actor = Actor(id: modelEntity.id, nameEntity: textEntity)
            
            actors.append(actor)
            entities.append(modelEntity)
            checkOnSelected()

        }
    }
    
    func placeSecondPoint(named entityName: String, for anchor: ARAnchor, arView: ARView) {
        
        
        }
    
//    func giveRandomColorToModel(entity: ModelEntity) -> UIColor {
//        var newMaterial = SimpleMaterial()
//        let red = CGFloat.random(in: 0.1...0.9)
//        let green = CGFloat.random(in: 0.1...0.9)
//        let blue = CGFloat.random(in: 0.1...0.9)
//        newMaterial.color.tint = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
//        entity.model?.materials = [newMaterial]
//        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
//    }
    
    func setTextEntity(parentEntity: Entity, name: String) -> ModelEntity {
        let actor = actors.first { actor in
            actor.id == parentEntity.id
        }
        let text = MeshResource.generateText(name, extrusionDepth: 0.02, font: .boldSystemFont(ofSize: 0.1))
        let shader = SimpleMaterial(color: .white, roughness: 10, isMetallic: false)
        actor?.nameEntity.model?.mesh = text
        actor?.nameEntity.name = name
        return ModelEntity(mesh: text, materials: [shader])
    }
    
    func checkOnSelected() {
        for entity in entities {
            if entity == selectedEntity {
                entity.model?.materials = [SimpleMaterial(color: .green, roughness: 4, isMetallic: true)]
            } else {
                entity.model?.materials = [SimpleMaterial(color: .white, roughness: 4, isMetallic: true)]
            }
        }
    }
    
    func createLine() {
        //TODO: 
    }
}

extension CameraScreenInteractor: CameraScreenInteractorProtocol {
    
    func startRecording() {
        cameraService.startRecording()

    }
    
    func stopRecording() {
        cameraService.stopRecording()
    }
    
    
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView) {
        if gesture.state == .began {
            let location = gesture.location(in: arView)
            if let tappedEntity = arView.entity(at: location) {
                tappedEntity.removeFromParent()
                actors.removeAll { actor in
                    actor.id == tappedEntity.id
                }
                if tappedEntity == selectedEntity {
                    presenter?.changeNameButtonVisibility()
                }
                selectedEntity = nil
            }
        }
    }
    
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView) {
        let location = gesture.location(in: arView)
        if let tappedEntity = arView.entity(at: location) {
            if selectedEntity == nil {
                presenter?.changeNameButtonVisibility()
            }
            selectedEntity = tappedEntity
            checkOnSelected()
        }
        
    }
    
    
    func prepareRecorder() {
        cameraService.prepareRecorder()
    }
    
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) -> ARView {
        for anchor in anchors {
            guard let anchorName = anchor.name, anchorName == "FinalBaseMesh" else { return arView }
            if firstStep {
                placeObject(named: anchorName, for: anchor, arView: arView)
            } else {
                
            }
            
        }
        return arView
    }
    
    
    func prepareARView(arView: ARView) {
        arView.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.session.run(configuration)
    }
    
    func addActor(arView: ARView) {
        let results = arView.raycast(from: arView.center, allowing: .estimatedPlane, alignment: .horizontal)
        guard let result = results.first else { return }
        let anchor = ARAnchor(name: "FinalBaseMesh", transform: result.worldTransform)
        arView.session.add(anchor: anchor)
    }
    
    func changeName(arView: ARView) {
        guard let selectedEntity = selectedEntity else { return }
        presenter?.changeNameAlert(completion: { result in
            _ = self.setTextEntity(parentEntity: selectedEntity, name: result)
        })
        
    }
    
}

