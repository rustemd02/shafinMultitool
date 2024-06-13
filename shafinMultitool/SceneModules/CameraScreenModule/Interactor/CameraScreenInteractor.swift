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
    func finishEditingAtOnce(completion: @escaping (Bool) -> ())
    func finishEditingOneByOne(completion: @escaping (Bool) -> ())
    func changeResolution()
    func changeFPS()
    func changeSpeed()
    func goToScenesOverviewScreen(arView: ARView, completion: @escaping (Bool) -> ())
    func focusOnTap(focusPoint: CGPoint)
    func fetchSettingsButtonValues() -> SettingsValues
    
    func getNumberOfRowsInPickerView(tag: Int) -> Int
    func getSelectedRowNumberForPickerView(tag: Int) -> Int
    func titleForRow(row: Int, tag: Int) -> String
    func didSelectRow(row: Int, tag: Int)
    
    func startDialogueRecogniotion(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int)
    func updateScript(newScript: String)
    func reformatScript(script: String) -> (names: [String], phrases: [String])
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
    private var speechRecognitionService = SpeechRecognitionService.shared
    private var raycastCoordinates: simd_float4x4?
    
    private var timer = Timer()
    private var elapsedTime = 1
    
    var sceneName: String?
    var newScene: Bool?
    
    var anchors: [ARAnchor] = []
    var sceneData: SceneData?
    
    var currentSpeedMultiplier: Double = 0.7
    
    private let processingQueue = DispatchQueue(label: "processingQueue")
    
    
    func placeActor(named entityName: String, for anchor: ARAnchor, arView: ARView) -> ModelEntity? {
        let modelEntity = createModel(named: entityName, for: anchor, arView: arView)
        
        if raycastCoordinates != nil {
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
            
//            let components = entityName.components(separatedBy: "_")
//            let pathNumberEntityName = components[1]
            
            let pathNumberEntity = setTextEntity(parentEntity: pointEntity, name: "", size: 0.1, color: .white)
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
        guard let sceneData = sceneData else { return nil }
        var sceneActors = sceneData.actors
        if sceneActors == nil {
            sceneActors = actors
        }
        guard let sceneActors = sceneActors else { return nil }
        for actor in sceneActors {
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
        let defaultWhiteBalance = 4000
        let defaultISO = 200
        let defaultSpeedMultiplier: Double = 1
        
        var width = UserDefaults.standard.integer(forKey: "resolutionWidth")
        var height = UserDefaults.standard.integer(forKey: "resolutionHeight")
        var resolutionDescription = UserDefaults.standard.string(forKey: "resolutionDescription")
        var fps = UserDefaults.standard.integer(forKey: "framerate")
        var wb = UserDefaults.standard.integer(forKey: "whiteBalance")
        var iso = UserDefaults.standard.integer(forKey: "iso")
        var speedMultiplier = UserDefaults.standard.double(forKey: "speedMultiplier")
        
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
        
        if speedMultiplier == 0 {
            speedMultiplier = defaultSpeedMultiplier
            UserDefaults.standard.set(speedMultiplier, forKey: "speedMultiplier")
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
        finishEditingAtOnce { _ in }
        //finishEditingOneByOne {_ in}
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
    
    func changeSpeed() {
        guard let currSpeedDescription = UserDefaults.standard.string(forKey: "speedMultiplier") else { return }
        let currSpeedEnum = SpeedValues.withLabel("speed" + currSpeedDescription.replacingOccurrences(of: ".", with: ""))
        let newSpeedEnum = currSpeedEnum?.next()
        currentSpeedMultiplier = newSpeedEnum?.rawValue ?? 1
        UserDefaults.standard.set(newSpeedEnum?.rawValue, forKey: "speedMultiplier")
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
    
    func getSelectedRowNumberForPickerView(tag: Int) -> Int {
        let settingsValues = DBService.shared.fetchSettingsButtonValues()
        if tag == 1 {
            return cameraService.getIsoValues().firstIndex { iso in
                settingsValues.iso == iso
            }!
        } else if tag == 2 {
            return cameraService.getWBValues().firstIndex { wb in
                settingsValues.wb == wb
            }!
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
                    presenter?.changeButtonVisibility(buttonName: "changeNameButton")
                }
                selectedEntity = nil
            }
        }
    }
    
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView) {
        let location = gesture.location(in: arView)
        if let tappedEntity = arView.entity(at: location) {
            if tappedEntity == selectedEntity {
                presenter?.changeButtonVisibility(buttonName: "changeNameButton")
                selectedEntity = nil
                checkOnSelected()
            } else if actorEntities.contains(where: { entity in
                tappedEntity == entity
            }) {
                if selectedEntity == nil {
                    presenter?.changeButtonVisibility(buttonName: "changeNameButton")
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
        if newScene {
            let sceneData = SceneData(name: sceneName, actors: actors, script: "")
            self.sceneData = sceneData
            presenter?.setSceneData(sceneData: sceneData)
        } else {
            guard let (worldMap, sceneData) = DBService.shared.loadARWorldMap(sceneName: sceneName) else { return }
            speechRecognitionService.stopRecognition()
            presenter?.setSceneData(sceneData: sceneData)
            updateScript(newScript: sceneData.script ?? "")
            self.sceneData = sceneData
            actors = sceneData.actors ?? []
            if !actors.isEmpty { presenter?.changeButtonVisibility(buttonName: "finishEditingButton") }
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
            guard let anchorName = anchor.name, anchorName == "Person" || anchorName.contains("Circle") else { continue }
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
        sceneData?.actors = actors
        guard let sceneData = sceneData else { return }
        actors = []
        self.anchors = []
        speechRecognitionService.stopRecognition()
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
    
    func finishEditingAtOnce(completion: @escaping (Bool) -> Void) {
        for pathEntity in pathEntities {
            pathEntity.isEnabled = false
        }

        let group = DispatchGroup()

        actorEntities.forEach { actorEntity in
            group.enter()

            guard let actor = actors.first(where: { $0.anchorIDs.first == actorEntity.anchor?.anchorIdentifier }) else {
                group.leave()
                return
            }

            let coordinates = actor.anchorIDs.compactMap { anchorID in
                anchors.first(where: { $0.identifier == anchorID })?.transform
            }

            guard coordinates.count > 1 else {
                group.leave()
                return
            }

            // Скорость движения модели в метрах в секунду
            let speed: Double = 0.15 * currentSpeedMultiplier // Примерное значение, подберите соответственно вашим нуждам

            // Устанавливаем модель на первую точку
            DispatchQueue.main.async {
                actorEntity.setTransformMatrix(coordinates[0], relativeTo: nil)
            }

            // Задержка для установки начальной позиции
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.moveActorEntity(actorEntity, along: coordinates, with: speed, group: group)
            }
        }

        group.notify(queue: .main) {
            self.pathEntities.forEach { $0.isEnabled = true }
            completion(true)
        }
    }

    private func moveActorEntity(_ actorEntity: ModelEntity, along coordinates: [simd_float4x4], with speed: Double, group: DispatchGroup) {
        guard coordinates.count > 1 else {
            group.leave()
            return
        }

        let totalDuration = coordinates.dropFirst().enumerated().reduce(0.0) { (total, arg) -> TimeInterval in
            let (index, endPosition) = arg
            let startPosition = coordinates[index].columns.3
            let distance = simd_distance(startPosition, endPosition.columns.3)
            return total + TimeInterval(distance) / TimeInterval(speed)
        }

        func moveToNextCoordinate(index: Int) {
            guard index < coordinates.count - 1 else {
                group.leave()
                return
            }

            let startPosition = coordinates[index].columns.3
            let endPosition = coordinates[index + 1].columns.3
            let distance = simd_distance(startPosition, endPosition)
            let moveDuration = TimeInterval(distance) / TimeInterval(speed)

            DispatchQueue.main.async {
                actorEntity.move(to: coordinates[index + 1], relativeTo: nil, duration: moveDuration)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + moveDuration) {
                moveToNextCoordinate(index: index + 1)
            }
        }

        moveToNextCoordinate(index: 0)
    }

    
    func finishEditingOneByOne(completion: @escaping (Bool) -> Void) {
        for pathEntity in self.pathEntities {
            pathEntity.isEnabled = false
        }
        
        let moveQueue = DispatchQueue(label: "moveQueue")
        let group = DispatchGroup()
        
        for actorEntity in self.actorEntities {
            guard let actor = actors.first(where: { $0.anchorIDs.first == actorEntity.anchor?.anchorIdentifier }) else { continue }

            var coordinates: [simd_float4x4] = actor.anchorIDs.compactMap { anchorID in
                self.anchors.first(where: { $0.identifier == anchorID })?.transform
            }
            
            guard coordinates.count > 1 else {
                continue
            }
            
            moveQueue.async {
                for i in 0..<(coordinates.count - 1) {
                    group.enter()
                    
                    let currentPosition = coordinates[i]
                    let destination = coordinates[i + 1]

                    let x1 = currentPosition.columns.3.x
                    let z1 = currentPosition.columns.3.z
                    let x2 = destination.columns.3.x
                    let z2 = destination.columns.3.z
                    let distance = hypot(x2 - x1, z2 - z1)
                    
                    let speed: Double = 0.15 * self.currentSpeedMultiplier // Скорость должна быть определена вашими требованиями
                    let duration = TimeInterval(Double(distance) / speed)

                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        actorEntity.move(to: destination, relativeTo: nil, duration: duration)
                    }
                    
                    // Ждем пока не завершится текущее перемещение перед тем как начать следующее
                    Thread.sleep(forTimeInterval: duration)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            for pathEntity in self.pathEntities {
                pathEntity.isEnabled = true
            }
            completion(true)
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
    
    func startDialogueRecogniotion(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int) {
        if speechRecognitionService.task != nil {
            speechRecognitionService.stopRecognition()
        }
        
        speechRecognitionService.recognise { recognised in
            let lastTwoWordsRecognised = recognised
                .split(separator: " ")
                .suffix(2)
                .joined(separator: " ")
                .lowercased()
            
            let lastTwoWordsScript = phrases[curPhraseIndex]
                .split(separator: " ")
                .suffix(2)
                .joined(separator: " ")
                .components(separatedBy: CharacterSet.letters.inverted)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            
            if lastTwoWordsScript.elementsEqual(lastTwoWordsRecognised) {
                var newNameIndex = curNameIndex
                let newPhraseIndex = curPhraseIndex + 1
                
                if newPhraseIndex >= phrases.count { return }
                
                if phrases[newPhraseIndex].contains(":") {
                    newNameIndex += 1
                }
                self.presenter?.displayDialogue(names: names, curNameIndex: newNameIndex, phrases: phrases, curPhraseIndex: newPhraseIndex)
                //self.speechRecognitionService.stopRecognition()
            }
            
        }
    }
    
    func updateScript(newScript: String) {
        self.sceneData?.script = newScript
        guard let sceneData = sceneData else { return }
        presenter?.setSceneData(sceneData: sceneData)
    }
    
    func reformatScript(script: String) -> (names: [String], phrases: [String]) {
        var currentName: String = ""
        var currentMessage: String = ""
        var text = script
        var names: [String] = []
        var phrases: [String] = []
        
        var readingName = true
        var nextName = ""
        var possibleName = false
        
        for char in text {
            if char != ":" && readingName {
                if char != " " {
                    currentName.append(char)
                }
                if possibleName {
                    if (char == " " && !currentName.isEmpty) || char == "," {
                        possibleName = false
                        readingName = false
                        currentName = ""
                    }
                    currentMessage.append(char)
                }
                
            } else if (char != ":" && char != "." && char != "?" && char != "!") && !readingName {
                currentMessage.append(char)
                
            } else {
                if char == ":" {
                    currentName = currentName.replacingOccurrences(of: "\n", with: "")
                    names.append(currentName)
                    currentMessage = ""
                }
                currentName = ""
                readingName = false
                
                if char != "." && char != "?" && char != "!" {
                    currentMessage.append(char)
                    
                } else {
                    currentMessage.append(char)
                    phrases.append(currentMessage)
                    currentMessage = ""
                    readingName = true
                    possibleName = true
                }
            }
        }
        return (names, phrases)
    }
    
}

