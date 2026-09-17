import SwiftUI

/// Optional clarification for one accepted still. Answers belong to the
/// ViewModel/pipeline; showing or dismissing this view never supplies an answer.
struct PauseSceneControlSheet: View {
    let facts: PauseSceneControlFacts
    let onAnswer: (PauseSceneControlFacts.Category, PauseSceneControlFacts.State) -> Void
    let onReset: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Text(SETCopyKey.cameraSceneControlDone.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camera_scene_control_done")
            }
            .padding(.horizontal, SETSpacing.x4)
            ScrollView {
                VStack(alignment: .leading, spacing: SETSpacing.x4) {
                    Text(SETCopyKey.cameraSceneControlTitle.localizedTextKey)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("camera_scene_control_title")
                    Text(SETCopyKey.cameraSceneControlScope.localizedTextKey)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.setTextSecondary)

                    ForEach(PauseSceneControlFacts.Category.allCases, id: \.rawValue) { category in
                        VStack(alignment: .leading, spacing: SETSpacing.x2) {
                            Text(Self.questionKey(for: category).localizedTextKey)
                                .font(SETTypography.uiBodyFont(weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Menu {
                                ForEach(PauseSceneControlFacts.State.allCases, id: \.rawValue) { state in
                                    Button { onAnswer(category, state) } label: {
                                        Text(Self.answerKey(for: state).localizedTextKey)
                                    }
                                }
                            } label: {
                                HStack(spacing: SETSpacing.x3) {
                                    Text(Self.answerKey(for: facts.state(for: category)).localizedTextKey)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, SETSpacing.x3)
                                .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget,
                                       alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Text(Self.questionKey(for: category).localizedTextKey))
                            .accessibilityValue(Text(Self.answerKey(for: facts.state(for: category)).localizedTextKey))
                            .accessibilityIdentifier("camera_scene_control_" + category.rawValue)
                        }
                    }

                    Button(action: onReset) {
                        Text(SETCopyKey.cameraSceneControlReset.localizedTextKey)
                            .underline()
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget,
                                   alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("camera_scene_control_reset")
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(SETSpacing.x4)
            }
            .accessibilityIdentifier("camera_scene_control_scroll")
        }
        .font(SETTypography.uiBodyFont())
        .foregroundStyle(.setTextPrimary)
        .tint(.setOrange)
        .background(Color.setInk.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { onClose() }
        .transaction { transaction in
            if reduceMotionOverride ?? reduceMotion {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    static func questionKey(for category: PauseSceneControlFacts.Category) -> SETCopyKey {
        switch category {
        case .objects: return .cameraSceneControlObjects
        case .participants: return .cameraSceneControlParticipants
        case .lighting: return .cameraSceneControlLighting
        }
    }

    static func answerKey(for state: PauseSceneControlFacts.State) -> SETCopyKey {
        switch state {
        case .unknown: return .cameraSceneControlUnknown
        case .allowed: return .cameraSceneControlAllowed
        case .forbidden: return .cameraSceneControlForbidden
        }
    }
}
