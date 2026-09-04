import Foundation
import UIKit

@MainActor
final class CommercialShellModeControl: UIView {
    enum Intent: Equatable {
        case openScenes
        case returnCamera
    }

    static let surfaceColor = SETPalette.ink.uiColor

    var onIntentRequested: ((Intent) -> Void)?
    private(set) var renderedSection: CommercialSection = .camera
    private(set) var isInteractionLocked = false

    /// The shell is created before any route-specific SwiftUI environment is
    /// installed, so it owns the one presentation locale needed by its UIKit
    /// copy. DEBUG launch overrides remain opt-in; production follows the
    /// device locale exactly.
    private let presentationLocale: Locale

    private let titleLabel = UILabel()
    private let capsuleView = UIView()
    private let tallyView = UIView()
    private let cameraButton = UIButton(type: .custom)
    private let scenesButton = UIButton(type: .custom)
    private var tallyLeadingConstraint: NSLayoutConstraint?
    private var hasRenderedInitialState = false

    override init(frame: CGRect) {
        presentationLocale = Self.resolvePresentationLocale()
        super.init(frame: frame)
        configureView()
        render(selectedSection: .camera, isInteractionLocked: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CommercialShellModeControl does not support storyboard construction")
    }

    private static func resolvePresentationLocale() -> Locale {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(SETGalleryLaunchConfiguration.localeArgument) else {
            return .current
        }
        return SETGalleryLaunchConfiguration(arguments: arguments).locale.locale
#else
        return .current
#endif
    }

    override var intrinsicContentSize: CGSize {
        SETABRollCapsuleContract.minimumControlSize
    }

    func render(selectedSection: CommercialSection, isInteractionLocked: Bool) {
        self.renderedSection = selectedSection
        self.isInteractionLocked = isInteractionLocked

        let selectedRollSection: SETRollSection? = switch selectedSection {
        case .camera: .camera
        case .scenes: .scenes
        case .history: nil
        }
        let animationDuration = UIAccessibility.isReduceMotionEnabled
            ? SETMotion.reducedMotionCrossfadeDuration
            : SETMotion.reflowGeometryDuration

        applyButtonState(selectedRollSection: selectedRollSection)
        tallyView.isHidden = selectedRollSection == nil
        tallyLeadingConstraint?.constant = selectedRollSection == .camera
            ? SETSpacing.x1
            : SETABRollCapsuleContract.minimumSegmentSize.width + SETSpacing.x1

        if hasRenderedInitialState, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: animationDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.layoutIfNeeded()
            }
        } else {
            UIView.performWithoutAnimation {
                self.layoutIfNeeded()
            }
        }
        hasRenderedInitialState = true
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        accessibilityIdentifier = "commercial-shell-mode-control"
        accessibilityLabel = SETCopyKey.accessibilityCapsule.localizedString(locale: presentationLocale)

        titleLabel.text = SETABRollCapsuleContract.title
        titleLabel.font = SETTypography.uiFont(.hudMono, size: SETTypographySize.micro)
        titleLabel.textColor = SETPalette.textSecondary.uiColor
        titleLabel.textAlignment = .center
        titleLabel.backgroundColor = SETPalette.surfaceSolid.uiColor
        titleLabel.isOpaque = true
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        capsuleView.backgroundColor = SETPalette.surfaceSolid.uiColor
        capsuleView.isOpaque = true
        capsuleView.accessibilityIdentifier = "commercial-shell-mode-capsule"
        // Core Animation does not clamp the SwiftUI-style sentinel radius (999)
        // reliably when masksToBounds is active. Derive the UIKit pill radius
        // from the published capsule-height token so the complete surface renders.
        capsuleView.layer.cornerRadius = SETABRollCapsuleContract.minimumSegmentSize.height / 2
        capsuleView.layer.borderColor = SETPalette.hairline.uiColor.cgColor
        capsuleView.layer.borderWidth = SETStroke.hairline
        capsuleView.clipsToBounds = true
        capsuleView.translatesAutoresizingMaskIntoConstraints = false

        tallyView.backgroundColor = SETPalette.setOrange.uiColor
        tallyView.translatesAutoresizingMaskIntoConstraints = false

        configure(button: cameraButton, section: .camera, action: #selector(cameraTapped))
        configure(button: scenesButton, section: .scenes, action: #selector(scenesTapped))

        addSubview(titleLabel)
        addSubview(capsuleView)
        capsuleView.addSubview(tallyView)
        capsuleView.addSubview(cameraButton)
        capsuleView.addSubview(scenesButton)

        let segmentWidth = SETABRollCapsuleContract.minimumSegmentSize.width
        let segmentHeight = SETABRollCapsuleContract.minimumSegmentSize.height
        tallyLeadingConstraint = tallyView.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: SETTypographySize.micro),

            capsuleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsuleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsuleView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: SETSpacing.x1),
            capsuleView.heightAnchor.constraint(equalToConstant: segmentHeight),

            tallyLeadingConstraint!,
            tallyView.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            tallyView.widthAnchor.constraint(equalToConstant: SETStroke.standard),
            tallyView.heightAnchor.constraint(equalToConstant: SETSpacing.x3),

            cameraButton.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            cameraButton.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            cameraButton.widthAnchor.constraint(equalToConstant: segmentWidth),
            cameraButton.heightAnchor.constraint(equalToConstant: segmentHeight),

            scenesButton.leadingAnchor.constraint(equalTo: cameraButton.trailingAnchor),
            scenesButton.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            scenesButton.widthAnchor.constraint(equalToConstant: segmentWidth),
            scenesButton.heightAnchor.constraint(equalToConstant: segmentHeight),

            bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor)
        ])
    }

    private func configure(
        button: UIButton,
        section: SETRollSection,
        action: Selector
    ) {
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.titleLabel?.font = SETTypography.uiFont(.hudMono, size: SETTypographySize.label)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitle(section.label.localizedString(locale: presentationLocale), for: .normal)
        button.setTitleColor(SETPalette.textPrimary.uiColor, for: .normal)
        button.setTitleColor(SETPalette.textSecondary.uiColor, for: .disabled)
        button.accessibilityIdentifier = section.accessibilityIdentifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func applyButtonState(selectedRollSection: SETRollSection?) {
        let cameraSelected = selectedRollSection == .camera
        let scenesSelected = selectedRollSection == .scenes
        let isLocked = isInteractionLocked

        cameraButton.isUserInteractionEnabled = !isLocked
        scenesButton.isUserInteractionEnabled = !isLocked
        cameraButton.isEnabled = cameraButton.isUserInteractionEnabled
        scenesButton.isEnabled = scenesButton.isUserInteractionEnabled

        cameraButton.setTitleColor(
            cameraSelected ? SETPalette.textPrimary.uiColor : SETPalette.textSecondary.uiColor,
            for: .normal
        )
        scenesButton.setTitleColor(
            scenesSelected ? SETPalette.textPrimary.uiColor : SETPalette.textSecondary.uiColor,
            for: .normal
        )

        cameraButton.accessibilityLabel = SETCopyKey.accessibilityCamera.localizedString(locale: presentationLocale)
        scenesButton.accessibilityLabel = SETCopyKey.accessibilityScenes.localizedString(locale: presentationLocale)
        cameraButton.accessibilityHint = SETCopyKey.accessibilityReturnCamera.localizedString(locale: presentationLocale)
        scenesButton.accessibilityHint = SETCopyKey.accessibilityOpenScenes.localizedString(locale: presentationLocale)
        cameraButton.accessibilityValue = isLocked
            ? SETCopyKey.accessibilityTransition.localizedString(locale: presentationLocale)
            : nil
        scenesButton.accessibilityValue = isLocked
            ? SETCopyKey.accessibilityTransition.localizedString(locale: presentationLocale)
            : nil

        cameraButton.accessibilityTraits = traits(selected: cameraSelected, isLocked: isLocked)
        scenesButton.accessibilityTraits = traits(selected: scenesSelected, isLocked: isLocked)
        accessibilityValue = isLocked
            ? SETCopyKey.accessibilityTransition.localizedString(locale: presentationLocale)
            : selectedRollSection?.label.localizedString(locale: presentationLocale)
    }

    private func traits(selected: Bool, isLocked: Bool) -> UIAccessibilityTraits {
        var result: UIAccessibilityTraits = [.button]
        if selected { result.insert(.selected) }
        if isLocked { result.insert(.notEnabled) }
        return result
    }

    @objc
    private func cameraTapped() {
        guard !isInteractionLocked, renderedSection != .camera else { return }
        onIntentRequested?(.returnCamera)
    }

    @objc
    private func scenesTapped() {
        guard !isInteractionLocked, renderedSection != .scenes else { return }
        onIntentRequested?(.openScenes)
    }
}
