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

final class LegacySceneGeneratorCameraViewController: UIViewController {
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
        hostingController.view.isUserInteractionEnabled = false
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
        recordButton.addTarget(self, action: #selector(recordButtonPressed), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopButtonPressed), for: .touchUpInside)
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

    @objc private func recordButtonPressed() {
        viewModel.startRecording()
    }

    @objc private func stopButtonPressed() {
        viewModel.stopRecording()
    }
}

private struct LegacySceneGeneratorSwiftUIOverlay: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ThirdsGridOverlay()
                    .stroke(Color.black.opacity(0.48), lineWidth: 1)

                if viewModel.isHintsEnabled {
                    HintAnnotationsOverlayView(
                        overlayState: viewModel.coachingOverlayState,
                        annotations: viewModel.coachingOverlayAnnotations,
                        canvasSize: proxy.size
                    )

                    if viewModel.liveHint != nil {
                        VStack {
                            LiveHintChipView(
                                liveHint: viewModel.liveHint,
                                fallbackSuggestion: nil,
                                boundingBox: viewModel.coachingOverlayState.primaryBoundingBox,
                                canvasSize: proxy.size
                            )
                            .padding(.top, 47)

                            Spacer()
                        }
                    }
                }

                VStack {
                    Spacer()

                    if viewModel.isMarkingMode {
                        markingHint
                            .padding(.bottom, 68)
                    }

                    captions
                        .padding(.bottom, 18)
                }
                .padding(.horizontal, 16)
            }
        }
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
                .font(.system(size: 11, weight: .bold))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(.white.opacity(0.94))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.52))
        )
    }

    private func legacySubtitle(text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.5))
            )
    }
}

private struct HintAnnotationsOverlayView: View {
    let overlayState: OverlayState
    let annotations: [OverlayAnnotationPresentation]
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            if let boundingBox = overlayState.primaryBoundingBox {
                Rectangle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    .frame(width: boundingBox.width * canvasSize.width,
                           height: boundingBox.height * canvasSize.height)
                    .position(x: boundingBox.midX * canvasSize.width,
                              y: boundingBox.midY * canvasSize.height)
            }

            ForEach(annotations) { annotation in
                if let rect = annotation.targetRegion, !rect.isDegenerate {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(annotationColor(for: annotation.kind), lineWidth: max(1, CGFloat(annotation.emphasis) * 2))
                        .frame(width: CGFloat(rect.width) * canvasSize.width,
                               height: CGFloat(rect.height) * canvasSize.height)
                        .position(x: CGFloat(rect.x + rect.width / 2) * canvasSize.width,
                                  y: CGFloat(rect.y + rect.height / 2) * canvasSize.height)
                }
            }
        }
    }

    private func annotationColor(for kind: OverlayKind) -> Color {
        switch kind {
        case .arrow:
            return .yellow.opacity(0.9)
        case .regionHighlight:
            return .white.opacity(0.7)
        case .horizonLine:
            return .blue.opacity(0.85)
        }
    }
}
