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
    func displayDialogue(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int)
    func setSceneData(sceneData: SceneData)
    func changeNameAlert(completion: @escaping (String) -> ())
    func changeButtonVisibility(buttonName: String)
    func ifChangeNameButtonVisible() -> Bool
    func updateStopwatchLabel(formattedTime: String)
    func getCurrentARView() -> ARView?
}

class CameraScreenViewController: UIViewController {
    
    // MARK: - Properties
    var presenter: CameraScreenPresenterProtocol?
    private var ifFinishEditingButtonHidden = true
    
    private var backgroundView = UIView()
    private let coverView = UIView()
    
    private var arView = ARView()
    private var loadingView = UIView()
    private var loadingLabel = UILabel()
    private var sceneData: SceneData?
    
    private var warningTimer = Timer()
    
    private let tapGesture = UITapGestureRecognizer()
    private let longGesture = UILongPressGestureRecognizer()
    
    private let settingsBarBackgroundView = UIView()
    private let backButton = UIButton(type: .custom)
    private let changeResolutionButton = UIButton(type: .custom)
    private let divider = UILabel()
    private let centerDot = UILabel()
    private let changeFPSButton = UIButton(type: .custom)
    private let changeScriptButtonBackgroundView = UIView()
    private let changeScriptButton = UIButton(type: .custom)
    private let changeWBButton = UIButton(type: .custom)
    private let changeISOButton = UIButton(type: .custom)
    private let settingPickerView = UIPickerView()
    
    private let addActorButton = UIButton(type: .custom)
    private let finishEditingButton = UIButton(type: .custom)
    private let changeNameButton = UIButton(type: .custom)
    private let recordButton = UIButton(type: .custom)
    private let stopButton = UIButton(type: .custom)
    
    private let stopwatchBackgroundView = UIView()
    private let stopwatchLabel = UILabel()
    
    private var subtitlesNameLabel = UILabel.subtitlesNameLabel(withText: "")
    private var subtitlesPhraseLabel = UILabel.subtitlesPhraseLabel(withText: "")
    
    private let processingQueue = DispatchQueue(label: "processingQueue")
    private var currentWarnings: [String] = []
    private var warningViews: [UIView] = []
    private var drawings: [CAShapeLayer] = []
    
    private var linesLayer: CALayer!

    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        presenter?.viewDidLoad()
        presenter?.prepareRecorder()
        arView.session.delegate = self
        tapGesture.delegate = self
        settingPickerView.dataSource = self
        settingPickerView.delegate = self
        setupARView(arView: arView)
        setupUI()
        
        tapGesture.addTarget(self, action: #selector(handleTap))
        longGesture.addTarget(self, action: #selector(longTap))
        longGesture.minimumPressDuration = 1.7
        backButton.addTarget(self, action: #selector(goToScenesOverviewScreen), for: .touchUpInside)
        changeScriptButton.addTarget(self, action: #selector(changeScriptButtonPressed), for: .touchUpInside)
        changeResolutionButton.addTarget(self, action: #selector(changeResolutionButtonPressed), for: .touchUpInside)
        changeFPSButton.addTarget(self, action: #selector(changeFPSButtonPressed), for: .touchUpInside)
        changeISOButton.addTarget(self, action: #selector(changeISOButtonPressed), for: .touchUpInside)
        changeWBButton.addTarget(self, action: #selector(changeWBButtonPressed), for: .touchUpInside)
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
                
        backgroundView.addSubview(addActorButton)
        addActorButton.backgroundColor = .white
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
        if ifFinishEditingButtonHidden { finishEditingButton.isHidden = true }
        finishEditingButton.backgroundColor = .white
        finishEditingButton.layer.cornerRadius = 30
        finishEditingButton.layer.masksToBounds = true
        finishEditingButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
        finishEditingButton.tintColor = .black
        finishEditingButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.topMargin.equalToSuperview().offset(20)
            make.centerX.equalTo(addActorButton.snp.centerX)
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
        recordButton.backgroundColor = .red
        recordButton.setImage(UIImage(systemName: "largecircle.fill.circle"), for: .normal)
        recordButton.layer.cornerRadius = 30
        recordButton.layer.masksToBounds = true
        recordButton.tintColor = UIColor.white
        recordButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.bottomMargin.equalToSuperview().inset(5)
            make.centerX.equalTo(addActorButton.snp.centerX)
        }
        
        backgroundView.addSubview(stopButton)
        stopButton.isHidden = true
        stopButton.backgroundColor = .white
        stopButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        stopButton.layer.cornerRadius = 30
        stopButton.layer.masksToBounds = true
        stopButton.tintColor = UIColor.black
        stopButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.bottomMargin.equalToSuperview().inset(5)
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
        
        arView.addSubview(centerDot)
        centerDot.text = "+"
        centerDot.font = .systemFont(ofSize: 30)
        centerDot.textColor = .white
        centerDot.snp.makeConstraints { make in
            make.center.equalTo(arView.snp.center)
        }
        
        loadingAnimation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        drawRuleOfThirdsLines()
        setupSettingsBar()
        fetchSettingsButtonValues()
    }
    
    private func setupSettingsBar() {
        arView.addSubview(settingsBarBackgroundView)
        settingsBarBackgroundView.backgroundColor = .black.withAlphaComponent(0.4)
        settingsBarBackgroundView.snp.makeConstraints { make in
            make.leading.top.trailing.equalTo(arView)
            make.height.equalTo(37.5)
        }
        
        settingsBarBackgroundView.addSubview(backButton)
        backButton.setImage(UIImage(systemName: "arrow.uturn.backward.circle.fill"), for: .normal)
        backButton.tintColor = .white
        backButton.snp.makeConstraints { make in
            make.centerY.equalTo(settingsBarBackgroundView)
            make.leadingMargin.equalTo(settingsBarBackgroundView.snp_leadingMargin).offset(15)
        }
        
        settingsBarBackgroundView.addSubview(changeResolutionButton)
        changeResolutionButton.setTitle("3K", for: .normal)
        changeResolutionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        changeResolutionButton.setTitleColor(.white, for: .normal)
        changeResolutionButton.snp.makeConstraints { make in
            make.centerY.equalTo(settingsBarBackgroundView)
            make.leadingMargin.equalTo(backButton.snp_trailingMargin).offset(40)
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
        
        changeScriptButtonBackgroundView.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        changeScriptButtonBackgroundView.layer.cornerRadius = 10
        changeScriptButtonBackgroundView.layer.masksToBounds = true
        settingsBarBackgroundView.addSubview(changeScriptButtonBackgroundView)
        changeScriptButtonBackgroundView.snp.makeConstraints { make in
            make.height.equalTo(30)
            make.center.equalTo(settingsBarBackgroundView)
        }

        changeScriptButton.setTitle(sceneData?.name, for: .normal)
        changeScriptButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        changeScriptButtonBackgroundView.addSubview(changeScriptButton)
        changeScriptButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.bottom.leading.trailing.equalToSuperview().inset(10)
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
        
        settingsBarBackgroundView.addSubview(coverView)
        coverView.snp.makeConstraints { make in
            make.edges.equalTo(settingsBarBackgroundView)
        }
        coverView.isHidden = true

        backgroundView.addSubview(settingPickerView)
        settingPickerView.isHidden = true
        settingPickerView.setValue(UIColor.white, forKeyPath: "textColor")
        settingPickerView.backgroundColor = .black.withAlphaComponent(0.4)
        settingPickerView.layer.cornerRadius = 10
        settingPickerView.snp.makeConstraints { make in
            make.rightMargin.equalTo(arView.snp_rightMargin).offset(-12.5)
            make.bottomMargin.equalTo(backgroundView.snp_bottomMargin)
        }
    }
    
    func drawRuleOfThirdsLines() {
        let screenWidth = arView.bounds.width
        let screenHeight = arView.bounds.height

        linesLayer = CALayer()
        linesLayer.frame = arView.bounds
        arView.layer.addSublayer(linesLayer)
        
        ruleOfThirdsLineConfig(at: CGPoint(x: screenWidth / 3, y: 0), to: CGPoint(x: screenWidth / 3, y: screenHeight))
        ruleOfThirdsLineConfig(at: CGPoint(x: 2 * screenWidth / 3, y: 0), to: CGPoint(x: 2 * screenWidth / 3, y: screenHeight))

        ruleOfThirdsLineConfig(at: CGPoint(x: 0, y: screenHeight / 3), to: CGPoint(x: screenWidth, y: screenHeight / 3))
        ruleOfThirdsLineConfig(at: CGPoint(x: 0, y: 2 * screenHeight / 3), to: CGPoint(x: screenWidth, y: 2 * screenHeight / 3))
    }

    func ruleOfThirdsLineConfig(at start: CGPoint, to end: CGPoint) {
        let linePath = UIBezierPath()
        linePath.move(to: start)
        linePath.addLine(to: end)
        
        let lineLayer = CAShapeLayer()
        lineLayer.path = linePath.cgPath
        lineLayer.strokeColor = UIColor.darkGray.cgColor
        lineLayer.lineWidth = 1.0
        linesLayer.addSublayer(lineLayer)
    }

    private func fetchSettingsButtonValues() {
        guard let (settingsValues, convertedResolution) = presenter?.fetchSettingsButtonValues() else { return }
        changeResolutionButton.setTitle(convertedResolution, for: .normal)
        changeFPSButton.setTitle(settingsValues.fps.description, for: .normal)
        changeWBButton.setTitle(settingsValues.wb.description, for: .normal)
        changeISOButton.setTitle(settingsValues.iso.description, for: .normal)
    }
    
    private func setupARView(arView: ARView) {
        presenter?.prepareARView(arView: arView)
    }
    
    @objc
    private func addActor() {
        finishEditingButton.isHidden = false
        ifFinishEditingButtonHidden = false
        animateButtonPress(button: finishEditingButton)
        presenter?.addActor(arView: arView)
    }
    
    @objc
    private func finishEditing() {
        finishEditingButton.isHidden = true
        ifFinishEditingButtonHidden = true
        animateButtonPress(button: finishEditingButton)
        presenter?.finishEditing()
    }
    
    @objc
    private func changeName() {
        presenter?.changeName(arView: arView)
    }
    
    
    @objc
    private func changeScriptButtonPressed() {
        guard let sceneData = sceneData else { return }
        animateButtonPress(button: self.changeScriptButton)
        presenter?.goToEditScriptScreen(with: sceneData)
    }
    
    @objc
    private func recordButtonPressed() {
        self.centerDot.isHidden = true
        
        UIView.animate(withDuration: 0.2, animations: {
            self.recordButton.alpha = 0
            self.addActorButton.alpha = 0
            self.finishEditingButton.alpha = 0
            self.changeNameButton.alpha = 0
            self.changeScriptButtonBackgroundView.alpha = 0
            self.changeScriptButton.alpha = 0
            self.stopwatchBackgroundView.alpha = 1
            self.stopwatchLabel.alpha = 1
        }, completion: { _ in
            self.recordButton.isHidden = true
            self.addActorButton.isHidden = true
            self.finishEditingButton.isHidden = true
            self.changeNameButton.isHidden = true
            self.changeScriptButtonBackgroundView.isHidden = true
            self.changeScriptButton.isHidden = true
            self.stopButton.isHidden = false
            self.coverView.isHidden = false
            self.stopwatchBackgroundView.isHidden = false
            self.stopwatchLabel.isHidden = false
            
            UIView.animate(withDuration: 0.2) {
                self.stopButton.alpha = 1
                self.coverView.alpha = 1
                self.stopwatchBackgroundView.alpha = 1
                self.stopwatchLabel.alpha = 1
            }
        })

        
        presenter?.startRecording()
    }
    
    @objc
    private func stopButtonPressed() {
        self.centerDot.isHidden = false
        
        UIView.animate(withDuration: 0.2, animations: {
            self.stopButton.alpha = 0
            self.coverView.alpha = 0
            self.stopwatchBackgroundView.alpha = 0
            self.stopwatchLabel.alpha = 0
        }, completion: { _ in
            self.stopButton.isHidden = true
            self.coverView.isHidden = true
            self.stopwatchBackgroundView.isHidden = true
            self.stopwatchLabel.isHidden = true
            
            self.recordButton.isHidden = false
            self.addActorButton.isHidden = false
            if !self.ifFinishEditingButtonHidden {
                self.finishEditingButton.isHidden = false
            }
            self.changeScriptButtonBackgroundView.isHidden = false
            self.changeScriptButton.isHidden = false
            
            UIView.animate(withDuration: 0.2) {
                self.recordButton.alpha = 1
                self.addActorButton.alpha = 1
                if !self.ifFinishEditingButtonHidden {
                    self.finishEditingButton.alpha = 1
                }
                self.changeScriptButtonBackgroundView.alpha = 1
                self.changeScriptButton.alpha = 1
            }
        })

        
        presenter?.stopRecording()
    }
    
    @objc
    private func goToScenesOverviewScreen() {
        animateButtonPress(button: backButton)
        presenter?.goToScenesOverviewScreen(arView: arView)
    }
    
    @objc
    private func changeResolutionButtonPressed() {
        presenter?.changeResolution()
        settingValueAnimation(button: changeResolutionButton)
    }
    
    @objc
    private func changeFPSButtonPressed() {
        presenter?.changeFPS()
        settingValueAnimation(button: changeFPSButton)
    }
    
    @objc
    private func changeISOButtonPressed() {
        settingPickerView.tag = 1
        changeSettingButtonPressed(tag: 1)
    }
    
    @objc
    private func changeWBButtonPressed() {
        settingPickerView.tag = 2
        changeSettingButtonPressed(tag: 2)
        
    }
    
    private func changeSettingButtonPressed(tag: Int) {
        settingPickerView.reloadAllComponents()
        let selectedRow = presenter?.getSelectedRowNumberForPickerView(tag: tag)
        settingPickerView.selectRow(selectedRow ?? 0, inComponent: 0, animated: false)
        pickerViewShowAnimation()
    }
    
    @objc
    private func handleTap(_ gesture: UITapGestureRecognizer) {
        presenter?.handleTap(gesture, arView)
    }
    
    @objc
    private func longTap(_ gesture: UILongPressGestureRecognizer) {
        presenter?.longTap(gesture, arView)
    }
    
    // MARK: - Animations
    private func loadingAnimation() {
        UIView.animate(withDuration: 0.5, delay: 3) {
            self.loadingView.alpha = 0
            self.loadingLabel.alpha = 0
        }
    }
    
    private func pickerViewShowAnimation() {
        if !settingPickerView.isHidden { return }
        
        settingPickerView.alpha = 0
        settingPickerView.isHidden = false
        
        let startY = view.frame.size.height
        let finishY = settingPickerView.frame.origin.y
        settingPickerView.frame.origin.y = startY
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.settingPickerView.alpha = 1
            self.settingPickerView.frame.origin.y = finishY
        }
    }
    
    private func pickerViewDismissAnimation() {
        if settingPickerView.isHidden { return }
        
        UIView.animate(withDuration: 0.2) {
            self.settingPickerView.alpha = 0
        } completion: { _ in
            self.settingPickerView.isHidden = true
        }
    }
    
    private func settingValueAnimation(button: UIButton) {
        UIView.animate(withDuration: 0.15) {
            button.alpha = 0
        } completion: { _ in
            self.fetchSettingsButtonValues()
            UIView.animate(withDuration: 0.15) {
                button.alpha = 1
            }
        }
    }
    
    private func focusPointAnimation(coordinates: CGPoint) {
        let focusPointView = UIView(frame: CGRect(x: coordinates.x - 50, y: coordinates.y - 50, width: 100, height: 100))
        focusPointView.layer.borderWidth = 2.0
        focusPointView.layer.borderColor = UIColor.yellow.cgColor
        focusPointView.backgroundColor = .clear
        arView.addSubview(focusPointView)
        
        UIView.animate(withDuration: 0.5) {
            focusPointView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            focusPointView.alpha = 0
        }
    }
    
    func animateButtonPress(button: UIButton) {
        UIView.animate(withDuration: 0.2, animations: {
            button.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            button.alpha = 0.8
        }, completion: { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = CGAffineTransform(scaleX: 1, y: 1)
                button.alpha = 1
            }
        })
    }
}

extension CameraScreenViewController: CameraScreenViewProtocol {
    
    func setSceneData(sceneData: SceneData) {
        self.sceneData = sceneData
        changeScriptButton.setTitle(sceneData.name, for: .normal)
        destroySubtitles()
        reformatScript(from: sceneData.script ?? "")
    }
    
    func reformatScript(from text: String) {
        if let result = presenter?.reformatScript(script: text) {
            let names = result.names
            let phrases = result.phrases
            displayDialogue(names: names, curNameIndex: 0, phrases: phrases, curPhraseIndex: 0)
        }
    }
    
    func displayDialogue(names: [String], curNameIndex: Int, phrases: [String], curPhraseIndex: Int) {
        if names.isEmpty || phrases.isEmpty { return }
        subtitlesNameLabel.text = names[curNameIndex]
        subtitlesPhraseLabel.text = phrases[curPhraseIndex]

        let stackView = UIStackView(arrangedSubviews: [subtitlesNameLabel, subtitlesPhraseLabel])
        stackView.axis = .horizontal
        stackView.alignment = .firstBaseline
        stackView.distribution = .fill
        stackView.spacing = 0
        view.addSubview(stackView)
        
        stackView.snp.remakeConstraints { make in
            make.centerX.equalToSuperview().offset(-15)
            make.bottom.equalToSuperview().offset(-30)
        }

        presenter?.startDialogueRecogniotion(names: names, curNameIndex: curNameIndex, phrases: phrases, curPhraseIndex: curPhraseIndex)
        
    }
    
    func destroySubtitles() {
        subtitlesNameLabel.text = ""
        subtitlesPhraseLabel.text = ""
    }
    
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
    
    fileprivate func changeButtonVisibilityAnimation(button: UIButton) {
        button.alpha = button.isHidden ? 0 : 1
        button.transform = button.isHidden ? CGAffineTransform(scaleX: 0.1, y: 0.1) : .identity
        
        if button.isHidden {
            button.isHidden = !button.isHidden
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                button.alpha = 1
                button.transform = .identity
            })
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                button.alpha = 0
                button.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            }, completion: { _ in
                button.isHidden = !button.isHidden
            })
        }
    }
    
    func changeButtonVisibility(buttonName: String) {
        if buttonName == "changeNameButton" {
            changeButtonVisibilityAnimation(button: changeNameButton)
        } else if buttonName == "finishEditingButton" {
            finishEditingButton.isHidden = false
            ifFinishEditingButtonHidden = false
        }
    }
    
    func getCurrentARView() -> ARView? {
        return arView
    }
    
    func addWarning(with text: String) {
        if currentWarnings.contains(text) { return }
        let warning = UIView.warningView(withImageName: text)
        currentWarnings.append(text)
        self.arView.addSubview(warning)
        warning.alpha = 0
        var offsetValue = 35
        if warningViews.count == 1 { offsetValue += 65 }
        if warningViews.count == 2 { return }
        warning.snp.makeConstraints { make in
            make.centerX.equalTo(backButton.snp.centerXWithinMargins)
            make.topMargin.equalTo(self.settingsBarBackgroundView.snp_bottomMargin).offset(offsetValue)
        }
        self.warningViews.append(warning)
        UIView.animate(withDuration: 0.4) {
            warning.alpha = 1
        } completion: { _ in
            Timer.scheduledTimer(timeInterval: TimeInterval(2), target: self, selector: #selector(self.hideWarning), userInfo: nil, repeats: false)
        }
    }
    
    @objc
    func hideWarning() {
        UIView.animate(withDuration: 0.4, animations: {
            self.warningViews.first?.alpha = 0
        }, completion: { _ in
            self.currentWarnings.removeFirst()
            self.warningViews.first?.removeFromSuperview()
            self.warningViews.removeFirst()
        })
    }
    
    func highlightFace(face: VNFaceObservation) {
        let boundingBox = face.boundingBox
        
        let screenWidth = arView.bounds.width
        let screenHeight = arView.bounds.height
        
        let distanceThreshold: CGFloat = 0.1 // Пороговое значение для определения близости к краю
        let isCloseToEdge = boundingBox.origin.x < distanceThreshold || boundingBox.origin.y < distanceThreshold ||
        (1 - (boundingBox.origin.x + boundingBox.width)) < distanceThreshold ||
        (1 - (boundingBox.origin.y + boundingBox.height)) < distanceThreshold
        
        // Проверим, нарушается ли правило третей для лица
        let isViolation = boundingBox.origin.x < 0.33 || boundingBox.origin.x + boundingBox.width > 0.66
        
        // Если лицо близко к краю экрана и нарушается правило третей, рисуем boundingBox
        if isCloseToEdge && isViolation {
            let convertedBoundingBox = CGRect(x: boundingBox.origin.x * screenWidth,
                                              y: (1 - boundingBox.origin.y) * screenHeight - boundingBox.height * screenHeight,
                                              width: boundingBox.width * screenWidth,
                                              height: boundingBox.height * screenHeight)
            
            let faceBoundingBoxShape = CAShapeLayer()
            faceBoundingBoxShape.frame = convertedBoundingBox
            faceBoundingBoxShape.fillColor = UIColor.clear.cgColor
            faceBoundingBoxShape.strokeColor = UIColor.red.cgColor
            faceBoundingBoxShape.path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: convertedBoundingBox.width, height: convertedBoundingBox.height)).cgPath
            
            arView.layer.addSublayer(faceBoundingBoxShape)
            
            addWarning(with: "person.crop.rectangle")
            
            self.drawings.append(faceBoundingBoxShape)
            
        }
    }
}

extension CameraScreenViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        processingQueue.async {
            CameraService.shared.gazeDetection(pixelBuffer: frame.capturedImage) { observation in
                DispatchQueue.main.async {
                    self.drawings.forEach { drawing in drawing.removeFromSuperlayer() }
                }

                for face in observation {
                    guard let faceCaptureQuality = face.faceCaptureQuality else { return }
                    DispatchQueue.main.async {
                        self.highlightFace(face: face)
                        if faceCaptureQuality < 0.35 {
                            self.addWarning(with: "blur")
                        }
                    }
                    
                }
            }
        }
        presenter?.session(session, didUpdate: frame)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        presenter?.session(session, didAdd: anchors, arView: arView)
    }
    
    
}

extension CameraScreenViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let _ = touch.view as? UIButton { return false }
        let touchPoint = touch.location(in: self.view)
        let arViewTouchPoint = touch.location(in: arView)
        let focusPoint = CGPoint(x: touchPoint.y / arView.bounds.height, y: touchPoint.x / arView.bounds.width)
            
        if settingsBarBackgroundView.frame.contains(touchPoint) {
            fetchSettingsButtonValues()
        }
        presenter?.focusOnTap(focusPoint: focusPoint)
        focusPointAnimation(coordinates: arViewTouchPoint)
        pickerViewDismissAnimation()
        return true
    }
}

    // MARK: - PickerView classes
extension CameraScreenViewController: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        guard let numberOfRows = presenter?.getNumberOfRowsInPickerView(tag: settingPickerView.tag) else { return 0 }
        return numberOfRows
    }
    
    
}

extension CameraScreenViewController: UIPickerViewDelegate {
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return presenter?.titleForRow(row: row, tag: settingPickerView.tag)
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        presenter?.didSelectRow(row: row, tag: settingPickerView.tag)
        self.fetchSettingsButtonValues()
    }
}


