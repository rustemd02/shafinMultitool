//
//  StageSelectionViewController.swift
//  shafinMultitool
//
//  Created on 15.11.2025.
//

import UIKit
import SwiftUI

private struct StageSelectionView: View {
    let onOpenSceneLibrary: () -> Void

    private let backgroundTop = Color(red: 0.10, green: 0.11, blue: 0.13)
    private let backgroundBottom = Color(red: 0.05, green: 0.06, blue: 0.08)
    private let cardFill = Color.white.opacity(0.06)
    private let cardStroke = Color.white.opacity(0.10)
    private let accent = Color(red: 0.83, green: 0.63, blue: 0.38)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [backgroundTop, backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("SHAFIN MULTITOOL")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))

                        Text("Съёмка по сцене")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Один спокойный вход вместо раздельных режимов. Выбираем или создаём сцену, размечаем пространство, генерируем AR-объекты и остаёмся в том же рабочем окне для записи с подсказками.")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Как теперь устроен демо-флоу")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        FlowRow(index: "1",
                                title: "Сцена",
                                subtitle: "Создать новую или открыть сохранённую")
                        FlowRow(index: "2",
                                title: "AR workspace",
                                subtitle: "Разметка, генерация и playback в одной сессии")
                        FlowRow(index: "3",
                                title: "Запись",
                                subtitle: "Подсказки поверх сцены, без переключения режима камеры")
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Основной режим")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)

                        Text("Открыть сцену")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Scene library ведёт сразу в единое AR-рабочее место. Legacy-сцены не смешиваются с новыми проектами.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 10) {
                            FeatureRow(text: "Новые scene projects хранятся отдельно от legacy")
                            FeatureRow(text: "Разметка, генерация, preview и запись живут на одном экране")
                            FeatureRow(text: "Live hints можно включать вручную, а при записи они активируются автоматически")
                        }

                        Button(action: onOpenSceneLibrary) {
                            Text("Выбрать сцену")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.82))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(accent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(cardStroke, lineWidth: 1)
                            )
                    )

                    Text("Playback остаётся дополнительным инструментом внутри workspace, а не отдельной стартовой веткой.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }
}

private struct FlowRow: View {
    let index: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(index)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

private struct FeatureRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.78))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class StageSelectionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let hostingController = UIHostingController(
            rootView: StageSelectionView(
                onOpenSceneLibrary: { [weak self] in
                    self?.openSceneLibrary()
                }
            )
        )

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    private func openSceneLibrary() {
        let vc = SOModuleBuilder.build()
        navigationController?.pushViewController(vc, animated: true)
    }
}

class LandscapeHostingController<Content: View>: UIHostingController<Content> {
}
