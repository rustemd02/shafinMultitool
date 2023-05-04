//
//  MainScreenPresenter.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import Foundation
import AVKit
import ARKit
import RealityKit


protocol CameraScreenPresenterProtocol: AnyObject {
    func viewDidLoad()
    func prepareARView(arView: ARView)
    func addActor(arView: ARView)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) -> ARView
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView)
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView)
    func changeName(arView: ARView)
    func startRecording()
    func stopRecording()
    func prepareRecorder(arView: ARView)
    func changeNameAlert(completion: @escaping (String) -> ())
    func changeNameButtonVisibility()

}

class CameraScreenPresenter {
    weak var view: CameraScreenViewProtocol?
    let router: CameraScreenRouterProtocol
    let interactor: CameraScreenInteractorProtocol
    
    init(router: CameraScreenRouterProtocol, interactor: CameraScreenInteractorProtocol) {
        self.router = router
        self.interactor = interactor
    }
    
    
}


extension CameraScreenPresenter: CameraScreenPresenterProtocol {
    
    func changeNameButtonVisibility() {
        view?.changeNameButtonVisibility()
    }
    
    func changeNameAlert(completion: @escaping (String) -> ()) {
        view?.changeNameAlert(completion: completion)
    }
    
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView) {
        interactor.longTap(gesture, arView)
    }
    
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView) {
        interactor.handleTap(gesture, arView)
    }
    
    func stopRecording() {
        interactor.stopRecording()
    }
    
    func prepareRecorder(arView: ARView) {
        interactor.prepareRecorder(arView: arView)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) -> ARView {
        return interactor.session(session, didAdd: anchors, arView: arView)
    }
    
    func startRecording() {
        interactor.startRecording()
    }

    func addActor(arView: ARView) {
        return interactor.addActor(arView: arView)
    }
    
    func changeName(arView: ARView) {
        return interactor.changeName(arView: arView)
    }
    
    func viewDidLoad() {
    }
    
    func prepareARView(arView: ARView) {
        interactor.prepareARView(arView: arView)
    }
    
    
}
