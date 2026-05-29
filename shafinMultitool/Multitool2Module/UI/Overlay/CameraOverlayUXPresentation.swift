import Foundation

struct CameraOverlayUXPresentation: Equatable {
    let showsLiveWaitingHint: Bool
    let liveWaitingTitle: String?
    let liveWaitingBody: String?
    let showsPausePanel: Bool
    let pausePanelTitle: String?
    let pausePanelBody: String?
    let pausePrimaryActionTitle: String
    let canShowDecisionTrace: Bool

    static func make(isPaused: Bool,
                     liveHint: LiveHintPresentation?,
                     pauseCritique: PauseCritiquePresentation?,
                     previewSuggestions: [Suggestion]) -> CameraOverlayUXPresentation {
        if isPaused {
            let hasCritique = pauseCritique != nil
            let hasSuggestions = !previewSuggestions.isEmpty
            return CameraOverlayUXPresentation(
                showsLiveWaitingHint: false,
                liveWaitingTitle: nil,
                liveWaitingBody: nil,
                showsPausePanel: true,
                pausePanelTitle: pauseTitle(hasCritique: hasCritique, hasSuggestions: hasSuggestions),
                pausePanelBody: pauseBody(hasCritique: hasCritique, hasSuggestions: hasSuggestions),
                pausePrimaryActionTitle: "Продолжить",
                canShowDecisionTrace: hasCritique
            )
        }

        return CameraOverlayUXPresentation(
            showsLiveWaitingHint: liveHint == nil,
            liveWaitingTitle: liveHint == nil ? "Анализ кадра активен" : nil,
            liveWaitingBody: liveHint == nil ? "Live-подсказка появится только при уверенном сигнале. Для подробного разбора нажми паузу." : nil,
            showsPausePanel: false,
            pausePanelTitle: nil,
            pausePanelBody: nil,
            pausePrimaryActionTitle: "Пауза",
            canShowDecisionTrace: liveHint != nil
        )
    }

    private static func pauseTitle(hasCritique: Bool, hasSuggestions: Bool) -> String {
        if hasCritique {
            return "Разбор кадра"
        }
        if hasSuggestions {
            return "Быстрые подсказки"
        }
        return "Анализирую кадр"
    }

    private static func pauseBody(hasCritique: Bool, hasSuggestions: Bool) -> String {
        if hasCritique {
            return "Можно продолжить съёмку сразу или открыть объяснение решения."
        }
        if hasSuggestions {
            return "Расширенный разбор не готов, но есть быстрые подсказки. Можно продолжить и попробовать другой ракурс."
        }
        return "Остановил поток и собираю признаки. Если разбор не нужен, нажми «Продолжить»."
    }
}
