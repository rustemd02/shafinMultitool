//
//  MainScreenView.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import UIKit
import RealityKit
import ARKit
import SnapKit

protocol CameraScreenViewProtocol: AnyObject {
    func changeNameAlert(completion: @escaping (String) -> ())
    func changeNameButtonVisibility()
    func ifChangeNameButtonVisible() -> Bool
    func updateStopwatchLabel(formattedTime: String)
}

class CameraScreenViewController: UIViewController {
    
    // MARK: - Properties
    var presenter: CameraScreenPresenterProtocol?
    private var ifFinishEditingButtonHidden = true
    
    private var backgroundView = UIView()
    
    private var arView = ARView()
    private var loadingView = UIView()
    private var loadingLabel = UILabel()
    
    private let tapGesture = UITapGestureRecognizer()
    private let longGesture = UILongPressGestureRecognizer()
    
    private let settingsBarBackgroundView = UIView()
    private let changeResolutionButton = UIButton(type: .custom)
    private let divider = UILabel()
    private let changeFPSButton = UIButton(type: .custom)
    private let changeWBButton = UIButton(type: .custom)
    private let changeISOButton = UIButton(type: .custom)
    
    //private let settingsButton = UIButton(type: .custom)
    private let addActorButton = UIButton(type: .custom)
    private let finishEditingButton = UIButton(type: .custom)
    private let changeNameButton = UIButton(type: .custom)
    private let recordButton = UIButton(type: .custom)
    private let stopButton = UIButton(type: .custom)
    
    private let stopwatchBackgroundView = UIView()
    private let stopwatchLabel = UILabel()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        presenter?.viewDidLoad()
        presenter?.prepareRecorder()
        arView.session.delegate = self
        tapGesture.delegate = self
        setupARView(arView: arView)
        setupUI()
        fetchSettingsButtonValues()
        
        tapGesture.addTarget(self, action: #selector(handleTap))
        longGesture.addTarget(self, action: #selector(longTap))
        longGesture.minimumPressDuration = 1.7
        //settingsButton.addTarget(self, action: #selector(settingsButtonPressed), for: .touchUpInside)
        changeResolutionButton.addTarget(self, action: #selector(changeResolutionButtonPressed), for: .touchUpInside)
        changeFPSButton.addTarget(self, action: #selector(changeFPSButtonPressed), for: .touchUpInside)
        addActorButton.addTarget(self, action: #selector(addActor), for: .touchUpInside)
        finishEditingButton.addTarget(self, action: #selector(finishEditing), for: .touchUpInside)
        changeNameButton.addTarget(self, action: #selector(changeName), for: .touchUpInside)
        recordButton.addTarget(self, action: #selector(recordButtonPressed), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopButtonPressed), for: .touchUpInside)
        
    }
    
    // MARK: - Private functions
    private func setupUI() {
        view.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        backgroundView.addSubview(arView)
        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(longGesture)
        
        arView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leadingMargin.equalToSuperview()
            make.width.equalTo(arView.snp.height).multipliedBy(16.0/9.0)
            make.height.equalToSuperview()
        }
        
        setupSettingsBar()
        
        backgroundView.addSubview(loadingView)
        loadingView.backgroundColor = .black.withAlphaComponent(0.7)
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        backgroundView.addSubview(loadingLabel)
        loadingLabel.textColor = .white
        loadingLabel.text = "Перемещайте устройство, чтобы начать"
        loadingLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        backgroundView.addSubview(addActorButton)
        addActorButton.backgroundColor = .white.withAlphaComponent(0.5)
        addActorButton.layer.cornerRadius = 37.5
        addActorButton.layer.masksToBounds = true
        addActorButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addActorButton.tintColor = .black
        addActorButton.snp.makeConstraints { make in
            make.width.height.equalTo(75)
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(10)
        }
        
        backgroundView.addSubview(finishEditingButton)
        finishEditingButton.isHidden = true
        finishEditingButton.backgroundColor = .white.withAlphaComponent(0.5)
        finishEditingButton.layer.cornerRadius = 22.5
        finishEditingButton.layer.masksToBounds = true
        finishEditingButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
        finishEditingButton.tintColor = .black
        finishEditingButton.snp.makeConstraints { make in
            make.width.height.equalTo(45)
            make.left.equalTo(addActorButton.snp_rightMargin).offset(20)
            make.bottom.equalToSuperview().inset(50)
        }
        
        
        backgroundView.addSubview(changeNameButton)
        changeNameButton.backgroundColor = .white.withAlphaComponent(0.5)
        changeNameButton.layer.cornerRadius = 30
        changeNameButton.layer.masksToBounds = true
        changeNameButton.setImage(UIImage(systemName: "ellipsis.rectangle"), for: .normal)
        changeNameButton.tintColor = .black
        changeNameButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.leftMargin.equalToSuperview().offset(40)
            make.centerY.equalTo(addActorButton.snp_centerYWithinMargins)
        }
        changeNameButton.isHidden = true
        
        backgroundView.addSubview(recordButton)
        recordButton.backgroundColor = .red.withAlphaComponent(0.5)
        //recordButton.setImage(UIImage(systemName: "largecircle.fill.circle"), for: .normal)
        recordButton.layer.cornerRadius = 30
        recordButton.layer.masksToBounds = true
        recordButton.tintColor = UIColor.black
        recordButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.bottomMargin.equalToSuperview()
            make.centerX.equalTo(addActorButton.snp.centerX)
        }
        
        backgroundView.addSubview(stopButton)
        stopButton.isHidden = true
        stopButton.backgroundColor = .green.withAlphaComponent(0.5)
        //stopButton.setImage(UIImage(systemName: "largecircle.fill.circle"), for: .normal)
        stopButton.layer.cornerRadius = 30
        stopButton.layer.masksToBounds = true
        stopButton.tintColor = UIColor.black
        stopButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.bottomMargin.equalToSuperview()
            make.centerX.equalTo(addActorButton.snp.centerX)
        }
        
        settingsBarBackgroundView.addSubview(stopwatchBackgroundView)
        stopwatchBackgroundView.isHidden = true
        stopwatchBackgroundView.backgroundColor = .red.withAlphaComponent(0.8)
        stopwatchBackgroundView.layer.cornerRadius = 10
        stopwatchBackgroundView.layer.masksToBounds = true
        stopwatchBackgroundView.snp.makeConstraints { make in
            make.width.equalTo(120)
            make.height.equalTo(30)
            make.center.equalTo(settingsBarBackgroundView)
        }
        
        stopwatchBackgroundView.addSubview(stopwatchLabel)
        stopwatchLabel.isHidden = true
        stopwatchLabel.textColor = .white
        stopwatchLabel.text = "00:00"
        stopwatchLabel.font = .boldSystemFont(ofSize: 16)
        stopwatchLabel.snp.makeConstraints { make in
            make.center.equalTo(stopwatchBackgroundView)
        }
        
//        backgroundView.addSubview(settingsButton)
//        settingsButton.backgroundColor = .white.withAlphaComponent(0.5)
//        settingsButton.layer.cornerRadius = 16
//        settingsButton.layer.masksToBounds = true
//        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
//        settingsButton.tintColor = .black
//        settingsButton.snp.makeConstraints { make in
//            make.width.equalTo(55)
//            make.height.equalTo(30)
//            make.top.equalTo(arView.snp_topMargin).offset(20)
//            make.centerX.equalTo(recordButton.snp_centerXWithinMargins)
//        }
        
        loadingAnimation()
    }
    
    private func setupSettingsBar() {
        arView.addSubview(settingsBarBackgroundView)
        settingsBarBackgroundView.backgroundColor = .black.withAlphaComponent(0.4)
        settingsBarBackgroundView.snp.makeConstraints { make in
            make.leading.top.trailing.equalTo(arView)
            make.height.equalTo(37.5)
        }
        
        settingsBarBackgroundView.addSubview(changeResolutionButton)
        changeResolutionButton.setTitle("3K", for: .normal)
        changeResolutionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        changeResolutionButton.setTitleColor(.white, for: .normal)
        changeResolutionButton.snp.makeConstraints { make in
            make.centerY.equalTo(settingsBarBackgroundView)
            make.leadingMargin.equalTo(settingsBarBackgroundView.snp_leadingMargin).offset(15)
        }
        
        settingsBarBackgroundView.addSubview(divider)
        divider.text = "·"
        divider.font = .boldSystemFont(ofSize: 25)
        divider.textColor = .white
        divider.snp.makeConstraints { make in
            make.centerY.equalTo(settingsBarBackgroundView.snp.centerY)
            make.leadingMargin.equalTo(changeResolutionButton.snp_trailingMargin).offset(25)
        }
        
        settingsBarBackgroundView.addSubview(changeFPSButton)
        changeFPSButton.setTitle("22", for: .normal)
        changeFPSButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        changeFPSButton.setTitleColor(.white, for: .normal)
        changeFPSButton.snp.makeConstraints { make in
            make.centerY.equalTo(settingsBarBackgroundView)
            make.leadingMargin.equalTo(divider.snp.trailingMargin).offset(25)
        }
        
        let wbLabel = UILabel()
        wbLabel.text = "WB"
        wbLabel.textColor = .lightGray
        wbLabel.font = .systemFont(ofSize: 11)
        settingsBarBackgroundView.addSubview(wbLabel)
        
        changeWBButton.setTitle("9999K", for: .normal)
        changeWBButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        changeWBButton.setTitleColor(.white, for: .normal)
        settingsBarBackgroundView.addSubview(changeWBButton)
        changeWBButton.snp.makeConstraints { make in
            make.topMargin.equalTo(settingsBarBackgroundView.snp_topMargin).offset(-2)
            make.trailingMargin.equalTo(settingsBarBackgroundView.snp.trailingMargin).inset(15)
        }
        wbLabel.snp.makeConstraints { make in
            make.topMargin.equalTo(changeWBButton.snp_bottomMargin).offset(8)
            make.centerX.equalTo(changeWBButton.snp.centerX)
        }
        
        let isoLabel = UILabel()
        isoLabel.text = "ISO"
        isoLabel.textColor = .lightGray
        isoLabel.font = .systemFont(ofSize: 11)
        settingsBarBackgroundView.addSubview(isoLabel)
        
        changeISOButton.setTitle("230", for: .normal)
        changeISOButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        changeISOButton.setTitleColor(.white, for: .normal)
        settingsBarBackgroundView.addSubview(changeISOButton)
        changeISOButton.snp.makeConstraints { make in
            make.topMargin.equalTo(settingsBarBackgroundView.snp_topMargin).offset(-2)
            make.rightMargin.equalTo(changeWBButton.snp.leftMargin).inset(-50)
        }
        isoLabel.snp.makeConstraints { make in
            make.topMargin.equalTo(changeISOButton.snp_bottomMargin).offset(8)
            make.centerX.equalTo(changeISOButton.snp.centerX)
        }
        
    }
    
    private func fetchSettingsButtonValues() {
        //Анимировать
        guard let (settingsValues, convertedResolution) = presenter?.fetchSettingsButtonValues() else { return }
        changeResolutionButton.setTitle(convertedResolution, for: .normal)
        changeFPSButton.setTitle(settingsValues.fps.description, for: .normal)
        changeWBButton.setTitle(settingsValues.wb.description, for: .normal)
        changeISOButton.setTitle(settingsValues.iso.description, for: .normal)
        
    }
    
    private func setupARView(arView: ARView) {
        presenter?.prepareARView(arView: arView)
    }
    
    private func loadingAnimation() {
        UIView.animate(withDuration: 0.5, delay: 3) {
            self.loadingView.alpha = 0
            self.loadingLabel.alpha = 0
        }
    }
    
    @objc
    private func addActor() {
        finishEditingButton.isHidden = false
        ifFinishEditingButtonHidden = false
        presenter?.addActor(arView: arView)
    }
    
    @objc
    private func finishEditing() {
        finishEditingButton.isHidden = true
        ifFinishEditingButtonHidden = true
        presenter?.finishEditing()
    }
    
    @objc
    private func changeName() {
        presenter?.changeName(arView: arView)
    }
    
    @objc
    private func settingsButtonPressed() {
        presenter?.openSettings()
    }
    
    @objc
    private func recordButtonPressed() {
        recordButton.isHidden = true
        addActorButton.isHidden = true
        finishEditingButton.isHidden = true
        changeNameButton.isHidden = true
        //settingsButton.isHidden = true
        stopwatchBackgroundView.isHidden = false
        stopwatchLabel.isHidden = false
        stopButton.isHidden = false
        
        presenter?.startRecording()
    }
    
    @objc
    private func stopButtonPressed() {
        stopButton.isHidden = true
        addActorButton.isHidden = false
        if !ifFinishEditingButtonHidden {
            finishEditingButton.isHidden = false
        }
        stopwatchBackgroundView.isHidden = true
        stopwatchLabel.isHidden = true
        //settingsButton.isHidden = false
        recordButton.isHidden = false
        
        presenter?.stopRecording()
    }
    
    @objc
    private func changeResolutionButtonPressed() {
        presenter?.changeResolution()
        fetchSettingsButtonValues()
    }
    
    @objc
    private func changeFPSButtonPressed() {
        presenter?.changeFPS()
        fetchSettingsButtonValues()
    }
    
    @objc
    private func handleTap(_ gesture: UITapGestureRecognizer) {
        presenter?.handleTap(gesture, arView)
    }
    
    @objc
    private func longTap(_ gesture: UILongPressGestureRecognizer) {
        presenter?.longTap(gesture, arView)
    }
    
    
}

extension CameraScreenViewController: CameraScreenViewProtocol {
    func ifChangeNameButtonVisible() -> Bool {
        return changeNameButton.isHidden ? true : false
    }
    
    func updateStopwatchLabel(formattedTime: String) {
        stopwatchLabel.text = formattedTime
    }
    
    
    func changeNameAlert(completion: @escaping (String) -> ()) {
        let alertController = UIAlertController(title: "Введите имя актёра", message: nil, preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.placeholder = "Имя"
        }
        
        let cancelAction = UIAlertAction(title: "Отмена", style: .cancel, handler: nil)
        let saveAction = UIAlertAction(title: "Сохранить", style: .default) { _ in
            guard let nameTextField = alertController.textFields?.first, let name = nameTextField.text else { return }
            completion(name)
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(saveAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    
    func updateARViewSession(arView: ARView) {
        self.arView = arView
    }
    
    func changeNameButtonVisibility() {
        changeNameButton.alpha = changeNameButton.isHidden ? 0 : 1
        changeNameButton.transform = changeNameButton.isHidden ? CGAffineTransform(scaleX: 0.1, y: 0.1) : .identity
        
        if changeNameButton.isHidden {
            changeNameButton.isHidden = !changeNameButton.isHidden
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                self.changeNameButton.alpha = 1
                self.changeNameButton.transform = .identity
            })
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                self.changeNameButton.alpha = 0
                self.changeNameButton.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            }, completion: { _ in
                self.changeNameButton.isHidden = !self.changeNameButton.isHidden
            })
        }
        
    }
    
}

extension CameraScreenViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        presenter?.session(session, didUpdate: frame)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        presenter?.session(session, didAdd: anchors, arView: arView)
    }
    
    
}

extension CameraScreenViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let _ = touch.view as? UIButton { return false }
        return true
    }
}
