//
//  MainScreenInteractor.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import Foundation
import ARKit
import RealityKit


protocol CameraScreenInteractorProtocol: AnyObject {
    func startRecording()
    func stopRecording()
    func prepareARView(arView: ARView)
    func prepareRecorder()
    func addActor(arView: ARView)
    func finishEditing()
    func changeResolution()
    func changeFPS()
    func fetchSettingsButtonValues() -> SettingsValues
    func changeName(arView: ARView)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView)
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView)
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView)
}


class CameraScreenInteractor {
    // MARK: - Properties
    weak var presenter: CameraScreenPresenterProtocol?
    private var actorEntities: [ModelEntity] = []
    private var pathEntities: [ModelEntity] = []
    private var selectedEntity: ModelEntity?
    private var cameraService = CameraService.shared
    private var raycastCoordinates: simd_float4x4?
    
    private var timer = Timer()
    private var elapsedTime = 1
    
    
    func placeActor(named entityName: String, for anchor: ARAnchor, arView: ARView) {
        let modelEntity = createModel(named: entityName, for: anchor, arView: arView)
        let color = giveRandomColorToModel(entity: modelEntity)
        let textEntity = modelEntity.children.first
        var actor = ActorEntity(id: modelEntity.id, nameEntity: textEntity as! ModelEntity, color: color)
        guard let raycastCoordinates = raycastCoordinates else { return }
        actor.coordinates.append(raycastCoordinates)
        actors.append(actor)
        actorEntities.append(modelEntity)
        checkOnSelected()
    }
    
    func addPoint(named entityName: String, for anchor: ARAnchor, arView: ARView) {
        let modelEntity = createModel(named: entityName, for: anchor, arView: arView)
        modelEntity.scale = modelEntity.scale - 0.4
        guard let raycastCoordinates = raycastCoordinates else { return }
        
        if let index = actors.firstIndex(where: { $0.id == selectedEntity?.id }) {
            let color = actors[index].color
            modelEntity.model?.materials = [SimpleMaterial(color: color ?? .white, roughness: 4, isMetallic: true)]
            actors[index].coordinates.append(raycastCoordinates)
            
            let pathNumberEntity = setTextEntity(parentEntity: modelEntity, name: (actors[index].coordinates.count - 1).description, size: 0.1, color: .white)
            pathNumberEntity.position.y += 0.3
            modelEntity.addChild(pathNumberEntity)
        }
        pathEntities.append(modelEntity)
    }
    
    func createModel(named entityName: String, for anchor: ARAnchor, arView: ARView) -> ModelEntity {
        let modelEntity = try? ModelEntity.loadModel(named: entityName)
        if let modelEntity = modelEntity {
            modelEntity.generateCollisionShapes(recursive: true)
            let anchorEntity = AnchorEntity(anchor: anchor)
            anchorEntity.addChild(modelEntity)
            arView.installGestures([.translation, .rotation], for: modelEntity)
            arView.scene.addAnchor(anchorEntity)
            
            if entityName == "Circle" {
                return modelEntity
            }
            
            let textEntity = setTextEntity(parentEntity: modelEntity, name: "Актёр " + (actors.count + 1).description, size: 0.1, color: .green)
            textEntity.name = "Актёр " + (actors.count + 1).description
            
            textEntity.position.y += 1.05
            textEntity.position.x -= 0.2
            
            modelEntity.addChild(textEntity)
            
            return modelEntity
        }

        return ModelEntity()
    }
    
    func giveRandomColorToModel(entity: ModelEntity) -> UIColor {
        var newMaterial = SimpleMaterial()
        let red = CGFloat.random(in: 0.1...0.9)
        let green = CGFloat.random(in: 0.1...0.9)
        let blue = CGFloat.random(in: 0.1...0.9)
        newMaterial.color.tint = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        entity.model?.materials = [newMaterial]
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    func setTextEntity(parentEntity: ModelEntity, name: String, size: CGFloat, color: UIColor) -> ModelEntity {
        let actor = actors.first { actor in
            actor.id == parentEntity.id
        }
        let text = MeshResource.generateText(name, extrusionDepth: 0.02, font: .boldSystemFont(ofSize: size))
        let shader = SimpleMaterial(color: color, roughness: 10, isMetallic: false)
        actor?.nameEntity.model?.mesh = text
        actor?.nameEntity.name = name
        return ModelEntity(mesh: text, materials: [shader])
    }
    
    func checkOnSelected() {
        for entity in actorEntities {
            let textEntity = entity.children.first as? ModelEntity
            
            if entity == selectedEntity {
                textEntity?.model?.materials = [SimpleMaterial(color: .green, roughness: 4, isMetallic: true)]
            } else {
                textEntity?.model?.materials = [SimpleMaterial(color: .white, roughness: 4, isMetallic: true)]
            }
        }
    }
    
    func setDefaultSettings() {
        let defaultWidth = 3840
        let defaultHeight = 2160
        let defaultResolutionDescription = "uhd"
        let defaultFps = 25
        let defaultWhiteBalance = 5600
        let defaultISO = 800

        var width = UserDefaults.standard.integer(forKey: "resolutionWidth")
        var height = UserDefaults.standard.integer(forKey: "resolutionHeight")
        var resolutionDescription = UserDefaults.standard.string(forKey: "resolutionDescription")
        var fps = UserDefaults.standard.integer(forKey: "framerate")
        var wb = UserDefaults.standard.integer(forKey: "whiteBalance")
        var iso = UserDefaults.standard.integer(forKey: "iso")

        if width == 0 {
            width = defaultWidth
            UserDefaults.standard.set(width, forKey: "resolutionWidth")
        }
        if height == 0 {
            height = defaultHeight
            UserDefaults.standard.set(height, forKey: "resolutionHeight")
        }
        
        if resolutionDescription == nil {
            resolutionDescription = defaultResolutionDescription
            UserDefaults.standard.set(resolutionDescription, forKey: "resolutionDescription")
        }
        
        if fps == 0 {
            fps = defaultFps
            UserDefaults.standard.set(fps, forKey: "framerate")
        }
        if wb == 0 {
            wb = defaultWhiteBalance
            UserDefaults.standard.set(wb, forKey: "whiteBalance")
        }
        if iso == 0 {
            iso = defaultISO
            UserDefaults.standard.set(iso, forKey: "iso")
        }
    }

}

extension CameraScreenInteractor: CameraScreenInteractorProtocol {
    // MARK: - Videorecording
    func prepareRecorder() {
        setDefaultSettings()
        cameraService.prepareRecorder()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
//        session.getCurrentWorldMap { <#ARWorldMap?#>, <#Error?#> in
//            <#code#>
//        }
        cameraService.session(session, didUpdate: frame)
    }
    
    
    func startRecording() {
        timer = Timer(timeInterval: 1.0, target: self, selector: #selector(startCounting), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .default)
        finishEditing()
        cameraService.startRecording()
        
    }
    
    @objc func startCounting() {
        let seconds = elapsedTime % 60
        let minutes = (elapsedTime / 60) % 60
        presenter?.updateStopwatchLabel(formattedTime: String(format: "%02d:%02d", minutes, seconds))
        elapsedTime+=1
    }
    
    func changeResolution() {
        guard let currResDescription = UserDefaults.standard.string(forKey: "resolutionDescription") else { return }
        guard let currResEnum = Resolutions.withLabel(currResDescription) else { return }
        let newResEnum = currResEnum.next()
        let (width, height) = Converter.shared.resolutionEnumToRawValues(Resolution: newResEnum)
        UserDefaults.standard.set(width, forKey: "resolutionWidth")
        UserDefaults.standard.set(height, forKey: "resolutionHeight")
        UserDefaults.standard.set(String(describing: newResEnum), forKey: "resolutionDescription")
        cameraService.changeResolution(width: width, height: height)
    }
    
    func changeFPS() {
        guard let currFPSDescription = UserDefaults.standard.string(forKey: "framerate") else { return }
        guard let currFPSEnum = FPSValues.withLabel("fps" + currFPSDescription) else { return }
        let newFPSEnum = currFPSEnum.next()
        cameraService.changeFPS(fps: newFPSEnum.rawValue)
        UserDefaults.standard.set(newFPSEnum.rawValue, forKey: "framerate")
    }
    
    func stopRecording() {
        cameraService.stopRecording()
        timer.invalidate()
        RunLoop.main.perform {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        elapsedTime = 1
    }
    
    // MARK: - AR handling functions
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
            if tappedEntity == selectedEntity {
                presenter?.changeNameButtonVisibility()
                selectedEntity = nil
                checkOnSelected()
            } else if actorEntities.contains(where: { entity in
                tappedEntity == entity
            }) {
                if selectedEntity == nil {
                    presenter?.changeNameButtonVisibility()
                }
                guard let tappedEntity = tappedEntity as? ModelEntity else { return }
                selectedEntity = tappedEntity
            }
            checkOnSelected()
        }
        
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) {
        for anchor in anchors {
            guard let anchorName = anchor.name, anchorName == "Person" else { return }
            if selectedEntity == nil {
                placeActor(named: anchorName, for: anchor, arView: arView)
            } else {
                addPoint(named: "Circle", for: anchor, arView: arView)
            }
            
        }
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
        let anchor = ARAnchor(name: "Person", transform: result.worldTransform)
        arView.session.add(anchor: anchor)
    }
    
    func finishEditing() {
        for pathEntity in pathEntities {
            pathEntity.isEnabled = false
        }
        
        let queue = DispatchQueue(label: "moveQueue")
        var index = 0
        for actorEntity in self.actorEntities {
            let actor = actors.first { actor in
                actor.id == actorEntity.id
            }
            guard let coordinates = actor?.coordinates else { continue }
            
            for i in 0..<coordinates.count - 1 {
                let currentPosition = coordinates[i]
                let destination = coordinates[i+1]
                
                let x1: Float = currentPosition.columns.0.x
                let y1: Float = currentPosition.columns.0.z
                let x2: Float = destination.columns.0.x
                let y2: Float = destination.columns.0.z
                let distance = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2))
                
                let speed: Float = 0.07
                let duration = distance / speed
                
                queue.asyncAfter(deadline: .now() + Double(index) * 1) {
                    actorEntity.move(to: coordinates[i+1], relativeTo: nil, duration: TimeInterval(duration))
                }
                index += 1
            }
            for pathEntity in pathEntities {
                pathEntity.isEnabled = true
            }
        }
        
    }
    
    func changeName(arView: ARView) {
        guard let selectedEntity = selectedEntity else { return }
        presenter?.changeNameAlert(completion: { result in
            _ = self.setTextEntity(parentEntity: selectedEntity, name: result, size: 0.1, color: .green)
        })
        
    }
    
    func fetchSettingsButtonValues() -> SettingsValues {
        return DBService.shared.fetchSettingsButtonValues()
    }
    
}

