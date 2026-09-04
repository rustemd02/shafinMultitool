//
//  LegacySceneGeneratorCameraShell.swift
//  shafinMultitool
//
//  Created on 19.06.2026.
//

import Combine
import AVKit
import SnapKit
import SwiftUI
import UIKit

struct LegacySceneGeneratorCameraShell: UIViewControllerRepresentable {
    let viewModel: SceneGeneratorViewModel
    let onBack: () -> Void
    let presentationLocale: Locale
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let dynamicTypeSize: DynamicTypeSize

    init(
        viewModel: SceneGeneratorViewModel,
        presentationLocale: Locale = .current,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        dynamicTypeSize: DynamicTypeSize = .large,
        onBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.presentationLocale = presentationLocale
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.dynamicTypeSize = dynamicTypeSize
        self.onBack = onBack
    }

    func makeUIViewController(context: Context) -> LegacySceneGeneratorCameraViewController {
        viewModel.setPresentationLocale(presentationLocale)
        return LegacySceneGeneratorCameraViewController(
            viewModel: viewModel,
            presentationLocale: presentationLocale,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            dynamicTypeSize: dynamicTypeSize,
            onBack: onBack
        )
    }

    func updateUIViewController(_ uiViewController: LegacySceneGeneratorCameraViewController, context: Context) {
        uiViewController.updateEnvironment(
            presentationLocale: presentationLocale,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            dynamicTypeSize: dynamicTypeSize
        )
    }
}

final class LegacySceneGeneratorCameraViewController: UIViewController, UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {
    private let viewModel: SceneGeneratorViewModel
    private let onBack: () -> Void
    private var presentationLocale: Locale
    private var reduceMotion: Bool
    private var reduceTransparency: Bool
    private var dynamicTypeSize: DynamicTypeSize
    private var cancellables = Set<AnyCancellable>()

    private let backgroundView = UIView()
    private let arContainerView = UIView()
    private let settingsBarBackgroundView = UIView()
    private let settingsBarHairlineView = UIView()
    private let backButton = UIButton(type: .custom)
    private let sceneButtonBackgroundView = UIView()
    private let sceneButtonAccentView = UIView()
    private let sceneButton = UIButton(type: .custom)
    private let stopwatchBackgroundView = UIView()
    private let stopwatchAccentView = UIView()
    private let stopwatchLabel = UILabel()
    private let captureSettingsStackView = UIStackView()
    private let resolutionChipButton = UIButton(type: .custom)
    private let fpsChipButton = UIButton(type: .custom)
    private let recordingSoundChipButton = UIButton(type: .custom)

    private let addActorButton = UIButton(type: .custom)
    private let previewButton = UIButton(type: .custom)
    private let regenerateButton = UIButton(type: .custom)
    private let hintButton = UIButton(type: .custom)
    private let recordButton = UIButton(type: .custom)
    private let stopButton = UIButton(type: .custom)
    private let rightControlStackView = UIStackView()
    private let recordingReviewBand = UIView()
    private let recordingReviewAccentView = UIView()
    private let recordingReviewStatusLabel = UILabel()
    private let recordingReviewPlayButton = UIButton(type: .system)
    private let recordingReviewShareButton = UIButton(type: .system)

    private let centerDot = UILabel()
    private let loadingView = UIView()
    private let loadingLabel = UILabel()
    private let loadingPerforationStripView = UIStackView()
    private let settingPickerView = UIPickerView()

    private var arHostingController: UIHostingController<ARSceneContainer>?
    private var overlayHostingController: UIHostingController<AnyView>?
    private var overlayActorDragLongPressRecognizer: UILongPressGestureRecognizer?
    private var shellTouchProbeTapRecognizer: UITapGestureRecognizer?
    private var shellTouchProbeLongPressRecognizer: UILongPressGestureRecognizer?
    private var overlayTouchProbeTapRecognizer: UITapGestureRecognizer?
    private var recordingPlayer: AVPlayer?
    private weak var recordingPlayerViewController: AVPlayerViewController?
    private let recordingPlaybackOwnerID = UUID()
    private var recordingPlaybackTask: Task<Void, Never>?
    private var recordingPlaybackRequestID = UUID()

    init(
        viewModel: SceneGeneratorViewModel,
        presentationLocale: Locale = .current,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        dynamicTypeSize: DynamicTypeSize = .large,
        onBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.presentationLocale = presentationLocale
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.dynamicTypeSize = dynamicTypeSize
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateEnvironment(
        presentationLocale: Locale,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        dynamicTypeSize: DynamicTypeSize
    ) {
        let localeChanged = self.presentationLocale.identifier != presentationLocale.identifier
        let environmentChanged = localeChanged
            || self.reduceMotion != reduceMotion
            || self.reduceTransparency != reduceTransparency
            || self.dynamicTypeSize != dynamicTypeSize
        guard environmentChanged else { return }

        self.presentationLocale = presentationLocale
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.dynamicTypeSize = dynamicTypeSize
        viewModel.setPresentationLocale(presentationLocale)
        overlayHostingController?.rootView = makeOverlayRoot()
        if localeChanged {
            refreshUI()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        bindViewModel()
        refreshUI()
#if DEBUG
        // Simulator UI-test lane: no ARKit session can start, so the loading
        // overlay would otherwise block the settings bar forever.
        if ProcessInfo.processInfo.arguments.contains("-SHAFIN_GENERATOR_MARK_AR_READY") {
            // `viewDidLoad` can run inside a SwiftUI representable update
            // transaction. Defer the DEBUG-only @Published mutation until the
            // next MainActor turn so SwiftUI never observes a publish during
            // its own view update.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                viewModel.testingMarkARSessionReady()
                self.loadingView.isHidden = true
                self.loadingLabel.isHidden = true
                self.refreshUI()
            }
        }
#endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard recordingPlayerViewController?.presentingViewController === self else {
            releaseRecordingPlayer()
            return
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let workspaceIsBeingRemoved = isBeingDismissed
            || isMovingFromParent
            || navigationController?.isBeingDismissed == true
            || navigationController?.isMovingFromParent == true
        if presentedViewController === recordingPlayerViewController,
           !workspaceIsBeingRemoved {
            return
        }
        releaseRecordingPlayer()
    }

    deinit {
        recordingPlayer?.pause()
        recordingPlayerViewController?.player = nil
    }

    private func setupUI() {
        view.backgroundColor = SETPalette.ink.uiColor
        view.addSubview(backgroundView)
        backgroundView.backgroundColor = SETPalette.ink.uiColor
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
        setupRecordingReviewBand()
        setupLoadingView()
        setupTouchDiagnostics()
    }

    private func embedARView() {
        let hostingController = UIHostingController(
            rootView: ARSceneContainer(
                viewModel: viewModel,
                presentationLocale: presentationLocale
            )
        )
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
        let hostingController = UIHostingController(rootView: makeOverlayRoot())
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

    private func makeOverlayRoot() -> AnyView {
        AnyView(
            LegacySceneGeneratorSwiftUIOverlay(
                viewModel: viewModel,
                presentationLocale: presentationLocale,
                dynamicTypeSize: dynamicTypeSize
            )
            .environment(\.locale, presentationLocale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.setReduceMotionOverride, reduceMotion)
            .environment(\.setReduceTransparencyOverride, reduceTransparency)
        )
    }

    private func setupSettingsBar() {
        arContainerView.addSubview(settingsBarBackgroundView)
        settingsBarBackgroundView.backgroundColor = SETPalette.ink.uiColor
        settingsBarBackgroundView.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview()
            // The bar owns a full minimum hit target so its centered scene
            // command never places the 44pt accessibility frame above the
            // camera surface (the compact editorial pill remains 30pt).
            make.height.equalTo(SETComponentMetric.minimumHitTarget)
        }

        settingsBarBackgroundView.addSubview(settingsBarHairlineView)
        settingsBarHairlineView.backgroundColor = SETPalette.hairline.uiColor
        settingsBarHairlineView.snp.makeConstraints { make in
            make.height.equalTo(SETStroke.hairline)
            make.leading.trailing.bottom.equalToSuperview()
        }

        settingsBarBackgroundView.addSubview(backButton)
        backButton.setImage(UIImage(systemName: "arrow.uturn.backward.circle.fill"), for: .normal)
        backButton.tintColor = SETPalette.warmWhite.uiColor
        backButton.accessibilityIdentifier = "generator_back_button"
        backButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityBack)
        backButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leadingMargin.equalToSuperview().offset(15)
            make.width.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }

        captureSettingsStackView.axis = .horizontal
        captureSettingsStackView.alignment = .center
        captureSettingsStackView.spacing = 6
        settingsBarBackgroundView.addSubview(captureSettingsStackView)
        configureCaptureSettingChip(resolutionChipButton)
        configureCaptureSettingChip(fpsChipButton)
        fpsChipButton.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: SETTypography.uiFont(.hudMono, size: 12))
        fpsChipButton.titleLabel?.adjustsFontForContentSizeCategory = true
        fpsChipButton.accessibilityIdentifier = "generator_capture_fps_button"
        fpsChipButton.isAccessibilityElement = true
        fpsChipButton.accessibilityTraits = .staticText
        fpsChipButton.isUserInteractionEnabled = false
        configureCaptureSettingChip(recordingSoundChipButton)
        recordingSoundChipButton.accessibilityIdentifier = "generator_recording_sound_button"
        recordingSoundChipButton.isAccessibilityElement = true
        captureSettingsStackView.addArrangedSubview(resolutionChipButton)
        captureSettingsStackView.addArrangedSubview(fpsChipButton)
        captureSettingsStackView.addArrangedSubview(recordingSoundChipButton)
        resolutionChipButton.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }
        fpsChipButton.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }
        recordingSoundChipButton.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }
        captureSettingsStackView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(backButton.snp.trailing).offset(34)
        }

        sceneButtonBackgroundView.backgroundColor = SETPalette.surfaceSolid.uiColor
        sceneButtonBackgroundView.layer.cornerRadius = 15
        sceneButtonBackgroundView.layer.borderWidth = SETStroke.hairline
        sceneButtonBackgroundView.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        sceneButtonBackgroundView.layer.masksToBounds = true
        settingsBarBackgroundView.addSubview(sceneButtonBackgroundView)
        sceneButtonBackgroundView.snp.makeConstraints { make in
            make.height.equalTo(30)
            make.width.equalTo(SETComponentMetric.capsuleSegmentWidth + SETSpacing.x8)
            make.trailing.equalToSuperview().inset(SETSpacing.x3)
            make.centerY.equalToSuperview()
        }

        sceneButtonBackgroundView.addSubview(sceneButtonAccentView)
        sceneButtonAccentView.backgroundColor = SETPalette.hairline.uiColor
        sceneButtonAccentView.snp.makeConstraints { make in
            make.width.equalTo(2)
            make.leading.top.bottom.equalToSuperview()
        }

        sceneButton.titleLabel?.font = SETTypography.uiFont(.display, size: 15)
        sceneButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        sceneButton.titleLabel?.numberOfLines = 1
        sceneButton.setTitleColor(SETPalette.warmWhite.uiColor, for: .normal)
        sceneButton.accessibilityIdentifier = "generator_scene_button"
        sceneButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityOpenScenes)
        // Keep the editorial pill compact while giving the actual UIButton a
        // full minimum hit frame. The button sits above the visual background
        // so its accessibility frame is not clipped to the 30pt pill.
        settingsBarBackgroundView.addSubview(sceneButton)
        sceneButton.snp.makeConstraints { make in
            make.center.equalTo(sceneButtonBackgroundView)
            make.leading.trailing.equalTo(sceneButtonBackgroundView).inset(SETSpacing.x3)
            make.width.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }

        stopwatchBackgroundView.isHidden = true
        stopwatchBackgroundView.backgroundColor = SETPalette.ink.uiColor
        stopwatchBackgroundView.layer.cornerRadius = 15
        stopwatchBackgroundView.layer.borderWidth = SETStroke.hairline
        stopwatchBackgroundView.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        stopwatchBackgroundView.layer.masksToBounds = true
        settingsBarBackgroundView.addSubview(stopwatchBackgroundView)
        stopwatchBackgroundView.snp.makeConstraints { make in
            make.width.equalTo(120)
            make.height.equalTo(30)
            make.center.equalToSuperview()
        }

        stopwatchBackgroundView.addSubview(stopwatchAccentView)
        stopwatchAccentView.backgroundColor = SETPalette.setOrange.uiColor
        stopwatchAccentView.snp.makeConstraints { make in
            make.width.equalTo(2)
            make.leading.top.bottom.equalToSuperview()
        }

        stopwatchLabel.textColor = SETPalette.warmWhite.uiColor
        stopwatchLabel.font = SETTypography.uiFont(.hudMono, size: 13)
        stopwatchLabel.text = viewModel.localizedCopy(.hudRec) + " 00:00"
        stopwatchBackgroundView.addSubview(stopwatchLabel)
        stopwatchLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func setupLegacyControls() {
        rightControlStackView.axis = .vertical
        rightControlStackView.alignment = .fill
        rightControlStackView.distribution = .fill
        rightControlStackView.spacing = 8
        backgroundView.addSubview(rightControlStackView)
        rightControlStackView.snp.makeConstraints { make in
            make.width.equalTo(56)
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualTo(settingsBarBackgroundView.snp.bottom).offset(12)
            make.bottom.lessThanOrEqualToSuperview().inset(12)
        }

        configureRailButton(addActorButton, imageName: "plus")
        addActorButton.accessibilityIdentifier = "generator_mark_object_button"
        rightControlStackView.addArrangedSubview(addActorButton)

        configureRailButton(previewButton, imageName: "play")
        previewButton.accessibilityIdentifier = "generator_preview_button"
        rightControlStackView.addArrangedSubview(previewButton)

        configureRailButton(regenerateButton, imageName: "sparkles")
        regenerateButton.accessibilityIdentifier = "generator_regenerate_button"
        rightControlStackView.addArrangedSubview(regenerateButton)

        configureRailButton(hintButton, imageName: "lightbulb")
        hintButton.accessibilityIdentifier = "generator_hint_button"
        rightControlStackView.addArrangedSubview(hintButton)

        configureRailButton(recordButton, imageName: "largecircle.fill.circle")
        recordButton.accessibilityIdentifier = "generator_record_button"
        rightControlStackView.addArrangedSubview(recordButton)

        configureRailButton(stopButton, imageName: "stop.fill")
        stopButton.accessibilityIdentifier = "generator_stop_recording_button"
        stopButton.isHidden = true
        rightControlStackView.addArrangedSubview(stopButton)

        for button in [addActorButton, previewButton, regenerateButton, hintButton, recordButton, stopButton] {
            button.snp.makeConstraints { make in
                make.height.equalTo(48)
            }
        }

        centerDot.text = "+"
        centerDot.font = SETTypography.uiFont(.hudMono, size: 30)
        centerDot.textColor = SETPalette.warmWhite.uiColor
        arContainerView.addSubview(centerDot)
        centerDot.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        backgroundView.addSubview(settingPickerView)
        settingPickerView.isHidden = true
        settingPickerView.backgroundColor = SETPalette.hudScrim.uiColor
        settingPickerView.layer.cornerRadius = 10
        settingPickerView.snp.makeConstraints { make in
            make.rightMargin.equalTo(arContainerView.snp_rightMargin).offset(-12.5)
            make.bottomMargin.equalTo(backgroundView.snp_bottomMargin)
        }
    }

    private func setupRecordingReviewBand() {
        recordingReviewBand.backgroundColor = SETPalette.ink.uiColor
        recordingReviewBand.accessibilityIdentifier = "generator_recording_review_band"
        recordingReviewBand.isHidden = true
        backgroundView.addSubview(recordingReviewBand)
        recordingReviewBand.snp.makeConstraints { make in
            make.leading.equalTo(arContainerView.snp.leading).offset(16)
            make.bottom.equalTo(arContainerView.snp.bottom).inset(92)
            make.height.greaterThanOrEqualTo(56)
            make.trailing.lessThanOrEqualTo(rightControlStackView.snp.leading).offset(-12)
            make.width.lessThanOrEqualTo(360)
        }

        recordingReviewAccentView.backgroundColor = SETPalette.setOrange.uiColor
        recordingReviewBand.addSubview(recordingReviewAccentView)
        recordingReviewAccentView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(SETStroke.standard)
        }

        recordingReviewStatusLabel.textColor = SETPalette.warmWhite.uiColor
        recordingReviewStatusLabel.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: SETTypography.uiFont(.hudMono, size: 12))
        recordingReviewStatusLabel.adjustsFontForContentSizeCategory = true
        recordingReviewStatusLabel.numberOfLines = 2
        recordingReviewBand.addSubview(recordingReviewStatusLabel)
        recordingReviewStatusLabel.snp.makeConstraints { make in
            make.leading.equalTo(recordingReviewAccentView.snp.trailing).offset(10)
            make.top.equalToSuperview().offset(8)
            make.bottom.equalToSuperview().inset(8)
        }

        configureRecordingReviewButton(
            recordingReviewPlayButton,
            systemImage: "play.fill",
            accessibilityIdentifier: "generator_recording_playback_button"
        )
        configureRecordingReviewButton(
            recordingReviewShareButton,
            systemImage: "square.and.arrow.up",
            accessibilityIdentifier: "generator_recording_share_button"
        )
        recordingReviewBand.addSubview(recordingReviewShareButton)
        recordingReviewShareButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(4)
            make.centerY.equalToSuperview()
            make.width.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }
        recordingReviewBand.addSubview(recordingReviewPlayButton)
        recordingReviewPlayButton.snp.makeConstraints { make in
            make.trailing.equalTo(recordingReviewShareButton.snp.leading)
            make.centerY.equalToSuperview()
            make.width.height.greaterThanOrEqualTo(SETComponentMetric.minimumHitTarget)
        }
        recordingReviewStatusLabel.snp.makeConstraints { make in
            make.trailing.lessThanOrEqualTo(recordingReviewPlayButton.snp.leading).offset(-4)
        }
    }

    private func configureRecordingReviewButton(
        _ button: UIButton,
        systemImage: String,
        accessibilityIdentifier: String
    ) {
        button.tintColor = SETPalette.warmWhite.uiColor
        button.setImage(UIImage(systemName: systemImage), for: .normal)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.adjustsImageWhenHighlighted = true
    }

    private func setupLoadingView() {
        backgroundView.addSubview(loadingView)
        loadingView.backgroundColor = SETPalette.ink.uiColor.withAlphaComponent(0.88)
        loadingView.accessibilityIdentifier = "generator_progress_overlay"
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        loadingLabel.textColor = SETPalette.warmWhite.uiColor
        loadingLabel.font = SETTypography.uiFont(.hudMono, size: 15)
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 2
        backgroundView.addSubview(loadingLabel)
        loadingLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(32)
        }

        setupLoadingPerforationStrip()
    }

    /// Static deterministic perforation strip: the generator-progress edge
    /// micro-rhythm (policy §6.1). Decorative only — removed from hit testing
    /// and from the accessibility tree.
    private func setupLoadingPerforationStrip() {
        loadingPerforationStripView.axis = .horizontal
        loadingPerforationStripView.spacing = 4
        loadingPerforationStripView.isUserInteractionEnabled = false
        loadingPerforationStripView.isAccessibilityElement = false
        loadingPerforationStripView.accessibilityElementsHidden = true

        for index in 0..<14 {
            let perforationView = UIView()
            perforationView.backgroundColor = index < 7 ? SETPalette.setOrange.uiColor : .clear
            perforationView.layer.borderWidth = SETStroke.hairline
            perforationView.layer.borderColor = SETPalette.hairline.uiColor.cgColor
            perforationView.isUserInteractionEnabled = false
            perforationView.isAccessibilityElement = false
            loadingPerforationStripView.addArrangedSubview(perforationView)
            perforationView.snp.makeConstraints { make in
                make.width.equalTo(6)
                make.height.equalTo(10)
            }
        }

        loadingView.addSubview(loadingPerforationStripView)
        loadingPerforationStripView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(loadingLabel.snp.bottom).offset(14)
        }
    }

    private func configureRailButton(_ button: UIButton, imageName: String) {
        button.backgroundColor = SETPalette.surfaceSolid.uiColor
        button.layer.cornerRadius = SETRadius.control / 2
        button.layer.borderWidth = SETStroke.hairline
        button.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        button.layer.masksToBounds = true
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = SETPalette.warmWhite.uiColor
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
        recordingReviewPlayButton.addTarget(self, action: #selector(recordingPlaybackButtonPressed), for: .touchUpInside)
        recordingReviewShareButton.addTarget(self, action: #selector(recordingShareButtonPressed), for: .touchUpInside)
        resolutionChipButton.addTarget(self, action: #selector(resolutionChipPressed), for: .touchUpInside)
        recordingSoundChipButton.addTarget(self, action: #selector(recordingSoundChipPressed), for: .touchUpInside)
    }

    private func bindViewModel() {
        let chromePublishers: [AnyPublisher<Void, Never>] = [
            viewModel.$sceneTitle.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isRecording.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isRecordingStarting.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isRecordingFinalizing.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$recordingResolutionLabel.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$recordingSourceFPS.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$recordingSoundEnabled.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$recordingElapsedTime.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$recordingReferences.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$latestAvailableRecordingArtifact.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$sceneDescription.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$plannedScene.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isMarkingMode.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isGenerating.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$generationStage.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isHintsEnabled.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isARSessionReady.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isARSessionInterrupted.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isARSessionRecovering.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$statusMessage.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$activeStoryboardEditDraft.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(chromePublishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshUI()
            }
            .store(in: &cancellables)
    }

    func refreshUI() {
        sceneButton.setTitle(viewModel.sceneTitle, for: .normal)
        sceneButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityOpenScenes)
        sceneButtonBackgroundView.isHidden = viewModel.isRecording
        stopwatchBackgroundView.isHidden = !viewModel.isRecording
        stopwatchLabel.text = viewModel.localizedCopy(.hudRec) + " " + formattedTime(viewModel.recordingElapsedTime)
        refreshCaptureSettingChips()
        refreshRecordingReviewBand()

        let hasDescription = !viewModel.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasGeneratedScene = viewModel.plannedScene != nil

        addActorButton.backgroundColor = SETPalette.surfaceSolid.uiColor
        addActorButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityMarkObject)
        addActorButton.tintColor = SETPalette.warmWhite.uiColor
        addActorButton.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        addActorButton.setImage(UIImage(systemName: viewModel.isMarkingMode ? "checkmark" : "plus"), for: .normal)
        addActorButton.isEnabled = viewModel.canToggleMarkingMode
        addActorButton.alpha = addActorButton.isEnabled ? 1 : 0.45

        previewButton.isHidden = !hasGeneratedScene
        previewButton.isEnabled = viewModel.isPlaying || viewModel.canStartPlayback
        previewButton.alpha = previewButton.isEnabled ? 1 : 0.45
        previewButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityPreviewScene)
        previewButton.setImage(UIImage(systemName: viewModel.isPlaying ? "stop.fill" : "play"), for: .normal)

        regenerateButton.isHidden = !hasDescription
        regenerateButton.isEnabled = hasDescription && viewModel.canGenerateScene
        regenerateButton.alpha = regenerateButton.isEnabled ? 1 : 0.45
        regenerateButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityRegenerateScene)

        hintButton.backgroundColor = SETPalette.surfaceSolid.uiColor
        hintButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityToggleHints)
        hintButton.tintColor = SETPalette.warmWhite.uiColor
        hintButton.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        hintButton.setImage(UIImage(systemName: viewModel.isHintsEnabled ? "lightbulb.fill" : "lightbulb"), for: .normal)
        hintButton.isEnabled = viewModel.canToggleHints
        hintButton.alpha = hintButton.isEnabled ? 1 : 0.45

        recordButton.isHidden = viewModel.isRecording
        recordButton.isEnabled = viewModel.canStartRecording
        recordButton.alpha = recordButton.isEnabled ? 1 : 0.45
        recordButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityRecord)
        recordButton.backgroundColor = recordButton.isEnabled ? SETPalette.setOrange.uiColor : SETPalette.surfaceSolid.uiColor
        recordButton.tintColor = recordButton.isEnabled ? SETPalette.ink.uiColor : SETPalette.warmWhite.uiColor
        recordButton.layer.borderColor = recordButton.isEnabled ? UIColor.clear.cgColor : SETPalette.hairline.uiColor.cgColor
        stopButton.isHidden = !viewModel.isRecording
        stopButton.accessibilityLabel = viewModel.localizedCopy(.accessibilityStopRecording)
        stopButton.backgroundColor = SETPalette.surfaceSolid.uiColor
        stopButton.tintColor = SETPalette.warmWhite.uiColor
        stopButton.layer.borderColor = SETPalette.hairline.uiColor.cgColor

        loadingView.isHidden = viewModel.isARSessionReady && !viewModel.isGenerating
        // Simulator UI-test lane: the AR session can never become ready, so
        // keep the loading overlay hidden when the test hook marked it ready.
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SHAFIN_GENERATOR_MARK_AR_READY") {
            loadingView.isHidden = true
        }
#endif
        loadingLabel.isHidden = loadingView.isHidden
        loadingLabel.text = viewModel.isGenerating
            ? generatorProgressLabel()
            : viewModel.statusMessage
        centerDot.isHidden = !viewModel.isMarkingMode

        let passTouchesToAR = SceneGeneratorViewModel.shouldPassTouchesThroughSwiftUIOverlay(
            isMarkingMode: viewModel.isMarkingMode,
            hasActiveStoryboardEditor: viewModel.activeStoryboardEditDraft != nil
        )
        #if DEBUG
        // UI-test lane: the overlay's full-container hit area swallows taps
        // aimed at the settings bar; disable it so chrome stays reachable.
        // Storyboard fixtures and an active editor intentionally keep the
        // overlay interactive because their tray/editor controls live there.
        let hasStoryboardFixture = ProcessInfo.processInfo.arguments.contains(
            SETGalleryLaunchConfiguration.generatorStoryboardFixtureArgument
        )
        if ProcessInfo.processInfo.arguments.contains("-SHAFIN_GENERATOR_MARK_AR_READY")
            && !passTouchesToAR
            && viewModel.activeStoryboardEditDraft == nil
            && !hasStoryboardFixture {
            overlayHostingController?.view.isUserInteractionEnabled = false
            return
        }
        #endif
        overlayHostingController?.view.isUserInteractionEnabled = !passTouchesToAR
    }

    private func generatorProgressLabel() -> String {
        switch viewModel.generationStage {
        case .reading:
            return viewModel.localizedCopy(.generatorProgressReading)
        case .planning:
            return viewModel.localizedCopy(.generatorProgressAnchors)
        case .placing:
            return viewModel.localizedCopy(.generatorProgressFrame)
        case nil:
            return viewModel.statusMessage
        }
    }

    private func configureCaptureSettingChip(_ button: UIButton) {
        button.backgroundColor = SETPalette.hudScrim.uiColor
        button.layer.cornerRadius = 8
        button.layer.borderWidth = SETStroke.hairline
        button.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        button.layer.masksToBounds = true
        button.titleLabel?.font = SETTypography.uiFont(.hudMono, size: 12)
        button.setTitleColor(SETPalette.warmWhite.uiColor, for: .normal)
        button.setTitleColor(SETPalette.textSecondary.uiColor, for: .highlighted)
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 9, bottom: 2, right: 9)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func refreshCaptureSettingChips() {
        resolutionChipButton.setTitle(currentResolutionLabel(), for: .normal)
        resolutionChipButton.isEnabled = false
        resolutionChipButton.alpha = 0.72
        fpsChipButton.setTitle(currentFPSLabel(), for: .normal)
        recordingSoundChipButton.setTitle(
            viewModel.localizedCopy(
                viewModel.recordingSoundEnabled ? .captureSoundOn : .captureSoundOff
            ),
            for: .normal
        )
        recordingSoundChipButton.isEnabled = viewModel.canToggleRecordingSound
        recordingSoundChipButton.alpha = recordingSoundChipButton.isEnabled ? 1 : 0.55
        recordingSoundChipButton.accessibilityLabel = viewModel.localizedCopy(
            .accessibilityToggleRecordingSound
        )
        recordingSoundChipButton.accessibilityValue = viewModel.localizedCopy(
            viewModel.recordingSoundEnabled ? .captureSoundOn : .captureSoundOff
        )
        recordingSoundChipButton.accessibilityTraits = viewModel.recordingSoundEnabled
            ? [.button, .selected]
            : [.button]
        resolutionChipButton.accessibilityLabel = SETCopyKey.captureResolution.localizedFormat(
            locale: presentationLocale,
            arguments: [currentResolutionLabel()]
        )
        fpsChipButton.accessibilityLabel = SETCopyKey.captureFPS.localizedFormat(
            locale: presentationLocale,
            arguments: [currentFPSAccessibilityValue()]
        )
    }

    private func refreshRecordingReviewBand() {
        let isRecording = viewModel.isRecording
            || viewModel.isRecordingStarting
            || viewModel.isRecordingFinalizing
        let hasReferences = !viewModel.recordingReferences.isEmpty
        let hasAvailableArtifact = viewModel.latestAvailableRecordingArtifact != nil

        recordingReviewBand.isHidden = isRecording || !hasReferences
        recordingReviewStatusLabel.text = viewModel.localizedCopy(
            hasAvailableArtifact ? .generatorRecordingReady : .generatorRecordingMissing
        )
        recordingReviewPlayButton.accessibilityLabel = viewModel.localizedCopy(.generatorRecordingPlay)
        recordingReviewShareButton.accessibilityLabel = viewModel.localizedCopy(.generatorRecordingShare)
        recordingReviewPlayButton.isEnabled = hasAvailableArtifact && !isRecording
        recordingReviewShareButton.isEnabled = hasAvailableArtifact && !isRecording
        recordingReviewPlayButton.alpha = recordingReviewPlayButton.isEnabled ? 1 : 0.45
        recordingReviewShareButton.alpha = recordingReviewShareButton.isEnabled ? 1 : 0.45
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

    private func formattedTime(_ elapsedTime: TimeInterval) -> String {
        let totalSeconds = Int(elapsedTime.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func currentResolutionLabel() -> String {
        viewModel.recordingResolutionLabel
    }

    private func currentFPSLabel() -> String {
        guard let fps = viewModel.recordingSourceFPS, fps > 0 else { return "FPS —" }
        return "\(fps) FPS"
    }

    private func currentFPSAccessibilityValue() -> String {
        guard let fps = viewModel.recordingSourceFPS, fps > 0 else { return "—" }
        return "\(fps) FPS"
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
        // The AR buffer owns the real dimensions; there is no scaler/crop
        // selector to cycle here.
    }

    @objc private func recordingSoundChipPressed() {
        guard viewModel.canToggleRecordingSound else { return }
        viewModel.setRecordingSoundEnabled(!viewModel.recordingSoundEnabled)
    }

    @objc private func hintButtonLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }

        let alert = UIAlertController(
            title: SETCopyKey.generatorDemoAnalysisTitle.localizedString(locale: presentationLocale),
            message: SETCopyKey.generatorDemoAnalysisMessage.localizedString(locale: presentationLocale),
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
        alert.addAction(
            UIAlertAction(
                title: SETCopyKey.libraryCancel.localizedString(locale: presentationLocale),
                style: .cancel
            )
        )
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

    @objc private func recordingPlaybackButtonPressed() {
        guard let artifact = viewModel.latestAvailableRecordingArtifact else { return }

        releaseRecordingPlayer()
        let requestID = UUID()
        recordingPlaybackRequestID = requestID
        let ownerID = recordingPlaybackOwnerID
        let viewModel = self.viewModel
        recordingPlaybackTask = Task { @MainActor [weak self] in
            await viewModel.releaseRecordingPlaybackLease(ownerID: ownerID)
            guard let self,
                  !Task.isCancelled,
                  self.recordingPlaybackRequestID == requestID,
                  self.viewIfLoaded?.window != nil else { return }

            do {
                _ = try await viewModel.acquireRecordingPlaybackLease(ownerID: ownerID)
                guard !Task.isCancelled,
                      self.recordingPlaybackRequestID == requestID,
                      self.viewIfLoaded?.window != nil else {
                    await viewModel.releaseRecordingPlaybackLease(ownerID: ownerID)
                    return
                }

                let player = AVPlayer(url: artifact.localURL)
                let playerViewController = AVPlayerViewController()
                playerViewController.player = player
                self.recordingPlayer = player
                self.recordingPlayerViewController = playerViewController
                self.present(playerViewController, animated: true) { [weak self, weak playerViewController] in
                    playerViewController?.presentationController?.delegate = self
                    player.play()
                }
            } catch {
                guard self.recordingPlaybackRequestID == requestID else { return }
                self.viewModel.errorMessage = self.viewModel.localizedCopy(.generatorErrorRecorder)
            }
        }
    }

    @objc private func recordingShareButtonPressed() {
        guard let artifact = viewModel.latestAvailableRecordingArtifact else { return }

        let activityViewController = UIActivityViewController(
            activityItems: [artifact.localURL],
            applicationActivities: nil
        )
        activityViewController.popoverPresentationController?.sourceView = recordingReviewShareButton
        activityViewController.popoverPresentationController?.sourceRect = recordingReviewShareButton.bounds
        present(activityViewController, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard recordingPlayer != nil else { return }
        releaseRecordingPlayer()
    }

    private func releaseRecordingPlayer() {
        recordingPlaybackTask?.cancel()
        recordingPlaybackTask = nil
        recordingPlaybackRequestID = UUID()
        recordingPlayer?.pause()
        recordingPlayerViewController?.player = nil
        recordingPlayer = nil
        recordingPlayerViewController = nil
        let viewModel = self.viewModel
        let ownerID = recordingPlaybackOwnerID
        Task { @MainActor in
            await viewModel.releaseRecordingPlaybackLease(ownerID: ownerID)
        }
    }

    private func demoModeTitle(_ mode: CameraDemoSceneMode) -> String {
        let key: SETCopyKey = switch mode {
        case .auto: .generatorDemoModeAuto
        case .object: .generatorDemoModeObject
        case .portrait: .generatorDemoModePortrait
        case .cinematicPortrait: .generatorDemoModeCinematicPortrait
        case .dialogue: .generatorDemoModeDialogue
        }
        return key.localizedString(locale: presentationLocale)
    }
}

private struct LegacySceneGeneratorSwiftUIOverlay: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel
    let presentationLocale: Locale
    let dynamicTypeSize: DynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride
    @State private var decisionTrace: DecisionTracePresentation?
    @State private var isStoryboardTrayExpanded = false
    @State private var storyboardEditorDetent: PresentationDetent = .medium

    private var isMotionReduced: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var storyboardEditorDetents: Set<PresentationDetent> {
#if DEBUG
        switch viewModel.testingStoryboardFixtureID {
        case "storyboard.editor-medium", "storyboard.editor-large":
            // UIKit's medium detent is unavailable in compact landscape
            // height. A fixture-only height detent keeps the medium baseline
            // measurable while production retains .medium/.large.
            return [.height(300), .large]
        default:
            return [.medium, .large]
        }
#else
        return [.medium, .large]
#endif
    }

    private var storyboardEditorInitialDetent: PresentationDetent {
#if DEBUG
        switch viewModel.testingStoryboardFixtureID {
        case "storyboard.editor-medium":
            return .height(300)
        case "storyboard.editor-large":
            return .large
        default:
            return .medium
        }
#else
        return .medium
#endif
    }

    var body: some View {
        GeometryReader { proxy in
            let isHintPauseActive = viewModel.isHintPauseAnalysisActive
            ZStack {
                if isHintPauseActive,
                   let acceptedSnapshot = viewModel.acceptedHintPauseSnapshot,
                   acceptedSnapshot.displayImage != nil {
                    SETPauseSnapshotFrame(snapshot: acceptedSnapshot)
                        .ignoresSafeArea()
                }

                if !isHintPauseActive {
                    ThirdsGridOverlay()
                        .stroke(SETPalette.blackGuide.color, lineWidth: 1)
                        .allowsHitTesting(false)

                    objectLabelsOverlay
                        .allowsHitTesting(false)
                }

                if viewModel.isHintsEnabled {
                    if !isHintPauseActive {
                        HintAnnotationsOverlayView(
                            overlayState: viewModel.coachingOverlayState,
                            annotations: viewModel.coachingOverlayAnnotations,
                            canvasSize: proxy.size,
                            displayTransform: viewModel.hintDisplayTransform,
                            showPrimaryBoundingBox: shouldShowPrimaryHintBoundingBox
                        )
                        .allowsHitTesting(false)
                    }

                    hintTopControls

                    if isHintPauseActive {
                        hintPausePanel()
                    } else if viewModel.liveHint != nil {
                        liveHintPanel(size: proxy.size)
                    } else {
                        liveStatusPanel
                    }
                }

                if !isHintPauseActive, shouldShowBeatHUD {
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

                if !isHintPauseActive {
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
        }
        .sheet(item: $viewModel.activeStoryboardEditDraft) { draft in
            StoryboardBeatEditorSheet(draft: draft, viewModel: viewModel)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .presentationDetents(storyboardEditorDetents, selection: $storyboardEditorDetent)
                .presentationDragIndicator(.visible)
                .modifier(StoryboardEditorPresentationModifier())
                .onAppear {
                    storyboardEditorDetent = storyboardEditorInitialDetent
                }
        }
        .sheet(item: $decisionTrace) { trace in
            DecisionTraceView(trace: trace)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
#if DEBUG
            if viewModel.testingStoryboardFixtureID == "storyboard.tray-expanded" {
                isStoryboardTrayExpanded = true
            }
#endif
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
                    .accessibilityLabel(Text(SETCopyKey.accessibilityExplainHint.localizedTextKey))
                    .accessibilityIdentifier("generator_decision_trace")
                }

                Button(action: toggleHintPauseAnalysis) {
                    Image(systemName: viewModel.isHintPauseAnalysisActive ? "play.circle.fill" : "pause.circle.fill")
                        .accessibilityHidden(true)
                }
                .buttonStyle(ARHintIconButtonStyle())
                .accessibilityLabel(Text(
                    (viewModel.isHintPauseAnalysisActive
                        ? SETCopyKey.accessibilityResumeHint
                        : SETCopyKey.accessibilityPauseHint).localizedTextKey
                ))
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
                title: viewModel.localizedCopy(
                    viewModel.isRecording ? .arStatusStabilizing : .arStatusActive
                ),
                message: viewModel.localizedCopy(
                    viewModel.isRecording ? .arStatusHintAppears : .arStatusReviewAction
                )
            )
            .padding(.top, 52)

            Spacer()
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func hintPausePanel() -> some View {
        VStack {
            Spacer()

            SETPauseReviewBand(
                title: hintPauseBandTitle,
                detail: hintPauseBandDetail,
                isLoading: hintPauseIsLoading,
                actionTitle: hintPauseIsFailure ? .pauseFailureRecovery : .actionMoreTake,
                loadingEventID: "\(viewModel.hintPausePresentationState.snapshotID ?? "hint-pause").pause-loading",
                eventLedger: viewModel.hintPauseMotionEventLedger,
                reduceMotion: isMotionReduced,
                actionAccessibilityIdentifier: nil,
                onAction: resumeHintLiveAnalysis
            )
        }
        .padding(.bottom, 18)
    }

    private var hintPauseIsLoading: Bool {
        if case .loading = viewModel.hintPausePresentationState { return true }
        return false
    }

    private var hintPauseIsFailure: Bool {
        if case .failure = viewModel.hintPausePresentationState { return true }
        return false
    }

    private var hintPauseBandTitle: String {
        switch viewModel.hintPausePresentationState {
        case .loading:
            return viewModel.localizedCopy(.pauseLoading)
        case .success:
            return SETLocalizedPauseCopy.title(number: viewModel.hintPauseTakeNumber, locale: presentationLocale)
        case .empty:
            return viewModel.localizedCopy(.pauseEmpty)
        case .failure:
            return viewModel.localizedCopy(hintPauseFailureTitleKey)
        case .idle, .resuming:
            return viewModel.localizedCopy(.arPauseTitle)
        }
    }

    private var hintPauseBandDetail: String? {
        switch viewModel.hintPausePresentationState {
        case .loading, .idle, .resuming:
            return viewModel.localizedCopy(.arPauseMessage)
        case .success:
            return SETLocalizedPauseCopy.summary(for: viewModel.hintPauseCritique, locale: presentationLocale)
        case .empty:
            return nil
        case .failure:
            return viewModel.localizedCopy(hintPauseFailureDetailKey)
        }
    }

    private var hintPauseFailureTitleKey: SETCopyKey {
        switch viewModel.hintPauseFailureReason {
        case .noAcceptedEvidence: return .pauseFailureNoEvidenceTitle
        case .displayRenderFailed: return .pauseFailureRenderTitle
        case .pipelineUnavailable: return .pauseFailurePipelineTitle
        case .timeout: return .pauseFailureTimeoutTitle
        case nil: return .pauseFailure
        }
    }

    private var hintPauseFailureDetailKey: SETCopyKey {
        switch viewModel.hintPauseFailureReason {
        case .noAcceptedEvidence: return .pauseFailureNoEvidenceDetail
        case .displayRenderFailed: return .pauseFailureRenderDetail
        case .pipelineUnavailable: return .pauseFailurePipelineDetail
        case .timeout: return .pauseFailureTimeoutDetail
        case nil: return .pauseFailureRecovery
        }
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

    private var beatHUD: some View {
        let total = max(viewModel.beatTimelineItems.count, 1)
        let activeIndex = min(max(viewModel.activeBeatIndex, 0), total - 1)
        let activeItem = viewModel.beatTimelineItems[activeIndex]
        let progress = min(max(viewModel.beatProgress, 0), 1)
        let currentCaption = currentBeatCaption

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(SETCopyKey.generatorBeatStatus.localizedFormat(
                    locale: presentationLocale,
                    arguments: [
                        activeIndex + 1,
                        total,
                        activeItem.kindCopyKey.localizedString(locale: presentationLocale)
                    ]
                ))
                    .font(SETTypography.font(.hudMono, size: 12))
                    .foregroundColor(.setTextPrimary)
                    .lineLimit(1)

                if activeItem.hasDialogueCaption {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.setTextSecondary)
                }

                if activeItem.hasActionCaption {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.setTextSecondary)
                }
            }

            if let currentCaption {
                Text(currentCaption)
                    .font(SETTypography.font(.hudMono, size: 10))
                    .foregroundColor(.setTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.setHairline)
                    Rectangle()
                        .fill(Color.setWarmWhite)
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
                        Rectangle()
                            .fill(item.index == activeIndex ? Color.setWarmWhite : SETPalette.textTertiary.color)
                            .frame(width: markerWidth, height: item.index == activeIndex ? 5 : 4)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 210, alignment: .leading)
        .background(
            Rectangle()
                .fill(Color.setHUDScrim)
                .overlay(
                    Rectangle()
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.setOrange)
                        .frame(width: SETStroke.standard)
                }
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
                .foregroundColor(.setOrange)

            Text(SETCopyKey.arMarkingHint.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: 14))
                .foregroundColor(.setTextPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color.setHUDScrim)
                .overlay(
                    Rectangle()
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.setOrange)
                        .frame(width: SETStroke.standard)
                }
        )
    }

    private var storyboardStrip: some View {
        let activeBeatID = activeStoryboardBeatID
        let progress = min(max(viewModel.beatProgress, 0), 1)
        let selectedBeatID = viewModel.selectedStoryboardBeatID ?? activeBeatID ?? viewModel.storyboardBeatItems.first?.beatID ?? ""

        return SETMontageReflow(
            items: viewModel.storyboardBeatItems,
            selectedID: selectedBeatID,
            axis: .horizontal,
            onSelect: { item in
                selectStoryboardBeat(item)
            }
        ) { item, isSelected in
            StoryboardBeatChip(
                item: item,
                isActive: isSelected || item.beatID == activeBeatID,
                isSelected: isSelected,
                progress: item.beatID == activeBeatID ? progress : 0
            )
            .accessibilityIdentifier("storyboard_beat_\(item.beatID)")
            .accessibilityLabel(
                SETCopyKey.storyboardEditBeat.localizedFormat(
                    locale: presentationLocale,
                    arguments: [
                        item.kindCopyKey.localizedString(locale: presentationLocale),
                        item.index + 1
                    ]
                )
            )
        }
        .frame(height: 88)
        .background(
            Rectangle()
                .fill(Color.setHUDScrim)
                .overlay(Rectangle().stroke(Color.setHairline, lineWidth: SETStroke.hairline))
        )
    }

    private func selectStoryboardBeat(_ item: StoryboardBeatPresentationItem) {
        viewModel.selectStoryboardBeat(beatID: item.beatID, reduceMotion: isMotionReduced)
    }

    @ViewBuilder
    private var storyboardPresentation: some View {
        storyboardTray
    }

    private var storyboardTray: some View {
        VStack(spacing: 6) {
            if isStoryboardTrayExpanded {
                storyboardStrip
                    .transition(
                        isMotionReduced
                            ? .opacity.animation(
                                .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                            )
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }

            Button {
                if isMotionReduced {
                    // The reduced-motion transition owns opacity only; the
                    // tray's insertion/removal and all surrounding geometry
                    // resolve in the same layout pass.
                    isStoryboardTrayExpanded.toggle()
                } else {
                    withAnimation(SETMotion.standardSpring) {
                        isStoryboardTrayExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isStoryboardTrayExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))

                    Text(SETCopyKey.storyboardTrayCount.localizedFormat(
                        locale: presentationLocale,
                        arguments: [viewModel.storyboardBeatItems.count]
                    ))
                        .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                        .monospacedDigit()
                }
                .foregroundStyle(.setTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                        .fill(Color.setHUDScrim)
                        .overlay(
                            RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                                .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                        )
                )
                // Keep the visible tray chip compact while exposing a stable
                // minimum hit frame around it.
                .frame(minWidth: SETComponentMetric.minimumHitTarget,
                       minHeight: SETComponentMetric.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("storyboard_tray_toggle")
            .accessibilityLabel(Text(
                (isStoryboardTrayExpanded ? SETCopyKey.storyboardTrayCollapse : SETCopyKey.storyboardTrayExpand).localizedTextKey
            ))
        }
        .animation(
            isMotionReduced
                ? nil
                : SETMotion.standardSpring,
            value: isStoryboardTrayExpanded
        )
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
                .font(SETTypography.font(.hudMono, size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(.setTextPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 260)
        .background(
            Rectangle()
                .fill(Color.setHUDScrim)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.setHairline)
                        .frame(width: SETStroke.hairline)
                }
        )
    }

    private func legacySubtitle(text: String) -> some View {
        Text(text)
            .font(SETTypography.font(.screenplay, size: 16))
            .foregroundColor(.setTextPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 280)
            .background(
                Rectangle()
                    .fill(Color.setHUDScrim)
                    .overlay(
                        Rectangle()
                            .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                    )
            )
    }
}

private struct ObjectTrackingLabel: View {
    let item: ARObjectLabelPresentation

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.swiftUIColor)
                .frame(width: 6, height: 6)

            Text(item.text)
                .font(SETTypography.font(.hudMono, size: 11))
                .foregroundStyle(.setTextPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.setHUDScrim)
                .overlay(
                    Capsule()
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                )
        )
    }
}

private struct StoryboardBeatChip: View {
    let item: StoryboardBeatPresentationItem
    let isActive: Bool
    let isSelected: Bool
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("\(item.index + 1)")
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .foregroundStyle(isActive ? Color.setInk : Color.setTextPrimary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(isActive ? Color.setWarmWhite : Color.setHairline)
                    )

                Text(item.kindCopyKey.localizedTextKey)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .foregroundStyle(.setTextSecondary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if item.hasDialogueCaption {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.setTextSecondary)
                }

                if item.hasActionCaption {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.setTextSecondary)
                }
            }

            Text(item.summary)
                .font(SETTypography.font(.screenplay, size: SETTypographySize.body))
                .foregroundStyle(.setTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.setHairline)
                    Capsule()
                        .fill(isActive ? Color.setWarmWhite : SETPalette.textTertiary.color)
                        .frame(width: geometry.size.width * CGFloat(isActive ? min(max(progress, 0), 1) : 1))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
                Rectangle()
                    .fill(Color.setSurfaceSolid)
                .overlay(
                    Rectangle().stroke(
                        isSelected ? Color.setHairline : (isActive ? Color.setOrange : Color.setHairline),
                        lineWidth: SETStroke.standard
                    )
                )
        )
    }
}

private struct StoryboardBeatEditorSheet: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel
    @Environment(\.locale) private var locale
    @State private var draft: StoryboardBeatEditDraft
    @State private var isDeleteConfirmationPresented = false

    private var isMutationInFlight: Bool {
        viewModel.isStoryboardMutationInFlight
    }

    init(draft: StoryboardBeatEditDraft, viewModel: SceneGeneratorViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            HStack(spacing: SETSpacing.x2) {
                Button {
                    viewModel.cancelStoryboardEditor()
                } label: {
                    Text(SETCopyKey.libraryCancel.localizedTextKey)
                        .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                        .foregroundStyle(.setTextSecondary)
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SETCopyKey.libraryCancel.localizedTextKey)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("storyboard_editor_cancel")

                Text(SETCopyKey.storyboardEditorTitle.localizedTextKey)
                    .font(SETTypography.scaledFont(.display, size: SETTypographySize.title, relativeTo: .title2))
                    .foregroundStyle(.setTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await save() }
                } label: {
                    Text(isMutationInFlight
                         ? SETCopyKey.storyboardSaving.localizedTextKey
                         : SETCopyKey.generatorMarkerSave.localizedTextKey)
                        .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                        .foregroundStyle(.setTextPrimary)
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMutationInFlight
                                    ? SETCopyKey.storyboardSaving.localizedTextKey
                                    : SETCopyKey.generatorMarkerSave.localizedTextKey)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("storyboard_editor_save")
                .disabled(isMutationInFlight)
                .accessibilityRespondsToUserInteraction(!isMutationInFlight)
            }
            .padding(.horizontal, SETSpacing.x3)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .background(Color.setInk)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.setHairline)
                    .frame(height: SETStroke.hairline)
            }
            .overlay(alignment: .bottom) {
                CutSeam(axis: .horizontal)
                    .frame(width: SETComponentMetric.registrationMarkLength * 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

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
                            validationField: viewModel.storyboardValidationField,
                            validationMessage: viewModel.storyboardValidationMessage,
                            onDelete: { removeAction(id: action.id) }
                        )
                        .disabled(isMutationInFlight)
                    }

                    Button(action: addAction) {
                        Label(SETCopyKey.storyboardActionAdd.localizedTextKey, systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(StoryboardEditorSecondaryButtonStyle())
                    .disabled(isMutationInFlight)

                    HStack(spacing: 10) {
                        Button {
                            Task { await move(offset: -1) }
                        } label: {
                            Label(SETCopyKey.storyboardMoveLeft.localizedTextKey, systemImage: "chevron.left")
                        }
                        .buttonStyle(StoryboardEditorSecondaryButtonStyle())
                        .disabled(isMutationInFlight)

                        Button {
                            Task { await move(offset: 1) }
                        } label: {
                            Label(SETCopyKey.storyboardMoveRight.localizedTextKey, systemImage: "chevron.right")
                        }
                        .buttonStyle(StoryboardEditorSecondaryButtonStyle())
                        .disabled(isMutationInFlight)
                    }

                    Button {
                        isDeleteConfirmationPresented = true
                    } label: {
                        HStack(spacing: SETSpacing.x2) {
                            Image(systemName: "trash")
                            Text(SETCopyKey.libraryDelete.localizedTextKey).underline()
                        }
                    }
                    .buttonStyle(StoryboardEditorDestructiveButtonStyle())
                    .disabled(isMutationInFlight)
                    .accessibilityIdentifier("storyboard_editor_delete")
                    }
                    .padding(18)
                }
                .background(Color.setInk.ignoresSafeArea())
            }

            if isDeleteConfirmationPresented {
                deleteConfirmationOverlay
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storyboard_editor_sheet")
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.setInk.opacity(0.9)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                Text(SETCopyKey.storyboardDeleteTitle.localizedTextKey)
                    .font(SETTypography.scaledFont(.display, size: SETTypographySize.title, relativeTo: .title2))
                    .foregroundStyle(.setTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: SETCopyKey.storyboardDeleteDetail.localizedFormat(
                    locale: locale,
                    arguments: [draft.title]
                ))
                .font(SETTypography.scaledFont(.screenplay, size: SETTypographySize.body, relativeTo: .body))
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SETSpacing.x2) {
                    Button {
                        isDeleteConfirmationPresented = false
                    } label: {
                        Text(SETCopyKey.libraryCancel.localizedTextKey)
                            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                            .foregroundStyle(.setTextPrimary)
                            .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        Rectangle().stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                    }
                    .disabled(isMutationInFlight)

                    Button {
                        isDeleteConfirmationPresented = false
                        Task { await deleteBeat() }
                    } label: {
                        Text(SETCopyKey.storyboardDeleteConfirm.localizedTextKey)
                            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                            .foregroundStyle(.setOrange)
                            .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        Rectangle().stroke(Color.setOrange, lineWidth: SETStroke.hairline)
                    }
                    .accessibilityIdentifier("storyboard_editor_delete_confirm")
                    .disabled(isMutationInFlight)
                }
            }
            .padding(SETSpacing.x4)
            .frame(maxWidth: SETComponentMetric.chipMaxWidth)
            .background(Color.setSurfaceSolid)
            .overlay {
                Rectangle().stroke(Color.setHairline, lineWidth: SETStroke.standard)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.setOrange)
                    .frame(width: SETStroke.standard)
            }
            .padding(.horizontal, SETSpacing.x4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("storyboard_editor_delete_confirmation")
        }
    }

    private func targetOptions(for action: StoryboardActionEditDraft) -> [StoryboardEntityOption] {
        guard action.type.usesStoryboardTarget else {
            return [StoryboardEntityOption(
                id: "none",
                label: SETCopyKey.storyboardNoTarget.localizedString(locale: locale),
                kind: .none
            )]
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
                text: SETCopyKey.storyboardNewAction.localizedString(locale: locale),
                isDeleted: false,
                isNew: true
            )
        )
    }

    private func removeAction(id: String) {
        draft.actions.removeAll { $0.id == id }
    }

    private func save() async {
        _ = await viewModel.applyStoryboardBeatEdit(draft)
    }

    private func deleteBeat() async {
        _ = await viewModel.deleteStoryboardBeat(beatID: draft.beatID)
    }

    private func move(offset: Int) async {
        _ = await viewModel.moveStoryboardBeat(beatID: draft.beatID, offset: offset)
    }
}

private struct StoryboardEditorPresentationModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCompactAdaptation(.sheet)
        } else {
            content
        }
    }
}

private struct StoryboardBeatInspectorCard: View {
    let title: String
    let inspector: StoryboardBeatInspectorPresentation
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(SETTypography.scaledFont(.display, size: 18, relativeTo: .headline))
                    .foregroundStyle(.setTextPrimary)

                Text(inspector.kindCopyKey.localizedTextKey)
                    .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .caption))
                    .foregroundStyle(.setTextSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                            .fill(Color.setSurfaceSolid)
                            .overlay(
                                RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                                    .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                            )
                    )

                Spacer()

                Label(inspector.durationText, systemImage: "timer")
                    .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .caption))
                    .foregroundStyle(.setTextSecondary)
            }

            Text(inspector.summary)
                .font(SETTypography.scaledFont(.screenplay, size: SETTypographySize.body, relativeTo: .body))
                .foregroundStyle(.setTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if !inspector.actorLabels.isEmpty {
                    inspectorChipRow(title: SETCopyKey.storyboardInspectorActors.localizedString(locale: locale),
                                     labels: inspector.actorLabels,
                                     icon: "person.2.fill")
                }

                if !inspector.targetLabels.isEmpty {
                    inspectorChipRow(title: SETCopyKey.storyboardInspectorTargets.localizedString(locale: locale),
                                     labels: inspector.targetLabels,
                                     icon: "scope")
                }

                if !inspector.warnings.isEmpty {
                    inspectorChipRow(title: SETCopyKey.storyboardInspectorWarnings.localizedString(locale: locale),
                                     labels: inspector.warnings,
                                     icon: "exclamationmark.triangle.fill")
                }
            }
        }
        .padding(14)
        .background(
            Rectangle()
                .fill(Color.setSurfaceSolid)
                .overlay(
                    Rectangle()
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                )
        )
        .accessibilityIdentifier("storyboard_editor_inspector")
    }

    private func inspectorChipRow(title: String, labels: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .caption))
                .foregroundStyle(.setTextSecondary)

            FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .caption))
                        .foregroundStyle(.setTextPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                                .fill(Color.setSurfaceSolid)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
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
    let validationField: StoryboardValidationField?
    let validationMessage: String?
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.type.storyboardEditorCopyKey.localizedTextKey)
                    .font(SETTypography.scaledFont(.screenplay, size: SETTypographySize.label, relativeTo: .callout))
                    .foregroundStyle(.setTextPrimary)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.setTextSecondary)
                .accessibilityLabel(SETCopyKey.storyboardActionDelete.localizedTextKey)
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker(SETCopyKey.storyboardLabelActor.localizedTextKey, selection: $action.actorId) {
                    ForEach(actorOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                .tint(.setTextPrimary)
                validationRecovery(for: .actor(actionID: action.id))
            }

            Picker(SETCopyKey.storyboardLabelType.localizedTextKey, selection: $action.type) {
                ForEach(SceneGeneratorViewModel.supportedStoryboardEditActionTypes, id: \.rawValue) { type in
                    Text(type.storyboardEditorCopyKey.localizedTextKey).tag(type)
                }
            }
            .pickerStyle(.menu)
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
            .tint(.setTextPrimary)
            .onChange(of: action.type) { newType in
                if !newType.usesStoryboardTarget {
                    action.target = nil
                }
            }

            if action.type.usesStoryboardTarget {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(SETCopyKey.storyboardLabelTarget.localizedTextKey, selection: Binding<String?>(
                        get: { action.target },
                        set: { action.target = $0 }
                    )) {
                        ForEach(targetOptions) { option in
                            Text(option.label).tag(optionalTargetTag(for: option))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                    .tint(.setTextPrimary)
                    validationRecovery(for: .target(actionID: action.id))
                }
            }

            TextField(SETCopyKey.storyboardLabelText.localizedTextKey, text: $action.text, axis: .vertical)
                .font(SETTypography.scaledFont(.screenplay, size: SETTypographySize.label, relativeTo: .body))
                .lineLimit(1...3)
                .foregroundStyle(.setTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: SETRadius.control, style: .continuous)
                        .fill(Color.setHairline)
                )
        }
        .padding(12)
        .background(
            Rectangle()
                .fill(Color.setSurfaceSolid)
                .overlay(
                    Rectangle()
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
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

    @ViewBuilder
    private func validationRecovery(for field: StoryboardValidationField) -> some View {
        if validationField == field, let validationMessage {
            VStack(alignment: .leading, spacing: 4) {
                Text(validationMessage)
                    .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                    .foregroundStyle(.setTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("storyboard_editor_validation_error")
                Rectangle()
                    .fill(Color.setOrange)
                    .frame(height: SETStroke.standard)
            }
        }
    }
}

private struct StoryboardEditorSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
            .foregroundStyle(configuration.isPressed ? Color.setTextSecondary : Color.setTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .background(Color.setSurfaceSolid)
            .overlay(
                Rectangle()
                    .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
            )
    }
}

private struct StoryboardEditorDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
            .foregroundStyle(configuration.isPressed ? Color.setTextSecondary : Color.setTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .background(Color.setSurfaceSolid)
            .overlay(alignment: .leading) {
                // The single destructive accent: one orange edge, no red.
                Rectangle()
                    .fill(Color.setOrange)
                    .frame(width: 2)
            }
            .overlay(
                Rectangle()
                    .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
            )
    }
}

private extension SceneAction.ActionType {
    var storyboardEditorTitle: String {
        storyboardEditorCopyKey.localizedString
    }

    var storyboardEditorCopyKey: SETCopyKey {
        switch self {
        case .stand:
            return .storyboardActionStand
        case .walk:
            return .storyboardActionWalk
        case .lookAt:
            return .storyboardActionLookAt
        case .pickUp:
            return .storyboardActionPickUp
        case .give:
            return .storyboardActionGive
        case .talk:
            return .storyboardActionTalk
        case .describedAction:
            return .storyboardActionDescription
        default:
            return .storyboardActionDescription
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
            .font(SETTypography.font(.hudMono, size: 11))
            .foregroundStyle(configuration.isPressed ? Color.setTextSecondary : Color.setTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .background(
                Capsule()
                    .fill(Color.setHUDScrim)
                    .overlay(
                        Capsule()
                            .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                    )
            )
    }
}

private struct ARHintIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(Color.setHUDScrim)
                .overlay(
                    Circle()
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                )
                .frame(width: 32, height: 32)

            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(configuration.isPressed ? Color.setTextSecondary : Color.setTextPrimary)
        }
        .frame(width: SETComponentMetric.minimumHitTarget,
               height: SETComponentMetric.minimumHitTarget)
        .contentShape(Rectangle())
    }
}

private struct ARLiveHintCheckView: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.setWarmWhite)
            .padding(6)
            .background(
                Circle()
                    .fill(Color.setHUDScrim)
                    .overlay(
                        Circle()
                            .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
                    )
            )
            .accessibilityLabel(Text(SETCopyKey.accessibilityFrameHeld.localizedTextKey))
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
                    .font(SETTypography.font(.hudMono, size: 11))
                    .foregroundStyle(.setTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if onExplain != nil {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.setTextSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .background(
                Capsule()
                    .fill(Color.setHUDScrim)
                    .overlay(
                        Capsule()
                            .stroke(toneColor, lineWidth: SETStroke.hairline)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(onExplain == nil)
        .allowsHitTesting(onExplain != nil)
        .accessibilityLabel(liveHint.text)
        .accessibilityIdentifier("generator_decision_trace_chip")
    }

    /// Single-accent tone grammar: corrective hints carry the orange focus
    /// edge; abstention keeps warm-white; unknown states stay neutral.
    private var toneColor: Color {
        if liveHint.actionType == .leaveFrameAsIs {
            return .setWarmWhite
        }
        if liveHint.actionType == nil {
            return SETPalette.textSecondary.color
        }
        return .setOrange
    }
}

private struct ARLiveAnalysisStatusChip: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.setOrange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SETTypography.font(.hudMono, size: 12))
                    .foregroundStyle(.setTextPrimary)
                    .lineLimit(1)

                Text(message)
                    .font(SETTypography.font(.hudMono, size: 10))
                    .foregroundStyle(.setTextSecondary)
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
                .fill(Color.setHUDScrim)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.setHairline, lineWidth: SETStroke.hairline)
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
                    .stroke(SETPalette.decorativeGrid.color, lineWidth: 1)
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
                            .font(SETTypography.font(.hudMono, size: 11))
                            .foregroundColor(.setInk)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color, in: Capsule())
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

    /// Single-accent grammar: actionable/corrective annotations are orange,
    /// informational geometry is warm-white. Ink label text keeps contrast on
    /// both fills (ink on orange 6.3:1, ink on warmWhite well above AA).
    private func annotationColor(for annotation: OverlayAnnotationPresentation) -> Color {
        switch annotation.tone {
        case .success:
            return .setWarmWhite
        case .warning:
            return .setOrange
        case .danger:
            return .setOrange
        case .neutral:
            switch annotation.kind {
            case .arrow:
                return .setOrange
            case .regionHighlight:
                return .setWarmWhite
            case .horizonLine:
                return .setWarmWhite
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
