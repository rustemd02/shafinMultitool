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
    
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var whiteBackgroundLayer: CALayer?
    private var outputURL: URL?

    
    
    
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
    
    
    func prepareRecorder(arView: ARView) {
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        // Настройка входного устройства для захвата видео
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            return
        }
        captureSession.addInput(videoDeviceInput)
        
        // Настройка вывода превью видео
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.connection?.videoOrientation = .portrait
        
        arView.layer.addSublayer(videoPreviewLayer)
        videoPreviewLayer.frame = arView.bounds
        
        self.videoPreviewLayer = videoPreviewLayer
        
        // Настройка вывода для записи видео
        let whiteBackgroundLayer = CALayer()
        whiteBackgroundLayer.frame = arView.bounds
        whiteBackgroundLayer.backgroundColor = UIColor.white.cgColor
        
        arView.layer.addSublayer(whiteBackgroundLayer)
        
        self.whiteBackgroundLayer = whiteBackgroundLayer
        
        captureSession.commitConfiguration()
        self.captureSession = captureSession
    }
    
    func startRecording() {
        guard let captureSession = captureSession, let outputURL = getVideoFileURL() else {
            return
        }
        
        self.outputURL = outputURL
        
        let movieFileOutput = AVCaptureMovieFileOutput()

        captureSession.beginConfiguration()
        
        if captureSession.canAddOutput(movieFileOutput) {
            captureSession.addOutput(movieFileOutput)
        }
        
        if let connection = movieFileOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
        
        captureSession.commitConfiguration()
        
        cameraService.outputURL = outputURL
        movieFileOutput.startRecording(to: outputURL, recordingDelegate: cameraService)
    }
    
    func stopRecording() {
        guard let captureSession = captureSession else {
            return
        }
    
        captureSession.stopRunning()
        
        if let whiteBackgroundLayer = whiteBackgroundLayer {
            whiteBackgroundLayer.removeFromSuperlayer()
        }
        
        if let videoPreviewLayer = videoPreviewLayer {
            videoPreviewLayer.removeFromSuperlayer()
        }
    }
    
    private func getVideoFileURL() -> URL? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let date = dateFormatter.string(from: Date())
        let fileName = "video_\(date).mov"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        return fileURL
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

