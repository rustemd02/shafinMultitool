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
    func updateStopwatchLabel(formattedTime: String)
}

class CameraScreenViewController: UIViewController {
    
    // MARK: - Properties
    var presenter: CameraScreenPresenterProtocol?
    private var ifFinishEditingButtonHidden = true
    //private var ifChangeNameButtonHidden = true
    
    private var arView = ARView()
    private var loadingView = UIView()
    private var loadingLabel = UILabel()
    
    private let tapGesture = UITapGestureRecognizer()
    private let longGesture = UILongPressGestureRecognizer()
    
    private let settingsButton = UIButton(type: .custom)
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
        
        tapGesture.addTarget(self, action: #selector(handleTap))
        longGesture.addTarget(self, action: #selector(longTap))
        longGesture.minimumPressDuration = 1.7
        settingsButton.addTarget(self, action: #selector(settingsButtonPressed), for: .touchUpInside)
        addActorButton.addTarget(self, action: #selector(addActor), for: .touchUpInside)
        finishEditingButton.addTarget(self, action: #selector(finishEditing), for: .touchUpInside)
        changeNameButton.addTarget(self, action: #selector(changeName), for: .touchUpInside)
        recordButton.addTarget(self, action: #selector(recordButtonPressed), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopButtonPressed), for: .touchUpInside)
        
    }
    
    // MARK: - Private functions
    private func setupUI() {
        view.addSubview(arView)
        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(longGesture)
        
        arView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        arView.addSubview(loadingView)
        loadingView.backgroundColor = .black.withAlphaComponent(0.7)
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        arView.addSubview(loadingLabel)
        loadingLabel.textColor = .white
        loadingLabel.text = "Перемещайте устройство, чтобы начать"
        loadingLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        arView.addSubview(addActorButton)
        addActorButton.backgroundColor = .white.withAlphaComponent(0.5)
        addActorButton.layer.cornerRadius = 37.5
        addActorButton.layer.masksToBounds = true
        addActorButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addActorButton.tintColor = .black
        addActorButton.snp.makeConstraints { make in
            make.width.height.equalTo(75)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(50)
        }
        
        arView.addSubview(finishEditingButton)
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
        
        
        arView.addSubview(changeNameButton)
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
        
        arView.addSubview(recordButton)
        recordButton.backgroundColor = .red.withAlphaComponent(0.5)
        //recordButton.setImage(UIImage(systemName: "largecircle.fill.circle"), for: .normal)
        recordButton.layer.cornerRadius = 30
        recordButton.layer.masksToBounds = true
        recordButton.tintColor = UIColor.black
        recordButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.rightMargin.equalToSuperview().inset(40)
            make.centerY.equalTo(addActorButton.snp_centerYWithinMargins)
        }
        
        arView.addSubview(stopButton)
        stopButton.isHidden = true
        stopButton.backgroundColor = .green.withAlphaComponent(0.5)
        //stopButton.setImage(UIImage(systemName: "largecircle.fill.circle"), for: .normal)
        stopButton.layer.cornerRadius = 30
        stopButton.layer.masksToBounds = true
        stopButton.tintColor = UIColor.black
        stopButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.rightMargin.equalToSuperview().inset(40)
            make.centerY.equalTo(addActorButton.snp_centerYWithinMargins)
        }
        
        arView.addSubview(stopwatchBackgroundView)
        stopwatchBackgroundView.isHidden = true
        stopwatchBackgroundView.backgroundColor = .black.withAlphaComponent(0.5)
        stopwatchBackgroundView.layer.cornerRadius = 10
        stopwatchBackgroundView.layer.masksToBounds = true
        stopwatchBackgroundView.snp.makeConstraints { make in
            make.width.equalTo(120)
            make.height.equalTo(30)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(50)
        }
        
        stopwatchBackgroundView.addSubview(stopwatchLabel)
        stopwatchLabel.isHidden = true
        stopwatchLabel.textColor = .white
        stopwatchLabel.text = "00:00"
        stopwatchLabel.snp.makeConstraints { make in
            make.center.equalTo(stopwatchBackgroundView)
        }
        
        arView.addSubview(settingsButton)
        settingsButton.backgroundColor = .white.withAlphaComponent(0.5)
        settingsButton.layer.cornerRadius = 16
        settingsButton.layer.masksToBounds = true
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.tintColor = .black
        settingsButton.snp.makeConstraints { make in
            make.width.equalTo(55)
            make.height.equalTo(30)
            make.top.equalTo(arView.snp_topMargin).offset(20)
            make.centerX.equalTo(recordButton.snp_centerXWithinMargins)
        }
        
        loadingAnimation()
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
        settingsButton.isHidden = true
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
        settingsButton.isHidden = false
        recordButton.isHidden = false
        
        presenter?.stopRecording()
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
