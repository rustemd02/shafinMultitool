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
    func finishEditingAtOnce(completion: @escaping (Bool) -> ())
    func finishEditingOneByOne(completion: @escaping (Bool) -> ())
    func session(_ session: ARSession, didAdd anchors: [ARAnchor], arView: ARView)
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    func handleTap(_ gesture: UITapGestureRecognizer, _ arView: ARView)
    func longTap(_ gesture: UILongPressGestureRecognizer, _ arView: ARView)
    func changeName(arView: ARView)
    func startRecording()
    func stopRecording()
    func prepareRecorder()
    func fetchSettingsButtonValues() -> (SettingsValues, String)
    func changeFPS()
    func changeResolution()
    func changeSpeed()
    func goToScenesOverviewScreen(arView: ARView)
    func goToEditScriptScreen(with sceneData: SceneData)
    func focusOnTap(focusPoint: CGPoint)
    
    func getNumberOfRowsInPickerView(tag: Int) -> Int
    func getSelectedRowNumberForPickerView(tag: Int) -> Int
    func titleForRow(row: Int, tag: Int) -> String
    func didSelectRow(row: Int, tag: Int)
    
    func startDialogueRecogniotion(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int)
    
    func displayDialogue(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int)
    func updateScript(newScript: String)
    func reformatScript(script: String) -> (names: [String], phrases: [String])
    func setSceneData(sceneData: SceneData)
    func changeNameAlert(completion: @escaping (String) -> ())
    func changeButtonVisibility(buttonName: String)
    func ifChangeNameButtonVisible() -> Bool
    func updateStopwatchLabel(formattedTime: String)
    func getCurrentARView() -> ARView?

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
    
    func displayDialogue(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int) {
        view?.displayDialogue(names: names, curNameIndex: curNameIndex, phrases: phrases, curPhraseIndex: curPhraseIndex)
    }
    
    func startDialogueRecogniotion(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int) {
        interactor.startDialogueRecogniotion(names: names, curNameIndex: curNameIndex, phrases: phrases, curPhraseIndex: curPhraseIndex)
    }
    
    func updateScript(newScript: String) {
        interactor.updateScript(newScript: newScript)
    }
    
    func reformatScript(script: String) -> (names: [String], phrases: [String]) {
        return interactor.reformatScript(script: script)
    }
    
    func setSceneData(sceneData: SceneData) {
        view?.setSceneData(sceneData: sceneData)
    }
    
    func goToEditScriptScreen(with sceneData: SceneData) {
        router.openEditScriptScreen(with: sceneData) { updatedScript in
            self.interactor.updateScript(newScript: updatedScript)
        }
    }
    
    func getCurrentARView() -> ARView? {
        return view?.getCurrentARView()
    }
    
    func ifChangeNameButtonVisible() -> Bool {
        return ((view?.ifChangeNameButtonVisible()) != nil)
    }
    
    func goToScenesOverviewScreen(arView: ARView) {
        interactor.goToScenesOverviewScreen(arView: arView) { didSave in
            self.router.openScenesOverviewScreen()
        }
    }
    
    func changeResolution() {
        interactor.changeResolution()
    }
    
    func changeSpeed() {
        interactor.changeSpeed()
    }
    
    func focusOnTap(focusPoint: CGPoint) {
        interactor.focusOnTap(focusPoint: focusPoint)
    }
    
    func changeFPS() {
        interactor.changeFPS()
    }
    
    func getNumberOfRowsInPickerView(tag: Int) -> Int {
        return interactor.getNumberOfRowsInPickerView(tag: tag)
    }
    
    func getSelectedRowNumberForPickerView(tag: Int) -> Int {
        return interactor.getSelectedRowNumberForPickerView(tag: tag)
    }
    
    func titleForRow(row: Int, tag: Int) -> String {
        return interactor.titleForRow(row: row, tag: tag)
    }
    
    func didSelectRow(row: Int, tag: Int) {
        return interactor.didSelectRow(row: row, tag: tag)
    }
    
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        interactor.session(session, didUpdate: frame)
    }
    
    
    func changeButtonVisibility(buttonName: String) {
        view?.changeButtonVisibility(buttonName: buttonName)
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
    
    func finishEditingAtOnce(completion: @escaping (Bool) -> ()) {
        interactor.finishEditingAtOnce(completion: completion)
    }
    
    func finishEditingOneByOne(completion: @escaping (Bool) -> ()) {
        interactor.finishEditingOneByOne(completion: completion)
    }
    
    func changeName(arView: ARView) {
        return interactor.changeName(arView: arView)
    }
    
    func viewDidLoad() {
    }
    
    func prepareARView(arView: ARView) {
        interactor.prepareARView(arView: arView)
    }
    
    func fetchSettingsButtonValues() -> (SettingsValues, String) {
        let settingsValues = interactor.fetchSettingsButtonValues()
        let resolution = settingsValues.resolution
        var convertedResolution = ""
        if ifResolutionsEqual(resolution, [(1280,720)]) {
            convertedResolution = "HD"
        } else if ifResolutionsEqual(resolution, [(1920,1080)]) {
            convertedResolution = "FHD"
        } else if ifResolutionsEqual(resolution, [(3840,2160)]) {
            convertedResolution = "4K"
        }
        return (settingsValues, convertedResolution)
        
    }
    
    func ifResolutionsEqual(_ array1: [(width: Int, height: Int)], _ array2: [(width: Int, height: Int)]) -> Bool {
        return array1.count == array2.count && array1.elementsEqual(array2, by: { $0 == $1 })
    }
    
    
}
