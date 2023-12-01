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
    func goToScenesOverviewScreen(arView: ARView, completion: @escaping (Bool) -> ())
    func focusOnTap(focusPoint: CGPoint)
    func fetchSettingsButtonValues() -> SettingsValues
    
    func getNumberOfRowsInPickerView(tag: Int) -> Int
    func titleForRow(row: Int, tag: Int) -> String
    func didSelectRow(row: Int, tag: Int)
    
    func getCurrentARView() -> ARView?
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
    
    var sceneName: String?
    var newScene: Bool?

    var anchors: [ARAnchor] = []
    var sceneData: SceneData?
    
    
    func placeActor(named entityName: String, for anchor: ARAnchor, arView: ARView) -> ModelEntity? {
        let modelEntity = createModel(named: entityName, for: anchor, arView: arView)
        
        if let raycastCoordinates = raycastCoordinates {
            let color = setRandomColorToModel(entity: modelEntity)
            guard let actorName = modelEntity.children.first?.name else { return nil }
            let (red, green, blue, alpha) = Converter.shared.cgFloatValuesFromUIColor(color: color)
            var actor = ActorData(id: modelEntity.id, name: actorName, red: red, green: green, blue: blue, alpha: alpha)
            actor.anchorIDs.append(anchor.identifier)
            actors.append(actor)
        }
        
        actorEntities.append(modelEntity)
        checkOnSelected()
        return modelEntity
    }
    
    func addPoint(named entityName: String, for anchor: ARAnchor, arView: ARView) -> ModelEntity? {
        let pointEntity = createModel(named: entityName, for: anchor, arView: arView)
        pointEntity.scale = pointEntity.scale - 0.4
        let actor = getActorByHisAnchor(anchor: anchor)
        
        if let index = actors.firstIndex(where: { $0.anchorIDs.first == selectedEntity?.anchor?.anchorIdentifier ?? actor?.anchorIDs.first }) {
            let color = actors[index].color
            pointEntity.model?.materials = [SimpleMaterial(color: color, roughness: 4, isMetallic: true)]
            if selectedEntity != nil {
                actors[index].anchorIDs.append(anchor.identifier)
            }
            
            let pathNumberEntity = setTextEntity(parentEntity: pointEntity, name: (actors[index].anchorIDs.count - 1).description, size: 0.1, color: .white)
            pathNumberEntity.position.y += 0.3
            pointEntity.addChild(pathNumberEntity)
        }
        
        pathEntities.append(pointEntity)
        return pointEntity
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
            
            var name = "Актёр " + (actors.count + 1).description
            let actor = getActorByHisAnchor(anchor: anchor)
            if actor != nil { name = actor?.name ?? name }
            
            let textEntity = setTextEntity(parentEntity: modelEntity, name: name, size: 0.1, color: .white)
            textEntity.name = name
            
            textEntity.position.y += 1.05
            textEntity.position.x -= 0.2
            
            modelEntity.addChild(textEntity)
            
            return modelEntity
        }
        
        return ModelEntity()
    }
    
    func setRandomColorToModel(entity: ModelEntity) -> UIColor {
        var newMaterial = SimpleMaterial()
        let red = CGFloat.random(in: 0.1...0.9)
        let green = CGFloat.random(in: 0.1...0.9)
        let blue = CGFloat.random(in: 0.1...0.9)
        newMaterial.color.tint = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        entity.model?.materials = [newMaterial]
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    func setColorToModel(entity: ModelEntity, anchor: ARAnchor) {
        var newMaterial = SimpleMaterial()
        guard let actor = getActorByHisAnchor(anchor: anchor) else { return }
        
        let red = actor.red
        let green = actor.green
        let blue = actor.blue
        let alpha = actor.alpha
        newMaterial.color.tint = UIColor(red: red, green: green, blue: blue, alpha: alpha)
        entity.model?.materials = [newMaterial]
    }
    
    func setTextEntity(parentEntity: ModelEntity, name: String, size: CGFloat, color: UIColor) -> ModelEntity {
        var actor = actors.first { actor in
            actor.anchorIDs.first == parentEntity.anchor?.anchorIdentifier
        }
        
        if actor == nil {
            actor = actors.first { actor in
                actor.id == parentEntity.id
            }
        }

        let textEntity = parentEntity.children.first as? ModelEntity
        
        let text = MeshResource.generateText(name, extrusionDepth: 0.02, font: .boldSystemFont(ofSize: size))
        let shader = SimpleMaterial(color: color, roughness: 10, isMetallic: false)
        if let index = actors.firstIndex(where: { $0.id == actor?.id }) {
            actors[index].name = name
        }
        textEntity?.model?.mesh = text
        textEntity?.name = name
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
    
    func getActorByHisAnchor(anchor: ARAnchor) -> ActorData? {
        guard let sceneData = sceneData, let actors = sceneData.actors else { return nil }
        for actor in actors {
            for anchorID in actor.anchorIDs {
                if anchorID == anchor.identifier {
                    return actor
                }
            }
        }
        return nil
    }
    
    func setDefaultSettings() {
        let defaultWidth = 3840
        let defaultHeight = 2160
        let defaultResolutionDescription = "uhd"
        let defaultFps = 25
        let defaultWhiteBalance = 5600
        let defaultISO = 100
        
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
    func getCurrentARView() -> ARView? {
        return presenter?.getCurrentARView()
    }
    
    // MARK: - Videorecording
    func prepareRecorder() {
        setDefaultSettings()
        cameraService.prepareRecorder()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
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
        elapsedTime = 1
        RunLoop.main.perform {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
    
    // MARK: - PickerView
    func getNumberOfRowsInPickerView(tag: Int) -> Int {
        if tag == 1 {
            return cameraService.getIsoValues().count
        } else if tag == 2 {
            return cameraService.getWBValues().count
        }
        return 0
    }
    
    func titleForRow(row: Int, tag: Int) -> String {
        if tag == 1 {
            return cameraService.getIsoValues()[row].description
        } else if tag == 2 {
            return cameraService.getWBValues()[row].description + "K"
        }
        return ""
    }
    
    func didSelectRow(row: Int, tag: Int) {
        if tag == 1 {
            let isoValue = cameraService.getIsoValues()[row]
            changeISO(iso: isoValue)
        } else if tag == 2 {
            let wbValue = cameraService.getWBValues()[row]
            changeWB(wb: wbValue)
        }
    }
    
    func changeISO(iso: Int) {
        cameraService.changeISO(iso: iso)
        UserDefaults.standard.set(iso, forKey: "iso")
    }
    
    func changeWB(wb: Int) {
        cameraService.changeWB(wb: wb)
        UserDefaults.standard.set(wb, forKey: "whiteBalance")
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
            guard let anchorName = anchor.name, anchorName == "Person" || anchorName == "Circle" else { return }
            self.anchors.append(anchor)
            if anchorName == "Person" {
                _ = placeActor(named: anchorName, for: anchor, arView: arView)
            } else {
                _ = addPoint(named: anchorName, for: anchor, arView: arView)
            }
            
        }
    }
    
    func prepareARView(arView: ARView) {
        guard let sceneName = sceneName else { return }
        guard let newScene = newScene else { return }
        
        arView.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        if !newScene {
            guard let (worldMap, sceneData) = DBService.shared.loadARWorldMap(sceneName: sceneName) else { return }
            self.sceneData = sceneData
            actors = sceneData.actors ?? []
            retrieveActorModels(worldMap: worldMap)
            configuration.initialWorldMap = worldMap
        }
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.session.run(configuration)
    }
    
    func retrieveActorModels(worldMap: ARWorldMap) {
        let anchors = worldMap.anchors.sorted {
            switch ($0.name, $1.name) {
                case let (a?, b?):
                    return a > b
                case (.none, .some):
                    return false
                case (.some, .none):
                    return true
                case (.none, .none):
                    return false
                }
        }
        
        guard let arView = getCurrentARView() else { return }
        for anchor in anchors {
            guard let anchorName = anchor.name, anchorName == "Person" || anchorName == "Circle" else { continue }
            self.anchors.append(anchor)
            if anchorName == "Person" {
                let modelEntity = placeActor(named: anchorName, for: anchor, arView: arView)
                guard let modelEntity = modelEntity else { return }
                setColorToModel(entity: modelEntity, anchor: anchor)
            } else {
                let modelEntity = addPoint(named: anchorName, for: anchor, arView: arView)
                guard let modelEntity = modelEntity else { return }
                setColorToModel(entity: modelEntity, anchor: anchor)
            }
        }
    }
    
    func goToScenesOverviewScreen(arView: ARView, completion: @escaping (Bool) -> ()) {
        guard let sceneName = sceneName else { return }
        let sceneData = SceneData(name: sceneName, actors: actors)
        actors = []
        self.anchors = []
        arView.session.pause()
        arView.session.getCurrentWorldMap { map, _ in
            try? DBService.shared.saveARWorldMap(map: map, sceneData: sceneData)
            completion(true)
        }
    }
    
    func addActor(arView: ARView) {
        let results = arView.raycast(from: arView.center, allowing: .estimatedPlane, alignment: .horizontal)
        guard let result = results.first else { return }
        self.raycastCoordinates = result.worldTransform
        if selectedEntity == nil {
            let anchor = ARAnchor(name: "Person", transform: result.worldTransform)
            arView.session.add(anchor: anchor)
        } else {
            let anchor = ARAnchor(name: "Circle", transform: result.worldTransform)
            arView.session.add(anchor: anchor)
        }
    }
    
    
    func finishEditing() {
        for pathEntity in pathEntities {
            pathEntity.isEnabled = false
        }
        
        let queue = DispatchQueue(label: "moveQueue")
        var index = 0
        for actorEntity in self.actorEntities {
            let actor = actors.first { actor in
                actor.anchorIDs.first == actorEntity.anchor?.anchorIdentifier
            }
            guard let actor = actor else { return }
            var coordinates: [simd_float4x4] = []
            for anchorID in actor.anchorIDs {
                for anchor in anchors {
                    if anchor.identifier == anchorID {
                        coordinates.append(anchor.transform)
                    }
                }
            }
            
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
                    actorEntity.move(to: destination, relativeTo: nil, duration: TimeInterval(duration))
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
        presenter?.changeNameAlert(completion: { newName in
            _ = self.setTextEntity(parentEntity: selectedEntity, name: newName, size: 0.1, color: .green)
        })
        
    }
    
    func fetchSettingsButtonValues() -> SettingsValues {
        return DBService.shared.fetchSettingsButtonValues()
    }
    
    func focusOnTap(focusPoint: CGPoint) {
        cameraService.focusOnTap(focusPoint: focusPoint)
    }
    
}

