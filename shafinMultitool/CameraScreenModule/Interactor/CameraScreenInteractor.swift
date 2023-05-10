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
    func prepareRecorder(arView: ARView)
    func addActor(arView: ARView)
    func finishEditing()
    func changeName(arView: ARView)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) -> ARView
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView)
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView)
}


class CameraScreenInteractor {
    weak var presenter: CameraScreenPresenterProtocol?
    var firstStep = true
    var actorEntities: [ModelEntity] = []
    var pathEntities: [ModelEntity] = []
    var selectedEntity: ModelEntity?
    var cameraService = CameraService()
    var raycastCoordinates: simd_float4x4?
    
    
    func placeActor(named entityName: String, for anchor: ARAnchor, arView: ARView) {
        //let color = giveRandomColorToModel(entity: modelEntity)
        let modelEntity = createModel(named: entityName, for: anchor, arView: arView)
        let textEntity = modelEntity.children.first
        var actor = ActorEntity(id: modelEntity.id, nameEntity: textEntity as! ModelEntity)
        guard let raycastCoordinates = raycastCoordinates else { return }
        actor.coordinates.append(raycastCoordinates)
        actors.append(actor)
        actorEntities.append(modelEntity)
        
        checkOnSelected()
        
        
    }
    
    func addPoints(named entityName: String, for anchor: ARAnchor, arView: ARView) {
        let model = createModel(named: entityName, for: anchor, arView: arView)
        pathEntities.append(model)
        model.scale = model.scale - 0.5
        guard let raycastCoordinates = raycastCoordinates else { return }
        
        if let index = actors.firstIndex(where: { $0.id == selectedEntity?.id }) {
            actors[index].coordinates.append(raycastCoordinates)
        }
    }
    
    func createModel(named entityName: String, for anchor: ARAnchor, arView: ARView) -> ModelEntity {
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
            
            if firstStep {
                selectedEntity = modelEntity
            }
            
            let textEntity = setTextEntity(parentEntity: modelEntity, name: "Актёр " + (actors.count + 1).description)
            textEntity.name = "Актёр " + (actors.count + 1).description
            
            textEntity.position.y += 1.05
            textEntity.position.x -= 0.2
            
            modelEntity.addChild(textEntity)
            
            return modelEntity
        }
        return ModelEntity()
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
    
    func setTextEntity(parentEntity: ModelEntity, name: String) -> ModelEntity {
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
        for entity in actorEntities {
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
            guard let tappedEntity = tappedEntity as? ModelEntity else { return }
            selectedEntity = tappedEntity
            checkOnSelected()
        }
        
    }
    
    
    func prepareRecorder(arView: ARView) {
        cameraService.prepareRecorder(arView: arView)
    }
    
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) -> ARView {
        for anchor in anchors {
            guard let anchorName = anchor.name, anchorName == "FinalBaseMesh" else { return arView }
            if firstStep {
                placeActor(named: anchorName, for: anchor, arView: arView)
                firstStep = false
            } else {
                addPoints(named: anchorName, for: anchor, arView: arView)
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
        self.raycastCoordinates = result.worldTransform
        let anchor = ARAnchor(name: "FinalBaseMesh", transform: result.worldTransform)
        arView.session.add(anchor: anchor)
    }
    
    func finishEditing() {
        firstStep = true
        for pathEntity in pathEntities {
            pathEntity.isEnabled = false
        }
        
        let actor = actors.first { actor in
            actor.id == selectedEntity?.id
        }
        guard let coordinates = actor?.coordinates else { return }
        let queue = DispatchQueue(label: "moveQueue")
        var index = 0
        for coordinate in coordinates {
            queue.asyncAfter(deadline: .now() + Double(index) * 2.0) {
                self.selectedEntity?.move(to: coordinate, relativeTo: nil, duration: 2)
            }
            index += 1
        }
    }
    
    func changeName(arView: ARView) {
        guard let selectedEntity = selectedEntity else { return }
        presenter?.changeNameAlert(completion: { result in
            _ = self.setTextEntity(parentEntity: selectedEntity, name: result)
        })
        
    }
    
}

