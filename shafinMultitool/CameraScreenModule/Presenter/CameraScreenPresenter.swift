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
    func finishEditing()
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView)
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView)
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView)
    func changeName(arView: ARView)
    func startRecording()
    func stopRecording()
    func prepareRecorder()
    func openSettings()
    
    func changeNameAlert(completion: @escaping (String) -> ())
    func changeNameButtonVisibility()
    func ifChangeNameButtonVisible() -> Bool
    func updateStopwatchLabel(formattedTime: String)

}

class CameraScreenPresenter {
    // MARK: - Properties
    weak var view: CameraScreenViewProtocol?
    let router: CameraScreenRouterProtocol
    let interactor: CameraScreenInteractorProtocol
    
    init(router: CameraScreenRouterProtocol, interactor: CameraScreenInteractorProtocol) {
        self.router = router
        self.interactor = interactor
    }
    
}


extension CameraScreenPresenter: CameraScreenPresenterProtocol {
    func ifChangeNameButtonVisible() -> Bool {
        return ((view?.ifChangeNameButtonVisible()) != nil)
    }
    
    func openSettings() {
        router.openSettings()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        interactor.session(session, didUpdate: frame)
    }
    
    
    func changeNameButtonVisibility() {
        view?.changeNameButtonVisibility()
    }
    
    func changeNameAlert(completion: @escaping (String) -> ()) {
        view?.changeNameAlert(completion: completion)
    }
    
    func updateStopwatchLabel(formattedTime: String) {
        view?.updateStopwatchLabel(formattedTime: formattedTime)
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
    
    func prepareRecorder() {
        interactor.prepareRecorder()
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView) {
        interactor.session(session, didAdd: anchors, arView: arView)
    }
    
    func startRecording() {
        interactor.startRecording()
    }

    func addActor(arView: ARView) {
        return interactor.addActor(arView: arView)
    }
    
    func finishEditing() {
        interactor.finishEditing()
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
