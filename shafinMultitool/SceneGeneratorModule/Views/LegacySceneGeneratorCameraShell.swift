//
//  LegacySceneGeneratorCameraShell.swift
//  shafinMultitool
//
//  Created on 19.06.2026.
//

import Combine
import SnapKit
import SwiftUI
import UIKit

struct LegacySceneGeneratorCameraShell: UIViewControllerRepresentable {
    @ObservedObject var viewModel: SceneGeneratorViewModel
    let onBack: () -> Void

    func makeUIViewController(context: Context) -> LegacySceneGeneratorCameraViewController {
        LegacySceneGeneratorCameraViewController(viewModel: viewModel, onBack: onBack)
    }

    func updateUIViewController(_ uiViewController: LegacySceneGeneratorCameraViewController, context: Context) {
        uiViewController.refreshUI()
    }
}

final class LegacySceneGeneratorCameraViewController: UIViewController, UIGestureRecognizerDelegate {
    private let viewModel: SceneGeneratorViewModel
    private let onBack: () -> Void
    private var cancellables = Set<AnyCancellable>()

    private let backgroundView = UIView()
    private let arContainerView = UIView()
    private let settingsBarBackgroundView = UIView()
    private let backButton = UIButton(type: .custom)
    private let sceneButtonBackgroundView = UIView()
    private let sceneButton = UIButton(type: .custom)
    private let stopwatchBackgroundView = UIView()
    private let stopwatchLabel = UILabel()
    private let captureSettingsStackView = UIStackView()
    private let resolutionChipButton = UIButton(type: .custom)
    private let fpsChipButton = UIButton(type: .custom)

    private let addActorButton = UIButton(type: .custom)
    private let previewButton = UIButton(type: .custom)
    private let regenerateButton = UIButton(type: .custom)
    private let hintButton = UIButton(type: .custom)
    private let recordButton = UIButton(type: .custom)
    private let stopButton = UIButton(type: .custom)

    private let centerDot = UILabel()
    private let loadingView = UIView()
    private let loadingLabel = UILabel()
    private let settingPickerView = UIPickerView()

    private var arHostingController: UIHostingController<ARSceneContainer>?
    private var overlayHostingController: UIHostingController<LegacySceneGeneratorSwiftUIOverlay>?
    private var overlayActorDragLongPressRecognizer: UILongPressGestureRecognizer?
    private var shellTouchProbeTapRecognizer: UITapGestureRecognizer?
    private var shellTouchProbeLongPressRecognizer: UILongPressGestureRecognizer?
    private var overlayTouchProbeTapRecognizer: UITapGestureRecognizer?

    init(viewModel: SceneGeneratorViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        bindViewModel()
        refreshUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySplitButtonMasks()
    }

    private func setupUI() {
        view.backgroundColor = .black
        view.addSubview(backgroundView)
        backgroundView.backgroundColor = .black
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        backgroundView.addSubview(arContainerView)
        arContainerView.clipsToBounds = true
        arContainerView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leadingMargin.equalToSuperview()
            make.width.equalTo(arContainerView.snp.height).multipliedBy(16.0 / 9.0)
            make.height.equalToSuperview()
        }

        embedARView()
        embedSwiftUIOverlay()
        setupSettingsBar()
        setupLegacyControls()
        setupLoadingView()
        setupTouchDiagnostics()
    }

    private func embedARView() {
        let hostingController = UIHostingController(rootView: ARSceneContainer(viewModel: viewModel))
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        arContainerView.addSubview(hostingController.view)
        hostingController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hostingController.didMove(toParent: self)
        arHostingController = hostingController
    }

    private func embedSwiftUIOverlay() {
        let overlay = LegacySceneGeneratorSwiftUIOverlay(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: overlay)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = true
        let overlayTapGesture = UITapGestureRecognizer(target: self, action: #selector(overlayTouchProbeTapped(_:)))
        overlayTapGesture.cancelsTouchesInView = false
        overlayTapGesture.delaysTouchesBegan = false
        overlayTapGesture.delaysTouchesEnded = false
        overlayTapGesture.delegate = self
        hostingController.view.addGestureRecognizer(overlayTapGesture)
        overlayTouchProbeTapRecognizer = overlayTapGesture

        let actorDragGesture = UILongPressGestureRecognizer(target: self, action: #selector(storyboardActorDragLongPressed(_:)))
        actorDragGesture.minimumPressDuration = 0.35
        actorDragGesture.cancelsTouchesInView = false
        actorDragGesture.delaysTouchesBegan = false
        actorDragGesture.delaysTouchesEnded = false
        actorDragGesture.delegate = self
        hostingController.view.addGestureRecognizer(actorDragGesture)
        overlayActorDragLongPressRecognizer = actorDragGesture
        addChild(hostingController)
        arContainerView.addSubview(hostingController.view)
        hostingController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hostingController.didMove(toParent: self)
        overlayHostingController = hostingController
    }

    private func setupSettingsBar() {
        arContainerView.addSubview(settingsBarBackgroundView)
        settingsBarBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        settingsBarBackgroundView.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview()
            make.height.equalTo(37.5)
        }

        settingsBarBackgroundView.addSubview(backButton)
        backButton.setImage(UIImage(systemName: "arrow.uturn.backward.circle.fill"), for: .normal)
        backButton.tintColor = .white
        backButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leadingMargin.equalToSuperview().offset(15)
        }

        captureSettingsStackView.axis = .horizontal
        captureSettingsStackView.alignment = .center
        captureSettingsStackView.spacing = 6
        settingsBarBackgroundView.addSubview(captureSettingsStackView)
        configureCaptureSettingChip(resolutionChipButton)
        configureCaptureSettingChip(fpsChipButton)
        captureSettingsStackView.addArrangedSubview(resolutionChipButton)
        captureSettingsStackView.addArrangedSubview(fpsChipButton)
        resolutionChipButton.snp.makeConstraints { make in
            make.height.equalTo(24)
        }
        fpsChipButton.snp.makeConstraints { make in
            make.height.equalTo(24)
        }
        captureSettingsStackView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(backButton.snp.trailing).offset(34)
        }

        sceneButtonBackgroundView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        sceneButtonBackgroundView.layer.cornerRadius = 10
        sceneButtonBackgroundView.layer.masksToBounds = true
        settingsBarBackgroundView.addSubview(sceneButtonBackgroundView)
        sceneButtonBackgroundView.snp.makeConstraints { make in
            make.height.equalTo(30)
            make.center.equalToSuperview()
        }

        sceneButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        sceneButton.setTitleColor(.white, for: .normal)
        sceneButtonBackgroundView.addSubview(sceneButton)
        sceneButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.bottom.leading.trailing.equalToSuperview().inset(10)
        }

        stopwatchBackgroundView.isHidden = true
        stopwatchBackgroundView.backgroundColor = UIColor.red.withAlphaComponent(0.8)
        stopwatchBackgroundView.layer.cornerRadius = 10
        stopwatchBackgroundView.layer.masksToBounds = true
        settingsBarBackgroundView.addSubview(stopwatchBackgroundView)
        stopwatchBackgroundView.snp.makeConstraints { make in
            make.width.equalTo(120)
            make.height.equalTo(30)
            make.center.equalToSuperview()
        }

        stopwatchLabel.textColor = .white
        stopwatchLabel.font = .boldSystemFont(ofSize: 16)
        stopwatchLabel.text = "00:00"
        stopwatchBackgroundView.addSubview(stopwatchLabel)
        stopwatchLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func setupLegacyControls() {
        configureRoundButton(addActorButton,
                             size: 75,
                             backgroundColor: .white,
                             imageName: "plus",
                             tintColor: .black)
        backgroundView.addSubview(addActorButton)
        addActorButton.snp.makeConstraints { make in
            make.width.height.equalTo(75)
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(10)
        }

        configureRoundButton(previewButton,
                             size: 60,
                             backgroundColor: .white,
                             imageName: "play",
                             tintColor: .black)
        backgroundView.addSubview(previewButton)
        previewButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.topMargin.equalToSuperview().offset(15)
            make.centerX.equalTo(addActorButton.snp.centerX).offset(-10)
        }

        configureRoundButton(regenerateButton,
                             size: 60,
                             backgroundColor: .white,
                             imageName: "sparkles",
                             tintColor: .black)
        backgroundView.addSubview(regenerateButton)
        regenerateButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.topMargin.equalToSuperview().offset(25)
            make.centerX.equalTo(addActorButton.snp.centerX).offset(10)
        }

        configureRoundButton(hintButton,
                             size: 60,
                             backgroundColor: UIColor.white.withAlphaComponent(0.5),
                             imageName: "lightbulb",
                             tintColor: .black)
        backgroundView.addSubview(hintButton)
        hintButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.leftMargin.equalToSuperview().offset(40)
            make.centerY.equalTo(addActorButton.snp_centerYWithinMargins)
        }

        configureRoundButton(recordButton,
                             size: 60,
                             backgroundColor: .red,
                             imageName: "largecircle.fill.circle",
                             tintColor: .white)
        backgroundView.addSubview(recordButton)
        recordButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.bottomMargin.equalToSuperview().inset(5)
            make.centerX.equalTo(addActorButton.snp.centerX)
        }

        configureRoundButton(stopButton,
                             size: 60,
                             backgroundColor: .white,
                             imageName: "stop.fill",
                             tintColor: .black)
        backgroundView.addSubview(stopButton)
        stopButton.snp.makeConstraints { make in
            make.width.height.equalTo(60)
            make.bottomMargin.equalToSuperview().inset(5)
            make.centerX.equalTo(addActorButton.snp.centerX)
        }

        centerDot.text = "+"
        centerDot.font = .systemFont(ofSize: 30)
        centerDot.textColor = .white
        arContainerView.addSubview(centerDot)
        centerDot.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        backgroundView.addSubview(settingPickerView)
        settingPickerView.isHidden = true
        settingPickerView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        settingPickerView.layer.cornerRadius = 10
        settingPickerView.snp.makeConstraints { make in
            make.rightMargin.equalTo(arContainerView.snp_rightMargin).offset(-12.5)
            make.bottomMargin.equalTo(backgroundView.snp_bottomMargin)
        }
    }

    private func setupLoadingView() {
        backgroundView.addSubview(loadingView)
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 16, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 2
        backgroundView.addSubview(loadingLabel)
        loadingLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(32)
        }
    }

    private func configureRoundButton(_ button: UIButton,
                                      size: CGFloat,
                                      backgroundColor: UIColor,
                                      imageName: String,
                                      tintColor: UIColor) {
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = size / 2
        button.layer.masksToBounds = true
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = tintColor
    }

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backButtonPressed), for: .touchUpInside)
        sceneButton.addTarget(self, action: #selector(sceneButtonPressed), for: .touchUpInside)
        addActorButton.addTarget(self, action: #selector(markingButtonPressed), for: .touchUpInside)
        previewButton.addTarget(self, action: #selector(previewButtonPressed), for: .touchUpInside)
        regenerateButton.addTarget(self, action: #selector(regenerateButtonPressed), for: .touchUpInside)
        hintButton.addTarget(self, action: #selector(hintButtonPressed), for: .touchUpInside)
        hintButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hintButtonLongPressed(_:))))
        recordButton.addTarget(self, action: #selector(recordButtonPressed), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopButtonPressed), for: .touchUpInside)
        resolutionChipButton.addTarget(self, action: #selector(resolutionChipPressed), for: .touchUpInside)
        fpsChipButton.addTarget(self, action: #selector(fpsChipPressed), for: .touchUpInside)
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshUI()
                }
            }
            .store(in: &cancellables)
    }

    func refreshUI() {
        sceneButton.setTitle(viewModel.sceneTitle, for: .normal)
        sceneButtonBackgroundView.isHidden = viewModel.isRecording
        stopwatchBackgroundView.isHidden = !viewModel.isRecording
        stopwatchLabel.text = formattedTime(viewModel.recordingElapsedTime)
        refreshCaptureSettingChips()

        let hasDescription = !viewModel.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasGeneratedScene = viewModel.plannedScene != nil

        addActorButton.backgroundColor = viewModel.isMarkingMode ? .systemGreen : .white
        addActorButton.tintColor = viewModel.isMarkingMode ? .white : .black
        addActorButton.setImage(UIImage(systemName: viewModel.isMarkingMode ? "checkmark" : "plus"), for: .normal)

        previewButton.isHidden = !hasGeneratedScene
        previewButton.isEnabled = hasGeneratedScene && !viewModel.isRecording
        previewButton.alpha = previewButton.isEnabled ? 1 : 0.45
        previewButton.setImage(UIImage(systemName: viewModel.isPlaying ? "stop.fill" : "play"), for: .normal)

        regenerateButton.isHidden = !hasDescription
        regenerateButton.isEnabled = hasDescription && !viewModel.isGenerating
        regenerateButton.alpha = regenerateButton.isEnabled ? 1 : 0.45

        hintButton.backgroundColor = UIColor.white.withAlphaComponent(viewModel.isHintsEnabled ? 0.85 : 0.5)
        hintButton.setImage(UIImage(systemName: viewModel.isHintsEnabled ? "lightbulb.fill" : "lightbulb"), for: .normal)

        recordButton.isHidden = viewModel.isRecording
        recordButton.isEnabled = hasGeneratedScene
        recordButton.alpha = hasGeneratedScene ? 1 : 0.45
        stopButton.isHidden = !viewModel.isRecording

        loadingView.isHidden = viewModel.isARSessionReady && !viewModel.isGenerating
        loadingLabel.isHidden = loadingView.isHidden
        loadingLabel.text = viewModel.isGenerating ? "Собираю сцену" : viewModel.statusMessage
        centerDot.isHidden = !viewModel.isMarkingMode

        let passTouchesToAR = SceneGeneratorViewModel.shouldPassTouchesThroughSwiftUIOverlay(
            isMarkingMode: viewModel.isMarkingMode,
            hasActiveStoryboardEditor: viewModel.activeStoryboardEditDraft != nil
        )
        overlayHostingController?.view.isUserInteractionEnabled = !passTouchesToAR
    }

    private func configureCaptureSettingChip(_ button: UIButton) {
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        button.layer.masksToBounds = true
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.65), for: .highlighted)
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 9, bottom: 2, right: 9)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func refreshCaptureSettingChips() {
        resolutionChipButton.setTitle(currentResolutionLabel(), for: .normal)
        fpsChipButton.setTitle(currentFPSLabel(), for: .normal)
        resolutionChipButton.accessibilityLabel = "Разрешение \(currentResolutionLabel())"
        fpsChipButton.accessibilityLabel = "Частота \(currentFPSLabel()) кадров"
    }

    private func setupTouchDiagnostics() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(shellTouchProbeTapped(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delaysTouchesBegan = false
        tapGesture.delaysTouchesEnded = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        shellTouchProbeTapRecognizer = tapGesture

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(shellTouchProbeLongPressed(_:)))
        longPressGesture.minimumPressDuration = 0.35
        longPressGesture.cancelsTouchesInView = false
        longPressGesture.delaysTouchesBegan = false
        longPressGesture.delaysTouchesEnded = false
        longPressGesture.delegate = self
        view.addGestureRecognizer(longPressGesture)
        shellTouchProbeLongPressRecognizer = longPressGesture
    }

    private func applySplitButtonMasks() {
        guard previewButton.bounds.width > 0, regenerateButton.bounds.width > 0 else { return }

        let previewMask = CAShapeLayer()
        previewMask.frame = previewButton.bounds
        let previewPath = UIBezierPath()
        previewPath.move(to: CGPoint(x: 0, y: 0))
        previewPath.addLine(to: CGPoint(x: 0, y: previewButton.bounds.height))
        previewPath.addLine(to: CGPoint(x: previewButton.bounds.width, y: 0))
        previewPath.close()
        previewMask.path = previewPath.cgPath
        previewButton.layer.mask = previewMask
        previewButton.imageEdgeInsets = UIEdgeInsets(top: 0,
                                                     left: 0,
                                                     bottom: previewButton.bounds.height / 3.5,
                                                     right: previewButton.bounds.width / 3.5)

        let regenerateMask = CAShapeLayer()
        regenerateMask.frame = regenerateButton.bounds
        let regeneratePath = UIBezierPath()
        regeneratePath.move(to: CGPoint(x: 0, y: regenerateButton.bounds.height))
        regeneratePath.addLine(to: CGPoint(x: regenerateButton.bounds.width, y: regenerateButton.bounds.height))
        regeneratePath.addLine(to: CGPoint(x: regenerateButton.bounds.width, y: 0))
        regeneratePath.close()
        regenerateMask.path = regeneratePath.cgPath
        regenerateButton.layer.mask = regenerateMask
        regenerateButton.imageEdgeInsets = UIEdgeInsets(top: regenerateButton.bounds.height / 3.5,
                                                        left: regenerateButton.bounds.width / 3.5,
                                                        bottom: 0,
                                                        right: 0)
    }

    private func formattedTime(_ elapsedTime: TimeInterval) -> String {
        let totalSeconds = Int(elapsedTime.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func currentResolutionLabel() -> String {
        let description = UserDefaults.standard.string(forKey: "resolutionDescription")?.lowercased()
        let width = UserDefaults.standard.integer(forKey: "resolutionWidth")
        let height = UserDefaults.standard.integer(forKey: "resolutionHeight")

        if description == "uhd" || width >= 3840 || height >= 2160 {
            return "4K"
        }
        if description == "fhd" || width >= 1920 || height >= 1080 {
            return "FHD"
        }
        if description == "hd" || width >= 1280 || height >= 720 {
            return "HD"
        }
        return "4K"
    }

    private func currentFPSLabel() -> String {
        let fps = UserDefaults.standard.integer(forKey: "framerate")
        return String(fps == 0 ? 30 : fps)
    }

    @objc private func backButtonPressed() {
        onBack()
    }

    @objc private func sceneButtonPressed() {
        viewModel.showInput()
    }

    @objc private func markingButtonPressed() {
        viewModel.toggleMarkingMode()
    }

    @objc private func previewButtonPressed() {
        if viewModel.isPlaying {
            viewModel.stopScene()
        } else {
            viewModel.playScene()
        }
    }

    @objc private func regenerateButtonPressed() {
        Task { await viewModel.generateScene() }
    }

    @objc private func hintButtonPressed() {
        viewModel.toggleHintsEnabled()
    }

    @objc private func resolutionChipPressed() {
        let presets: [(description: String, width: Int, height: Int)] = [
            ("hd", 1280, 720),
            ("fhd", 1920, 1080),
            ("uhd", 3840, 2160)
        ]
        let currentDescription = UserDefaults.standard.string(forKey: "resolutionDescription")?.lowercased()
        let currentWidth = UserDefaults.standard.integer(forKey: "resolutionWidth")
        let currentIndex = presets.firstIndex { preset in
            preset.description == currentDescription || preset.width == currentWidth
        } ?? (presets.count - 1)
        let next = presets[(currentIndex + 1) % presets.count]
        UserDefaults.standard.set(next.description, forKey: "resolutionDescription")
        UserDefaults.standard.set(next.width, forKey: "resolutionWidth")
        UserDefaults.standard.set(next.height, forKey: "resolutionHeight")
        refreshCaptureSettingChips()
        SceneGeneratorDiagnosticsLogger.shared.log("[CAPTURE_SETTINGS] resolution changed label=\(currentResolutionLabel()), width=\(next.width), height=\(next.height)")
    }

    @objc private func fpsChipPressed() {
        let presets = [24, 25, 30, 60]
        let currentFPS = UserDefaults.standard.integer(forKey: "framerate")
        let currentIndex = presets.firstIndex(of: currentFPS) ?? 1
        let next = presets[(currentIndex + 1) % presets.count]
        UserDefaults.standard.set(next, forKey: "framerate")
        refreshCaptureSettingChips()
        SceneGeneratorDiagnosticsLogger.shared.log("[CAPTURE_SETTINGS] fps changed fps=\(next)")
    }

    @objc private func hintButtonLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }

        let alert = UIAlertController(
            title: "Режим анализа",
            message: "Скрытая настройка для записи демо. На экране съёмки режим не показывается.",
            preferredStyle: .actionSheet
        )
        for mode in CameraDemoSceneMode.allCases {
            let marker = mode == viewModel.cameraDemoSceneMode ? "✓ " : ""
            alert.addAction(
                UIAlertAction(title: marker + demoModeTitle(mode), style: .default) { [weak self] _ in
                    Task { @MainActor in
                        self?.viewModel.setCameraDemoSceneMode(mode)
                    }
                }
            )
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.popoverPresentationController?.sourceView = hintButton
        alert.popoverPresentationController?.sourceRect = hintButton.bounds
        present(alert, animated: true)
    }

    @objc private func shellTouchProbeTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: arContainerView)
        SceneGeneratorDiagnosticsLogger.shared.log(
            "[TOUCH_TRACE] shell tap ended point=(\(Self.formatGestureCoordinate(location.x)), \(Self.formatGestureCoordinate(location.y))), insideAR=\(arContainerView.bounds.contains(location)), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil"), overlayInteractive=\(overlayHostingController?.view.isUserInteractionEnabled == true)"
        )
    }

    @objc private func shellTouchProbeLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: arContainerView)
        let insideAR = arContainerView.bounds.contains(location)
        if Self.shouldLogStoryboardActorDragGestureState(recognizer.state) {
            SceneGeneratorDiagnosticsLogger.shared.log(
                "[TOUCH_TRACE] shell longPress state=\(Self.storyboardActorDragGestureStateDescription(recognizer.state)) point=(\(Self.formatGestureCoordinate(location.x)), \(Self.formatGestureCoordinate(location.y))), insideAR=\(insideAR), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil"), overlayInteractive=\(overlayHostingController?.view.isUserInteractionEnabled == true)"
            )
        }

        guard insideAR,
              !viewModel.isMarkingMode,
              viewModel.activeStoryboardEditDraft == nil,
              viewModel.plannedScene != nil,
              !viewModel.isPlaying,
              !viewModel.isGenerating,
              !viewModel.isRecording
        else { return }

        viewModel.handleStoryboardActorDragGesture(state: recognizer.state, at: location)
    }

    @objc private func overlayTouchProbeTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: arContainerView)
        SceneGeneratorDiagnosticsLogger.shared.log(
            "[TOUCH_TRACE] overlay tap ended point=(\(Self.formatGestureCoordinate(location.x)), \(Self.formatGestureCoordinate(location.y))), insideAR=\(arContainerView.bounds.contains(location)), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil")"
        )
    }

    @objc private func storyboardActorDragLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer === overlayActorDragLongPressRecognizer,
              viewModel.activeStoryboardEditDraft != nil
        else { return }

        let location = recognizer.location(in: arContainerView)
        guard arContainerView.bounds.contains(location) else { return }

        if Self.shouldLogStoryboardActorDragGestureState(recognizer.state) {
            SceneGeneratorDiagnosticsLogger.shared.log(
                "[AR_GESTURE] overlay longPress state=\(Self.storyboardActorDragGestureStateDescription(recognizer.state)) point=(\(Self.formatGestureCoordinate(location.x)), \(Self.formatGestureCoordinate(location.y)))"
            )
        }
        viewModel.handleStoryboardActorDragGesture(state: recognizer.state, at: location)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === overlayActorDragLongPressRecognizer else { return true }

        let location = touch.location(in: arContainerView)
        let hasActiveEditor = viewModel.activeStoryboardEditDraft != nil
        let isBusy = viewModel.isPlaying || viewModel.isGenerating || viewModel.isRecording
        let isInsideAR = arContainerView.bounds.contains(location)
        let shouldReceive = hasActiveEditor && !isBusy && isInsideAR
        SceneGeneratorDiagnosticsLogger.shared.log(
            "[TOUCH_TRACE] overlay longPress shouldReceive=\(shouldReceive), point=(\(Self.formatGestureCoordinate(location.x)), \(Self.formatGestureCoordinate(location.y))), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil"), busy=\(isBusy), insideAR=\(isInsideAR), touchView=\(Self.touchViewDescription(touch.view))"
        )
        return shouldReceive
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        isTouchDiagnosticRecognizer(gestureRecognizer)
            || isTouchDiagnosticRecognizer(otherGestureRecognizer)
            || gestureRecognizer === overlayActorDragLongPressRecognizer
            || otherGestureRecognizer === overlayActorDragLongPressRecognizer
    }

    private func isTouchDiagnosticRecognizer(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer === shellTouchProbeTapRecognizer
            || recognizer === shellTouchProbeLongPressRecognizer
            || recognizer === overlayTouchProbeTapRecognizer
    }

    private static func shouldLogStoryboardActorDragGestureState(_ state: UIGestureRecognizer.State) -> Bool {
        switch state {
        case .began, .ended, .cancelled, .failed:
            return true
        default:
            return false
        }
    }

    private static func storyboardActorDragGestureStateDescription(_ state: UIGestureRecognizer.State) -> String {
        switch state {
        case .possible:
            return "possible"
        case .began:
            return "began"
        case .changed:
            return "changed"
        case .ended:
            return "ended"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }

    private static func formatGestureCoordinate(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func touchViewDescription(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        return String(describing: type(of: view))
    }

    @objc private func recordButtonPressed() {
        viewModel.startRecording()
    }

    @objc private func stopButtonPressed() {
        viewModel.stopRecording()
    }

    private func demoModeTitle(_ mode: CameraDemoSceneMode) -> String {
        switch mode {
        case .auto:
            return "Авто"
        case .object:
            return "Предмет"
        case .portrait:
            return "Портрет"
        case .cinematicPortrait:
            return "Кино-портрет"
        case .dialogue:
            return "Диалог"
        }
    }
}

private struct LegacySceneGeneratorSwiftUIOverlay: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel
    @State private var decisionTrace: DecisionTracePresentation?
    @State private var isStoryboardTrayExpanded = false
    @State private var storyboardEditorDetent: PresentationDetent = .medium

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ThirdsGridOverlay()
                    .stroke(Color.black.opacity(0.48), lineWidth: 1)
                    .allowsHitTesting(false)

                objectLabelsOverlay
                    .allowsHitTesting(false)

                if viewModel.isHintsEnabled {
                    HintAnnotationsOverlayView(
                        overlayState: viewModel.coachingOverlayState,
                        annotations: viewModel.coachingOverlayAnnotations,
                        canvasSize: proxy.size,
                        displayTransform: viewModel.hintDisplayTransform,
                        showPrimaryBoundingBox: shouldShowPrimaryHintBoundingBox
                    )
                    .allowsHitTesting(false)

                    hintTopControls

                    if viewModel.isHintPauseAnalysisActive {
                        hintPausePanel(size: proxy.size)
                    } else if viewModel.liveHint != nil {
                        liveHintPanel(size: proxy.size)
                    } else {
                        liveStatusPanel
                    }
                }

                if shouldShowBeatHUD {
                    VStack {
                        HStack {
                            beatHUD
                            Spacer()
                        }
                        .padding(.top, beatHUDTopPadding)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                }

                VStack {
                    Spacer()

                    if viewModel.isMarkingMode {
                        markingHint
                            .padding(.bottom, 68)
                            .allowsHitTesting(false)
                    }

                    if shouldShowStoryboardStrip {
                        storyboardPresentation
                            .padding(.bottom, 8)
                    }

                    captions
                        .padding(.bottom, shouldShowStoryboardStrip ? 8 : 18)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(item: $viewModel.activeStoryboardEditDraft) { draft in
            StoryboardBeatEditorSheet(draft: draft, viewModel: viewModel)
                .presentationDetents([.medium, .large], selection: $storyboardEditorDetent)
                .presentationDragIndicator(.visible)
                .modifier(StoryboardEditorPresentationModifier())
                .onAppear {
                    storyboardEditorDetent = .medium
                }
        }
        .sheet(item: $decisionTrace) { trace in
            DecisionTraceView(trace: trace)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var shouldShowBeatHUD: Bool {
        viewModel.isPlaying && !viewModel.beatTimelineItems.isEmpty
    }

    private var shouldShowStoryboardStrip: Bool {
        viewModel.plannedScene != nil && !viewModel.storyboardBeatItems.isEmpty && !viewModel.isGenerating
    }

    private var beatHUDTopPadding: CGFloat {
        viewModel.isHintsEnabled && (viewModel.liveHint != nil || viewModel.isHintPauseAnalysisActive) ? 92 : 47
    }

    private var shouldShowPrimaryHintBoundingBox: Bool {
        viewModel.liveHint?.id.hasPrefix("lh_demo_") != true
    }

    private var objectLabelsOverlay: some View {
        ZStack {
            ForEach(viewModel.objectLabelItems) { item in
                ObjectTrackingLabel(item: item)
                    .position(item.position)
            }
        }
    }

    private var hintTopControls: some View {
        VStack {
            HStack {
                Spacer()

                if canShowDecisionTrace {
                    Button(action: showDecisionTrace) {
                        Image(systemName: "questionmark.circle.fill")
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(ARHintIconButtonStyle())
                    .accessibilityLabel("Показать объяснение live-подсказки")
                }

                Button(action: toggleHintPauseAnalysis) {
                    Image(systemName: viewModel.isHintPauseAnalysisActive ? "play.circle.fill" : "pause.circle.fill")
                        .accessibilityHidden(true)
                }
                .buttonStyle(ARHintIconButtonStyle())
                .accessibilityLabel(viewModel.isHintPauseAnalysisActive ? "Продолжить live-анализ" : "Запустить углубленный разбор кадра")
            }
            .padding(.top, 47)
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private func liveHintPanel(size: CGSize) -> some View {
        VStack {
            HStack {
                if let liveHint = viewModel.liveHint {
                    if liveHint.actionType == .leaveFrameAsIs {
                        Spacer()
                        ARLiveHintCheckView()
                        Spacer()
                    } else {
                        ARLiveHintCompactChip(
                            liveHint: liveHint,
                            onExplain: canShowDecisionTrace ? showDecisionTrace : nil
                        )
                        .frame(maxWidth: min(size.width * 0.34, 300), alignment: .leading)

                        Spacer()
                    }
                }
            }

            Spacer()
        }
        .padding(.top, 75)
        .padding(.horizontal, 16)
    }

    private var liveStatusPanel: some View {
        VStack {
            ARLiveAnalysisStatusChip(
                title: viewModel.isRecording ? "Стабилизирую кадр" : "Анализ кадра активен",
                message: viewModel.isRecording ? "Подсказка появится при уверенном сигнале." : "Для полного разбора нажми «Разбор»."
            )
            .padding(.top, 52)

            Spacer()
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func hintPausePanel(size: CGSize) -> some View {
        VStack {
            Spacer()

            if let pauseCritique = viewModel.hintPauseCritique {
                PauseCritiqueCardView(
                    critique: pauseCritique,
                    legacySuggestions: viewModel.hintPreviewSuggestions,
                    maxHeight: pausePanelMaxHeight(for: size),
                    onContinue: resumeHintLiveAnalysis,
                    onExplain: canShowDecisionTrace ? showDecisionTrace : nil
                )
            } else {
                PauseStatusPanelView(
                    title: "Анализирую кадр",
                    message: "Остановил поток и собираю признаки для разбора.",
                    suggestions: viewModel.hintPreviewSuggestions,
                    maxHeight: pausePanelMaxHeight(for: size),
                    onContinue: resumeHintLiveAnalysis
                )
            }
        }
        .padding(.bottom, 18)
    }

    private var canShowDecisionTrace: Bool {
        viewModel.makeHintDecisionTrace() != nil
    }

    private func toggleHintPauseAnalysis() {
        if viewModel.isHintPauseAnalysisActive {
            resumeHintLiveAnalysis()
        } else {
            decisionTrace = nil
            viewModel.startHintPauseAnalysis()
        }
    }

    private func resumeHintLiveAnalysis() {
        decisionTrace = nil
        viewModel.resumeHintLiveAnalysis()
    }

    private func showDecisionTrace() {
        decisionTrace = viewModel.makeHintDecisionTrace()
    }

    private func pausePanelMaxHeight(for size: CGSize) -> CGFloat {
        max(210, size.height * 0.42)
    }

    private var beatHUD: some View {
        let total = max(viewModel.beatTimelineItems.count, 1)
        let activeIndex = min(max(viewModel.activeBeatIndex, 0), total - 1)
        let activeItem = viewModel.beatTimelineItems[activeIndex]
        let progress = min(max(viewModel.beatProgress, 0), 1)
        let currentCaption = currentBeatCaption

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Такт \(activeIndex + 1)/\(total) · \(activeItem.kindTitle)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if activeItem.hasDialogueCaption {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }

                if activeItem.hasActionCaption {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                }
            }

            if let currentCaption {
                Text(currentCaption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)

            GeometryReader { geometry in
                let itemCount = max(viewModel.beatTimelineItems.count, 1)
                let slotWidth = max(0, geometry.size.width / CGFloat(itemCount))
                let markerSpacing = min(3, max(0.25, slotWidth * 0.25))
                let markerWidth = max(0.5, min(7, slotWidth - markerSpacing))

                HStack(spacing: markerSpacing) {
                    ForEach(viewModel.beatTimelineItems) { item in
                        Capsule()
                            .fill(item.index == activeIndex ? Color.white.opacity(0.92) : Color.white.opacity(0.32))
                            .frame(width: markerWidth, height: item.index == activeIndex ? 5 : 4)
                            .overlay(alignment: .center) {
                                if item.hasDialogueCaption || item.hasActionCaption {
                                    Circle()
                                        .fill(item.hasDialogueCaption ? Color.cyan.opacity(0.95) : Color.yellow.opacity(0.95))
                                        .frame(width: min(3, markerWidth), height: min(3, markerWidth))
                                }
                            }
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 210, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var currentBeatCaption: String? {
        let candidates = [
            viewModel.activeActionCaption,
            viewModel.activeDialogueCaption,
            viewModel.activeScreenTextCaption,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var markingHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .foregroundColor(.green.opacity(0.9))

            Text("Тапните на объект для разметки")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.green.opacity(0.55), lineWidth: 1)
                )
        )
    }

    private var storyboardStrip: some View {
        let activeBeatID = activeStoryboardBeatID
        let progress = min(max(viewModel.beatProgress, 0), 1)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.storyboardBeatItems) { item in
                    Button {
                        viewModel.openStoryboardEditor(for: item.beatID)
                    } label: {
                        StoryboardBeatChip(
                            item: item,
                            isActive: item.beatID == activeBeatID,
                            progress: item.beatID == activeBeatID ? progress : 0
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Редактировать \(item.kindTitle) \(item.index + 1)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var storyboardPresentation: some View {
        storyboardTray
    }

    private var storyboardTray: some View {
        VStack(spacing: 6) {
            if isStoryboardTrayExpanded {
                storyboardStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isStoryboardTrayExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isStoryboardTrayExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))

                    Text("Такты \(viewModel.storyboardBeatItems.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.52))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isStoryboardTrayExpanded ? "Свернуть сториборд" : "Развернуть сториборд")
        }
    }

    private var activeStoryboardBeatID: String? {
        guard viewModel.isPlaying,
              viewModel.beatTimelineItems.indices.contains(viewModel.activeBeatIndex)
        else { return nil }
        return viewModel.beatTimelineItems[viewModel.activeBeatIndex].beatID
    }

    @ViewBuilder
    private var captions: some View {
        VStack(spacing: 8) {
            if let screenText = viewModel.activeScreenTextCaption {
                legacyCaption(text: screenText, systemImage: "text.bubble")
            }

            if let actionCaption = viewModel.activeActionCaption {
                legacyCaption(text: actionCaption, systemImage: "sparkles")
            }

            if let dialogueCaption = viewModel.activeDialogueCaption {
                legacySubtitle(text: dialogueCaption)
            }
        }
    }

    private func legacyCaption(text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(.white.opacity(0.94))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 260)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.52))
        )
    }

    private func legacySubtitle(text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.5))
            )
    }
}

private struct ObjectTrackingLabel: View {
    let item: ARObjectLabelPresentation

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.swiftUIColor.opacity(0.95))
                .frame(width: 6, height: 6)

            Text(item.text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.58))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
    }
}

private struct StoryboardBeatChip: View {
    let item: StoryboardBeatPresentationItem
    let isActive: Bool
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("\(item.index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? .black : .white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(isActive ? Color.white.opacity(0.92) : Color.white.opacity(0.18)))

                Text(item.kindTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if item.hasDialogueCaption {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.cyan)
                }

                if item.hasActionCaption {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                }
            }

            Text(item.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(isActive ? Color.white.opacity(0.88) : Color.white.opacity(0.28))
                        .frame(width: geometry.size.width * CGFloat(isActive ? min(max(progress, 0), 1) : 1))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 132, height: 54, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.white.opacity(0.38) : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct StoryboardBeatEditorSheet: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel
    @State private var draft: StoryboardBeatEditDraft
    @State private var isSaving = false

    init(draft: StoryboardBeatEditDraft, viewModel: SceneGeneratorViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StoryboardBeatInspectorCard(
                        title: draft.title,
                        inspector: viewModel.buildStoryboardBeatInspector(for: draft)
                    )

                    ForEach($draft.actions) { $action in
                        StoryboardActionEditorRow(
                            action: $action,
                            actorOptions: draft.actorOptions,
                            targetOptions: targetOptions(for: action),
                            onDelete: { removeAction(id: action.id) }
                        )
                    }

                    Button(action: addAction) {
                        Label("Добавить действие", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(StoryboardEditorSecondaryButtonStyle())

                    HStack(spacing: 10) {
                        Button {
                            Task { await move(offset: -1) }
                        } label: {
                            Label("Влево", systemImage: "chevron.left")
                        }
                        .buttonStyle(StoryboardEditorSecondaryButtonStyle())

                        Button {
                            Task { await move(offset: 1) }
                        } label: {
                            Label("Вправо", systemImage: "chevron.right")
                        }
                        .buttonStyle(StoryboardEditorSecondaryButtonStyle())
                    }

                    Button(role: .destructive) {
                        Task { await deleteBeat() }
                    } label: {
                        Label("Удалить такт", systemImage: "trash")
                    }
                    .buttonStyle(StoryboardEditorDestructiveButtonStyle())
                }
                .padding(18)
            }
            .background(Color.black.opacity(0.94).ignoresSafeArea())
            .navigationTitle("Редактор такта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        viewModel.cancelStoryboardEditor()
                    }
                    .foregroundStyle(.white.opacity(0.86))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Сохраняю" : "Сохранить") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func targetOptions(for action: StoryboardActionEditDraft) -> [StoryboardEntityOption] {
        guard action.type.usesStoryboardTarget else {
            return [StoryboardEntityOption(id: "none", label: "Нет цели", kind: .none)]
        }
        if action.type == .give {
            return draft.targetOptions.filter { option in
                !(option.kind == .actor && option.id == action.actorId)
            }
        }
        return draft.targetOptions
    }

    private func addAction() {
        let actorID = draft.actorOptions.first?.id ?? "actor_1"
        draft.actions.append(
            StoryboardActionEditDraft(
                id: "manual_action_\(UUID().uuidString)",
                actorId: actorID,
                type: .describedAction,
                target: nil,
                text: "Новое действие",
                isDeleted: false,
                isNew: true
            )
        )
    }

    private func removeAction(id: String) {
        draft.actions.removeAll { $0.id == id }
    }

    private func save() async {
        isSaving = true
        _ = await viewModel.applyStoryboardBeatEdit(draft)
        isSaving = false
    }

    private func deleteBeat() async {
        isSaving = true
        _ = await viewModel.deleteStoryboardBeat(beatID: draft.beatID)
        isSaving = false
    }

    private func move(offset: Int) async {
        isSaving = true
        _ = await viewModel.moveStoryboardBeat(beatID: draft.beatID, offset: offset)
        isSaving = false
    }
}

private struct StoryboardEditorPresentationModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            content
        }
    }
}

private struct StoryboardBeatInspectorCard: View {
    let title: String
    let inspector: StoryboardBeatInspectorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text(inspector.kindTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.10)))

                Spacer()

                Label(inspector.durationText, systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Text(inspector.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if !inspector.actorLabels.isEmpty {
                    inspectorChipRow(title: "Актёры", labels: inspector.actorLabels, color: .cyan, icon: "person.2.fill")
                }

                if !inspector.targetLabels.isEmpty {
                    inspectorChipRow(title: "Цели", labels: inspector.targetLabels, color: .yellow, icon: "scope")
                }

                if !inspector.warnings.isEmpty {
                    inspectorChipRow(title: "Проверка", labels: inspector.warnings, color: .orange, icon: "exclamationmark.triangle.fill")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func inspectorChipRow(title: String, labels: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))

            FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(color.opacity(0.16))
                                .overlay(
                                    Capsule()
                                        .stroke(color.opacity(0.34), lineWidth: 1)
                                )
                        )
                }
            }
        }
    }
}

private struct StoryboardActionEditorRow: View {
    @Binding var action: StoryboardActionEditDraft
    let actorOptions: [StoryboardEntityOption]
    let targetOptions: [StoryboardEntityOption]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.type.storyboardEditorTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.9))
            }

            Picker("Актёр", selection: $action.actorId) {
                ForEach(actorOptions) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .pickerStyle(.menu)

            Picker("Тип", selection: $action.type) {
                ForEach(SceneGeneratorViewModel.supportedStoryboardEditActionTypes, id: \.rawValue) { type in
                    Text(type.storyboardEditorTitle).tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: action.type) { newType in
                if !newType.usesStoryboardTarget {
                    action.target = nil
                }
            }

            if action.type.usesStoryboardTarget {
                Picker("Цель", selection: Binding<String?>(
                    get: { action.target },
                    set: { action.target = $0 }
                )) {
                    ForEach(targetOptions) { option in
                        Text(option.label).tag(optionalTargetTag(for: option))
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Текст подписи или реплики", text: $action.text, axis: .vertical)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1...3)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .onChange(of: action.actorId) { actorID in
            if action.type == .give, action.target == actorID {
                action.target = nil
            }
        }
    }

    private func optionalTargetTag(for option: StoryboardEntityOption) -> String? {
        option.kind == .none ? nil : option.id
    }
}

private struct StoryboardEditorSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.68 : 0.94))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

private struct StoryboardEditorDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red.opacity(configuration.isPressed ? 0.68 : 0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.14 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.24), lineWidth: 1)
                    )
            )
    }
}

private extension SceneAction.ActionType {
    var storyboardEditorTitle: String {
        switch self {
        case .stand:
            return "Стоит"
        case .walk:
            return "Идёт"
        case .lookAt:
            return "Смотрит"
        case .pickUp:
            return "Берёт"
        case .give:
            return "Передаёт"
        case .talk:
            return "Реплика"
        case .describedAction:
            return "Описание"
        default:
            return rawValue
        }
    }

    var usesStoryboardTarget: Bool {
        switch self {
        case .walk, .lookAt, .pickUp, .give:
            return true
        default:
            return false
        }
    }
}

private struct ARHintControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.68 : 0.96))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(configuration.isPressed ? 0.42 : 0.54))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

private struct ARHintIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.68 : 0.96))
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(Color.black.opacity(configuration.isPressed ? 0.40 : 0.54))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

private struct ARLiveHintCheckView: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.green)
            .padding(6)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.46))
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.44), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Кадр зафиксирован")
    }
}

private struct ARLiveHintCompactChip: View {
    let liveHint: LiveHintPresentation
    let onExplain: (() -> Void)?

    var body: some View {
        Button(action: { onExplain?() }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(toneColor)
                    .frame(width: 6, height: 6)

                Text(liveHint.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if onExplain != nil {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.58))
                    .overlay(
                        Capsule()
                            .stroke(toneColor.opacity(0.55), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(onExplain == nil)
        .allowsHitTesting(onExplain != nil)
        .accessibilityLabel(liveHint.text)
    }

    private var toneColor: Color {
        if liveHint.actionType == .leaveFrameAsIs {
            return .green
        }
        if liveHint.actionType == nil {
            return .yellow
        }
        return .red
    }
}

private struct ARLiveAnalysisStatusChip: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)

                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: min(280, max(190, UIScreen.main.bounds.width * 0.34)), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

private struct HintAnnotationsOverlayView: View {
    let overlayState: OverlayState
    let annotations: [OverlayAnnotationPresentation]
    let canvasSize: CGSize
    let displayTransform: CGAffineTransform?
    let showPrimaryBoundingBox: Bool

    var body: some View {
        ZStack {
            if showPrimaryBoundingBox,
               !hasTargetAnnotation,
               let rawBoundingBox = overlayState.primaryBoundingBox,
               let boundingBox = displayRect(from: rawBoundingBox) {
                Rectangle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    .frame(width: boundingBox.width * canvasSize.width,
                           height: boundingBox.height * canvasSize.height)
                    .position(x: boundingBox.midX * canvasSize.width,
                              y: boundingBox.midY * canvasSize.height)
            }

            ForEach(annotations) { annotation in
                if annotation.tone != .success,
                   let targetRegion = annotation.targetRegion,
                   !targetRegion.isDegenerate,
                   let rect = displayRect(from: targetRegion) {
                    let color = annotationColor(for: annotation)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color, lineWidth: max(2, CGFloat(annotation.emphasis) * 3))
                        .frame(width: CGFloat(rect.width) * canvasSize.width,
                               height: CGFloat(rect.height) * canvasSize.height)
                        .position(x: rect.midX * canvasSize.width,
                                  y: rect.midY * canvasSize.height)

                    if let label = annotation.label {
                        Text(label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.92), in: Capsule())
                            .position(labelPosition(for: rect))
                    }
                }
            }
        }
    }

    private var hasTargetAnnotation: Bool {
        annotations.contains { annotation in
            annotation.tone != .success && annotation.targetRegion?.isDegenerate == false
        }
    }

    private func annotationColor(for annotation: OverlayAnnotationPresentation) -> Color {
        switch annotation.tone {
        case .success:
            return .green.opacity(0.92)
        case .warning:
            return .yellow.opacity(0.92)
        case .danger:
            return .red.opacity(0.94)
        case .neutral:
            switch annotation.kind {
            case .arrow:
                return .yellow.opacity(0.9)
            case .regionHighlight:
                return .white.opacity(0.7)
            case .horizonLine:
                return .blue.opacity(0.85)
            }
        }
    }

    private func labelPosition(for rect: CGRect) -> CGPoint {
        let x = max(36, min(canvasSize.width - 36, rect.minX * canvasSize.width + 40))
        let y = max(14, rect.minY * canvasSize.height - 12)
        return CGPoint(x: x, y: y)
    }

    private func displayRect(from rect: CGRect) -> CGRect? {
        let source = rect.clampedToUnitSquare
        guard let displayTransform else { return source.isDegenerate ? nil : source }
        return source.applyingToCorners(displayTransform).clampedToUnitSquare.nonDegenerate
    }

    private func displayRect(from rect: NormalizedRect) -> CGRect? {
        displayRect(from: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
    }
}

private extension CGRect {
    var isDegenerate: Bool {
        width <= 0 || height <= 0
    }

    var nonDegenerate: CGRect? {
        isDegenerate ? nil : self
    }

    var clampedToUnitSquare: CGRect {
        let minX = min(1, max(0, self.minX))
        let minY = min(1, max(0, self.minY))
        let maxX = min(1, max(0, self.maxX))
        let maxY = min(1, max(0, self.maxY))
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    func applyingToCorners(_ transform: CGAffineTransform) -> CGRect {
        let corners = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY)
        ].map { $0.applying(transform) }

        guard let first = corners.first else { return .zero }
        let bounds = corners.dropFirst().reduce(
            (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        ) { partial, point in
            (
                minX: min(partial.minX, point.x),
                minY: min(partial.minY, point.y),
                maxX: max(partial.maxX, point.x),
                maxY: max(partial.maxY, point.y)
            )
        }
        return CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.maxX - bounds.minX,
            height: bounds.maxY - bounds.minY
        )
    }
}
