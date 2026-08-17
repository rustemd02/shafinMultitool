import UIKit
import SnapKit

@MainActor
final class CommercialShellModeControl: UIView {
    enum Intent: Equatable {
        case openScenes
        case returnCamera
    }

    static let surfaceColor = UIColor(red: 0.045, green: 0.05, blue: 0.06, alpha: 1)

    var onIntentRequested: ((Intent) -> Void)?
    private(set) var renderedSection: CommercialSection = .camera
    private(set) var isInteractionLocked = false

    private struct Presentation {
        let symbolName: String
        let accessibilityIdentifier: String
        let accessibilityLabel: String
        let intent: Intent
    }

    private let button = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        render(selectedSection: .camera, isInteractionLocked: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CommercialShellModeControl does not support storyboard construction")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 44, height: 44)
    }

    func render(selectedSection: CommercialSection, isInteractionLocked: Bool) {
        self.renderedSection = selectedSection
        self.isInteractionLocked = isInteractionLocked

        UIView.performWithoutAnimation { [weak self] in
            self?.applyVisualState()
        }
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        accessibilityIdentifier = "commercial-shell-mode-control"

        button.backgroundColor = .clear
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityTraits = [.button]
        button.addTarget(self, action: #selector(controlTapped), for: .touchUpInside)

        addSubview(button)
        button.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func applyVisualState() {
        let presentation = Self.presentation(for: renderedSection)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

        button.setImage(
            UIImage(systemName: presentation.symbolName, withConfiguration: symbolConfiguration),
            for: .normal
        )
        button.tintColor = UIColor.white.withAlphaComponent(isInteractionLocked ? 0.45 : 0.86)
        button.accessibilityIdentifier = presentation.accessibilityIdentifier
        button.accessibilityLabel = presentation.accessibilityLabel
        button.accessibilityHint = presentation.intent == .openScenes
            ? "Открывает режим Сцены"
            : "Возвращает к Камере"
        button.accessibilityValue = isInteractionLocked ? "Переход выполняется" : nil
        button.isUserInteractionEnabled = !isInteractionLocked

        var traits: UIAccessibilityTraits = [.button]
        if isInteractionLocked {
            traits.insert(.notEnabled)
        }
        button.accessibilityTraits = traits
    }

    @objc
    private func controlTapped() {
        guard !isInteractionLocked else { return }
        onIntentRequested?(Self.presentation(for: renderedSection).intent)
    }

    private static func presentation(for section: CommercialSection) -> Presentation {
        switch section {
        case .camera:
            return Presentation(
                symbolName: "square.stack.3d.up",
                accessibilityIdentifier: "commercial-shell-open-scenes",
                accessibilityLabel: "Сцены",
                intent: .openScenes
            )
        case .scenes, .history:
            return Presentation(
                symbolName: "camera.fill",
                accessibilityIdentifier: "commercial-shell-return-camera",
                accessibilityLabel: "Камера",
                intent: .returnCamera
            )
        }
    }
}
