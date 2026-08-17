import UIKit
import SnapKit

@MainActor
final class CommercialShellSectionSwitcher: UIView {
    static let surfaceColor = UIColor(red: 0.045, green: 0.05, blue: 0.06, alpha: 1)

    var onSelectionRequested: ((CommercialSection) -> Void)?
    private(set) var selectedSection: CommercialSection = .camera

    private struct SectionPresentation {
        let section: CommercialSection
        let title: String
        let symbolName: String
        let accessibilityIdentifier: String
    }

    private static let presentations: [SectionPresentation] = [
        SectionPresentation(
            section: .camera,
            title: "Камера",
            symbolName: "camera.fill",
            accessibilityIdentifier: "commercial-shell-section-camera"
        ),
        SectionPresentation(
            section: .scenes,
            title: "Сцены",
            symbolName: "square.stack.3d.up",
            accessibilityIdentifier: "commercial-shell-section-scenes"
        ),
        SectionPresentation(
            section: .history,
            title: "История",
            symbolName: "clock",
            accessibilityIdentifier: "commercial-shell-section-history"
        )
    ]

    private let separatorView = UIView()
    private let controlsStackView = UIStackView()
    private var buttons: [CommercialSection: UIButton] = [:]
    private var selectionIndicators: [CommercialSection: UIView] = [:]
    private var isInteractionLocked = false

    private let separatorHeight = 1 / UIScreen.main.scale
    private let selectedColor = UIColor.systemYellow
    private let unselectedColor = UIColor.white.withAlphaComponent(0.72)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        render(selectedSection: .camera, isInteractionLocked: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CommercialShellSectionSwitcher does not support storyboard construction")
    }

    override var intrinsicContentSize: CGSize {
        let contentHeight = controlsStackView.arrangedSubviews
            .map { $0.intrinsicContentSize.height }
            .max() ?? 52
        let height = separatorHeight + max(contentHeight, 52) + safeAreaInsets.bottom
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    func render(selectedSection: CommercialSection, isInteractionLocked: Bool) {
        let selectionChanged = self.selectedSection != selectedSection
        self.selectedSection = selectedSection
        self.isInteractionLocked = isInteractionLocked

        let applyState = { [weak self] in
            guard let self else { return }
            self.applyVisualState()
        }

        guard selectionChanged, !UIAccessibility.isReduceMotionEnabled else {
            UIView.performWithoutAnimation(applyState)
            return
        }

        UIView.transition(
            with: controlsStackView,
            duration: 0.22,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .curveEaseInOut],
            animations: applyState
        )
    }

    private func configureView() {
        backgroundColor = Self.surfaceColor
        isOpaque = true
        accessibilityIdentifier = "commercial-shell-section-switcher"
        layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        separatorView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        separatorView.isAccessibilityElement = false
        addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(separatorHeight)
        }

        controlsStackView.axis = .horizontal
        controlsStackView.alignment = .fill
        controlsStackView.distribution = .fillEqually
        controlsStackView.spacing = 0
        controlsStackView.isAccessibilityElement = false
        addSubview(controlsStackView)
        controlsStackView.snp.makeConstraints { make in
            make.top.equalTo(separatorView.snp.bottom)
            make.leading.equalTo(layoutMarginsGuide.snp.leading)
            make.trailing.equalTo(layoutMarginsGuide.snp.trailing)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)
        }

        for presentation in Self.presentations {
            let button = UIButton(type: .system)
            button.backgroundColor = .clear
            button.accessibilityIdentifier = presentation.accessibilityIdentifier
            button.accessibilityLabel = presentation.title
            button.setTitle(presentation.title, for: .normal)
            button.setImage(UIImage(systemName: presentation.symbolName), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center

            var configuration = UIButton.Configuration.plain()
            configuration.imagePlacement = .top
            configuration.imagePadding = 4
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 6,
                leading: 4,
                bottom: 6,
                trailing: 4
            )
            button.configuration = configuration
            button.addTarget(self, action: #selector(selectionButtonTapped(_:)), for: .touchUpInside)

            let indicator = UIView()
            indicator.backgroundColor = selectedColor
            indicator.isAccessibilityElement = false
            indicator.isHidden = true
            button.addSubview(indicator)
            indicator.snp.makeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
                make.height.equalTo(2)
            }

            buttons[presentation.section] = button
            selectionIndicators[presentation.section] = indicator
            controlsStackView.addArrangedSubview(button)
        }
    }

    private func applyVisualState() {
        for presentation in Self.presentations {
            guard let button = buttons[presentation.section] else { continue }

            let isSelected = presentation.section == selectedSection
            let color = isSelected ? selectedColor : unselectedColor
            let preferredFont = UIFont.preferredFont(forTextStyle: .footnote)
            let weight: UIFont.Weight = isSelected ? .semibold : .regular
            let font = UIFont.systemFont(ofSize: preferredFont.pointSize, weight: weight)

            var configuration = button.configuration ?? UIButton.Configuration.plain()
            configuration.baseForegroundColor = color
            configuration.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { attributes in
                    var transformed = attributes
                    transformed.font = font
                    return transformed
                }
            button.configuration = configuration
            button.tintColor = color
            button.titleLabel?.font = font
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.isUserInteractionEnabled = !isInteractionLocked

            var traits: UIAccessibilityTraits = [.button]
            if isSelected {
                traits.insert(.selected)
            }
            if isInteractionLocked {
                traits.insert(.notEnabled)
            }
            button.accessibilityTraits = traits
            button.accessibilityValue = isSelected ? "Выбрано" : "Не выбрано"
            selectionIndicators[presentation.section]?.isHidden = !isSelected
        }

        invalidateIntrinsicContentSize()
    }

    @objc
    private func selectionButtonTapped(_ sender: UIButton) {
        guard !isInteractionLocked,
              let section = buttons.first(where: { $0.value === sender })?.key else {
            return
        }
        onSelectionRequested?(section)
    }
}
